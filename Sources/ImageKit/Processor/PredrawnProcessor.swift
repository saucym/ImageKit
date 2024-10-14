//
//  PredrawnProcessor.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/17.
//

import Foundation
import CoreGraphics
import SwiftUI

public protocol ProcessorProtocol {
    func isValid(request: ImageRequest) -> Bool
    func processor(request: ImageRequest, input: KKImage) -> KKImage
}

public extension RequestProcessor {
    static let preDrawn = RequestProcessor(rawValue: 1 << 1)
}

extension CGSize {
    public static func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
        return CGSize(width: lhs.width * rhs, height: lhs.height * rhs)
    }
    public static func / (lhs: CGSize, rhs: CGFloat) -> CGSize {
        return CGSize(width: lhs.width / rhs, height: lhs.height / rhs)
    }
}

public class PredrawnProcessor: ProcessorProtocol {
    public init() { }
    public func isValid(request: ImageRequest) -> Bool {
        let modes: [ContentMode] = [.fill, .fit]
        return request.processors.contains(.preDrawn)
            && modes.contains(request.mode)
    }
    
    public func processor(request: ImageRequest, input: KKImage) -> KKImage {
        #if os(iOS)
        if let images = input.images, request.isGif != false {
            var outImages = [KKImage]()
            for sub in images {
                if let image = processorOneImage(request: request, input: sub) {
                    outImages.append(image)
                }
            }
            
            if let image = KKImage.animatedImage(with: outImages, duration: input.duration), outImages.count == images.count {
                return image
            }
        } else if let image = processorOneImage(request: request, input: input) {
            return image
        }
        #else
        if let image = processorOneImage(request: request, input: input) {
            return image
        }
        #endif
        
        return input
    }
    
    private func rectFrom(_ imagePixelSize: CGSize,_ viewPixelSize: CGSize,_ mode: ContentMode, anchorPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> (CGRect, Int, Int) {
        let imageRatio = imagePixelSize.height / imagePixelSize.width
        let viewRatio = viewPixelSize.height / viewPixelSize.width
        var rect = CGRect.zero
        switch mode {
        case .fit: // like scaleAspectFit
            let scale = min(viewPixelSize.height / imagePixelSize.height, viewPixelSize.width / imagePixelSize.width, 1)
            rect.size = CGSize(width: imagePixelSize.width * scale, height: imagePixelSize.height * scale)
            return (rect, Int(rect.width), Int(rect.height))
        case .fill: // like scaleAspectFill
            if imageRatio < viewRatio {
                rect.size = CGSize(width: viewPixelSize.height / imageRatio, height: viewPixelSize.height)
                rect.origin = CGPoint(x: (viewPixelSize.width - rect.width) * anchorPoint.x, y: 0)
            } else {
                rect.size = CGSize(width: viewPixelSize.width, height: viewPixelSize.width * imageRatio)
                rect.origin = CGPoint(x: 0, y: (viewPixelSize.height - rect.height) * anchorPoint.y)
            }
            
            let scale = min(imagePixelSize.height / viewPixelSize.height, imagePixelSize.width / viewPixelSize.width, 1)
            if scale < 1 {
                rect = CGRect(x: rect.origin.x * scale, y: rect.origin.y * scale, width: rect.width * scale, height: rect.height * scale)
            }
            
            return (rect, Int(viewPixelSize.width * scale), Int(viewPixelSize.height * scale))
        }
    }
    
    private func processorOneImage(request: ImageRequest, input: KKImage) -> KKImage? {
        let imagePixelSize = input.size * input.scale
        let viewPixelSize: CGSize
        let w = request.size.width
        if let height = request.size.height {
            viewPixelSize = CGSize(width: w, height: height) * kScale
        } else {
            viewPixelSize = CGSize(width: w, height: input.size.height / input.size.width * w) * kScale
        }
        if imagePixelSize.width > viewPixelSize.width || imagePixelSize.height > viewPixelSize.height {
            let (rect, contextWidth, contextHeight) = self.rectFrom(imagePixelSize, viewPixelSize, request.mode)
            var info: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            if let cgImage = input.cgImage {
                if cgImage.alphaInfo == CGImageAlphaInfo.premultipliedLast
                    || cgImage.alphaInfo == CGImageAlphaInfo.premultipliedFirst
                    || cgImage.alphaInfo == CGImageAlphaInfo.last
                    || cgImage.alphaInfo == CGImageAlphaInfo.first {
                    info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
                }
                
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let width = Int(contextWidth * 4)
                let bytesPerRow = ((width + (64 - 1)) / 64) * 64;
                if let context = CGContext(data: nil, width: contextWidth, height: contextHeight, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: info) {
                    //图像数据做了字节对齐处理,CoreAnimation使用时无需再处理拷贝。具体做法是CGBitmapContextCreate创建位图画布时bytesPerRow参数传64倍数 https://www.aliyun.com/jiaocheng/415760.html
                    context.draw(cgImage, in: rect)
                    if let newCgImage = context.makeImage() {
                        #if os(iOS)
                        let image = KKImage(cgImage: newCgImage, scale: input.scale, orientation: input.imageOrientation)
                        return image
                        #else
                        return KKImage(cgImage: newCgImage, size: .init(width: newCgImage.width, height: newCgImage.height))
                        #endif
                    }
                }
            }
            
            if let image = KKImage.scaledFrom(input, to: .init(width: contextWidth, height: contextHeight), rect: rect) {
                return image
            }
        }
        
        return nil;
    }
}
