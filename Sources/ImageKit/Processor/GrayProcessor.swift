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
        #if os(iOS)
        if let images = input.images, !images.isEmpty {
            let newImages = images.map { $0.toGray() }
            if let newImage = KKImage.animatedImage(with: newImages, duration: input.duration) {
                return newImage
            }
        }
        #endif
        return input.toGray()
    }
}

private extension KKImage {
    func toGray() -> KKImage {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageByteOrderInfo.orderDefault.rawValue),
              let cgImage else {
            return self
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let grayImage = context.makeImage() else {
            return self
        }
        #if os(iOS)
        return KKImage(cgImage: grayImage, scale: scale, orientation: .up)
        #else
        return KKImage(cgImage: grayImage, scale: scale)
        #endif
    }
}
