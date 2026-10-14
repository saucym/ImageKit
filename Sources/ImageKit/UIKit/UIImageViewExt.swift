//
//  UIImageViewExt.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/9.
//

import Photos
import Foundation
import SwiftUI

#if os(OSX)
import AppKit
#else
import UIKit
#endif

private struct AssociatedKeys {
    static var request = 1
}

private final class ViewLoader {
    init(id: UUID, request: ImageRequest, task: Task<(), Never>) {
        self.id = id
        self.request = request
        self.task = task
    }

    let id: UUID
    let request: ImageRequest
    let task: Task<(), Never>

    deinit {
        task.cancel()
    }
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
        cancelImageLoad()
        image = nil

        let id = UUID()
        let task = Task { @MainActor [weak self] in
            do {
                let image = try await request.send()
                guard !Task.isCancelled,
                      let self,
                      ik_loader?.id == id else { return }
                self.image = image
            } catch is CancellationError {
            } catch {
                logInfo(error.localizedDescription)
            }
        }

        ik_loader = ViewLoader(id: id, request: request, task: task)
    }

    func cancelImageLoad() {
        let loader = ik_loader
        ik_loader = nil
        loader?.task.cancel()
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
            
            switch request.size {
            case .original:
                break
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
        #if os(iOS)
        let mode: ContentMode = imageView.contentMode == .scaleAspectFill ? .fill : .fit
        #else
        let mode: ContentMode = .fill
        #endif
        self.init(url,
                  size: .absolute(imageView.bounds.size),
                  mode: mode,
                  key: key,
                  isGif: isGif,
                  asset: asset,
                  processors: processors,
                  caches: caches,
                  context: context)
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
                     context: context,
                     animation: animation)
    }
}
