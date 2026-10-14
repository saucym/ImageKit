//
//  SystemDecoder.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/12.
//

import Foundation
import ImageIO

#if os(iOS)
extension KKImage.Orientation {
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

        #if os(iOS)
        let count = request.animation == .firstFrame ? min(CGImageSourceGetCount(source), 1) : CGImageSourceGetCount(source)
        #else
        let count = min(CGImageSourceGetCount(source), 1)
        #endif

        guard let image = decodeFrames(source: source, count: count, request: request) else {
            throw IKError.decoderImageIsNil
        }
        return image
    }

    private func decodeFrames(source: CGImageSource, count: Int, request: ImageRequest) -> KKImage? {
        func imageFrom(cgImage: CGImage, properties: NSDictionary?, transformed: Bool) -> KKImage {
            #if os(iOS)
            var orientation = KKImage.Orientation.up
            if !transformed, let properties,
               let num = properties[kCGImagePropertyOrientation] as? NSNumber,
               let ori = CGImagePropertyOrientation(rawValue: num.uint32Value) {
                orientation = KKImage.Orientation(ori)
            }
            return KKImage(cgImage: cgImage, scale: screenScale, orientation: orientation)
            #else
            return KKImage(cgImage: cgImage, scale: screenScale)
            #endif
        }
        
        func frameDuration(from properties: NSDictionary?) -> Double {
            let defaultFrameDuration = 0.100
            let gifInfo = properties?[kCGImagePropertyGIFDictionary as String] as? NSDictionary
            let pngInfo = properties?[kCGImagePropertyPNGDictionary as String] as? NSDictionary
            let unclampedDelayTime = (gifInfo?[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber)
                ?? (pngInfo?[kCGImagePropertyAPNGUnclampedDelayTime as String] as? NSNumber)
            let delayTime = (gifInfo?[kCGImagePropertyGIFDelayTime as String] as? NSNumber)
                ?? (pngInfo?[kCGImagePropertyAPNGDelayTime as String] as? NSNumber)
            guard let frameDuration = unclampedDelayTime ?? delayTime else {
                return defaultFrameDuration
            }
            return frameDuration.doubleValue > 0.011 ? frameDuration.doubleValue : defaultFrameDuration
        }

        var list = [KKImage]()
        var duration = 0.0
        for i in 0..<count {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as NSDictionary?
            let cgImage: CGImage?
            let transformed: Bool
            #if os(macOS)
            let maxPixelSize = thumbnailMaxPixelSize(request: request, properties: properties) ?? orientationMaxPixelSize(properties: properties)
            #else
            let maxPixelSize = thumbnailMaxPixelSize(request: request, properties: properties)
            #endif
            if let maxPixelSize {
                let options = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
                ] as CFDictionary
                cgImage = CGImageSourceCreateThumbnailAtIndex(source, i, options)
                transformed = true
            } else {
                let options = [kCGImageSourceShouldCacheImmediately: i == 0] as CFDictionary
                cgImage = CGImageSourceCreateImageAtIndex(source, i, options)
                transformed = false
            }
            guard let cgImage else {
                continue
            }
            list.append(imageFrom(cgImage: cgImage, properties: properties, transformed: transformed))
            duration += frameDuration(from: properties)
        }
        
        if list.count <= 1 {
            return list.first
        }
        #if os(iOS)
        return KKImage.animatedImage(with: list, duration: duration)
        #else
        return list.first
        #endif
    }

    private func thumbnailMaxPixelSize(request: ImageRequest, properties: NSDictionary?) -> Int? {
        guard request.processors.contains(.predrawn),
              let properties,
              let pixelWidth = properties[kCGImagePropertyPixelWidth as String] as? NSNumber,
              let pixelHeight = properties[kCGImagePropertyPixelHeight as String] as? NSNumber else {
            return nil
        }
        let orientation = (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.uint32Value ?? 1
        let isRotated = (5...8).contains(orientation)
        let width = CGFloat(truncating: isRotated ? pixelHeight : pixelWidth)
        let height = CGFloat(truncating: isRotated ? pixelWidth : pixelHeight)
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }

        let scale: CGFloat
        switch request.size {
        case .original:
            return nil
        case .width(let targetWidth, _):
            guard targetWidth.isFinite, targetWidth > 0 else { return nil }
            scale = targetWidth * screenScale / width
        case .absolute(let target):
            guard target.width.isFinite, target.height.isFinite, target.width > 0, target.height > 0 else { return nil }
            let widthScale = target.width * screenScale / width
            let heightScale = target.height * screenScale / height
            switch request.mode {
            case .fit: scale = min(widthScale, heightScale)
            case .fill: scale = max(widthScale, heightScale)
            }
        }
        // ImageIO's bound is the longest side; fill must retain enough pixels on the shorter side for cropping.
        return max(1, Int(ceil(max(width, height) * min(scale, 1))))
    }

    #if os(macOS)
    private func orientationMaxPixelSize(properties: NSDictionary?) -> Int? {
        guard let properties,
              let orientation = properties[kCGImagePropertyOrientation as String] as? NSNumber,
              orientation.intValue != 1,
              let width = properties[kCGImagePropertyPixelWidth as String] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight as String] as? NSNumber else { return nil }
        // NSImage(CGImage) has no orientation field, so normalize even when keeping the original resolution.
        return max(width.intValue, height.intValue, 1)
    }
    #endif
}
