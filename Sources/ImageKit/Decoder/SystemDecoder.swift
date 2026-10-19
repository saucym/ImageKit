//
//  SystemDecoder.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/12.
//

import Foundation
import ImageIO

#if os(iOS)
private extension KKImage.Orientation {
    init(_ cgOrientation: CGImagePropertyOrientation) {
        switch cgOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        }
    }
}
#endif

public class SystemDecoder: NSObject { }

extension SystemDecoder: ImageDecoder {
    public func isValid(request: ImageRequest) -> Bool {
        true
    }
    
    public func decode(request: ImageRequest, data: Data) throws -> KKImage {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            throw IKError.imageSourceCreateError
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { throw IKError.decoderImageIsNil }

        #if os(iOS)
        if frameCount > 1, request.animation != .firstFrame {
            guard let image = decodeAnimation(source: source, count: frameCount, request: request) else {
                throw IKError.decoderImageIsNil
            }
            return image
        }
        #endif
        let properties = FrameProperties(source: source, index: 0)
        guard let image = decodeFrame(source: source, index: 0, properties: properties, request: request) else {
            throw IKError.decoderImageIsNil
        }
        return image
    }

    #if os(iOS)
    private func decodeAnimation(source: CGImageSource, count: Int, request: ImageRequest) -> KKImage? {
        var frames = [KKImage]()
        frames.reserveCapacity(count)
        var duration = 0.0
        for index in 0..<count {
            let properties = FrameProperties(source: source, index: index)
            guard let frame = decodeFrame(source: source, index: index, properties: properties, request: request) else { continue }
            frames.append(frame)
            duration += properties.duration
        }
        return frames.count > 1 ? KKImage.animatedImage(with: frames, duration: duration) : frames.first
    }
    #endif

    private func decodeFrame(source: CGImageSource, index: Int, properties: FrameProperties, request: ImageRequest) -> KKImage? {
        let thumbnailSize: Int?
        if request.processors.contains(.predrawn), let pixelSize = properties.pixelSize {
            thumbnailSize = ImageResizePlan(request: request, sourceSize: pixelSize)?.thumbnailMaxPixelSize
        } else {
            thumbnailSize = nil
        }
        #if os(macOS)
        // NSImage has no orientation field, so normalize even when keeping the original resolution.
        let maxPixelSize = thumbnailSize ?? properties.orientationMaxPixelSize
        #else
        let maxPixelSize = thumbnailSize
        #endif
        let cgImage: CGImage?
        if let maxPixelSize {
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ] as CFDictionary
            cgImage = CGImageSourceCreateThumbnailAtIndex(source, index, options)
        } else {
            let options = [kCGImageSourceShouldCacheImmediately: index == 0] as CFDictionary
            cgImage = CGImageSourceCreateImageAtIndex(source, index, options)
        }
        guard let cgImage else { return nil }
        #if os(iOS)
        let orientation = maxPixelSize == nil ? KKImage.Orientation(properties.orientation) : .up
        return KKImage(cgImage: cgImage, scale: screenScale, orientation: orientation)
        #else
        return KKImage(cgImage: cgImage, scale: screenScale)
        #endif
    }
}

private struct FrameProperties {
    private let values: NSDictionary?

    init(source: CGImageSource, index: Int) {
        values = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as NSDictionary?
    }

    var orientation: CGImagePropertyOrientation {
        let value = (values?[kCGImagePropertyOrientation as String] as? NSNumber)?.uint32Value ?? 1
        return CGImagePropertyOrientation(rawValue: value) ?? .up
    }

    var pixelSize: CGSize? {
        guard let width = values?[kCGImagePropertyPixelWidth as String] as? NSNumber,
              let height = values?[kCGImagePropertyPixelHeight as String] as? NSNumber else { return nil }
        let isRotated = (5...8).contains(orientation.rawValue)
        return CGSize(width: CGFloat(truncating: isRotated ? height : width), height: CGFloat(truncating: isRotated ? width : height))
    }

    #if os(macOS)
    var orientationMaxPixelSize: Int? {
        guard orientation != .up, let pixelSize,
              let maximum = Int(exactly: max(pixelSize.width, pixelSize.height)), maximum > 0 else { return nil }
        return maximum
    }
    #else
    var duration: Double {
        let gif = values?[kCGImagePropertyGIFDictionary as String] as? NSDictionary
        let png = values?[kCGImagePropertyPNGDictionary as String] as? NSDictionary
        let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber)
            ?? (png?[kCGImagePropertyAPNGUnclampedDelayTime as String] as? NSNumber)
            ?? (gif?[kCGImagePropertyGIFDelayTime as String] as? NSNumber)
            ?? (png?[kCGImagePropertyAPNGDelayTime as String] as? NSNumber)
        guard let duration = delay?.doubleValue, duration.isFinite, duration > 0.011 else { return 0.1 }
        return duration
    }
    #endif
}
