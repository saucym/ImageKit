import Foundation
import Testing
@testable import ImageKit

@Suite("Loading behavior")
struct LoadingBehaviorTests {
    @Test
    func rejectsHTTPFailuresBeforeWritingDisk() async throws {
        let fixture = LoadingFixture(statusCode: 503)
        do {
            _ = try await fixture.loader.loadResult(request: fixture.request())
            Issue.record("expected HTTP failure")
        } catch IKError.invalidHTTPStatus(let statusCode) {
            #expect(statusCode == 503)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.disk.localPath(fixture.request()).path))
    }

    @Test
    func preservesNetworkErrors() async throws {
        let fixture = LoadingFixture(error: URLError(.timedOut))
        do {
            _ = try await fixture.request().send()
            Issue.record("expected network failure")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        }
    }

    @Test
    func preservesFileErrorsThroughPipeline() async throws {
        let fixture = LoadingFixture()
        let url = fixture.directory.appendingPathComponent("missing.png")
        let context = ImageRequest.Context(disk: fixture.disk, caches: [], processors: [], loaders: [LocalLoader()])
        let request = ImageRequest(url, size: .original, context: context)
        do {
            _ = try await request.send()
            Issue.record("expected missing-file failure")
        } catch let error as CocoaError {
            #expect(error.code == .fileReadNoSuchFile)
        }
    }

    @Test
    func diskCachePreservesBytesRegardlessOfExtension() throws {
        let fixture = LoadingFixture()
        let request = fixture.request()
        let bytes = Data([0x12, 0x34, 0x56])
        fixture.disk.store(bytes, for: request)
        let loaded = try #require(fixture.disk.load(request))
        guard case .data(let cachedBytes) = loaded else {
            Issue.record("expected raw disk data")
            return
        }
        #expect(cachedBytes == bytes)
    }

    @Test
    func diskHitStillUsesCustomDecoder() async throws {
        let fixture = LoadingFixture()
        let decoder = RecordingDecoder()
        let context = ImageRequest.Context(disk: fixture.disk, decoders: [decoder], caches: [], processors: [], loaders: [fixture.loader])
        let request = ImageRequest(fixture.url, size: .original, processors: [], context: context)
        _ = try await request.send()
        _ = try await request.send()
        #expect(fixture.plan.requestCount == 1)
        #expect(decoder.decodedData == [fixture.plan.data, fixture.plan.data])
    }

    @Test
    func corruptDiskDataIsReplacedByOneFreshDownload() async throws {
        let fixture = LoadingFixture()
        let decoder = RecordingDecoder(acceptedData: fixture.plan.data)
        let context = ImageRequest.Context(disk: fixture.disk, decoders: [decoder], caches: [], processors: [], loaders: [fixture.loader])
        let request = ImageRequest(fixture.url, size: .original, processors: [], context: context)
        let corruptData = Data([0xff])
        fixture.disk.store(corruptData, for: request)

        _ = try await request.send()
        #expect(decoder.decodedData == [corruptData, fixture.plan.data])
        #expect(fixture.plan.cachePolicies == [.reloadIgnoringLocalCacheData])
        _ = try await request.send()
        #expect(fixture.plan.requestCount == 1)
        #expect(decoder.decodedData.last == fixture.plan.data)
    }

    @Test(arguments: [false, true])
    func invalidDownloadedDataIsRemovedWithoutRepeatedRetries(seedCorruptCache: Bool) async throws {
        let fixture = LoadingFixture()
        let request = fixture.request()
        if seedCorruptCache { fixture.disk.store(Data([0xff]), for: request) }
        do {
            _ = try await request.send()
            Issue.record("expected invalid image failure")
        } catch IKError.imageSourceCreateError, IKError.decoderImageIsNil { }
        #expect(fixture.plan.requestCount == 1)
        #expect(fixture.disk.load(request) == nil)
    }

    @Test
    func missingDecoderDoesNotInvalidateCachedDataOrDownloadAgain() async throws {
        let fixture = LoadingFixture()
        let context = ImageRequest.Context(disk: fixture.disk, decoders: [], caches: [], loaders: [fixture.loader])
        let request = ImageRequest(fixture.url, size: .original, context: context)
        fixture.disk.store(fixture.plan.data, for: request)
        do {
            _ = try await request.send()
            Issue.record("expected missing decoder failure")
        } catch IKError.decoderIsEmpty { }
        #expect(fixture.plan.requestCount == 0)
        #expect(fixture.disk.load(request) != nil)
    }

    @Test
    func decoderCancellationDoesNotInvalidateCachedDataOrRetry() async throws {
        let fixture = LoadingFixture()
        let context = ImageRequest.Context(disk: fixture.disk, decoders: [CancelledDecoder()], caches: [], loaders: [fixture.loader])
        let request = ImageRequest(fixture.url, size: .original, context: context)
        fixture.disk.store(fixture.plan.data, for: request)
        do {
            _ = try await request.send()
            Issue.record("expected cancellation")
        } catch is CancellationError { }
        #expect(fixture.plan.requestCount == 0)
        #expect(fixture.disk.load(request) != nil)
    }

    @Test
    func cacheRecoveryPreservesNetworkFailure() async throws {
        let fixture = LoadingFixture(error: URLError(.timedOut))
        let request = fixture.request()
        fixture.disk.store(Data([0xff]), for: request)
        do {
            _ = try await request.send()
            Issue.record("expected recovery download failure")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        }
        #expect(fixture.plan.requestCount == 1)
        #expect(fixture.disk.load(request) == nil)
    }

    @Test
    func coalescesDownloadsForDifferentOutputSizes() async throws {
        let fixture = LoadingFixture(automaticallyResponds: false)
        let first = Task { try await fixture.loader.loadResult(request: fixture.request(size: .width(40), caches: [])) }
        try await fixture.plan.waitForRequest()
        let second = Task { try await fixture.loader.loadResult(request: fixture.request(size: .width(80), caches: [])) }
        try await Task.sleep(nanoseconds: 20_000_000)
        fixture.plan.respond()
        _ = try await first.value
        _ = try await second.value
        #expect(fixture.plan.requestCount == 1)
    }

    @Test
    func cancelingOneDownloadSubscriberKeepsAnotherAlive() async throws {
        let fixture = LoadingFixture(automaticallyResponds: false)
        let first = Task { try await fixture.loader.loadResult(request: fixture.request(size: .width(40), caches: [])) }
        try await fixture.plan.waitForRequest()
        let second = Task { try await fixture.loader.loadResult(request: fixture.request(size: .width(80), caches: [])) }
        try await Task.sleep(nanoseconds: 20_000_000)
        first.cancel()
        fixture.plan.respond()
        do {
            _ = try await first.value
            Issue.record("expected cancellation")
        } catch is CancellationError { }
        guard case .data(let data) = try #require(await second.value) else {
            Issue.record("expected shared download data")
            return
        }
        #expect(data == fixture.plan.data)
        #expect(fixture.plan.requestCount == 1)
    }

