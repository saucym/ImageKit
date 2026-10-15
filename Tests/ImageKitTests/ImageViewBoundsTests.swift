import Testing
import ImageKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Suite("Image view bounds")
@MainActor
struct ImageViewBoundsTests {
    @Test
    func installingImageLoaderLeavesOtherViewBoundsSafe() throws {
        let image = try #require(TestImage.image(size: CGSize(width: 4, height: 4)))
        let source = BoundsRecordingLoader(image: image)
        let context = ImageRequest.Context(caches: [], processors: [], loaders: [source])
        let imageView = KKImageView(frame: .zero)
        imageView.setImage(request: ImageRequest(URL(string: "https://example.com/image")!,
                                                size: .original, processors: [], caches: [], context: context))
        defer { imageView.cancelImageLoad() }

        let view = KKView(frame: CGRect(x: 0, y: 0, width: 20, height: 30))
        let bounds = CGRect(x: 3, y: 5, width: 80, height: 90)
        view.bounds = bounds
        #expect(view.bounds == bounds)

        let scrollView = KKScrollView(frame: CGRect(x: 0, y: 0, width: 20, height: 30))
        scrollView.bounds = bounds
        #expect(scrollView.bounds == bounds)
    }

    @Test
    func absoluteRequestsReloadAfterImageViewResizes() async throws {
        try await verifyResize(initialSize: .absolute(CGSize(width: 20, height: 30)),
                               expectedHeights: [30, 90])
    }

    @Test
    func widthRequestsPreserveAspectSizingAfterImageViewResizes() async throws {
        try await verifyResize(initialSize: .width(20), expectedHeights: [nil, nil])
    }

    private func verifyResize(initialSize: ImageRequest.Size,
                              expectedHeights: [CGFloat?]) async throws {
        let image = try #require(TestImage.image(size: CGSize(width: 4, height: 4)))
        let source = BoundsRecordingLoader(image: image)
        let context = ImageRequest.Context(caches: [], processors: [], loaders: [source])
        let view = KKImageView(frame: CGRect(x: 0, y: 0, width: 20, height: 30))
        view.setImage(request: ImageRequest(URL(string: "https://example.com/image")!,
                                           size: initialSize, processors: [], caches: [], context: context))
        defer { view.cancelImageLoad() }
        #expect(await eventually { await source.widths.count == 1 && view.image != nil })

        let resizedBounds = CGRect(x: 0, y: 0, width: 80, height: 90)
        view.bounds = resizedBounds
        #expect(view.bounds == resizedBounds)
        #expect(await eventually { await source.widths.count == 2 && view.image != nil })
        #expect(await source.widths == [20, 80])
        #expect(await source.heights == expectedHeights)
    }

    private func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return await condition()
    }
}

private actor BoundsRecordingLoader: DataLoader {
    private let image: KKImage
    private(set) var widths = [CGFloat?]()
    private(set) var heights = [CGFloat?]()

    init(image: KKImage) {
        self.image = image
    }

    nonisolated func isValid(request: ImageRequest) -> Bool { true }

    func load(request: ImageRequest) async -> LoadResult? {
        widths.append(request.size.width)
        heights.append(request.size.height)
        return .image(image)
    }
}
