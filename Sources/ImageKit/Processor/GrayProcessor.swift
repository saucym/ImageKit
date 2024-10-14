//
//  GrayProcessor.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/16.
//

import CoreGraphics
import Foundation

public extension RequestProcessor {
    static let Gay = RequestProcessor(rawValue: 1 << 0)
}

public struct GrayProcessor: ProcessorProtocol {
    public init () {}
    public func isValid(request: ImageRequest) -> Bool {
        return request.processors.contains(.Gay)
    }

    public func processor(request: ImageRequest, input: KKImage) -> KKImage {
        #if os(iOS)
        if let images = input.images, !images.isEmpty {
            let newImages = images.map { $0.imageToGray() }
            if let newImage = KKImage.animatedImage(with: newImages, duration: input.duration) {
                return newImage
            }
        }
        #endif
        
        return input.imageToGray()
    }

    public func cancel(request: ImageRequest) {
    }
}

private extension KKImage {
    func imageToGray() -> KKImage {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        if let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageByteOrderInfo.orderDefault.rawValue), let cgImage = self.cgImage {
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            if let mImage = context.makeImage() {
                #if os(iOS)
                let image = KKImage(cgImage: mImage, scale: scale, orientation: .up)
                #else
                let image = KKImage(cgImage: mImage, scale: scale)
                #endif
                return image
            }
        }
        return self
    }
}
