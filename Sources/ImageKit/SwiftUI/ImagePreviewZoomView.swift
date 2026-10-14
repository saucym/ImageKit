#if os(iOS)
import SwiftUI
import UIKit
import PhotosUI

@available(iOS 17.0, *)
struct ImagePreviewZoomView: UIViewRepresentable {
    let image: UIImage
    let livePhoto: PHLivePhoto?
    let showsLivePhotoButton: Bool
    let isLoadingLivePhoto: Bool
    let onSingleTap: () -> Void
    let onLivePhoto: () -> Void
    let onZoomChange: (Bool) -> Void

    func makeUIView(context: Context) -> ImagePreviewScrollView {
        ImagePreviewScrollView()
    }

    func updateUIView(_ view: ImagePreviewScrollView, context: Context) {
        view.update(image: image, livePhoto: livePhoto,
                    showsLivePhotoButton: showsLivePhotoButton, isLoadingLivePhoto: isLoadingLivePhoto,
                    onSingleTap: onSingleTap, onLivePhoto: onLivePhoto, onZoomChange: onZoomChange)
    }

    static func dismantleUIView(_ view: ImagePreviewScrollView, coordinator: ()) {
        view.stopReportingZoom()
    }
}

@available(iOS 17.0, *)
final class ImagePreviewScrollView: UIScrollView, UIScrollViewDelegate {
    private let mediaView = PreviewMediaView()
    private let tapDelegate = PreviewTapDelegate()
    private var onSingleTap: () -> Void = {}
    private var onLivePhoto: () -> Void = {}
    private var onZoomChange: (Bool) -> Void = { _ in }
    private var lastReportedZoom: Bool?
    private var pinchActive = false
    private var updatingLayout = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        delaysContentTouches = false
        decelerationRate = .fast
        addSubview(mediaView)
        mediaView.livePhotoButton.addTarget(self, action: #selector(loadLivePhoto), for: .touchUpInside)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(didDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = tapDelegate
        addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(didSingleTap))
        singleTap.delegate = tapDelegate
        singleTap.cancelsTouchesInView = false
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(image: UIImage, livePhoto: PHLivePhoto? = nil,
                showsLivePhotoButton: Bool = false, isLoadingLivePhoto: Bool = false,
                onSingleTap: @escaping () -> Void = {}, onLivePhoto: @escaping () -> Void = {},
                onZoomChange: @escaping (Bool) -> Void = { _ in }) {
        self.onSingleTap = onSingleTap
        self.onLivePhoto = onLivePhoto
        self.onZoomChange = onZoomChange
        // SwiftUI updates must not reset the scroll view's ongoing zoom or pan.
        isScrollEnabled = true
        mediaView.update(image: image, livePhoto: livePhoto,
                         showsLivePhotoButton: showsLivePhotoButton, isLoadingLivePhoto: isLoadingLivePhoto)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !updatingLayout, bounds.width > 0, bounds.height > 0,
              let image = mediaView.imageView.image, image.size.width > 0, image.size.height > 0 else { return }
        let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * fit, height: image.size.height * fit)
        if abs(size.width - mediaView.bounds.width) > 0.5 || abs(size.height - mediaView.bounds.height) > 0.5 {
            refitContent(to: size)
        }
        centerContent()
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer,
           !pinchActive, gestureRecognizer.numberOfTouches < 2, zoomScale <= minimumZoomScale + 0.001 {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        mediaView
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        pinchActive = true
        reportZoom()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard !updatingLayout else { return }
        centerContent()
        reportZoom()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        pinchActive = false
        centerContent()
        reportZoom()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { reportZoom(force: true) }
    }

    func stopReportingZoom() {
        onZoomChange(false)
        onZoomChange = { _ in }
    }

