import XCTest
@testable import ImageKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

final class CacheKeyTests: XCTestCase {
    func testCacheKeyForURLUsesMD5AndExtension() {
        let url = URL(string: "https://example.com/photo.PNG")!
        let key = ImageRequest.cacheKey(for: url)
        XCTAssertTrue(key.hasSuffix(".PNG"))
        XCTAssertEqual(key.dropLast(4).count, 32)
        XCTAssertEqual(key, ImageRequest.cacheKey(for: url))
    }
    
    func testCacheKeyDefaultsExtensionWhenMissing() {
        let url = URL(string: "https://example.com/photo")!
        let key = ImageRequest.cacheKey(for: url)
        XCTAssertTrue(key.hasSuffix(".jpg"))
    }
    
    func testMemoryCacheKeyChangesWithWidthAndProcessors() {
        let url = URL(string: "https://example.com/a.jpg")!
        let base = ImageRequest(url, size: .absolute(CGSize(width: 100, height: 100)))
        let wider = ImageRequest(url, size: .absolute(CGSize(width: 200, height: 200)))
        let gray = ImageRequest(url, size: .absolute(CGSize(width: 100, height: 100)), processors: [.gray, .predrawn])
        
        XCTAssertEqual(base.cacheKey(), base.cacheKey())
        XCTAssertNotEqual(base.cacheKey(), wider.cacheKey())
        XCTAssertNotEqual(base.cacheKey(), gray.cacheKey())
        XCTAssertEqual(base.cacheKey(width: 50), base.cacheKey(width: 50))
        XCTAssertNotEqual(base.cacheKey(width: 50), base.cacheKey(width: 80))
    }
}

final class DiskCacheTests: XCTestCase {
    private var tempDir: URL!
    private var disk: DiskCache!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ImageKitTests-\(UUID().uuidString)")
        disk = DiskCache(tempDir, splitSubDir: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testLocalPathSplitsSubdirectory() {
        let path = disk.localPath("abcdef.jpg")
        XCTAssertEqual(path.lastPathComponent, "abcdef.jpg")
        XCTAssertEqual(path.deletingLastPathComponent().lastPathComponent, "ab")
    }
    
    func testStoreAndLoadRoundTrip() throws {
        let url = URL(string: "https://example.com/roundtrip.png")!
        let context = ImageRequest.Context(disk: disk, caches: [], processors: [], loaders: [])
        let request = ImageRequest(url, size: .original, caches: [.disk], context: context)
        let data = try XCTUnwrap(TestImage.pngData(size: CGSize(width: 4, height: 4)))
        
        XCTAssertTrue(disk.isEnabled(for: request))
        disk.store(data, for: request)
        let loaded = try XCTUnwrap(disk.load(request))
        guard case .image(let image) = loaded else {
            return XCTFail("expected image")
        }
        XCTAssertEqual(image.size.width, 4, accuracy: 0.5)
    }
    
    func testDisabledWhenDiskNotRequested() {
        let url = URL(string: "https://example.com/x.png")!
        let request = ImageRequest(url, size: .original, caches: [.memory])
        XCTAssertFalse(disk.isEnabled(for: request))
    }
}

final class DecoderTests: XCTestCase {
    func testSystemDecoderDecodesPNG() throws {
        let data = try XCTUnwrap(TestImage.pngData(size: CGSize(width: 8, height: 6)))
        let request = ImageRequest(URL(string: "https://example.com/t.png")!, size: .original, processors: [])
        let image = try SystemDecoder().decode(request: request, data: data)
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        // Point size may differ by platform scale; require a valid non-empty bitmap.
        XCTAssertGreaterThan(pixelWidth, 0)
        XCTAssertGreaterThan(pixelHeight, 0)
        XCTAssertEqual(pixelWidth / pixelHeight, 8.0 / 6.0, accuracy: 0.05)
    }
    
    func testSystemDecoderRejectsInvalidData() {
        let request = ImageRequest(URL(string: "https://example.com/bad.png")!, size: .original)
        XCTAssertThrowsError(try SystemDecoder().decode(request: request, data: Data([0x00, 0x01]))) { error in
            let ik = error as? IKError
            XCTAssertTrue(ik == .imageSourceCreateError || ik == .decoderImageIsNil)
        }
    }
}

final class PredrawnProcessorTests: XCTestCase {
    func testPredrawnDownscalesLargerImage() throws {
        let source = try XCTUnwrap(TestImage.image(size: CGSize(width: 200, height: 100)))
        let request = ImageRequest(
            URL(string: "https://example.com/big.png")!,
            size: .absolute(CGSize(width: 40, height: 20)),
            mode: .fill,
            processors: .predrawn
        )
        let processor = PredrawnProcessor()
        XCTAssertTrue(processor.isValid(request: request))
        
        let result = processor.process(request: request, input: source)
        XCTAssertLessThanOrEqual(result.size.width * result.scale, 40 * screenScale + 1)
        XCTAssertLessThanOrEqual(result.size.height * result.scale, 20 * screenScale + 1)
    }
    
    func testPredrawnSkipsWhenAlreadySmallEnough() throws {
        let source = try XCTUnwrap(TestImage.image(size: CGSize(width: 20, height: 20)))
        let request = ImageRequest(
            URL(string: "https://example.com/small.png")!,
            size: .absolute(CGSize(width: 100, height: 100)),
            mode: .fit,
            processors: .predrawn
        )
        let result = PredrawnProcessor().process(request: request, input: source)
        XCTAssertEqual(result.size.width, source.size.width, accuracy: 0.5)
        XCTAssertEqual(result.size.height, source.size.height, accuracy: 0.5)
    }
    
    func testPredrawnInvalidWithoutFlag() {
        let request = ImageRequest(
            URL(string: "https://example.com/x.png")!,
            size: .absolute(CGSize(width: 40, height: 40)),
            processors: []
        )
        XCTAssertFalse(PredrawnProcessor().isValid(request: request))
    }
}

enum TestImage {
    static func image(size: CGSize) -> KKImage? {
        #if os(macOS)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
        #else
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        #endif
    }
    
    static func pngData(size: CGSize) -> Data? {
        guard let image = image(size: size) else { return nil }
        #if os(macOS)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
        #else
        return image.pngData()
        #endif
    }
}
