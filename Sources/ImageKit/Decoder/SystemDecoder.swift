//
//  SystemDecoder.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/12.
//

import Foundation
import ImageIO

public protocol DecoderProtocol {
    func isValid(request: ImageRequest) -> Bool
    func decoder(request: ImageRequest, data: Data) async throws -> KKImage
}

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

extension SystemDecoder: DecoderProtocol {
    public func isValid(request: ImageRequest) -> Bool {
        return true
    }
    
    public func decoder(request: ImageRequest, data: Data) async throws -> KKImage {
        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
            #if os(iOS)
            let count = CGImageSourceGetCount(source)
            #else
            let count = min(CGImageSourceGetCount(source), 1)
            #endif
            var image: KKImage?
            if (count == 0) {
                image = KKImage(data: data, scale: kScale)
            } else {
                if count == 1, request.processors.rawValue > 0 {
                    image = KKImage(data: data, scale: kScale)
                } else {
                    //Calculates frame duration for a gif frame out of the kCGImagePropertyGIFDictionary dictionary
                    func imageFrom(cgImage: CGImage, propreties: NSDictionary?) -> KKImage {
                        #if os(iOS)
                        var orientation = KKImage.Orientation.up
                        if let propreties = propreties {
                            if let num = propreties[kCGImagePropertyOrientation] as? NSNumber {
                                if let ori = CGImagePropertyOrientation(rawValue: num.uint32Value) {
                                    orientation = KKImage.Orientation(ori)
                                }
                            }
                        }
                        
                        return KKImage(cgImage: cgImage, scale: kScale, orientation: orientation)
                        #else
                        return KKImage(cgImage: cgImage, scale: kScale)
                        #endif
                    }
                    
                    func frameDuration(from gifInfo: NSDictionary?) -> Double {
                        let gifDefaultFrameDuration = 0.100
                        
                        guard let gifInfo = gifInfo else {
                            return gifDefaultFrameDuration
                        }
                        
                        let unclampedDelayTime = gifInfo[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber
                        let delayTime = gifInfo[kCGImagePropertyGIFDelayTime as String] as? NSNumber
                        let duration = unclampedDelayTime ?? delayTime
                        
                        guard let frameDuration = duration else { return gifDefaultFrameDuration }
                        
                        return frameDuration.doubleValue > 0.011 ? frameDuration.doubleValue : gifDefaultFrameDuration
                    }
                    
                    //TODO: The first picture needs to be set kCGImageSourceShouldCacheImmediately
                    var optionDict = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, nil, nil) as Dictionary
                    optionDict[kCGImageSourceShouldCacheImmediately] = kCFBooleanTrue
                    let option = optionDict as CFDictionary
                    var list = [KKImage]()
                    var duration = 0.0
                    let firstPropreties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                    for i in 0..<count {
                        if let cgImage = CGImageSourceCreateImageAtIndex(source, i, i == 0 ? option : nil) {
                            var propreties: NSDictionary?
                            if i == 0 {
                                propreties = firstPropreties
                            } else {
                                propreties = CGImageSourceCopyPropertiesAtIndex(source, i, nil)
                            }
                            let indexImage = imageFrom(cgImage: cgImage, propreties: firstPropreties)
                            list.append(indexImage)
                            
                            if let propreties = propreties {
                                if let gifInfo = propreties[kCGImagePropertyGIFDictionary as String] as? NSDictionary {
                                    duration += frameDuration(from: gifInfo)
                                }
                            }
                        }
                    }
                    
                    if list.count <= 1 {
                        image = list.first
                    } else if list.count > 1 {
                        #if os(iOS)
                        image = KKImage.animatedImage(with: list, duration: duration)
                        #else
                        image = list.first
                        #endif
                    }
                }
            }
            
            if let image {
                return image
            } else {
                throw IKError.decoderImageIsNil
            }
        } else {
            throw IKError.imageSourceCreateError
        }
    }
    
}