    @Test
    func legacyLoaderStillParticipatesInPipeline() async throws {
        let fixture = LoadingFixture()
        let decoder = RecordingDecoder()
        let context = ImageRequest.Context(disk: fixture.disk, decoders: [decoder], caches: [], processors: [], loaders: [LegacyLoader()])
        let request = ImageRequest(fixture.url, size: .original, processors: [], context: context)
        _ = try await request.send()
        #expect(decoder.decodedData == [Data([0x42])])
    }
}

private struct LegacyLoader: DataLoader {
    func isValid(request: ImageRequest) -> Bool { true }
    func load(request: ImageRequest) async -> LoadResult? { .data(Data([0x42])) }
}

private struct CancelledDecoder: ImageDecoder {
    func isValid(request: ImageRequest) -> Bool { true }
    func decode(request: ImageRequest, data: Data) throws -> KKImage { throw CancellationError() }
}

private final class RecordingDecoder: ImageDecoder {
    private let lock = NSLock()
    private var values = [Data]()
    private let acceptedData: Data?

    init(acceptedData: Data? = nil) {
        self.acceptedData = acceptedData
    }

    var decodedData: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func isValid(request: ImageRequest) -> Bool { true }

    func decode(request: ImageRequest, data: Data) throws -> KKImage {
        lock.lock()
        values.append(data)
        lock.unlock()
        if let acceptedData, data != acceptedData { throw IKError.imageSourceCreateError }
        return KKImage()
    }
}

