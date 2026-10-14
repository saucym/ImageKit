import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import ImageKit
#if os(iOS)
import UIKit
#endif

@Suite("Image decoding and processing")
struct DecodingBehaviorTests {
    @Test
    func fitDownsamplingConstrainsBothDimensions() throws {
        for size in [CGSize(width: 1200, height: 300), CGSize(width: 300, height: 1200)] {
            let data = try DecodingFixture.data(width: Int(size.width), height: Int(size.height))
            let request = request(size: .absolute(CGSize(width: 60, height: 80)), mode: .fit)
            let decoded = try SystemDecoder().decode(request: request, data: data)
            let image = try #require(decoded.cgImage)
            let scale = min(60 * screenScale / size.width, 80 * screenScale / size.height)
            #expect(abs(CGFloat(image.width) - size.width * scale) <= 1)
            #expect(abs(CGFloat(image.height) - size.height * scale) <= 1)
        }
    }

    @Test
    func fillDownsamplingKeepsEnoughPixelsForTheCrop() throws {
        for size in [CGSize(width: 1200, height: 300), CGSize(width: 300, height: 1200)] {
            let data = try DecodingFixture.data(width: Int(size.width), height: Int(size.height))
            let request = request(size: .absolute(CGSize(width: 60, height: 80)), mode: .fill)
            let decoded = try SystemDecoder().decode(request: request, data: data)
            let image = try #require(decoded.cgImage)
            #expect(CGFloat(image.width) >= 60 * screenScale - 1)
            #expect(CGFloat(image.height) >= 80 * screenScale - 1)
            let processed = try #require(PredrawnProcessor().process(request: request, input: decoded).cgImage)
            #expect(abs(CGFloat(processed.width) - 60 * screenScale) <= 1)
            #expect(abs(CGFloat(processed.height) - 80 * screenScale) <= 1)
        }
    }

    @Test
    func widthDownsamplingUsesTheAspectRatioAndIgnoresPlaceholderHeight() throws {
        let data = try DecodingFixture.data(width: 300, height: 1200)
        let request = request(size: .width(40, defaultHeight: 1))
        let image = try #require(SystemDecoder().decode(request: request, data: data).cgImage)
        #expect(abs(CGFloat(image.width) - 40 * screenScale) <= 1)
        #expect(abs(CGFloat(image.height) - 160 * screenScale) <= 1)
    }

    @Test
    func disablingPredrawingKeepsAllSourcePixels() throws {
        let data = try DecodingFixture.data(width: 1200, height: 300)
        let request = request(size: .absolute(CGSize(width: 10, height: 10)), processors: [])
        let image = try #require(SystemDecoder().decode(request: request, data: data).cgImage)
        #expect(image.width == 1200)
        #expect(image.height == 300)
    }

    @Test
    func downsamplingAppliesEXIFOrientationBeforeSizing() throws {
        let data = try DecodingFixture.data(width: 1200, height: 300, type: .jpeg, orientation: 6)
        let request = request(size: .absolute(CGSize(width: 60, height: 80)), mode: .fit)
        let decoded = try SystemDecoder().decode(request: request, data: data)
        let image = try #require(decoded.cgImage)
        #expect(abs(CGFloat(image.width) - 20 * screenScale) <= 1)
        #expect(abs(CGFloat(image.height) - 80 * screenScale) <= 1)
        #if os(iOS)
        #expect(decoded.imageOrientation == .up)
        #endif
    }

    @Test
    func originalImagesKeepEXIFOrientationAndFullResolution() throws {
        let data = try DecodingFixture.data(width: 1200, height: 300, type: .jpeg, orientation: 6)
        let decoded = try SystemDecoder().decode(request: request(size: .original, processors: []), data: data)
        let image = try #require(decoded.cgImage)
        #if os(macOS)
        #expect(image.width == 300)
        #expect(image.height == 1200)
        #else
        #expect(image.width == 1200)
        #expect(image.height == 300)
        #expect(decoded.imageOrientation == .right)
        #endif
    }

    @Test
    func predrawingPreservesTransparentAndTranslucentPixels() throws {
        let original = try DecodingFixture.image(width: 200, height: 100, alpha: 0.5)
        let request = request(size: .absolute(CGSize(width: 20, height: 10)))
        let processed = try #require(PredrawnProcessor().process(request: request, input: KKImage(cgImage: original, scale: 1)).cgImage)
        #expect(try DecodingFixture.pixel(in: processed, xFraction: 0.1).alpha == 0)
        #expect(abs(Int(try DecodingFixture.pixel(in: processed, xFraction: 0.9).alpha) - 128) <= 1)
    }

    @Test
    func grayscalePreservesAlpha() throws {
        let original = try DecodingFixture.image(width: 40, height: 20, alpha: 0.5)
        let request = request(size: .original, processors: .gray)
        let processed = try #require(GrayProcessor().process(request: request, input: KKImage(cgImage: original, scale: 1)).cgImage)
        let transparent = try DecodingFixture.pixel(in: processed, xFraction: 0.1)
        let translucent = try DecodingFixture.pixel(in: processed, xFraction: 0.9)
        #expect(transparent.alpha == 0)
        #expect(abs(Int(translucent.alpha) - 128) <= 1)
        #expect(translucent.red == translucent.green)
        #expect(translucent.green == translucent.blue)
    }

