//
//  UIImageViewExt.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/9.
//

import Photos
import Foundation

#if os(OSX)
import AppKit
#else
import UIKit
#endif

private struct AssociatedKeys {
    static var request = 1
}

private class ViewLoader {
    init(request: ImageRequest, task: Task<(), Never>) {
        self.request = request
        self.task = task
    }
    
    let request: ImageRequest
    let task: Task<(), Never>
}

public extension KKImageView {
    private var ik_loader: ViewLoader? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.request) as? ViewLoader }
        set { objc_setAssociatedObject(self, &AssociatedKeys.request, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    func setImage(url: URL, key: String? = nil) {
        setImage(request: ImageRequest(url, self, key: key))
    }

    func setImage(asset: PHAsset) {
        guard let url = URL(string: "ph://\(asset.localIdentifier)") else {
            return
        }
        setImage(request: ImageRequest(url, self, asset: asset))
    }
    
    func setImage(request: ImageRequest) {
        KKImageView.swizzleMethod
        image = nil
        
        let task = Task { @MainActor in
            do {
                let image = try await request.send()
                if ik_loader?.request.cacheKey() == request.cacheKey() {
                    self.image = image
                }
            } catch {
                logInfo(error.localizedDescription)
            }
        }
        
        ik_loader = ViewLoader(request: request, task: task)
    }
}

extension NSObject {
    fileprivate static func swizzling(_ originalSelector: Selector, _ swizzledSelector: Selector) {
        if let originalMethod = class_getInstanceMethod(self, originalSelector),
           let swizzledMethod = class_getInstanceMethod(self, swizzledSelector) {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        } else {
            logInfo("swizzling error")
        }
    }
}

extension KKImageView {
    internal static let swizzleMethod: Void = {
        swizzling(#selector(setter: bounds), #selector(setter: ik_bounds))
    }()
    
    @objc var ik_bounds: CGRect {
        get { bounds }
        set {
            self.ik_bounds = newValue
            guard let loader = ik_loader else { return }
            let request = loader.request
            let currentSize = CGSize(width: request.size.width ?? 0, height: request.size.height ?? bounds.height)
            guard !currentSize.equalTo(bounds.size) else { return }
            
            loader.task.cancel()
            switch request.size {
            case .original:
                setImage(request: request)
            case .absolute:
                setImage(request: request.makeRequest(size: .absolute(bounds.size)))
            case .width:
                setImage(request: request.makeRequest(size: .width(bounds.width)))
            }
        }
    }
}

extension ImageRequest {
    init(_ url: URL,
         _ imageView: KKImageView,
         key: String? = nil,
         processors: RequestProcessor = .predrawn,
         caches: RequestCache = [.memory, .disk],
         isGif: Bool? = nil,
         asset: PHAsset? = nil,
         context: Context = .default) {
        self.key = key ?? ImageRequest.cacheKey(for: url)
        self.url = url
        self.size = .absolute(imageView.bounds.size)
        #if os(iOS)
        self.mode = imageView.contentMode == .scaleAspectFill ? .fill : .fit
        #else
        self.mode = .fill
        #endif
        self.info = nil
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
    
    public func makeRequest(size newSize: Size) -> ImageRequest {
        ImageRequest(url,
                     size: newSize,
                     mode: mode,
                     key: key,
                     isGif: isGif,
                     info: info,
                     asset: asset,
                     processors: processors,
                     caches: caches,
                     context: context)
    }
}
