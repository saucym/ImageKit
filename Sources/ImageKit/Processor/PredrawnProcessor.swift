//
//  PredrawnProcessor.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/17.
//

import Foundation
import CoreGraphics
import SwiftUI
#if os(iOS)
import UIKit
#endif

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
        if let images = input.images, !images.isEmpty {
            if request.animation == .firstFrame {
                let first = images[0]
                return processOne(request: request, input: first) ?? first
            }
            let outImages = images.map { processOne(request: request, input: $0) ?? $0 }
            if let image = KKImage.animatedImage(with: outImages, duration: input.duration) {
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
    
    private func processOne(request: ImageRequest, input: KKImage) -> KKImage? {
        guard let cgImage = input.cgImage else { return nil }
        #if os(iOS)
        let isRotated: Bool
        switch input.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored: isRotated = true
        default: isRotated = false
        }
        let imagePixelSize = CGSize(width: isRotated ? cgImage.height : cgImage.width, height: isRotated ? cgImage.width : cgImage.height)
        #else
        let imagePixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        #endif
        let viewPixelSize: CGSize
        switch request.size {
        case .original:
            return nil
        case .absolute(let size):
            viewPixelSize = size * screenScale
        case .width(let width, _):
            viewPixelSize = CGSize(width: width, height: imagePixelSize.height / imagePixelSize.width * width) * screenScale
        }
        guard viewPixelSize.width.isFinite, viewPixelSize.height.isFinite,
              viewPixelSize.width > 0, viewPixelSize.height > 0 else { return nil }

        let outputSize: CGSize
        switch request.mode {
        case .fit:
            let scale = min(viewPixelSize.width / imagePixelSize.width, viewPixelSize.height / imagePixelSize.height, 1)
            outputSize = imagePixelSize * scale
        case .fill:
            let scale = min(imagePixelSize.width / viewPixelSize.width, imagePixelSize.height / viewPixelSize.height, 1)
            outputSize = viewPixelSize * scale
        }
        let contextWidth = max(1, Int(floor(outputSize.width)))
        let contextHeight = max(1, Int(floor(outputSize.height)))
        guard contextWidth != Int(imagePixelSize.width) || contextHeight != Int(imagePixelSize.height) else { return nil }
        let canvasSize = CGSize(width: contextWidth, height: contextHeight)
        let rect: CGRect
        switch request.mode {
        case .fit:
            rect = CGRect(origin: .zero, size: canvasSize)
        case .fill:
            let scale = max(canvasSize.width / imagePixelSize.width, canvasSize.height / imagePixelSize.height)
            let drawnSize = imagePixelSize * scale
            rect = CGRect(x: (canvasSize.width - drawnSize.width) / 2, y: (canvasSize.height - drawnSize.height) / 2, width: drawnSize.width, height: drawnSize.height)
        }
        let hasAlpha: Bool
        switch cgImage.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly: hasAlpha = true
        default: hasAlpha = false
        }
        let alphaInfo: CGImageAlphaInfo = hasAlpha ? .premultipliedFirst : .noneSkipFirst
        let info = CGBitmapInfo.byteOrder32Little.rawValue | alphaInfo.rawValue
        // Align rows so Core Animation can reuse the bitmap without copying.
        let bytesPerRow = ((contextWidth * 4 + 63) / 64) * 64
        guard let context = CGContext(data: nil, width: contextWidth, height: contextHeight, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
        context.interpolationQuality = .high
        #if os(iOS)
        context.translateBy(x: 0, y: canvasSize.height)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        input.draw(in: rect)
        UIGraphicsPopContext()
        #else
        context.draw(cgImage, in: rect)
        #endif
        guard let newCgImage = context.makeImage() else { return nil }
        #if os(iOS)
        return KKImage(cgImage: newCgImage, scale: input.scale, orientation: .up)
        #else
        return KKImage(cgImage: newCgImage, scale: input.scale)
        #endif
    }
}
