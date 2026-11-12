//
//  ImagePreviewZoom.swift
//  ImageKit
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// 列表缩略图的窗口坐标。预览打开和关闭时用来把图片从格子放大、再缩回去。
@MainActor
public final class ImagePreviewZoomModel {
    private var frames: [String: CGRect] = [:]
    private var viewport: CGRect?
    private var scrollHandler: ((String) -> Void)?
    #if os(iOS)
    private var previewImages: [String: UIImage] = [:]
    #endif

    public init() {}

    public func setFrame(_ frame: CGRect, for id: String) {
        guard frame.width > 1, frame.height > 1, frame.minX.isFinite, frame.minY.isFinite else { return }
        frames[id] = frame
    }

    public func removeFrame(for id: String) {
        frames.removeValue(forKey: id)
    }

    public func frame(for id: String) -> CGRect? {
        frames[id]
    }

    public func setViewport(_ viewport: CGRect) {
        guard viewport.width > 1, viewport.height > 1 else { return }
        self.viewport = viewport
    }

    public func setScrollHandler(_ handler: @escaping (String) -> Void) {
        scrollHandler = handler
    }

    #if os(iOS)
    public func setPreviewImage(_ image: UIImage, for id: String) {
        guard image.size.width > 1, image.size.height > 1 else { return }
        previewImages[id] = image
    }

    public func previewImage(for id: String) -> UIImage? {
        previewImages[id]
    }
    #endif

    /// 已经在列表可见区域内的格子，关闭动画可以立刻用，不用再等滚动。
    public func visibleFrame(for id: String) -> CGRect? {
        guard let frame = frame(for: id), frame.width > 1, frame.height > 1 else { return nil }
        guard let viewport, viewport.width > 1 else { return frame }
        return viewport.insetBy(dx: -1, dy: -1).contains(frame) ? frame : nil
    }

    /// 目标格已经完整露在列表里就直接用它的位置；否则先滚动，等它出现再返回。
    public func revealFrame(for id: String) async -> CGRect? {
        if let frame = visibleFrame(for: id) {
            return frame
        }
        scrollHandler?(id)
        for attempt in 0..<30 {
            try? await Task.sleep(nanoseconds: 16_000_000)
            if let frame = visibleFrame(for: id) {
                return frame
            }
            if attempt == 8 {
                scrollHandler?(id)
            }
        }
        guard let frame = frame(for: id) else { return nil }
        if let viewport {
            return viewport.intersects(frame) ? frame : nil
        }
        return frame
    }
}

public struct ImagePreviewDismissAction {
    public let run: () -> Void
    public init(_ run: @escaping () -> Void) { self.run = run }
}

private struct ImagePreviewZoomKey: EnvironmentKey {
    static let defaultValue: ImagePreviewZoomModel? = nil
}

private struct ImagePreviewDismissKey: EnvironmentKey {
    static let defaultValue: ImagePreviewDismissAction? = nil
}

private struct AllowsPreviewRevealKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    var imagePreviewZoom: ImagePreviewZoomModel? {
        get { self[ImagePreviewZoomKey.self] }
        set { self[ImagePreviewZoomKey.self] = newValue }
    }

    var imagePreviewDismiss: ImagePreviewDismissAction? {
        get { self[ImagePreviewDismissKey.self] }
        set { self[ImagePreviewDismissKey.self] = newValue }
    }

    var allowsPreviewReveal: Bool {
        get { self[AllowsPreviewRevealKey.self] }
        set { self[AllowsPreviewRevealKey.self] = newValue }
    }
}

enum ImagePreviewZoomMath {
    static func aspectFit(_ image: CGSize, in bounds: CGRect) -> CGRect {
        placed(image, in: bounds, fill: false)
    }

    static func aspectFill(_ image: CGSize, in bounds: CGRect) -> CGRect {
        placed(image, in: bounds, fill: true)
    }

