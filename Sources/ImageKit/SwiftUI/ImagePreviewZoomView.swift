#if os(iOS)
import SwiftUI
import UIKit
import PhotosUI

@available(iOS 17.0, *)
struct ImagePreviewZoomView: UIViewRepresentable {
    let image: UIImage
    var cropLayoutSize: CGSize? = nil
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
        view.update(image: image, cropLayoutSize: cropLayoutSize, livePhoto: livePhoto,
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
    private var fittedZoomActive = false
    private var cropLayoutSize: CGSize?

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

    func update(image: UIImage, cropLayoutSize: CGSize? = nil, livePhoto: PHLivePhoto? = nil,
                showsLivePhotoButton: Bool = false, isLoadingLivePhoto: Bool = false,
                onSingleTap: @escaping () -> Void = {}, onLivePhoto: @escaping () -> Void = {},
                onZoomChange: @escaping (Bool) -> Void = { _ in }) {
        self.onSingleTap = onSingleTap
        self.onLivePhoto = onLivePhoto
        self.onZoomChange = onZoomChange
        isScrollEnabled = true
        if mediaView.isRevealingImage {
            return
        }
        let finishingCrop = self.cropLayoutSize != nil && cropLayoutSize == nil
            && !pinchActive && zoomScale <= minimumZoomScale + 0.001
        if finishingCrop {
            let previous = self.cropLayoutSize
            self.cropLayoutSize = nil
            mediaView.revealFullImage(image, fullPixelSize: previous)
            setNeedsLayout()
            return
        }
        self.cropLayoutSize = cropLayoutSize
        mediaView.fullPixelSize = cropLayoutSize
        mediaView.update(image: image, livePhoto: livePhoto,
                         showsLivePhotoButton: showsLivePhotoButton, isLoadingLivePhoto: isLoadingLivePhoto)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !updatingLayout, !fittedZoomActive, !isZooming, bounds.width > 0, bounds.height > 0,
              let image = mediaView.imageView.image, image.size.width > 0, image.size.height > 0 else { return }
        let layoutSize = cropLayoutSize ?? mediaView.fullPixelSize ?? image.size
        let fit = min(bounds.width / layoutSize.width, bounds.height / layoutSize.height)
        let size = CGSize(width: layoutSize.width * fit, height: layoutSize.height * fit)
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
        if zoomScale > minimumZoomScale + 0.001 {
            setZoomScaleFitted(animated: animated)
            return
        }
        let target = min(2.5, maximumZoomScale)
        let contentBounds = mediaView.bounds
        guard target > minimumZoomScale, bounds.width > 1, bounds.height > 1,
              contentBounds.width > 1, contentBounds.height > 1 else { return }
        let size = CGSize(width: min(bounds.width / target, contentBounds.width),
                          height: min(bounds.height / target, contentBounds.height))
        let origin = CGPoint(
            x: min(max(contentBounds.minX, point.x - size.width / 2), contentBounds.maxX - size.width),
            y: min(max(contentBounds.minY, point.y - size.height / 2), contentBounds.maxY - size.height)
        )
        zoom(to: CGRect(origin: origin, size: size), animated: animated)
    }

    /// 缩放和位移放进同一次动画。系统的 setZoomScale(animated:) 会先把内容甩到新偏移上，再开始缩小。
    private func setZoomScaleFitted(animated: Bool) {
        let fitSize = mediaView.bounds.size
        let insetX = max((bounds.width - fitSize.width) / 2, 0)
        let insetY = max((bounds.height - fitSize.height) / 2, 0)
        let endInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
        let endOffset = CGPoint(x: -insetX, y: -insetY)
        let updates = {
            self.fittedZoomActive = true
            self.zoomScale = self.minimumZoomScale
            self.contentInset = endInset
            self.contentOffset = endOffset
        }
        let finish = {
            self.fittedZoomActive = false
            self.pinchActive = false
            self.centerContent()
            self.reportZoom()
        }
        guard animated else {
            updates()
            finish()
            return
        }
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction], animations: updates) { _ in
            finish()
        }
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
        guard contentInset != insets else { return }
        let wasUpdating = updatingLayout
        updatingLayout = true
        contentInset = insets
        updatingLayout = wasUpdating
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
    var fullPixelSize: CGSize?
    private let livePhotoView = PHLivePhotoView()
    private let activity = UIActivityIndicatorView(style: .medium)
    private var isRevealing = false
    var isRevealingImage: Bool { isRevealing }
    private var revealWork: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
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

    func revealFullImage(_ image: UIImage, fullPixelSize: CGSize?) {
        self.fullPixelSize = fullPixelSize
        isRevealing = true
        let crop = fullPixelSize.map { Self.centerCrop($0, in: bounds) } ?? imageView.frame
        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.path = UIBezierPath(rect: crop).cgPath
        imageView.layer.mask = mask
        imageView.frame = bounds
        imageView.contentMode = .scaleAspectFit
        UIView.transition(with: imageView, duration: 0.22, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.imageView.image = image
        } completion: { _ in
            guard let path = mask.path else {
                self.finishReveal()
                return
            }
            let target = UIBezierPath(rect: self.bounds).cgPath
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = path
            animation.toValue = target
            animation.duration = 0.32
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            mask.add(animation, forKey: "reveal")
            mask.path = target
            self.revealWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.finishReveal()
            }
            self.revealWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + animation.duration, execute: work)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !isRevealing {
            imageView.contentMode = .scaleAspectFit
            imageView.frame = bounds
        }
        livePhotoView.frame = bounds
        let badge = CGRect(x: max(bounds.width - 44, 0), y: max(bounds.height - 44, 0), width: 44, height: 44)
        livePhotoButton.frame = badge
        activity.center = CGPoint(x: badge.midX, y: badge.midY)
    }

    private func finishReveal() {
        imageView.layer.mask = nil
        imageView.contentMode = .scaleAspectFit
        imageView.frame = bounds
        isRevealing = false
        fullPixelSize = nil
    }

    private static func centerCrop(_ image: CGSize, in bounds: CGRect) -> CGRect {
        guard image.width > 0, image.height > 0, bounds.width > 0 else { return bounds }
        let side = min(image.width, image.height)
        let scale = bounds.width / image.width
        let length = side * scale
        return CGRect(x: (image.width - side) / 2 * scale,
                      y: (image.height - side) / 2 * scale,
                      width: length,
                      height: length)
    }
}
#endif
