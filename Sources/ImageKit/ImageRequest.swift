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

public struct RequestProcessor: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

public struct RequestCache: OptionSet {
    public static let memory = RequestCache(rawValue: 1 << 0)
    public static let disk = RequestCache(rawValue: 1 << 1)
    
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

public struct ImageRequest {
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
        public nonisolated let disk: DiskCache
        public nonisolated let decoders: [ImageDecoder]
        public nonisolated let caches: [ImageCache]
        public nonisolated let processors: [ImageProcessor]
        public nonisolated let loaders: [DataLoader]
        #if DEBUG
        let tag: Int // 1: hidden image
        #endif
        var taskMap = [Int: Task<KKImage, Error>]()
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
    public let isGif: Bool? // true: decode to gif, false: decode to image, nil: auto
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
                context: Context = .default) {
        self.key = key ?? ImageRequest.cacheKey(for: url)
        self.url = url
        self.size = size
        self.mode = mode
        self.info = info
        self.asset = asset
        self.processors = processors
        self.caches = caches
        self.context = context
        if let isGif {
            self.isGif = isGif
        } else {
            self.isGif = url.pathExtension.lowercased() == "gif"
        }
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
    
    /// Memory-cache identity: url key + display width + processors.
    func cacheKey(width: CGFloat? = nil) -> Int {
        var hasher = Hasher()
        hasher.combine(key)
        hasher.combine(width ?? size.width)
        hasher.combine(processors.rawValue)
        return hasher.finalize()
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
        for processor in context.processors where processor.isValid(request: self) {
            image = processor.process(request: self, input: image)
        }
        return image
    }
    
    func load() async throws -> LoadResult {
        for loader in context.loaders where loader.isValid(request: self) {
            if let result = await loader.load(request: self) {
                return result
            }
        }
        throw IKError.loaderIsEmpty
    }
}

private extension ImageRequest.Context {
    func load(request: ImageRequest) async throws -> KKImage {
        if let cached = try await request.cachedImage() {
            return cached
        }
        
        let key = request.cacheKey()
        let task: Task<KKImage, Error>
        if let existing = taskMap[key] {
            task = existing
        } else {
            task = Task {
                let result = try await request.load()
                switch result {
                case .image(let image):
                    let processed = request.process(image)
                    await request.cache(image: processed)
                    return processed
                case .data(let data):
                    let image = try request.decode(data: data)
                    let processed = request.process(image)
                    await request.cache(image: processed)
                    return processed
                }
            }
            taskMap[key] = task
        }
        do {
            let result = try await task.value
            taskMap[key] = nil
            return result
        } catch {
            taskMap[key] = nil
            throw error
        }
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