    static func lerp(_ a: CGRect, _ b: CGRect, _ progress: CGFloat) -> CGRect {
        let t = min(max(progress, 0), 1)
        return CGRect(
            x: a.minX + (b.minX - a.minX) * t,
            y: a.minY + (b.minY - a.minY) * t,
            width: a.width + (b.width - a.width) * t,
            height: a.height + (b.height - a.height) * t
        )
    }

    /// 跟预览页下拉时的 offset + scale 对齐，scale 包在 offset 外面。
    /// 列表缩略图是正方形居中裁切。宽图或长图在预览里适配之后，这块裁切落在最终画面的正中间。
    static func centerCrop(of image: CGSize, in bounds: CGRect) -> CGRect {
        let fit = aspectFit(image, in: bounds)
        guard image.width > 0, image.height > 0, fit.width > 0 else { return fit }
        let side = min(image.width, image.height)
        let scale = fit.width / image.width
        let length = side * scale
        let originX = (image.width - side) / 2 * scale
        let originY = (image.height - side) / 2 * scale
        return CGRect(x: fit.minX + originX, y: fit.minY + originY, width: length, height: length)
    }

    static func usesCenterCrop(bitmap: CGSize, full: CGSize) -> Bool {
        guard bitmap.width > 1, bitmap.height > 1, full.width > 1, full.height > 1 else { return false }
        let bitmapAspect = bitmap.width / bitmap.height
        let fullAspect = full.width / full.height
        return abs(bitmapAspect - 1) < 0.08 && abs(bitmapAspect - fullAspect) >= 0.08
    }

