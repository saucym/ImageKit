//
//  Request.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/9.
//

import Photos
import SwiftUI
import ImageIO

public struct RequestProcessor: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

public struct RequestCache: OptionSet {
    public static let Memory = RequestCache(rawValue: 1 << 0)
    public static let Disk = RequestCache(rawValue: 1 << 1)
    
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

public struct ImageRequest {
    public enum Size {
        case absolute(CGSize) // 写死大小
        case width(CGFloat, defaultHeight: CGFloat = 44)   // 限制宽度, 保持比例计算高度
        
        public var width: CGFloat {
            switch self {
            case .absolute(let cGSize): return cGSize.width
            case .width(let cGFloat, _): return cGFloat
            }
        }
        
        public var height: CGFloat? {
            switch self {
            case .absolute(let cGSize): return cGSize.height
            case .width: return nil
            }
        }
        
        public var defaultHeight: CGFloat {
            switch self {
            case .absolute(let cGSize): return cGSize.height
            case .width(_, let h): return h
            }
        }
    }
    
    public class Context {
        public static let `default` = Context()
        public let disk: DiskCache
        public let useSubDir: Bool
        public let decoder: [DecoderProtocol]
        public let cacher: [CacheProtocol]
        public let processor: [ProcessorProtocol]
        public let loader: [LoaderProtocol]
        #if DEBUG
        public var tag = 0 // 1: hidden image
        #endif
        public init(disk: DiskCache = .init(),
             useSubDir: Bool = true,
             decoder: [DecoderProtocol] = [SystemDecoder()],
             cacher: [CacheProtocol] = [MemoryCache.shared],
             processor: [ProcessorProtocol] = [GrayProcessor(), PredrawnProcessor()],
             loader: [LoaderProtocol] = [LocalLoader(), NetworkLoader()]) {
            self.disk = disk
            self.useSubDir = useSubDir
            self.decoder = decoder
            self.cacher = cacher
            self.processor = processor
            self.loader = loader
        }
    }
    
    public private(set) var key: String
    public private(set) var url: String
    public private(set) var size: Size
    public private(set) var mode: ContentMode
    public let isGif: Bool? // true: decode to gif, false: decode to image, nil: auto
    public let context: Context
    public var processors: RequestProcessor = .preDrawn
    public var caches: RequestCache
    public var info: AnyObject?
    public var asset: PHAsset?
    
    public init(_ url: String,
                size: Size,
                mode: ContentMode = .fill,
                key: String? = nil,
                processors: RequestProcessor = .preDrawn,
                caches: RequestCache = [.Memory, .Disk],
                isGif: Bool? = nil,
                context: Context = .default) {
        self.key = key ?? ImageRequest.cacheKeyFor(url)
        self.url = url
        self.size = size
        self.mode = mode
        self.processors = processors
        self.caches = caches
        self.context = context
        if let isGif {
            self.isGif = isGif
        } else {
            self.isGif = ((url as NSString).pathExtension.lowercased() == "gif")
        }
    }
    
    public init(_ url: String,
                _ imageView: KKImageView,
                key: String? = nil,
                processors: RequestProcessor = .preDrawn,
                caches: RequestCache = [.Memory, .Disk],
                isGif: Bool? = nil,
                context: Context = .default) {
        self.key = key ?? ImageRequest.cacheKeyFor(url)
        self.url = url
        self.size = .absolute(imageView.bounds.size)
        #if os(iOS)
        self.mode = imageView.contentMode == .scaleAspectFill ? .fill : .fit
        #else
        self.mode = .fill
        #endif
        self.processors = processors
        self.caches = caches
        self.context = context
        if let isGif {
            self.isGif = isGif
        } else {
            self.isGif = ((url as NSString).pathExtension.lowercased() == "gif")
        }
    }
    
    public func makeRequest(newSize: Size) -> ImageRequest {
        var newRequest = ImageRequest(self.url, size: newSize, mode: self.mode, key: self.key, processors: self.processors)
        newRequest.caches = self.caches
        newRequest.info = self.info
        newRequest.asset = self.asset
        return newRequest
    }

    static public func cacheKeyFor(_ url: String) -> String {
        var ext = (url as NSString).pathExtension
        if ext.count == 0 {
            ext = "jpg"
        }

        return url.md5 + ".\(ext)"
    }
}

extension ImageRequest {
    // MARK: - Decoder
    func decode(data: Data) async throws -> KKImage {
        for operation in context.decoder {
            if operation.isValid(request: self) == true {
                return try await operation.decoder(request: self, data: data)
            }
        }
        
        throw IKError.decoderIsEmpty
    }

    // MARK: - Cacher
    @MainActor func cachedImage() throws -> KKImage? {
        for operation in context.cacher {
            if operation.isValid(request: self) == true {
                if let image = try operation.imageFor(request: self) {
                    return image
                }
            }
        }
        return nil
    }
    
    @MainActor func cache(image: KKImage) {
        for operation in context.cacher {
            if operation.isValid(request: self) {
                operation.cache(image: image, for: self)
            }
        }
    }
    
    // MARK: - Processor
    func process(_ input: KKImage) -> KKImage {
        var img: KKImage = input
        for operation in context.processor {
            if operation.isValid(request: self) == true {
                img = operation.processor(request: self, input: img)
            }
        }
        
        return img
    }
    
    // MARK: - Loader
    func load() async throws -> ResultItem {
        for operation in context.loader {
            if operation.isValid(request: self) == true {
                if let res = await operation.loadFor(request: self) {
                    return res
                }
            }
        }
        
        throw IKError.loaderIsEmpty
    }
}

extension ImageRequest {
    public func send() async throws -> KKImage {
        let res: ResultItem
        if let tmp = try await cachedImage() {
            res = .image(tmp)
        } else {
            res = try await load()
        }
        
        switch res {
        case .image(let image):
            let result = process(image)
            await cache(image: result)
            return result
        case .data(let data):
            let image = try await decode(data: data)
            let result = process(image)
            await cache(image: result)
            return result
        }
    }
}

public enum ResultItem {
    case image(KKImage)
    case data(Data)
}

public enum IKError: Error {
    case decoderIsEmpty
    case loaderIsEmpty
    case imageSourceCreateError
    case decoderImageIsNil
}

public func logInfo(fileName: String = #file, funcName: String = #function, lineNum: Int = #line, _ items: Any..., separator: String = " ") {
    let stringItems = items.map{ String(describing: $0) }
    let combinedString = stringItems.joined(separator: separator)
    print("[\((fileName as NSString).lastPathComponent):\(lineNum), \(funcName)]: \(combinedString)")
}

public func logDebug(fileName: String = #file, funcName: String = #function, lineNum: Int = #line, _ text: @autoclosure () -> String) {
    #if DEBUG
    print("[\((fileName as NSString).lastPathComponent):\(lineNum), \(funcName)]: \(text())")
    #endif
}
