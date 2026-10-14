import Testing
import SwiftUI
import ImageKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Suite("Public image views")
@MainActor
struct PublicAPITests {
    @Test
    func requestAndLegacyInitializersCompile() {
        let request = ImageRequest(URL(string: "https://example.com/image")!, size: .original)
        let loader = URLImageLoader(request)
        _ = ImageView(request: request)
        _ = ImageView(url: request.url, size: request.size)
        _ = ImageView(loader: loader)
        _ = ImageCustomView(request: request) { _ in EmptyView() }
        _ = ImageCustomView(url: request.url, size: request.size) { _ in EmptyView() }
        _ = ImageCustomView(url: request.url, size: request.size) { _, _ in EmptyView() }
        _ = ImageCustomView(loader: loader) { _ in EmptyView() }
        _ = ImageCustomView(loader: loader) { _, _ in EmptyView() }
    }

    @Test
    func cancellingLoaderDoesNotPublishAndCanRestart() async throws {
        let source = ControlledViewLoader()
        let request = makeRequest(source: source)
        let loader = URLImageLoader(request)
        let first = Task { await loader.loadImage() }
        await source.waitForStarts(1)
        loader.cancel()
        await first.value
        #expect(isEmpty(loader.result.value))

        let second = Task { await loader.loadImage() }
        await source.waitForStarts(2)
        await source.completeNext(with: try #require(TestImage.image(size: CGSize(width: 3, height: 3))))
        #expect(isEmpty(loader.result.value))
        await source.completeNext(with: try #require(TestImage.image(size: CGSize(width: 7, height: 7))))
        await second.value
        guard case .success(let image) = loader.result.value else {
            Issue.record("restarted loader must publish its own result")
            return
        }
        #expect(image.size.width == 7)
    }

    @Test
    func cancellingCallerLeavesLoaderEmpty() async throws {
        let source = ControlledViewLoader()
        let loader = URLImageLoader(makeRequest(source: source))
        let task = Task { await loader.loadImage() }
        await source.waitForStarts(1)
        task.cancel()
        await task.value
        #expect(isEmpty(loader.result.value))
        await source.completeNext(with: try #require(TestImage.image(size: CGSize(width: 3, height: 3))))
        #expect(isEmpty(loader.result.value))
    }

    @Test
    func imageViewCancellationAndReplacementRejectOldResult() async throws {
        let source = ControlledViewLoader()
        let request = makeRequest(source: source)
        let view = KKImageView(frame: .zero)
        view.setImage(request: request)
        await source.waitForStarts(1)
        view.setImage(request: makeRequest(source: source))
        await source.waitForStarts(2)
        await source.completeNext(with: try #require(TestImage.image(size: CGSize(width: 3, height: 3))))
        #expect(view.image == nil)
        await source.completeNext(with: try #require(TestImage.image(size: CGSize(width: 7, height: 7))))
        #expect(await eventually { view.image?.size.width == 7 })

        view.setImage(request: request)
        await source.waitForStarts(3)
        view.cancelImageLoad()
        await source.completeNext(with: try #require(TestImage.image(size: CGSize(width: 11, height: 11))))
        #expect(view.image == nil)
    }

    #if os(macOS)
    @Test
    func completedLoaderIsCancelledWhenItsViewDisappears() async throws {
        let image = try #require(TestImage.image(size: CGSize(width: 3, height: 3)))
        let loader = CompletedViewLoader(image: image)
        let snapshot = PhaseSnapshot()
        let hostingView = NSHostingView(rootView:
            ImageCustomView(loader: loader) { _ in
                Color.clear.onAppear { snapshot.value = "appeared" }
            }
        )
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        defer { window.close() }
        #expect(await eventually { snapshot.value == "appeared" })
        // Let the success-only .task finish before removing the view.
        try await Task.sleep(for: .milliseconds(20))
        #expect(loader.cancelCount == 0)
        hostingView.removeFromSuperview()
        window.contentView = nil
        #expect(await eventually { loader.cancelCount > 0 })
    }

    @Test
    func defaultViewHonorsFitAndFill() throws {
        guard #available(macOS 13.0, *) else { return }
        let image = try #require(TestImage.image(size: CGSize(width: 40, height: 20)))
        func topAlpha(mode: ContentMode) throws -> CGFloat {
            let request = ImageRequest(URL(string: "https://example.com/image")!,
                                       size: .absolute(CGSize(width: 40, height: 40)),
                                       mode: mode, processors: [], caches: [])
            let loader = URLImageLoader(request)
            loader.result.value = .success(image)
            let renderer = ImageRenderer(content: ImageView(loader: loader))
            renderer.scale = 1
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            return try #require(bitmap.colorAt(x: 20, y: 2)).alphaComponent
        }
        #expect(try topAlpha(mode: .fit) < 0.01)
        #expect(try topAlpha(mode: .fill) > 0.99)
    }

    @Test
    func requestViewRetainsStateAndReloadsResourceOptionsAndContext() async throws {
        let source = ControlledViewLoader()
        let request = makeRequest(source: source)
        let input = ViewInput(request: request)
        let snapshot = PhaseSnapshot()
        let hostingView = NSHostingView(rootView: RequestHarness(input: input, snapshot: snapshot))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        defer { window.close() }

        #expect(await eventually { await source.startCount == 1 })
        input.revision += 1
        hostingView.layoutSubtreeIfNeeded()
        await source.completeNext(with: try #require(TestImage.image(size: CGSize(width: 3, height: 3))))
        #expect(await eventually { snapshot.value == "success:3" })
        #expect(await source.startCount == 1)

        input.request = ImageRequest(URL(string: "https://example.com/other")!,
                                     size: .original, key: request.key,
                                     processors: [], caches: [], context: request.context)
        #expect(await eventually { await source.startCount == 2 })
        await source.completeNext(with: try #require(TestImage.image(size: CGSize(width: 5, height: 5))))
        #expect(await eventually { snapshot.value == "success:5" })

        input.request = ImageRequest(input.request.url, size: .original, mode: .fit,
                                     key: request.key, processors: [], caches: [],
                                     context: request.context, animation: .firstFrame)
        #expect(await eventually { await source.startCount == 3 })
        await source.completeNext(with: try #require(TestImage.image(size: CGSize(width: 7, height: 7))))
        #expect(await eventually { snapshot.value == "success:7" })

        input.request = ImageRequest(input.request.url,
                                     size: input.request.size,
                                     mode: input.request.mode,
                                     key: request.key, processors: [], caches: [],
                                     context: ImageRequest.Context(caches: [], processors: [], loaders: [source]),
                                     animation: input.request.animation)
        #expect(await eventually { await source.startCount == 4 })
        await source.completeNext(with: try #require(TestImage.image(size: CGSize(width: 9, height: 9))))
        #expect(await eventually { snapshot.value == "success:9" })
    }
    #endif

    private func makeRequest(source: ControlledViewLoader) -> ImageRequest {
        let context = ImageRequest.Context(caches: [], processors: [], loaders: [source])
        return ImageRequest(URL(string: "https://example.com/image")!, size: .original,
                            processors: [], caches: [], context: context)
    }

    private func isEmpty(_ phase: ImagePhase) -> Bool {
        if case .empty = phase { return true }
        return false
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

private actor ControlledViewLoader: DataLoader {
    private var continuations = [CheckedContinuation<LoadResult?, Never>]()
    private var startWaiters = [(count: Int, continuation: CheckedContinuation<Void, Never>)]()
    private(set) var startCount = 0

    nonisolated func isValid(request: ImageRequest) -> Bool { true }

    func load(request: ImageRequest) async -> LoadResult? {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
            startCount += 1
            let ready = startWaiters.filter { $0.count <= startCount }
            startWaiters.removeAll { $0.count <= startCount }
            for waiter in ready { waiter.continuation.resume() }
        }
    }

    func waitForStarts(_ count: Int) async {
        if startCount >= count { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((count, continuation))
        }
    }

    func completeNext(with image: KKImage) {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume(returning: .image(image))
    }
}

#if os(macOS)
private final class CompletedViewLoader: ImageLoading {
    let request = ImageRequest(URL(string: "https://example.com/image")!, size: .original)
    let result = ImageResult()
    private let lock = NSLock()
    private var cancellations = 0

    @MainActor init(image: KKImage) {
        result.value = .success(image)
    }

    var cancelCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cancellations
    }

    func loadImage() async { }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancellations += 1
    }
}

@MainActor
private final class ViewInput: ObservableObject {
    @Published var request: ImageRequest
    @Published var revision = 0

    init(request: ImageRequest) { self.request = request }
}

@MainActor
private final class PhaseSnapshot {
    var value = ""
}

private struct RequestHarness: View {
    @ObservedObject var input: ViewInput
    let snapshot: PhaseSnapshot

    var body: some View {
        VStack {
            ImageCustomView(request: input.request) { phase in
                let value = description(phase)
                Text(value)
                    .onAppear { snapshot.value = value }
                    .onChange(of: value) { snapshot.value = $0 }
            }
            Text("\(input.revision)")
        }
    }

    private func description(_ phase: ImagePhase) -> String {
        switch phase {
        case .empty: "empty"
        case .failure: "failure"
        case .success(let image): "success:\(Int(image.size.width))"
        }
    }
}
#endif
