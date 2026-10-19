import Foundation
import Testing
@testable import ImageKit

@Suite("Live Photo resources")
struct LivePhotoResourceTests {
    @Test
    func preparesBothContextsConcurrentlyWithoutDiskCache() async throws {
        let imageLoader = ControlledLiveResourceLoader()
        let videoLoader = ControlledLiveResourceLoader()
        let image = request("image.heic", loader: imageLoader)
        let video = request("video.mov", loader: videoLoader)
        let task = Task { try await LivePhotoResources.prepare(image: image, video: video) }
        try await imageLoader.waitForStarts(1)
        try await videoLoader.waitForStarts(1)
        await imageLoader.complete(1, with: .success(.data(Data([1, 2, 3]))))
        await videoLoader.complete(1, with: .success(.data(Data([4, 5, 6]))))
        let resources = try await task.value

        #expect(resources.urls.map(\.pathExtension) == ["heic", "mov"])
        #expect(try Data(contentsOf: resources.urls[0]) == Data([1, 2, 3]))
        #expect(try Data(contentsOf: resources.urls[1]) == Data([4, 5, 6]))
        #expect(resources.urls[0] != image.localPath())
        #expect(resources.urls[1] != video.localPath())
    }

    @Test
    func preservesFailureAndCancelsTheOtherResource() async throws {
        let imageLoader = ControlledLiveResourceLoader()
        let videoLoader = ControlledLiveResourceLoader()
        let task = Task {
            try await LivePhotoResources.prepare(image: request("image.jpg", loader: imageLoader),
                                                 video: request("video.mov", loader: videoLoader))
        }
        try await imageLoader.waitForStarts(1)
        try await videoLoader.waitForStarts(1)
        await videoLoader.complete(1, with: .failure(URLError(.timedOut)))

        do {
            _ = try await task.value
            Issue.record("Expected the original resource error")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        }
        #expect(await imageLoader.cancellationCount == 1)
    }

    @Test
    func cancellationReachesBothResourceLoaders() async throws {
        let imageLoader = ControlledLiveResourceLoader()
        let videoLoader = ControlledLiveResourceLoader()
        let task = Task {
            try await LivePhotoResources.prepare(image: request("image.jpg", loader: imageLoader),
                                                 video: request("video.mov", loader: videoLoader))
        }
        try await imageLoader.waitForStarts(1)
        try await videoLoader.waitForStarts(1)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError { }
        #expect(await imageLoader.cancellationCount == 1)
        #expect(await videoLoader.cancellationCount == 1)
    }

    @Test
    func rejectsDecodedImagesWithoutOriginalPairingMetadata() async throws {
        let imageLoader = ControlledLiveResourceLoader()
        let videoLoader = ControlledLiveResourceLoader()
        let image = request("image.jpg", loader: imageLoader)
        let task = Task {
            try await LivePhotoResources.prepare(image: image, video: request("video.mov", loader: videoLoader))
        }
        try await imageLoader.waitForStarts(1)
        try await videoLoader.waitForStarts(1)
        await imageLoader.complete(1, with: .success(.image(KKImage())))
        do {
            _ = try await task.value
            Issue.record("Expected an original-data error")
        } catch LivePhotoResourceError.originalDataRequired(let url) {
            #expect(url == image.url)
        }
        #expect(await videoLoader.cancellationCount == 1)
    }

    @Test
    func cachedCopiesSurviveCacheRemovalAndAreReleasedWithResources() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ImageKit-LivePhotoTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = DiskCache(directory)
        let context = ImageRequest.Context(disk: disk, caches: [], processors: [], loaders: [])
        let image = ImageRequest(URL(string: "https://example.invalid/image.jpg")!, size: .original, context: context)
        let video = ImageRequest(URL(string: "https://example.invalid/video.mov")!, size: .original, context: context)
        disk.store(Data([1]), for: image)
        disk.store(Data([2]), for: video)
        var resources = try await LivePhotoResources.cached(image: image, video: video)
        let urls = try #require(resources?.urls)
        try FileManager.default.removeItem(at: directory)
        #expect(try Data(contentsOf: urls[0]) == Data([1]))
        #expect(try Data(contentsOf: urls[1]) == Data([2]))

