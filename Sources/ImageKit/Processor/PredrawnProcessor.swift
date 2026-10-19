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
        request.processors.contains(.predrawn)
    }
    
    public func process(request: ImageRequest, input: KKImage) -> KKImage {
        input.processingFrames(animation: request.animation) { frame in
            processFrame(request: request, input: frame) ?? frame
        }
    }
    
    private func processFrame(request: ImageRequest, input: KKImage) -> KKImage? {
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
        guard let plan = ImageResizePlan(request: request, sourceSize: imagePixelSize) else { return nil }
        let contextWidth = plan.width
        let contextHeight = plan.height
        guard contextWidth != Int(imagePixelSize.width) || contextHeight != Int(imagePixelSize.height) else { return nil }
        let canvasSize = plan.size
        let rect: CGRect
        switch request.mode {
        case .fit:
            rect = CGRect(origin: .zero, size: canvasSize)
        case .fill:
            let scale = max(canvasSize.width / imagePixelSize.width, canvasSize.height / imagePixelSize.height)
            let drawnSize = imagePixelSize * scale
            rect = CGRect(x: (canvasSize.width - drawnSize.width) / 2, y: (canvasSize.height - drawnSize.height) / 2, width: drawnSize.width, height: drawnSize.height)
        }
        let alphaInfo: CGImageAlphaInfo = cgImage.hasAlpha ? .premultipliedFirst : .noneSkipFirst
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
