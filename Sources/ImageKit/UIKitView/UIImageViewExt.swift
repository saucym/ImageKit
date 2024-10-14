//
//  KKImageViewExt.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/9.
//

import Photos
import Foundation

#if os(OSX)
import AppKit
let kScale = NSScreen.main?.backingScaleFactor ?? 1
#else
import UIKit
let kScale = UIScreen.main.scale
#endif

private struct AssociatedKeys {
    static var request = 1
}

private class Loader {
    init(req: ImageRequest, task: Task<(), Never>) {
        self.req = req
        self.task = task
    }
    
    let req: ImageRequest
    let task: Task<(), Never>
}

public extension KKImageView {
     private var ik_loader: Loader? {
        get { return objc_getAssociatedObject(self, &AssociatedKeys.request) as? Loader }
        set { objc_setAssociatedObject(self, &AssociatedKeys.request, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    func setImageWith(url: String, key: String? = nil) {
        let request = ImageRequest(url, self, key: key)
        self.setImageWith(request: request)
    }

    func setImageWith(asset: PHAsset) {
        var request = ImageRequest(asset.localIdentifier, self)
        request.asset = asset
        self.setImageWith(request: request)
    }
    
    func setImageWith(request: ImageRequest) {
        KKImageView.swizzleMethod
        self.image = nil
        
        let task = Task { @MainActor in
            do {
                let image = try await request.send()
                if self.ik_loader?.req.cacheKey() == request.cacheKey() {
                    self.image = image
                }
            } catch {
                logInfo(error.localizedDescription)
            }
        }
        
        ik_loader = Loader(req: request, task: task)
    }
}

extension NSObject {
    fileprivate static func swizzling(_ originalSelector: Selector, _ swizzledSelector: Selector) {
        if let originalMethod = class_getInstanceMethod(self, originalSelector), let swizzledMethod = class_getInstanceMethod(self, swizzledSelector) {
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
        get { return bounds }
        set {
            self.ik_bounds = newValue
            if let loader = ik_loader {
                let request = loader.req
                if CGSize(width: request.size.width, height: request.size.height ?? bounds.height).equalTo(bounds.size) == false {
                    loader.task.cancel()
                    switch request.size {
                    case .absolute:
                        let newReq = request.makeRequest(newSize: .absolute(bounds.size))
                        self.setImageWith(request: newReq)
                    case .width:
                        let newReq = request.makeRequest(newSize: .width(bounds.width))
                        self.setImageWith(request: newReq)
                    }
                }
            }
        }
    }
}

extension ImageRequest {
    func cacheKey(width: CGFloat? = nil) -> Int {
        var hasher = Hasher()
        hasher.combine(key)
        hasher.combine(width ?? size.width)
        hasher.combine(processors.rawValue)
        return hasher.finalize()
    }
}
