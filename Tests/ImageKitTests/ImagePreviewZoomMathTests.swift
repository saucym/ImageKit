import XCTest
@testable import ImageKit

final class ImagePreviewZoomMathTests: XCTestCase {
    func testAspectFitCentersInsideBounds() {
        let bounds = CGRect(x: 10, y: 20, width: 200, height: 100)
        let wide = ImagePreviewZoomMath.aspectFit(CGSize(width: 400, height: 100), in: bounds)
        XCTAssertEqual(wide.width, 200, accuracy: 0.01)
        XCTAssertEqual(wide.height, 50, accuracy: 0.01)
        XCTAssertEqual(wide.midX, bounds.midX, accuracy: 0.01)
        XCTAssertEqual(wide.midY, bounds.midY, accuracy: 0.01)

        let tall = ImagePreviewZoomMath.aspectFit(CGSize(width: 100, height: 400), in: bounds)
        XCTAssertEqual(tall.width, 25, accuracy: 0.01)
        XCTAssertEqual(tall.height, 100, accuracy: 0.01)
        XCTAssertEqual(tall.midX, bounds.midX, accuracy: 0.01)
    }

    func testAspectFillCoversBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 40, height: 40)
        let rect = ImagePreviewZoomMath.aspectFill(CGSize(width: 80, height: 40), in: bounds)
        XCTAssertGreaterThanOrEqual(rect.width, bounds.width - 0.01)
        XCTAssertGreaterThanOrEqual(rect.height, bounds.height - 0.01)
        XCTAssertEqual(rect.midX, bounds.midX, accuracy: 0.01)
        XCTAssertEqual(rect.midY, bounds.midY, accuracy: 0.01)
        XCTAssertEqual(rect.width / rect.height, 2, accuracy: 0.01)
    }

    func testLerpEndpoints() {
        let start = CGRect(x: 0, y: 0, width: 10, height: 20)
        let end = CGRect(x: 10, y: 30, width: 40, height: 60)
        XCTAssertEqual(ImagePreviewZoomMath.lerp(start, end, 0), start)
        XCTAssertEqual(ImagePreviewZoomMath.lerp(start, end, 1), end)
        let mid = ImagePreviewZoomMath.lerp(start, end, 0.5)
        XCTAssertEqual(mid, CGRect(x: 5, y: 15, width: 25, height: 40))
    }

    func testWideImageCenterCropIsTheMiddleOfTheFittedImage() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let image = CGSize(width: 2000, height: 1000)
        let fit = ImagePreviewZoomMath.aspectFit(image, in: bounds)
        let crop = ImagePreviewZoomMath.centerCrop(of: image, in: bounds)
        XCTAssertEqual(crop.width, fit.height, accuracy: 0.01)
        XCTAssertEqual(crop.height, fit.height, accuracy: 0.01)
        XCTAssertEqual(crop.midX, fit.midX, accuracy: 0.01)
        XCTAssertEqual(crop.midY, fit.midY, accuracy: 0.01)
        XCTAssertTrue(ImagePreviewZoomMath.usesCenterCrop(bitmap: CGSize(width: 32, height: 32), full: image))
    }

    func testTallImageCenterCropIsTheMiddleOfTheFittedImage() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let image = CGSize(width: 1000, height: 2000)
        let fit = ImagePreviewZoomMath.aspectFit(image, in: bounds)
        let crop = ImagePreviewZoomMath.centerCrop(of: image, in: bounds)
        XCTAssertEqual(crop.width, fit.width, accuracy: 0.01)
        XCTAssertEqual(crop.height, fit.width, accuracy: 0.01)
        XCTAssertEqual(crop.midX, fit.midX, accuracy: 0.01)
        XCTAssertEqual(crop.midY, fit.midY, accuracy: 0.01)
    }

    func testMatchingAspectDoesNotUseCenterCrop() {
        let full = CGSize(width: 2000, height: 1000)
        XCTAssertFalse(ImagePreviewZoomMath.usesCenterCrop(bitmap: CGSize(width: 200, height: 100), full: full))
        XCTAssertFalse(ImagePreviewZoomMath.usesCenterCrop(bitmap: CGSize(width: 40, height: 40), full: CGSize(width: 800, height: 800)))
    }

    func testDragKeepsCenterXAndScalesAroundTheOriginalCenter() {
        let rect = CGRect(x: 100, y: 200, width: 80, height: 120)
        let dragged = ImagePreviewZoomMath.dragged(rect, offsetY: 100)
        let scale = 1 - 100.0 / 1000.0
        XCTAssertEqual(dragged.width, rect.width * scale, accuracy: 0.01)
        XCTAssertEqual(dragged.height, rect.height * scale, accuracy: 0.01)
        XCTAssertEqual(dragged.midX, rect.midX, accuracy: 0.01)
        XCTAssertEqual(dragged.midY, rect.midY + 100 * scale, accuracy: 0.01)
    }
}

@MainActor
final class ImagePreviewZoomModelTests: XCTestCase {
    func testVisibleFrameDoesNotScroll() async {
        let model = ImagePreviewZoomModel()
        let frame = CGRect(x: 10, y: 10, width: 20, height: 20)
        model.setViewport(CGRect(x: 0, y: 0, width: 100, height: 100))
        model.setFrame(frame, for: "a")
        let scrolled = Flag()
        model.setScrollHandler { _ in scrolled.value = true }
        let revealed = await model.revealFrame(for: "a")
        XCTAssertEqual(revealed, frame)
        XCTAssertFalse(scrolled.value)
    }

    func testOffscreenFrameScrollsUntilItBecomesVisible() async {
        let model = ImagePreviewZoomModel()
        model.setViewport(CGRect(x: 0, y: 0, width: 100, height: 100))
        let landed = CGRect(x: 30, y: 40, width: 20, height: 20)
        let scrolled = Flag()
        model.setScrollHandler { id in
            XCTAssertEqual(id, "b")
            scrolled.value = true
            model.setFrame(landed, for: id)
        }
        let revealed = await model.revealFrame(for: "b")
        XCTAssertTrue(scrolled.value)
        XCTAssertEqual(revealed, landed)
    }

    func testPartiallyVisibleFrameIsScrolledFullyIntoView() async {
        let model = ImagePreviewZoomModel()
        model.setViewport(CGRect(x: 0, y: 0, width: 100, height: 100))
        model.setFrame(CGRect(x: 90, y: 10, width: 20, height: 20), for: "c")
        let landed = CGRect(x: 40, y: 40, width: 20, height: 20)
        model.setScrollHandler { id in
            model.setFrame(landed, for: id)
        }
        let revealed = await model.revealFrame(for: "c")
        XCTAssertEqual(revealed, landed)
    }
}

private final class Flag {
    var value = false
}
