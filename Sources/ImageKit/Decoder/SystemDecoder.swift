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
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw IKError.imageSourceCreateError
        }
        
        #if os(iOS)
        let count = CGImageSourceGetCount(source)
        #else
        let count = min(CGImageSourceGetCount(source), 1)
        #endif
        
        let image: KKImage?
        if count == 0 {
            image = KKImage(data: data, scale: screenScale)
        } else if count == 1, request.processors.rawValue > 0 {
            image = KKImage(data: data, scale: screenScale)
        } else {
            image = decodeFrames(source: source, count: count)
        }
        
        guard let image else {
            throw IKError.decoderImageIsNil
        }
        return image
    }
    
    private func decodeFrames(source: CGImageSource, count: Int) -> KKImage? {
        func imageFrom(cgImage: CGImage, properties: NSDictionary?) -> KKImage {
            #if os(iOS)
            var orientation = KKImage.Orientation.up
            if let properties,
               let num = properties[kCGImagePropertyOrientation] as? NSNumber,
               let ori = CGImagePropertyOrientation(rawValue: num.uint32Value) {
                orientation = KKImage.Orientation(ori)
            }
            return KKImage(cgImage: cgImage, scale: screenScale, orientation: orientation)
            #else
            return KKImage(cgImage: cgImage, scale: screenScale)
            #endif
        }
        
        func frameDuration(from gifInfo: NSDictionary?) -> Double {
            let gifDefaultFrameDuration = 0.100
            guard let gifInfo else { return gifDefaultFrameDuration }
            let unclampedDelayTime = gifInfo[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber
            let delayTime = gifInfo[kCGImagePropertyGIFDelayTime as String] as? NSNumber
            guard let frameDuration = unclampedDelayTime ?? delayTime else {
                return gifDefaultFrameDuration
            }
            return frameDuration.doubleValue > 0.011 ? frameDuration.doubleValue : gifDefaultFrameDuration
        }
        
        // First frame caches immediately so Core Animation can reuse the bitmap
        var optionDict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, nil, nil) as Dictionary
        optionDict[kCGImageSourceShouldCacheImmediately] = kCFBooleanTrue
        let option = optionDict as CFDictionary
        var list = [KKImage]()
        var duration = 0.0
        let firstProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        
        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, i == 0 ? option : nil) else {
                continue
            }
            let properties: NSDictionary? = i == 0 ? firstProperties : CGImageSourceCopyPropertiesAtIndex(source, i, nil)
            list.append(imageFrom(cgImage: cgImage, properties: firstProperties))
            
            if let properties,
               let gifInfo = properties[kCGImagePropertyGIFDictionary as String] as? NSDictionary {
                duration += frameDuration(from: gifInfo)
            }
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
}
