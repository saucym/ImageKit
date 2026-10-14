#if os(iOS)
import XCTest
import UIKit
@testable import ImageKit

@available(iOS 17.0, *)
final class ImagePreviewZoomTests: XCTestCase {
    @MainActor func testAspectFitCentersWideAndTallImagesAcrossViewportShapes() throws {
        let cases: [(CGSize, CGSize)] = [
            (CGSize(width: 1200, height: 600), CGSize(width: 390, height: 844)),
            (CGSize(width: 600, height: 1600), CGSize(width: 390, height: 844)),
            (CGSize(width: 600, height: 1600), CGSize(width: 844, height: 390)),
            (CGSize(width: 1200, height: 600), CGSize(width: 844, height: 390))
        ]
        for (imageSize, viewportSize) in cases {
            let scrollView = makeScrollView(imageSize: imageSize, viewportSize: viewportSize)
            let content = try XCTUnwrap(scrollView.viewForZooming(in: scrollView))
            let fit = min(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
            XCTAssertEqual(content.bounds.width, imageSize.width * fit, accuracy: 0.01)
            XCTAssertEqual(content.bounds.height, imageSize.height * fit, accuracy: 0.01)
            let visibleContent = content.convert(content.bounds, to: scrollView)
            XCTAssertEqual(visibleContent.midX, scrollView.bounds.midX, accuracy: 1 / UIScreen.main.scale)
            XCTAssertEqual(visibleContent.midY, scrollView.bounds.midY, accuracy: 1 / UIScreen.main.scale)
            XCTAssertEqual(scrollView.zoomScale, 1, accuracy: 0.001)
        }
    }

    @MainActor func testNativeZoomCanImmediatelyReverseAfterReachingMaximum() throws {
        let scrollView = makeScrollView()
        XCTAssertEqual(scrollView.minimumZoomScale, 1)
        XCTAssertEqual(scrollView.maximumZoomScale, 4)
        XCTAssertTrue(try XCTUnwrap(scrollView.pinchGestureRecognizer).isEnabled)
        for _ in 0..<3 {
            scrollView.setZoomScale(scrollView.maximumZoomScale, animated: false)
            scrollView.layoutIfNeeded()
            XCTAssertEqual(scrollView.zoomScale, 4, accuracy: 0.001)
            scrollView.setZoomScale(3, animated: false)
            scrollView.layoutIfNeeded()
            XCTAssertEqual(scrollView.zoomScale, 3, accuracy: 0.001)
            scrollView.setZoomScale(1, animated: false)
            scrollView.layoutIfNeeded()
            XCTAssertEqual(scrollView.zoomScale, 1, accuracy: 0.001)
        }
    }

    @MainActor func testDoubleTapZoomCentersTappedContentPointAndTogglesBack() throws {
        let scrollView = makeScrollView()
        let content = try XCTUnwrap(scrollView.viewForZooming(in: scrollView))
        let tap = CGPoint(x: 130, y: 280)
        scrollView.toggleZoom(at: tap, animated: false)
        scrollView.layoutIfNeeded()
        XCTAssertEqual(scrollView.zoomScale, 2.5, accuracy: 0.001)
        let tappedPoint = content.convert(tap, to: scrollView)
        XCTAssertEqual(tappedPoint.x, scrollView.bounds.midX, accuracy: 0.1)
        XCTAssertEqual(tappedPoint.y, scrollView.bounds.midY, accuracy: 0.1)
        scrollView.toggleZoom(at: tap, animated: false)
        scrollView.layoutIfNeeded()
        XCTAssertEqual(scrollView.zoomScale, 1, accuracy: 0.001)
        let visibleContent = content.convert(content.bounds, to: scrollView)
        XCTAssertEqual(visibleContent.midX, scrollView.bounds.midX, accuracy: 1 / UIScreen.main.scale)
        XCTAssertEqual(visibleContent.midY, scrollView.bounds.midY, accuracy: 1 / UIScreen.main.scale)
    }

    @MainActor func testDoubleTapNearImageEdgeStaysWithinScrollableBounds() {
        let scrollView = makeScrollView()
        scrollView.toggleZoom(at: CGPoint(x: 2, y: 2), animated: false)
        scrollView.layoutIfNeeded()
        XCTAssertEqual(scrollView.zoomScale, 2.5, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(scrollView.contentOffset.x, -scrollView.adjustedContentInset.left - 0.1)
        XCTAssertGreaterThanOrEqual(scrollView.contentOffset.y, -scrollView.adjustedContentInset.top - 0.1)
        XCTAssertLessThanOrEqual(scrollView.contentOffset.x, max(-scrollView.adjustedContentInset.left, scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right) + 0.1)
        XCTAssertLessThanOrEqual(scrollView.contentOffset.y, max(-scrollView.adjustedContentInset.top, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom) + 0.1)
    }

    @MainActor func testSwiftUIUpdatesPreserveZoomScaleAndPanPosition() {
        let image = makeImage(size: CGSize(width: 600, height: 1200))
        let scrollView = ImagePreviewScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        scrollView.update(image: image)
        scrollView.layoutIfNeeded()
        scrollView.setZoomScale(2, animated: false)
        scrollView.setContentOffset(CGPoint(x: 110, y: 180), animated: false)
        let beforeOffset = scrollView.contentOffset
        for _ in 0..<5 {
            scrollView.update(image: image)
            scrollView.layoutIfNeeded()
            XCTAssertEqual(scrollView.zoomScale, 2, accuracy: 0.001)
            XCTAssertEqual(scrollView.contentOffset.x, beforeOffset.x, accuracy: 0.1)
            XCTAssertEqual(scrollView.contentOffset.y, beforeOffset.y, accuracy: 0.1)
        }
    }

    @MainActor func testHigherResolutionImagePreservesCurrentZoomAndPan() {
        let scrollView = makeScrollView(imageSize: CGSize(width: 300, height: 600))
        scrollView.setZoomScale(2.5, animated: false)
        scrollView.setContentOffset(CGPoint(x: 200, y: 350), animated: false)
        let beforeOffset = scrollView.contentOffset
        scrollView.update(image: makeImage(size: CGSize(width: 1200, height: 2400)))
        scrollView.layoutIfNeeded()
        XCTAssertEqual(scrollView.zoomScale, 2.5, accuracy: 0.001)
        XCTAssertEqual(scrollView.contentOffset.x, beforeOffset.x, accuracy: 0.1)
        XCTAssertEqual(scrollView.contentOffset.y, beforeOffset.y, accuracy: 0.1)
    }

    @MainActor func testViewportResizePreservesZoomFactorAndRefitsAtMinimum() throws {
        let scrollView = makeScrollView()
        scrollView.setZoomScale(2, animated: false)
        scrollView.frame.size = CGSize(width: 844, height: 390)
        scrollView.setNeedsLayout()
        scrollView.layoutIfNeeded()
        XCTAssertEqual(scrollView.zoomScale, 2, accuracy: 0.001)
        scrollView.setZoomScale(1, animated: false)
        scrollView.layoutIfNeeded()
        let content = try XCTUnwrap(scrollView.viewForZooming(in: scrollView))
        XCTAssertEqual(content.bounds.width, 195, accuracy: 0.1)
        XCTAssertEqual(content.bounds.height, 390, accuracy: 0.1)
        let visibleContent = content.convert(content.bounds, to: scrollView)
        XCTAssertEqual(visibleContent.midX, scrollView.bounds.midX, accuracy: 1 / UIScreen.main.scale)
        XCTAssertEqual(visibleContent.midY, scrollView.bounds.midY, accuracy: 1 / UIScreen.main.scale)
        scrollView.frame.size = CGSize(width: 390, height: 844)
        scrollView.setNeedsLayout()
        scrollView.layoutIfNeeded()
        XCTAssertEqual(content.bounds.width, 390, accuracy: 0.1)
        XCTAssertEqual(content.bounds.height, 780, accuracy: 0.1)
    }

    @MainActor private func makeScrollView(imageSize: CGSize = CGSize(width: 600, height: 1200), viewportSize: CGSize = CGSize(width: 390, height: 844)) -> ImagePreviewScrollView {
        let scrollView = ImagePreviewScrollView(frame: CGRect(origin: .zero, size: viewportSize))
        scrollView.update(image: makeImage(size: imageSize))
        scrollView.layoutIfNeeded()
        return scrollView
    }

    @MainActor private func makeImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

#endif
