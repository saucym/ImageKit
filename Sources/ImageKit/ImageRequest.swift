//
//  ImageRequest.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/9.
//

import Photos
import SwiftUI
import ImageIO
import CryptoKit

public struct RequestProcessor: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

public struct RequestCache: OptionSet, Sendable {
    public static let memory = RequestCache(rawValue: 1 << 0)
    public static let disk = RequestCache(rawValue: 1 << 1)
    
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

public struct ImageRequest {
    public enum AnimationPolicy: Hashable, Sendable {
        case automatic
        case firstFrame
        case animated
    }

    public enum Size {
        case original // 资源大小
        case absolute(CGSize) // 写死大小
        case width(CGFloat, defaultHeight: CGFloat = 44)   // 限制宽度, 保持比例计算高度
        
        public var width: CGFloat? {
            switch self {
            case .original: nil
            case .absolute(let size): size.width
            case .width(let width, _): width
            }
        }
        
        public var height: CGFloat? {
            switch self {
            case .absolute(let size): size.height
            case .width, .original: nil
            }
        }
        
        public var defaultHeight: CGFloat? {
            switch self {
            case .original: nil
            case .absolute(let size): size.height
            case .width(_, let height): height
            }
        }
    }
    
    public actor Context {
        public static let `default` = Context()
        nonisolated let cacheIdentity = UUID()
        public nonisolated let disk: DiskCache
        public nonisolated let decoders: [ImageDecoder]
        public nonisolated let caches: [ImageCache]
        public nonisolated let processors: [ImageProcessor]
        public nonisolated let loaders: [DataLoader]
        #if DEBUG
        let tag: Int // 1: hidden image
        #endif
        private let tasks = SharedTaskStore<TaskKey, KKImage>()
        public init(disk: DiskCache = .init(),
                    decoders: [ImageDecoder] = [SystemDecoder()],
                    caches: [ImageCache] = [MemoryCache.shared],
                    processors: [ImageProcessor] = [GrayProcessor(), PredrawnProcessor()],
                    loaders: [DataLoader] = [LocalLoader(), NetworkLoader()],
                    tag: Int = 0) {
            self.disk = disk
            self.decoders = decoders
            self.caches = caches
            self.processors = processors
            self.loaders = loaders
            #if DEBUG
            self.tag = tag
            #endif
        }
    }
    
    public let key: String
    public let url: URL
    public let size: Size
    public let mode: ContentMode
    public let animation: AnimationPolicy
    public var isGif: Bool? {
        switch animation {
        case .automatic: nil
        case .firstFrame: false
        case .animated: true
        }
    }
    public let info: Any?
    public let asset: PHAsset?
    public let processors: RequestProcessor
    public let caches: RequestCache
    public let context: Context
    
    public init(_ url: URL,
                size: Size,
                mode: ContentMode = .fill,
                key: String? = nil,
                isGif: Bool? = nil,
                info: Any? = nil,
                asset: PHAsset? = nil,
                processors: RequestProcessor = .predrawn,
                caches: RequestCache = [.memory, .disk],
                context: Context = .default,
                animation: AnimationPolicy? = nil) {
        self.key = key ?? ImageRequest.cacheKey(for: url)
        self.url = url
        self.size = size
        self.mode = mode
        self.info = info
        self.asset = asset
        self.processors = processors
        self.caches = caches
        self.context = context
        self.animation = animation ?? isGif.map { $0 ? .animated : .firstFrame } ?? .automatic
    }
    
    public static func cacheKey(for url: URL) -> String {
        var ext = url.pathExtension
        if ext.isEmpty {
            ext = "jpg"
        }
        return url.absoluteString.md5 + ".\(ext)"
    }
    
    public func localPath() -> URL {
        context.disk.localPath(self)
    }
    
    struct OutputKey: Hashable, Sendable {
        let resource: String
        let assetIdentifier: String?
        let width: CGFloat?
        let height: CGFloat?
        let isOriginal: Bool
        let isFill: Bool
        let animation: AnimationPolicy
        let processors: Int
        let scale: CGFloat
        let context: UUID
    }

