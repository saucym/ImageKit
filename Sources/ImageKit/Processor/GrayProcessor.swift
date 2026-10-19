//
//  GrayProcessor.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/16.
//

import CoreGraphics
import Foundation

public extension RequestProcessor {
    static let gray = RequestProcessor(rawValue: 1 << 0)
}

public struct GrayProcessor: ImageProcessor {
    public init() {}
    
    public func isValid(request: ImageRequest) -> Bool {
        request.processors.contains(.gray)
    }

    public func process(request: ImageRequest, input: KKImage) -> KKImage {
        input.processingFrames(animation: request.animation) { frame in
            frame.toGray()
        }
    }
}

private extension KKImage {
    func toGray() -> KKImage {
        guard let cgImage, cgImage.colorSpace?.model != .monochrome else { return self }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let width = cgImage.width
        let height = cgImage.height
        let alphaInfo: CGImageAlphaInfo = cgImage.hasAlpha ? .premultipliedLast : .none
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: alphaInfo.rawValue) else {
            return self
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let grayImage = context.makeImage() else {
            return self
        }
        #if os(iOS)
        return KKImage(cgImage: grayImage, scale: scale, orientation: imageOrientation)
        #else
        return KKImage(cgImage: grayImage, scale: scale)
        #endif
    }
}
