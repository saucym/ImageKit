//
//  PredrawnProcessor.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/17.
//

import Foundation
import CoreGraphics
import SwiftUI

public extension RequestProcessor {
    static let predrawn = RequestProcessor(rawValue: 1 << 1)
}

extension CGSize {
    public static func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
        CGSize(width: lhs.width * rhs, height: lhs.height * rhs)
    }
    public static func / (lhs: CGSize, rhs: CGFloat) -> CGSize {
        CGSize(width: lhs.width / rhs, height: lhs.height / rhs)
    }
}

public class PredrawnProcessor: ImageProcessor {
    public init() { }
    
    public func isValid(request: ImageRequest) -> Bool {
        let modes: [ContentMode] = [.fill, .fit]
        return request.processors.contains(.predrawn) && modes.contains(request.mode)
    }
    
    public func process(request: ImageRequest, input: KKImage) -> KKImage {
        #if os(iOS)
        if let images = input.images, request.isGif != false {
            var outImages = [KKImage]()
            for sub in images {
                if let image = processOne(request: request, input: sub) {
                    outImages.append(image)
                }
            }
            if let image = KKImage.animatedImage(with: outImages, duration: input.duration),
               outImages.count == images.count {
                return image
            }
        } else if let image = processOne(request: request, input: input) {
            return image
        }
        #else
        if let image = processOne(request: request, input: input) {
            return image
        }
        #endif
        return input
    }
    
    private func rectFrom(_ imagePixelSize: CGSize, _ viewPixelSize: CGSize, _ mode: ContentMode, anchorPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> (CGRect, Int, Int) {
        let imageRatio = imagePixelSize.height / imagePixelSize.width
        let viewRatio = viewPixelSize.height / viewPixelSize.width
        var rect = CGRect.zero
        switch mode {
        case .fit:
            let scale = min(viewPixelSize.height / imagePixelSize.height, viewPixelSize.width / imagePixelSize.width, 1)
            rect.size = CGSize(width: imagePixelSize.width * scale, height: imagePixelSize.height * scale)
            return (rect, Int(rect.width), Int(rect.height))
        case .fill:
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
    
    private func processOne(request: ImageRequest, input: KKImage) -> KKImage? {
        let imagePixelSize = input.size * input.scale
        let viewPixelSize: CGSize
        let width = request.size.width ?? input.size.width
        if let height = request.size.height {
            viewPixelSize = CGSize(width: width, height: height) * screenScale
        } else {
            viewPixelSize = CGSize(width: width, height: input.size.height / input.size.width * width) * screenScale
        }
        guard imagePixelSize.width > viewPixelSize.width || imagePixelSize.height > viewPixelSize.height else {
            return nil
        }
        
        let (rect, contextWidth, contextHeight) = rectFrom(imagePixelSize, viewPixelSize, request.mode)
        var info: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        if let cgImage = input.cgImage {
            if cgImage.alphaInfo == .premultipliedLast
                || cgImage.alphaInfo == .premultipliedFirst
                || cgImage.alphaInfo == .last
                || cgImage.alphaInfo == .first {
                info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
            }
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bytesWidth = Int(contextWidth * 4)
            let bytesPerRow = ((bytesWidth + 63) / 64) * 64
            if let context = CGContext(data: nil, width: contextWidth, height: contextHeight, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: info) {
                // Align bytesPerRow to 64 so Core Animation can reuse the bitmap without copying
                context.draw(cgImage, in: rect)
                if let newCgImage = context.makeImage() {
                    #if os(iOS)
                    return KKImage(cgImage: newCgImage, scale: input.scale, orientation: input.imageOrientation)
                    #else
                    return KKImage(cgImage: newCgImage, size: .init(width: newCgImage.width, height: newCgImage.height))
                    #endif
                }
            }
        }
        
        return KKImage.scaledFrom(input, to: .init(width: contextWidth, height: contextHeight), rect: rect)
    }
}
