import Testing
@testable import ImageKit
import Foundation

@Suite("Request behavior")
struct RequestBehaviorTests {
    @MainActor @Test
    func cacheSeparatesOutputDimensionsAndOriginal() throws {
        let url = URL(string: "https://example.com/\(UUID().uuidString).png")!
        let request = ImageRequest(url, size: .absolute(CGSize(width: 100, height: 50)))
        let image = try #require(TestImage.image(size: CGSize(width: 100, height: 50)))
        let cache = MemoryCache.shared
        cache.cache(image, for: request)
        #expect(try cache.image(for: request) === image)
        #expect(try cache.image(for: request.makeRequest(size: .absolute(CGSize(width: 100, height: 100)))) == nil)
        #expect(try cache.image(for: request.makeRequest(size: .original)) == nil)
        #expect(try cache.image(for: ImageRequest(url, size: request.size, mode: .fit)) == nil)
        #expect(try cache.image(for: ImageRequest(url, size: request.size, animation: .firstFrame)) == nil)
        #expect(try cache.image(for: ImageRequest(url, size: request.size, context: .init())) == nil)
    }

    @Test
    func legacyAnimationFlagMapsToExplicitPolicy() {
        let url = URL(string: "https://example.com/image")!
        #expect(ImageRequest(url, size: .original).animation == .automatic)
        #expect(ImageRequest(url, size: .original, isGif: false).animation == .firstFrame)
        #expect(ImageRequest(url, size: .original, isGif: true).animation == .animated)
        #expect(ImageRequest(url, size: .original, isGif: true, animation: .firstFrame).animation == .firstFrame)
        #expect(ImageRequest(url, size: .original, animation: .animated).makeRequest(size: .width(20)).animation == .animated)
    }

    @Test
    func identicalRequestsShareLoadingAndDifferentHeightsDoNot() async throws {
        let loader = ControlledLoader()
        let context = ImageRequest.Context(caches: [], processors: [], loaders: [loader])
        let url = URL(string: "test://\(UUID().uuidString)")!
        let request = ImageRequest(url, size: .absolute(CGSize(width: 40, height: 20)), caches: [], context: context)
        let first = Task { try await request.send() }
        let second = Task { try await request.send() }
        try await loader.waitForLoads(1)
        try await Task.sleep(nanoseconds: 20_000_000)
        await loader.releaseAll()
        _ = try await first.value
        _ = try await second.value
        #expect(await loader.count == 1)

        let shorter = Task { try await request.send() }
        let taller = Task { try await request.makeRequest(size: .absolute(CGSize(width: 40, height: 80))).send() }
        try await loader.waitForLoads(3)
        await loader.releaseAll()
        _ = try await shorter.value
        _ = try await taller.value
        #expect(await loader.count == 3)
    }

    @Test
    func cancellingOneSubscriberPreservesOtherSubscriber() async throws {
        let loader = ControlledLoader()
        let context = ImageRequest.Context(caches: [], processors: [], loaders: [loader])
        let request = ImageRequest(URL(string: "test://cancel-one")!, size: .original, caches: [], context: context)
        let first = Task { try await request.send() }
        let second = Task { try await request.send() }
        try await loader.waitForLoads(1)
        // Let both callers subscribe before cancelling either one.
        try await Task.sleep(nanoseconds: 20_000_000)
        first.cancel()
        do {
            _ = try await first.value
            Issue.record("Cancelled subscriber returned an image")
        } catch is CancellationError { }
        await loader.releaseAll()
        _ = try await second.value
        #expect(await loader.count == 1)
    }

    @Test
    func cancelledRequestCanBeRetriedWithoutOldCompletionRemovingNewWork() async throws {
        let loader = ControlledLoader()
        let context = ImageRequest.Context(caches: [], processors: [], loaders: [loader])
        let request = ImageRequest(URL(string: "test://retry")!, size: .original, caches: [], context: context)
        let first = Task { try await request.send() }
        try await loader.waitForLoads(1)
        first.cancel()
        do {
            _ = try await first.value
            Issue.record("Cancelled subscriber returned an image")
        } catch is CancellationError { }
        let second = Task { try await request.send() }
        try await loader.waitForLoads(2)
        await loader.releaseAll()
        _ = try await second.value
        #expect(await loader.count == 2)
    }

    @Test
    func cancellingLastSubscriberCancelsUnderlyingWork() async throws {
        let loader = ControlledLoader()
        let context = ImageRequest.Context(caches: [], processors: [], loaders: [loader])
        let request = ImageRequest(URL(string: "test://cancel-last")!, size: .original, caches: [], context: context)
        let task = Task { try await request.send() }
        try await loader.waitForLoads(1)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled subscriber returned an image")
        } catch is CancellationError { }
        try await loader.waitForCancellation()
        await loader.releaseAll()
    }
}

private actor ControlledLoader: DataLoader {
    private(set) var count = 0
    private var cancellationCount = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    nonisolated func isValid(request: ImageRequest) -> Bool { true }

    func load(request: ImageRequest) async -> LoadResult? {
        count += 1
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuations.append($0) }
        } onCancel: {
            Task { await self.recordCancellation() }
        }
        return TestImage.image(size: CGSize(width: 10, height: 10)).map(LoadResult.image)
    }

    func waitForLoads(_ target: Int) async throws {
        for _ in 0..<200 {
            if count >= target { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw URLError(.timedOut)
    }

    func releaseAll() {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }

    func waitForCancellation() async throws {
        for _ in 0..<200 {
            if cancellationCount > 0 { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw URLError(.timedOut)
    }

    private func recordCancellation() {
        cancellationCount += 1
    }
}