    @Test
    func fillCropsSmallImagesWithoutUpscaling() throws {
        let original = try DecodingFixture.image(width: 20, height: 10)
        let request = request(size: .absolute(CGSize(width: 100, height: 100)))
        let image = try #require(PredrawnProcessor().process(request: request, input: KKImage(cgImage: original, scale: 1)).cgImage)
        #expect(image.width == 10)
        #expect(image.height == 10)
    }

    #if os(iOS)
    @Test
    func automaticAnimationUsesImageContentInsteadOfTheURLSuffix() throws {
        let data = try DecodingFixture.gifData()
        let request = ImageRequest(URL(string: "https://example.com/image.png")!, size: .original, processors: [])
        let image = try SystemDecoder().decode(request: request, data: data)
        #expect(image.images?.count == 2)
        #expect(abs(image.duration - 0.4) < 0.01)
        let frames = try #require(image.images)
        let first = try DecodingFixture.pixel(in: #require(frames[0].cgImage), xFraction: 0.9)
        let second = try DecodingFixture.pixel(in: #require(frames[1].cgImage), xFraction: 0.9)
        #expect(first.red > first.blue)
        #expect(second.blue > second.red)
    }

    @Test
    func firstFramePolicyDisablesAnimation() throws {
        let data = try DecodingFixture.gifData()
        let request = ImageRequest(URL(string: "https://example.com/image.gif")!, size: .original, processors: [], animation: .firstFrame)
        let image = try SystemDecoder().decode(request: request, data: data)
        #expect(image.images == nil)
        #expect(image.cgImage != nil)
    }

    @Test
    func animatedPolicyKeepsFramesThroughDownsamplingAndProcessing() throws {
        let data = try DecodingFixture.gifData()
        let request = ImageRequest(URL(string: "https://example.com/image")!, size: .absolute(CGSize(width: 8, height: 8)), mode: .fit, processors: [.gray, .predrawn], animation: .animated)
        let decoded = try SystemDecoder().decode(request: request, data: data)
        let processed = PredrawnProcessor().process(request: request, input: GrayProcessor().process(request: request, input: decoded))
        let frames = try #require(processed.images)
        #expect(frames.count == 2)
        #expect(abs(processed.duration - 0.4) < 0.01)
        for frame in frames {
            let cgImage = try #require(frame.cgImage)
            #expect(CGFloat(cgImage.width) <= 8 * screenScale + 1)
            #expect(CGFloat(cgImage.height) <= 8 * screenScale + 1)
        }
    }

    @Test
    func processorsPreserveTheVisualOrientation() throws {
        let cgImage = try DecodingFixture.image(width: 120, height: 40)
        let source = UIImage(cgImage: cgImage, scale: 1, orientation: .right)
        let grayRequest = request(size: .original, processors: .gray)
        let gray = GrayProcessor().process(request: grayRequest, input: source)
        #expect(gray.imageOrientation == .right)
        #expect(gray.cgImage?.width == 120)
        #expect(gray.cgImage?.height == 40)
        let resizeRequest = request(size: .absolute(CGSize(width: 20, height: 30)), mode: .fit)
        let resized = PredrawnProcessor().process(request: resizeRequest, input: gray)
        let resizedCGImage = try #require(resized.cgImage)
        #expect(resized.imageOrientation == .up)
        #expect(abs(CGFloat(resizedCGImage.width) - 10 * screenScale) <= 1)
        #expect(abs(CGFloat(resizedCGImage.height) - 30 * screenScale) <= 1)
    }
    #endif

    private func request(size: ImageRequest.Size, mode: ContentMode = .fill, processors: RequestProcessor = .predrawn) -> ImageRequest {
        ImageRequest(URL(string: "https://example.com/image")!, size: size, mode: mode, processors: processors)
    }
}

private enum DecodingFixture {
    struct Pixel {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8
    }

    static func image(width: Int, height: Int, alpha: CGFloat = 1, isBlue: Bool = false) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: isBlue ? 0 : 1, green: 0, blue: isBlue ? 1 : 0, alpha: alpha))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return try #require(context.makeImage())
    }

    static func data(width: Int, height: Int, type: UTType = .png, orientation: Int = 1) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        let properties = [kCGImagePropertyOrientation: orientation] as CFDictionary
        CGImageDestinationAddImage(destination, try image(width: width, height: height), properties)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func pixel(in image: CGImage, xFraction: CGFloat) throws -> Pixel {
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = (image.height / 2 * image.width + Int(CGFloat(image.width) * xFraction)) * 4
        return Pixel(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2], alpha: bytes[offset + 3])
    }

    #if os(iOS)
    static func gifData() throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil))
        for (index, duration) in [0.1, 0.3].enumerated() {
            let image = try image(width: 80, height: 40, isBlue: index == 1)
            let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: duration]] as CFDictionary
            CGImageDestinationAddImage(destination, image, properties)
        }
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
    #endif
}