    static func dragged(_ rect: CGRect, offsetY: CGFloat) -> CGRect {
        let scale = max(0.2, 1 - offsetY / 1000)
        let size = CGSize(width: rect.width * scale, height: rect.height * scale)
        let center = CGPoint(x: rect.midX, y: rect.midY + offsetY * scale)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    private static func placed(_ image: CGSize, in bounds: CGRect, fill: Bool) -> CGRect {
        guard image.width > 0, image.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = fill
            ? max(bounds.width / image.width, bounds.height / image.height)
            : min(bounds.width / image.width, bounds.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
}

#if os(iOS)
@available(iOS 17.0, *)
extension OnlinePreviewView.Item {
    func previewBitmap(preferOriginal: Bool) -> UIImage? {
        if preferOriginal {
            return originalBitmap() ?? thumbnailBitmap()
        }
        return thumbnailBitmap() ?? originalBitmap()
    }

    func originalBitmap() -> UIImage? {
        bitmap(loader.result.value)
    }

    func thumbnailBitmap() -> UIImage? {
        bitmap(thumbnail?.result.value)
    }

    private func bitmap(_ phase: ImagePhase?) -> UIImage? {
        guard case .success(let image) = phase else { return nil }
        guard image.size.width > 1, image.size.height > 1 else { return nil }
        return image
    }
}

struct PreviewHeroRepresentable: UIViewRepresentable {
    let image: UIImage
    let sourceCell: CGRect
    let dragOffset: CGFloat
    let layoutSize: CGSize?
    let from: CGFloat
    let to: CGFloat
    let duration: TimeInterval
    let dimPeak: CGFloat
    let onSettled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PreviewHeroView {
        PreviewHeroView()
    }

    func updateUIView(_ view: PreviewHeroView, context: Context) {
        context.coordinator.onSettled = onSettled
        guard sourceCell.width > 1, sourceCell.height > 1 else { return }
        view.play(image: image,
                  sourceCell: sourceCell,
                  dragOffset: dragOffset,
                  layoutSize: layoutSize,
                  from: from,
                  to: to,
                  duration: duration,
                  dimPeak: dimPeak) {
            context.coordinator.onSettled()
        }
    }

    final class Coordinator {
        var onSettled: () -> Void = {}
    }
}

final class PreviewHeroView: UIView {
    private let blackView = UIView()
    private let clipView = UIView()
    private let imageView = UIImageView()
    private let linkBox = PreviewHeroLinkBox()
    private var link: CADisplayLink?
    private var started = false
    private var pending: Pending?
    private var completion: (() -> Void)?
    private var fromImage = CGRect.zero
    private var toImage = CGRect.zero
    private var fromClip = CGRect.zero
    private var toClip = CGRect.zero
    private var dimPeak: CGFloat = 1
    private var animFrom: CGFloat = 0
    private var animTo: CGFloat = 1
    private var animStart: CFTimeInterval = 0
    private var animDuration: CFTimeInterval = 0.42

    private struct Pending {
        let image: UIImage
        let sourceCell: CGRect
        let dragOffset: CGFloat
        let layoutSize: CGSize?
        let from: CGFloat
        let to: CGFloat
        let duration: TimeInterval
        let dimPeak: CGFloat
        let completion: () -> Void
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        blackView.backgroundColor = .black
        blackView.isUserInteractionEnabled = false
        clipView.clipsToBounds = true
        clipView.isUserInteractionEnabled = false
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = false
        addSubview(blackView)
        addSubview(clipView)
        clipView.addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    deinit {
        link?.invalidate()
    }

    func play(image: UIImage,
              sourceCell: CGRect,
              dragOffset: CGFloat,
              layoutSize: CGSize?,
              from: CGFloat,
              to: CGFloat,
              duration: TimeInterval,
              dimPeak: CGFloat,
              completion: @escaping () -> Void) {
        guard !started else { return }
        pending = Pending(image: image,
                          sourceCell: sourceCell,
                          dragOffset: dragOffset,
                          layoutSize: layoutSize,
                          from: from,
                          to: to,
                          duration: duration,
                          dimPeak: dimPeak,
                          completion: completion)
        imageView.image = image
        setNeedsLayout()
        startIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blackView.frame = bounds
        startIfNeeded()
    }

    private func startIfNeeded() {
        guard !started, bounds.width > 1, bounds.height > 1, let pending else { return }
        started = true
        let fill = ImagePreviewZoomMath.aspectFill(pending.image.size, in: pending.sourceCell)
        let fit = ImagePreviewZoomMath.aspectFit(pending.image.size, in: bounds)
        let placed = pending.layoutSize.map { ImagePreviewZoomMath.centerCrop(of: $0, in: bounds) } ?? fit
        fromImage = fill
        toImage = pending.dragOffset > 1 ? ImagePreviewZoomMath.dragged(placed, offsetY: pending.dragOffset) : placed
        fromClip = pending.sourceCell
        toClip = bounds
        dimPeak = pending.dimPeak
        apply(pending.from)
        begin(from: pending.from, to: pending.to, duration: pending.duration, completion: pending.completion)
    }

    private func begin(from: CGFloat, to: CGFloat, duration: TimeInterval, completion: @escaping () -> Void) {
        animFrom = from
        animTo = to
        animDuration = max(duration, 0.01)
        animStart = CACurrentMediaTime()
        self.completion = completion
        linkBox.tick = { [weak self] in
            self?.step()
        }
        let link = CADisplayLink(target: linkBox, selector: #selector(PreviewHeroLinkBox.step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func step() {
        guard let link else { return }
        let raw = min(1, (CACurrentMediaTime() - animStart) / animDuration)
        let eased = 1 - pow(1 - raw, 3)
        apply(animFrom + (animTo - animFrom) * CGFloat(eased))
        guard raw >= 1 else { return }
        link.invalidate()
        self.link = nil
        let done = self.completion
        self.completion = nil
        DispatchQueue.main.async {
            done?()
        }
    }

    private func apply(_ progress: CGFloat) {
        let t = min(max(progress, 0), 1)
        let imageRect = ImagePreviewZoomMath.lerp(fromImage, toImage, t)
        let clipRect = ImagePreviewZoomMath.lerp(fromClip, toClip, t)
        guard clipRect.width > 0.5, clipRect.height > 0.5 else { return }
        blackView.alpha = dimPeak * min(1, t / 0.72)
        clipView.frame = clipRect
        imageView.frame = imageRect.offsetBy(dx: -clipRect.minX, dy: -clipRect.minY)
    }
}

private final class PreviewHeroLinkBox: NSObject {
    var tick: (() -> Void)?
    @objc func step() { tick?() }
}
#endif
