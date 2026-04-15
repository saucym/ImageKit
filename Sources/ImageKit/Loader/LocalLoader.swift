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
        return request.url.scheme != "http" && request.url.scheme != "https"
    }
    
    public func loadFor(request: ImageRequest) async -> ResultItem? {
        if request.url.isFileURL {
            do {
                let data = try Data(contentsOf: request.url)
                return .data(data)
            } catch {
                logInfo(error.localizedDescription)
                return nil
            }
        } else if request.url.scheme == "ph" {
            let localIdentifier = request.url.absoluteString.replacingOccurrences(of: "ph://", with: "")
            await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            if let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject {
                return await imageFor(asset: asset, size: request.size)
            }
        } else if let asset = request.asset {
            return await imageFor(asset: asset, size: request.size)
        } else if request.url.pathExtension.lowercased() == "gif" {
            if let path = Bundle.main.path(forResource: request.url.absoluteString, ofType: nil) {
                do {
                    let url = URL(fileURLWithPath: path)
                    let data = try Data(contentsOf: url)
                    return .data(data)
                } catch {
                    logInfo(error.localizedDescription)
                    return nil
                }
            }
        } else if let image = KKImage(named: request.url.absoluteString) {
            return .image(image)
        }
        return nil
    }
    
    private func imageFor(asset: PHAsset, size: ImageRequest.Size) async -> ResultItem? {
        var tSize: CGSize
        let mode: PHImageContentMode
        if let width = size.width {
            tSize = CGSize(width: width * kScale, height: 0)
            if asset.pixelHeight > asset.pixelWidth && asset.pixelWidth > 0 {
                mode = .default
                tSize.height = CGFloat(asset.pixelHeight) / CGFloat(asset.pixelWidth) * tSize.width
            } else {
                mode = .aspectFill
            }
            if tSize.height == 0 {
                if let height = size.height {
                    tSize.height = height * kScale
                } else if asset.pixelWidth > 0 {
                    tSize.height = CGFloat(asset.pixelHeight) / CGFloat(asset.pixelWidth) * tSize.width
                } else {
                    tSize.height = tSize.width
                }
            }
        } else {
            tSize = PHImageManagerMaximumSize
            mode = .default
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
    }
}
