//
//  LocalLoader.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/12.
//

import Photos
import Foundation
#if os(OSX)
import AppKit
#else
import UIKit
#endif

public protocol LoaderProtocol {
    func isValid(request: ImageRequest) -> Bool
    func loadFor(request: ImageRequest) async -> ResultItem?
}

public class LocalLoader: NSObject { }

extension LocalLoader: LoaderProtocol {
    public func isValid(request: ImageRequest) -> Bool {
        return !request.url.hasPrefix("http")
    }
    
    public func loadFor(request: ImageRequest) async -> ResultItem? {
        if request.url.hasPrefix("/") {
            do {
                let url = URL(fileURLWithPath: request.url)
                let data = try Data(contentsOf: url)
                return .data(data)
            } catch {
                logInfo(error.localizedDescription)
                return nil
            }
        } else if let asset = request.asset {
            var tSize = CGSize(width: request.size.width * kScale, height: 0)
            var mode = PHImageContentMode.aspectFill
            if asset.pixelHeight > asset.pixelWidth && asset.pixelWidth > 0 {
                mode = .default
                tSize.height = CGFloat(asset.pixelHeight) / CGFloat(asset.pixelWidth) * tSize.width
            }
            if tSize.height == 0 {
                if let height = request.size.height {
                    tSize.height = height * kScale
                } else if asset.pixelWidth > 0 {
                    tSize.height = CGFloat(asset.pixelHeight) / CGFloat(asset.pixelWidth) * tSize.width
                } else {
                    tSize.height = tSize.width
                }
            }
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.resizeMode = .exact
            options.deliveryMode = .highQualityFormat
            options.version = .current
            return await withCheckedContinuation { continuation in
                PHImageManager.default().requestImage(for: asset, targetSize: tSize, contentMode: mode, options: options) { (image, _) in
                    if let image {
                        continuation.resume(returning: .image(image))
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        } else if request.url.uppercased().hasSuffix(".GIF") {
            if let path = Bundle.main.path(forResource: request.url, ofType: nil) {
                do {
                    let url = URL(fileURLWithPath: path)
                    let data = try Data(contentsOf: url)
                    return .data(data)
                } catch {
                    logInfo(error.localizedDescription)
                    return nil
                }
            }
        } else if let image = KKImage(named: request.url) {
            return .image(image)
        }
        return nil
    }
}
