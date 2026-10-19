import Photos
import Foundation
import SwiftUI
import ObjectiveC

#if os(macOS)
import AppKit
#else
import UIKit
#endif

private enum ImageViewAssociation {
    static var load: UInt8 = 0
}

private final class ImageViewLoad {
    let id: UUID
    let request: ImageRequest
    let task: Task<Void, Never>

    init(id: UUID, request: ImageRequest, task: Task<Void, Never>) {
        self.id = id
        self.request = request
        self.task = task
    }

    deinit {
        task.cancel()
    }
}

public extension KKImageView {
    func setImage(url: URL, key: String? = nil) {
        setImage(request: ImageRequest(url, imageView: self, key: key))
    }

    func setImage(asset: PHAsset) {
        guard let url = URL(string: "ph://\(asset.localIdentifier)") else { return }
        setImage(request: ImageRequest(url, imageView: self, asset: asset))
    }

    func setImage(request: ImageRequest) {
        Self.installBoundsObserver
        cancelImageLoad()
        image = nil

        let id = UUID()
        let task = Task { @MainActor [weak self] in
            do {
                let image = try await request.send()
                guard !Task.isCancelled,
                      let self,
                      imageLoad?.id == id else { return }
                self.image = image
            } catch is CancellationError {
            } catch {
                logInfo(error.localizedDescription)
            }
        }
        imageLoad = ImageViewLoad(id: id, request: request, task: task)
    }

    func cancelImageLoad() {
        let load = imageLoad
        imageLoad = nil
        load?.task.cancel()
    }
}

private extension KKImageView {
    var imageLoad: ImageViewLoad? {
        get { objc_getAssociatedObject(self, &ImageViewAssociation.load) as? ImageViewLoad }
        set { objc_setAssociatedObject(self, &ImageViewAssociation.load, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    static let installBoundsObserver: Void = {
        let original = #selector(setter: bounds)
        let replacement = #selector(setter: imageKitBounds)
        guard let originalMethod = class_getInstanceMethod(KKImageView.self, original),
              let replacementMethod = class_getInstanceMethod(KKImageView.self, replacement) else {
            logInfo("Could not observe image view bounds changes")
            return
        }
        // An inherited Method belongs to the superclass; install an override before replacing it.
        if class_addMethod(KKImageView.self, original,
                           method_getImplementation(replacementMethod),
                           method_getTypeEncoding(replacementMethod)) {
            class_replaceMethod(KKImageView.self, replacement,
                                method_getImplementation(originalMethod),
                                method_getTypeEncoding(originalMethod))
        } else {
            method_exchangeImplementations(originalMethod, replacementMethod)
        }
    }()

    @objc dynamic var imageKitBounds: CGRect {
        get { bounds }
        set {
            self.imageKitBounds = newValue
            guard let request = imageLoad?.request else { return }
            let size: ImageRequest.Size
            switch request.size {
            case .original:
                return
            case .absolute(let current):
                guard current != bounds.size else { return }
                size = .absolute(bounds.size)
            case .width(let current, let placeholderHeight):
                guard current != bounds.width else { return }
                size = .width(bounds.width, defaultHeight: placeholderHeight)
            }
            setImage(request: request.resized(to: size))
        }
    }
}

private extension ImageRequest {
    init(_ url: URL, imageView: KKImageView, key: String? = nil, asset: PHAsset? = nil) {
        #if os(iOS)
        let mode: ContentMode = imageView.contentMode == .scaleAspectFill ? .fill : .fit
        #else
        let mode: ContentMode = .fill
        #endif
        self.init(url, size: .absolute(imageView.bounds.size), mode: mode, key: key, asset: asset)
    }
}