private final class LoadingFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ImageKitLoadingTests-\(UUID().uuidString)")
    let url = URL(string: "https://example.invalid/\(UUID().uuidString).png")!
    let disk: DiskCache
    let plan: StubResponse
    let loader: NetworkLoader
    private let session: URLSession

    init(statusCode: Int = 200, error: Error? = nil, automaticallyResponds: Bool = true) {
        disk = DiskCache(directory)
        plan = StubResponse(statusCode: statusCode, error: error, automaticallyResponds: automaticallyResponds)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoadingURLProtocol.self]
        session = URLSession(configuration: configuration)
        loader = NetworkLoader(session: session)
        LoadingURLProtocol.responses.set(plan, for: url)
    }

    deinit {
        session.invalidateAndCancel()
        LoadingURLProtocol.responses.remove(url)
        try? FileManager.default.removeItem(at: directory)
    }

    func request(size: ImageRequest.Size = .original, caches: RequestCache = [.disk]) -> ImageRequest {
        let context = ImageRequest.Context(disk: disk, caches: [], processors: [], loaders: [loader])
        return ImageRequest(url, size: size, processors: [], caches: caches, context: context)
    }
}

private final class StubResponse: @unchecked Sendable {
    let data = Data([0x12, 0x34])
    let statusCode: Int
    let error: Error?
    private let automaticallyResponds: Bool
    private let lock = NSLock()
    private var protocols = [LoadingURLProtocol]()
    private var starts = 0
    private var policies = [URLRequest.CachePolicy]()

    init(statusCode: Int, error: Error?, automaticallyResponds: Bool) {
        self.statusCode = statusCode
        self.error = error
        self.automaticallyResponds = automaticallyResponds
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return starts
    }

    var cachePolicies: [URLRequest.CachePolicy] {
        lock.lock()
        defer { lock.unlock() }
        return policies
    }

    func start(_ instance: LoadingURLProtocol) {
        lock.lock()
        starts += 1
        policies.append(instance.request.cachePolicy)
        protocols.append(instance)
        lock.unlock()
        if automaticallyResponds {
            respond()
        }
    }

    func stop(_ instance: LoadingURLProtocol) {
        lock.lock()
        protocols.removeAll { $0 === instance }
        lock.unlock()
    }

    func respond() {
        lock.lock()
        let pending = protocols
        protocols.removeAll()
        lock.unlock()
        for instance in pending {
            if let error {
                instance.client?.urlProtocol(instance, didFailWithError: error)
            } else {
                let response = HTTPURLResponse(url: instance.request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
                instance.client?.urlProtocol(instance, didReceive: response, cacheStoragePolicy: .notAllowed)
                instance.client?.urlProtocol(instance, didLoad: data)
                instance.client?.urlProtocolDidFinishLoading(instance)
            }
        }
    }

    func waitForRequest() async throws {
        for _ in 0..<200 {
            if requestCount > 0 { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw URLError(.timedOut)
    }
}

private final class LoadingURLProtocol: URLProtocol, @unchecked Sendable {
    static let responses = ResponseRegistry()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url.map { responses.response(for: $0) != nil } ?? false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url {
            Self.responses.response(for: url)?.start(self)
        }
    }

    override func stopLoading() {
        if let url = request.url {
            Self.responses.response(for: url)?.stop(self)
        }
    }
}

private final class ResponseRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var values = [URL: StubResponse]()

    func set(_ response: StubResponse, for url: URL) {
        lock.lock()
        values[url] = response
        lock.unlock()
    }

    func remove(_ url: URL) {
        lock.lock()
        values[url] = nil
        lock.unlock()
    }

    func response(for url: URL) -> StubResponse? {
        lock.lock()
        defer { lock.unlock() }
        return values[url]
    }
}
