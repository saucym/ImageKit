import Testing
@testable import ImageKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Suite("CacheKey")
struct CacheKeyTests {
    @Test
    func cacheKeyForURLUsesMD5AndExtension() {
        let url = URL(string: "https://example.com/photo.PNG")!
        let key = ImageRequest.cacheKey(for: url)
        #expect(key.hasSuffix(".PNG"))
        #expect(key.dropLast(4).count == 32)
        #expect(key == ImageRequest.cacheKey(for: url))
    }
    
    @Test
    func cacheKeyDefaultsExtensionWhenMissing() {
        let url = URL(string: "https://example.com/photo")!
        let key = ImageRequest.cacheKey(for: url)
        #expect(key.hasSuffix(".jpg"))
    }
    
    @Test
    func memoryCacheKeyChangesWithWidthAndProcessors() {
        let url = URL(string: "https://example.com/a.jpg")!
        let base = ImageRequest(url, size: .absolute(CGSize(width: 100, height: 100)))
        let wider = ImageRequest(url, size: .absolute(CGSize(width: 200, height: 200)))
        let gray = ImageRequest(url, size: .absolute(CGSize(width: 100, height: 100)), processors: [.gray, .predrawn])
        
        #expect(base.cacheKey() == base.cacheKey())
        #expect(base.cacheKey() != wider.cacheKey())
        #expect(base.cacheKey() != gray.cacheKey())
        #expect(base.cacheKey(width: 50) == base.cacheKey(width: 50))
        #expect(base.cacheKey(width: 50) != base.cacheKey(width: 80))
    }
}

@Suite("DiskCache")
struct DiskCacheTests {
    @Test
    func localPathSplitsSubdirectory() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ImageKitTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let disk = DiskCache(tempDir, splitSubDir: true)
        
        let path = disk.localPath("abcdef.jpg")
        #expect(path.lastPathComponent == "abcdef.jpg")
        #expect(path.deletingLastPathComponent().lastPathComponent == "ab")
    }
    
    @Test
    func storeAndLoadRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ImageKitTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let disk = DiskCache(tempDir, splitSubDir: true)
        
        let url = URL(string: "https://example.com/roundtrip.png")!
        let context = ImageRequest.Context(disk: disk, caches: [], processors: [], loaders: [])
        let request = ImageRequest(url, size: .original, caches: [.disk], context: context)
        let data = try #require(TestImage.pngData(size: CGSize(width: 4, height: 4)))
        
        #expect(disk.isEnabled(for: request))
        disk.store(data, for: request)
        let loaded = try #require(disk.load(request))
        guard case .image(let image) = loaded else {
            Issue.record("expected image")
            return
        }
        #expect(abs(image.size.width - 4) < 0.5)
    }
    
    @Test
    func disabledWhenDiskNotRequested() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ImageKitTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let disk = DiskCache(tempDir, splitSubDir: true)
        
        let url = URL(string: "https://example.com/x.png")!
        let request = ImageRequest(url, size: .original, caches: [.memory])
        #expect(!disk.isEnabled(for: request))
    }
}

@Suite("Decoder")
struct DecoderTests {
    @Test
    func systemDecoderDecodesPNG() throws {
        let data = try #require(TestImage.pngData(size: CGSize(width: 8, height: 6)))
        let request = ImageRequest(URL(string: "https://example.com/t.png")!, size: .original, processors: [])
        let image = try SystemDecoder().decode(request: request, data: data)
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        #expect(pixelWidth > 0)
        #expect(pixelHeight > 0)
        #expect(abs(pixelWidth / pixelHeight - 8.0 / 6.0) < 0.05)
    }
    
    @Test
    func systemDecoderRejectsInvalidData() {
        let request = ImageRequest(URL(string: "https://example.com/bad.png")!, size: .original)
        #expect(throws: IKError.self) {
            try SystemDecoder().decode(request: request, data: Data([0x00, 0x01]))
        }
    }
}

@Suite("PredrawnProcessor")
struct PredrawnProcessorTests {
    @Test
    func predrawnDownscalesLargerImage() throws {
        let source = try #require(TestImage.image(size: CGSize(width: 200, height: 100)))
        let request = ImageRequest(
            URL(string: "https://example.com/big.png")!,
            size: .absolute(CGSize(width: 40, height: 20)),
            mode: .fill,
            processors: .predrawn
        )
        let processor = PredrawnProcessor()
        #expect(processor.isValid(request: request))
        
        let result = processor.process(request: request, input: source)
        #expect(result.size.width * result.scale <= 40 * screenScale + 1)
        #expect(result.size.height * result.scale <= 20 * screenScale + 1)
    }
    
    @Test
    func predrawnSkipsWhenAlreadySmallEnough() throws {
        let source = try #require(TestImage.image(size: CGSize(width: 20, height: 20)))
        let request = ImageRequest(
            URL(string: "https://example.com/small.png")!,
            size: .absolute(CGSize(width: 100, height: 100)),
            mode: .fit,
            processors: .predrawn
        )
        let result = PredrawnProcessor().process(request: request, input: source)
        #expect(abs(result.size.width - source.size.width) < 0.5)
        #expect(abs(result.size.height - source.size.height) < 0.5)
    }
    
    @Test
    func predrawnInvalidWithoutFlag() {
        let request = ImageRequest(
            URL(string: "https://example.com/x.png")!,
            size: .absolute(CGSize(width: 40, height: 40)),
            processors: []
        )
        #expect(!PredrawnProcessor().isValid(request: request))
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