    private struct TaskKey: Hashable, Sendable {
        let output: OutputKey
        let caches: Int
    }

    var outputKey: OutputKey { outputKey(width: size.width) }

    private func outputKey(width: CGFloat?) -> OutputKey {
        OutputKey(resource: key,
                  assetIdentifier: asset?.localIdentifier,
                  width: width,
                  height: size.height,
                  isOriginal: size.width == nil,
                  isFill: mode == .fill,
                  animation: animation,
                  processors: processors.rawValue,
                  scale: screenScale,
                  context: context.cacheIdentity)
    }

    func cacheKey(width: CGFloat? = nil) -> Int {
        outputKey(width: width ?? size.width).hashValue
    }
}

extension ImageRequest {
    func decode(data: Data) throws -> KKImage {
        for decoder in context.decoders where decoder.isValid(request: self) {
            return try decoder.decode(request: self, data: data)
        }
        throw IKError.decoderIsEmpty
    }
    
    @MainActor func cachedImage() throws -> KKImage? {
        for cache in context.caches where cache.isValid(request: self) {
            if let image = try cache.image(for: self) {
                return image
            }
        }
        return nil
    }
    
    @MainActor func cache(image: KKImage) {
        for cache in context.caches where cache.isValid(request: self) {
            cache.cache(image, for: self)
        }
    }
    
    func process(_ input: KKImage) -> KKImage {
        var image = input
        #if os(iOS)
        if animation == .firstFrame, let first = input.images?.first {
            image = first
        }
        #endif
        for processor in context.processors where processor.isValid(request: self) {
            image = processor.process(request: self, input: image)
        }
        return image
    }
    
    func load() async throws -> LoadResult {
        try await loadResource().result
    }

    private func loadResource() async throws -> LoadedResource {
        for loader in context.loaders where loader.isValid(request: self) {
            try Task.checkCancellation()
            if let resourceLoader = loader as? any ResourceLoader {
                if let resource = try await resourceLoader.loadResource(request: self) {
                    return resource
                }
            } else if let result = try await loader.loadResult(request: self) {
                return LoadedResource(result: result)
            }
        }
        throw IKError.loaderIsEmpty
    }

    private func decode(_ resource: LoadedResource) throws -> KKImage {
        try Task.checkCancellation()
        switch resource.result {
        case .image(let image): return image
        case .data(let data):
            do {
                return try decode(data: data)
            } catch {
                try Task.checkCancellation()
                if case IKError.decoderIsEmpty = error { throw error }
                if error is CancellationError { throw error }
                resource.invalidateCachedData?()
                throw error
            }
        }
    }

    private func loadImage() async throws -> KKImage {
        if let cached = try await cachedImage() {
            try Task.checkCancellation()
            return cached
        }
        let resource = try await loadResource()
        let image: KKImage
        do {
            image = try decode(resource)
        } catch {
            try Task.checkCancellation()
            if case IKError.decoderIsEmpty = error { throw error }
            if error is CancellationError { throw error }
            guard let reload = resource.reload else { throw error }
            let reloaded = try await reload()
            image = try decode(reloaded)
        }
        try Task.checkCancellation()
        let processed = process(image)
        try Task.checkCancellation()
        await cache(image: processed)
        return processed
    }
}

private extension ImageRequest.Context {
    func load(request: ImageRequest) async throws -> KKImage {
        try Task.checkCancellation()
        if let cached = try await request.cachedImage() {
            try Task.checkCancellation()
            return cached
        }
        let key = ImageRequest.TaskKey(output: request.outputKey, caches: request.caches.rawValue)
        let image = try await tasks.value(for: key) {
            try await request.loadImage()
        }
        try Task.checkCancellation()
        return image
    }
}

extension ImageRequest {
    public func send() async throws -> KKImage {
        try await context.load(request: self)
    }
}

public enum IKError: Error {
    case decoderIsEmpty
    case loaderIsEmpty
    case imageSourceCreateError
    case decoderImageIsNil
    case invalidHTTPStatus(Int)
}

extension String {
    var md5: String {
        guard let data = data(using: .utf8) else {
            return self
        }
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