    func toggleZoom(at point: CGPoint, animated: Bool) {
        let target = zoomScale > minimumZoomScale + 0.001 ? minimumZoomScale : min(2.5, maximumZoomScale)
        let size = CGSize(width: bounds.width / target, height: bounds.height / target)
        let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                          width: size.width, height: size.height)
        zoom(to: rect, animated: animated)
    }

    private func refitContent(to size: CGSize) {
        updatingLayout = true
        defer { updatingLayout = false }
        let previousSize = mediaView.bounds.size
        let center = mediaView.convert(CGPoint(x: bounds.midX, y: bounds.midY), from: self)
        let relativeCenter = CGPoint(x: previousSize.width > 0 ? center.x / previousSize.width : 0.5,
                                     y: previousSize.height > 0 ? center.y / previousSize.height : 0.5)
        let previousScale = min(max(zoomScale, minimumZoomScale), maximumZoomScale)
        setZoomScale(minimumZoomScale, animated: false)
        mediaView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        setZoomScale(previousScale, animated: false)
        centerContent()
        let desired = CGPoint(x: relativeCenter.x * size.width * zoomScale - bounds.width / 2,
                              y: relativeCenter.y * size.height * zoomScale - bounds.height / 2)
        let maxX = max(-contentInset.left, contentSize.width - bounds.width + contentInset.right)
        let maxY = max(-contentInset.top, contentSize.height - bounds.height + contentInset.bottom)
        contentOffset = CGPoint(x: min(max(desired.x, -contentInset.left), maxX),
                                y: min(max(desired.y, -contentInset.top), maxY))
    }

    private func centerContent() {
        let horizontal = max((bounds.width - mediaView.frame.width) / 2, 0)
        let vertical = max((bounds.height - mediaView.frame.height) / 2, 0)
        let insets = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != insets { contentInset = insets }
    }

    private func reportZoom(force: Bool = false) {
        let active = pinchActive || zoomScale > minimumZoomScale + 0.001
        guard force || lastReportedZoom != active else { return }
        lastReportedZoom = active
        DispatchQueue.main.async { [weak self] in
            self?.onZoomChange(active)
        }
    }

    @objc private func didDoubleTap(_ recognizer: UITapGestureRecognizer) {
        toggleZoom(at: recognizer.location(in: mediaView), animated: true)
    }

    @objc private func didSingleTap() {
        onSingleTap()
    }

    @objc private func loadLivePhoto() {
        onLivePhoto()
    }
}

private final class PreviewTapDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UIControl { return false }
            view = current.superview
        }
        return true
    }
}

@available(iOS 17.0, *)
private final class PreviewMediaView: UIView {
    let imageView = UIImageView()
    let livePhotoButton = UIButton(type: .system)
    private let livePhotoView = PHLivePhotoView()
    private let activity = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        livePhotoView.contentMode = .scaleAspectFit
        livePhotoView.isMuted = false
        livePhotoView.isHidden = true
        livePhotoButton.tintColor = .white
        livePhotoButton.setImage(UIImage(systemName: "livephoto"), for: .normal)
        activity.color = .white
        activity.hidesWhenStopped = true
        addSubview(imageView)
        addSubview(livePhotoView)
        addSubview(livePhotoButton)
        addSubview(activity)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(image: UIImage, livePhoto: PHLivePhoto?, showsLivePhotoButton: Bool, isLoadingLivePhoto: Bool) {
        imageView.image = image
        if livePhotoView.livePhoto !== livePhoto { livePhotoView.livePhoto = livePhoto }
        livePhotoView.isHidden = livePhoto == nil
        imageView.isHidden = livePhoto != nil
        livePhotoButton.isHidden = !showsLivePhotoButton && livePhoto == nil
        livePhotoButton.isEnabled = livePhoto == nil && !isLoadingLivePhoto
        if isLoadingLivePhoto { activity.startAnimating() } else { activity.stopAnimating() }
        livePhotoButton.alpha = isLoadingLivePhoto ? 0 : 1
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        livePhotoView.frame = bounds
        let badge = CGRect(x: max(bounds.width - 44, 0), y: max(bounds.height - 44, 0), width: 44, height: 44)
        livePhotoButton.frame = badge
        activity.center = CGPoint(x: badge.midX, y: badge.midY)
    }
}
#endif
