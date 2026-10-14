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
            if request.animation == .firstFrame {
                return images[0].toGray()
            }
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
        guard let cgImage else { return self }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let width = cgImage.width
        let height = cgImage.height
        let hasAlpha: Bool
        switch cgImage.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly: hasAlpha = true
        default: hasAlpha = false
        }
        let alphaInfo: CGImageAlphaInfo = hasAlpha ? .premultipliedLast : .none
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
