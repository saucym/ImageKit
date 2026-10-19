import CoreGraphics
import Dispatch
import Foundation
import Testing
@testable import ImageKit
#if os(iOS)
import UIKit
#endif

@Suite("Cache management")
struct CacheManagementTests {
    @Test
    func diskExpiresAndDeletesAnOldEntryOnRead() throws {
        let fixture = CacheFixture(maxAge: 10)
        let request = fixture.request("expired")
        fixture.disk.store(Data([1, 2, 3]), for: request)
        let path = fixture.disk.localPath(request)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -11)], ofItemAtPath: path.path)
        #expect(fixture.disk.load(request) == nil)
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }

    @Test
    func diskEvictsTheLeastRecentlyModifiedEntry() throws {
        let fixture = CacheFixture(maxSize: 5)
        let older = fixture.request("older")
        let newer = fixture.request("newer")
        fixture.disk.store(Data([1, 2, 3]), for: older)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -100)], ofItemAtPath: fixture.disk.localPath(older).path)
        fixture.disk.store(Data([4, 5, 6]), for: newer)
        #expect(fixture.disk.load(older) == nil)
        #expect(try cachedData(fixture.disk, request: newer) == Data([4, 5, 6]))
    }

    @Test
    func firstStoreEnforcesAnExistingCacheBudget() throws {
        let fixture = CacheFixture()
        let older = fixture.request("older")
        let newer = fixture.request("newer")
        fixture.disk.store(Data([1, 2, 3]), for: older)
        fixture.disk.store(Data([4, 5, 6]), for: newer)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -100)], ofItemAtPath: fixture.disk.localPath(older).path)
        let smaller = DiskCache(fixture.disk.dir, maxSize: 5)
        let newest = fixture.request("newest")
        smaller.store(Data([7]), for: newest)
        #expect(smaller.load(older) == nil)
        #expect(try cachedData(smaller, request: newer) == Data([4, 5, 6]))
        #expect(try cachedData(smaller, request: newest) == Data([7]))
    }

    @Test
    func diskSkipsOversizedDataAndSupportsDisabledStorage() {
        let fixture = CacheFixture(maxSize: 2)
        let request = fixture.request("oversized")
        fixture.disk.store(Data([1, 2, 3]), for: request)
        #expect(fixture.disk.load(request) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.disk.localPath(request).path))
        let disabled = DiskCache(fixture.disk.dir, maxSize: 0)
        disabled.store(Data([1]), for: request)
        #expect(disabled.load(request) == nil)
        let expired = DiskCache(fixture.disk.dir, maxAge: 0)
        expired.store(Data([1]), for: request)
        #expect(expired.load(request) == nil)
    }

    @Test
    func diskRejectsAnExternallyWrittenOversizedEntryBeforeReadingIt() throws {
        let fixture = CacheFixture(maxSize: 2)
        let request = fixture.request("oversized")
        fixture.disk.store(Data([1]), for: request)
        let path = fixture.disk.localPath(request)
        try Data([1, 2, 3]).write(to: path)
        #expect(fixture.disk.load(request) == nil)
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }

    @Test
    func matchingInvalidationKeepsUpdatedData() throws {
        let fixture = CacheFixture()
        let request = fixture.request("replace")
        let old = Data([1])
        let updated = Data([2])
        fixture.disk.store(old, for: request)
        fixture.disk.store(updated, for: request)
        fixture.disk.remove(request, matching: old)
        #expect(try cachedData(fixture.disk, request: request) == updated)
        fixture.disk.remove(request, matching: updated)
        #expect(fixture.disk.load(request) == nil)
    }

    @Test
    func concurrentInvalidationAcrossInstancesCannotDeleteAReplacement() throws {
        let fixture = CacheFixture()
        let other = DiskCache(fixture.disk.dir)
        let request = fixture.request("replace")
        let old = Data([1])
        let updated = Data([2])
        for _ in 0..<100 {
            fixture.disk.store(old, for: request)
            DispatchQueue.concurrentPerform(iterations: 2) { index in
                if index == 0 {
                    other.store(updated, for: request)
                } else {
                    fixture.disk.remove(request, matching: old)
                }
            }
            #expect(try cachedData(fixture.disk, request: request) == updated)
        }
    }

    @Test
    func directoryAliasesShareInvalidationAndWriteSynchronization() throws {
        let fixture = CacheFixture()
        let alias = fixture.root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.root)
        let aliasedDirectory = alias.appendingPathComponent("cache", isDirectory: true)
        let other = DiskCache(aliasedDirectory)
        let request = fixture.request("replace")
        let old = Data([1])
        let updated = Data([2])
        for _ in 0..<100 {
            fixture.disk.store(old, for: request)
            DispatchQueue.concurrentPerform(iterations: 2) { index in
                if index == 0 {
                    other.store(updated, for: request)
                } else {
                    fixture.disk.remove(request, matching: old)
                }
            }
            #expect(try cachedData(fixture.disk, request: request) == updated)
        }
    }

    @Test
    func clearPreservesTheCacheDirectoryAndItsNeighbors() throws {
        let fixture = CacheFixture()
        let neighbor = fixture.root.appendingPathComponent("neighbor")
        try Data([9]).write(to: neighbor)
        fixture.disk.store(Data([1]), for: fixture.request("first"))
        fixture.disk.store(Data([2]), for: fixture.request("second"))
        fixture.disk.clear()
        #expect(FileManager.default.fileExists(atPath: fixture.disk.dir.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.disk.dir.path).isEmpty)
        #expect(try Data(contentsOf: neighbor) == Data([9]))
        fixture.disk.store(Data([3]), for: fixture.request("third"))
        #expect(try cachedData(fixture.disk, request: fixture.request("third")) == Data([3]))
    }

    @Test
    func removingAnEntryDoesNotRemoveOtherEntriesOrTheRoot() throws {
        let fixture = CacheFixture()
        let first = fixture.request("first")
        let second = fixture.request("second")
        fixture.disk.store(Data([1]), for: first)
        fixture.disk.store(Data([2]), for: second)
        fixture.disk.remove(first)
        fixture.disk.remove(fixture.request(""))
        fixture.disk.remove(fixture.request(".."))
        #expect(fixture.disk.load(first) == nil)
        #expect(try cachedData(fixture.disk, request: second) == Data([2]))
        #expect(FileManager.default.fileExists(atPath: fixture.disk.dir.path))
    }

    @Test
    func cacheOperationsDoNotFollowPartitionSymlinks() throws {
        let fixture = CacheFixture()
        let outside = fixture.root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let target = outside.appendingPathComponent("abcdef")
        try Data([9]).write(to: target)
        let link = fixture.disk.dir.appendingPathComponent("ab")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let request = fixture.request("abcdef")
        fixture.disk.store(Data([1]), for: request)
        #expect(fixture.disk.load(request) == nil)
        fixture.disk.remove(request)
        fixture.disk.clear()
        #expect(try Data(contentsOf: target) == Data([9]))
    }

    @Test
    func dotPrefixedKeysStayInsideTheCacheDirectory() throws {
        let fixture = CacheFixture()
        let request = fixture.request("..image")
        let neighbor = fixture.root.appendingPathComponent(request.key)
        try Data([9]).write(to: neighbor)

        #expect(fixture.disk.load(request) == nil)
        fixture.disk.store(Data([1]), for: request)
        #expect(try cachedData(fixture.disk, request: request) == Data([1]))
        #expect(fixture.disk.localPath(request).standardizedFileURL.path.hasPrefix(fixture.disk.dir.standardizedFileURL.path + "/"))
        #expect(try Data(contentsOf: neighbor) == Data([9]))

        fixture.disk.remove(request)
        #expect(fixture.disk.load(request) == nil)
        #expect(try Data(contentsOf: neighbor) == Data([9]))
        fixture.disk.store(Data([2]), for: request)
        fixture.disk.clear()
        #expect(try Data(contentsOf: neighbor) == Data([9]))
    }

    @Test
    func cacheOperationsDoNotFollowEntrySymlinks() throws {
        let fixture = CacheFixture()
        let request = fixture.request("linked")
        let target = fixture.root.appendingPathComponent("outside")
        try Data([9]).write(to: target)
        let link = fixture.disk.localPath(request)
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(fixture.disk.load(request) == nil)
        fixture.disk.store(Data([1]), for: request)
        fixture.disk.remove(request)
        fixture.disk.remove(request, matching: Data([9]))
        #expect(try FileManager.default.attributesOfItem(atPath: link.path)[.type] as? FileAttributeType == .typeSymbolicLink)
        fixture.disk.clear()
        #expect(try Data(contentsOf: target) == Data([9]))
    }

    @Test
    func diskHashingUsesConfigurationInsteadOfLockIdentity() {
        let fixture = CacheFixture()
        let equivalent = DiskCache(fixture.disk.dir, maxSize: fixture.disk.maxSize, maxAge: fixture.disk.maxAge)
        #expect(fixture.disk == equivalent)
        #expect(Set([fixture.disk, equivalent]).count == 1)
        #expect(fixture.disk != DiskCache(fixture.disk.dir, maxSize: 1))
    }

    @MainActor @Test
    func memoryUsesActualBitmapRowsForCostAndStillSupportsClear() async throws {
        let memory = MemoryCache(totalCostLimit: 1024 * 1024, countLimit: 8)
        #expect(memory.totalCostLimit == 1024 * 1024)
        #expect(memory.countLimit == 8)
        let bitmap = try makeBitmap(width: 7, height: 11, bytesPerRow: 64)
        #if os(iOS)
        let image = KKImage(cgImage: bitmap, scale: 1, orientation: .up)
        #else
        let image = KKImage(cgImage: bitmap, scale: 1)
        #endif
        #expect(MemoryCache.cost(of: image) == bitmap.bytesPerRow * bitmap.height)
        let request = ImageRequest(URL(string: "https://example.invalid/image")!, size: .original)
        memory.cache(image, for: request)
        #expect(try memory.image(for: request) === image)
        await memory.clear()
        #expect(try memory.image(for: request) == nil)
    }

    #if os(iOS)
    @MainActor @Test
    func memoryCountsEachAnimatedBitmapOnlyOnce() throws {
        let bitmap = try makeBitmap(width: 7, height: 11, bytesPerRow: 64)
        let secondBitmap = try makeBitmap(width: 7, height: 11, bytesPerRow: 64)
        let first = UIImage(cgImage: bitmap)
        let shared = UIImage(cgImage: bitmap)
        let second = UIImage(cgImage: secondBitmap)
        let animation = try #require(UIImage.animatedImage(with: [first, shared, second, first], duration: 0.4))
        #expect(MemoryCache.cost(of: animation) == bitmap.bytesPerRow * bitmap.height + secondBitmap.bytesPerRow * secondBitmap.height)
    }
    #endif

    private func cachedData(_ disk: DiskCache, request: ImageRequest) throws -> Data {
        let result = try #require(disk.load(request))
        guard case .data(let data) = result else {
            Issue.record("expected original disk bytes")
            return Data()
        }
        return data
    }

    private func makeBitmap(width: Int, height: Int, bytesPerRow: Int) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try #require(context.makeImage())
    }
}

private final class CacheFixture: @unchecked Sendable {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ImageKitCacheTests-\(UUID().uuidString)")
    let disk: DiskCache

    init(maxSize: Int = 1024 * 1024, maxAge: TimeInterval = 1000) {
        disk = DiskCache(root.appendingPathComponent("cache"), maxSize: maxSize, maxAge: maxAge)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func request(_ key: String) -> ImageRequest {
        ImageRequest(URL(string: "https://example.invalid/image")!, size: .original, key: key)
    }
}
