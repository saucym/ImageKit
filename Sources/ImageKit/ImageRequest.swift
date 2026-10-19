//
//  ImageRequest.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/9.
//

import Photos
import SwiftUI

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
        case original
        case absolute(CGSize)
        case width(CGFloat, defaultHeight: CGFloat = 44)
        
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
                size: Size = .original,
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
        let fileExtension = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        return url.absoluteString.md5 + ".\(fileExtension)"
    }
    
    public func localPath() -> URL {
        context.disk.localPath(self)
    }

    public func resized(to size: Size) -> ImageRequest {
        ImageRequest(url,
                     size: size,
                     mode: mode,
                     key: key,
                     info: info,
                     asset: asset,
                     processors: processors,
                     caches: caches,
                     context: context,
                     animation: animation)
    }

    @available(*, deprecated, renamed: "resized(to:)")
    public func makeRequest(size: Size) -> ImageRequest {
        resized(to: size)
    }
}