        resources = nil
        #expect(!FileManager.default.fileExists(atPath: urls[0].deletingLastPathComponent().path))
    }

    @Test
    func cachedPreparationHonorsDisabledDiskCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ImageKit-LivePhotoTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = DiskCache(directory)
        let context = ImageRequest.Context(disk: disk, caches: [], processors: [], loaders: [])
        let image = ImageRequest(URL(string: "https://example.invalid/image.jpg")!, size: .original, caches: [], context: context)
        let video = ImageRequest(URL(string: "https://example.invalid/video.mov")!, size: .original, caches: [], context: context)
        disk.store(Data([1]), for: image)
        disk.store(Data([2]), for: video)
        #expect(try await LivePhotoResources.cached(image: image, video: video) == nil)
    }

    @MainActor @Test
    func initializationDoesNotDownloadUncachedVideo() async {
        let source = ControlledLiveResourceLoader()
        let loader = URLImageLoader(request("image.jpg", loader: source), liveVideo: request("video.mov", loader: source))
        await Task.yield()
        #expect(await source.startCount == 0)
        #expect(!loader.result.livePhotoLoading)
        #expect(loader.result.livePhotoError == nil)
    }

    @MainActor @Test
    func invalidCachedPairDoesNotDownloadDuringInitialization() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ImageKit-LivePhotoTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = DiskCache(directory)
        let source = ControlledLiveResourceLoader()
        let context = ImageRequest.Context(disk: disk, caches: [], processors: [], loaders: [source])
        let image = ImageRequest(URL(string: "https://example.invalid/image.jpg")!, size: .original, context: context)
        let video = ImageRequest(URL(string: "https://example.invalid/video.mov")!, size: .original, context: context)
        disk.store(Data([1]), for: image)
        disk.store(Data([2]), for: video)

        let loader = URLImageLoader(image, liveVideo: video)
        try await waitUntil { loader.result.livePhotoError != nil }
        #expect(!loader.result.livePhotoLoading)
        #expect(await source.startCount == 0)
        if case .empty = loader.result.value { } else {
            Issue.record("Initialization unexpectedly loaded the still image")
        }
    }

    @MainActor @Test
    func loadingPublishesTheOriginalErrorWithoutReplacingTheStillImage() async throws {
        let imageLoader = ControlledLiveResourceLoader()
        let videoLoader = ControlledLiveResourceLoader()
        let loader = URLImageLoader(request("image.jpg", loader: imageLoader), liveVideo: request("video.mov", loader: videoLoader))
        let stillImage = KKImage()
        loader.result.value = .success(stillImage)
        loader.loadLivePhoto()
        try await imageLoader.waitForStarts(1)
        try await videoLoader.waitForStarts(1)
        await videoLoader.complete(1, with: .failure(URLError(.timedOut)))
        try await waitUntil { !loader.result.livePhotoLoading }

        #expect((loader.result.livePhotoError as? URLError)?.code == .timedOut)
        if case .success(let image) = loader.result.value {
            #expect(image === stillImage)
        } else {
            Issue.record("Live Photo failure replaced the still image")
        }
    }

    @MainActor @Test
    func releasingLoaderCancelsBothLivePhotoResources() async throws {
        let imageLoader = ControlledLiveResourceLoader()
        let videoLoader = ControlledLiveResourceLoader()
        var loader: URLImageLoader? = URLImageLoader(request("image.jpg", loader: imageLoader),
                                                    liveVideo: request("video.mov", loader: videoLoader))
        weak var releasedLoader = loader
        loader?.loadLivePhoto()
        try await imageLoader.waitForStarts(1)
        try await videoLoader.waitForStarts(1)

        loader = nil
        #expect(releasedLoader == nil)
        try await imageLoader.waitForCancellations(1)
        try await videoLoader.waitForCancellations(1)
    }

    @MainActor @Test
    func canceledWorkCannotPublishOverANewRequest() async throws {
        let imageLoader = ControlledLiveResourceLoader(respondsToCancellation: false)
        let videoLoader = ControlledLiveResourceLoader(respondsToCancellation: false)
        let loader = URLImageLoader(request("image.jpg", loader: imageLoader), liveVideo: request("video.mov", loader: videoLoader))
        loader.result.value = .success(KKImage())
        loader.loadLivePhoto()
        try await imageLoader.waitForStarts(1)
        try await videoLoader.waitForStarts(1)
        loader.cancel()
        loader.loadLivePhoto()
        try await imageLoader.waitForStarts(2)
        try await videoLoader.waitForStarts(2)
        #expect(loader.result.livePhotoLoading)

        await imageLoader.complete(2, with: .success(.data(Data([1]))))
        await videoLoader.complete(2, with: .failure(URLError(.notConnectedToInternet)))
        try await waitUntil { !loader.result.livePhotoLoading }
        #expect((loader.result.livePhotoError as? URLError)?.code == .notConnectedToInternet)

        await imageLoader.complete(1, with: .failure(URLError(.timedOut)))
        await videoLoader.complete(1, with: .success(.data(Data([2]))))
        await Task.yield()
        #expect((loader.result.livePhotoError as? URLError)?.code == .notConnectedToInternet)
        #expect(!loader.result.livePhotoLoading)
    }

    private func request(_ name: String, loader: ControlledLiveResourceLoader) -> ImageRequest {
        let context = ImageRequest.Context(caches: [], processors: [], loaders: [loader])
        return ImageRequest(URL(string: "test://live-photo/\(name)")!, size: .original, processors: [], caches: [], context: context)
    }

    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw URLError(.timedOut)
    }
}

private actor ControlledLiveResourceLoader: DataLoader {
    private let respondsToCancellation: Bool
    private var pending = [Int: CheckedContinuation<LoadResult?, Error>]()
    private(set) var startCount = 0
    private(set) var cancellationCount = 0

    init(respondsToCancellation: Bool = true) {
        self.respondsToCancellation = respondsToCancellation
    }

    nonisolated func isValid(request: ImageRequest) -> Bool { true }

    func load(request: ImageRequest) async -> LoadResult? {
        try? await loadResult(request: request)
    }

    func loadResult(request: ImageRequest) async throws -> LoadResult? {
        try Task.checkCancellation()
        startCount += 1
        let id = startCount
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled && respondsToCancellation {
                    continuation.resume(throwing: CancellationError())
                } else {
                    pending[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func complete(_ id: Int, with result: Result<LoadResult?, Error>) {
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    func waitForStarts(_ count: Int) async throws {
        for _ in 0..<200 {
            if startCount >= count { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw URLError(.timedOut)
    }

    func waitForCancellations(_ count: Int) async throws {
        for _ in 0..<200 {
            if cancellationCount >= count { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw URLError(.timedOut)
    }

    private func cancel(_ id: Int) {
        cancellationCount += 1
        if respondsToCancellation {
            pending.removeValue(forKey: id)?.resume(throwing: CancellationError())
        }
    }
}
