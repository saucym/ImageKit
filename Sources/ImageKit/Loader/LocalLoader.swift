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

public class LocalLoader: NSObject { }

extension URL {
    public var assetExists: Bool {
        if #available(iOS 16.0, *, macOS 13.0, *) {
            scheme == "ph" || FileManager.default.fileExists(atPath: path(percentEncoded: false))
        } else {
            scheme == "ph" || FileManager.default.fileExists(atPath: path)
        }
    }
}

extension LocalLoader: DataLoader {
    public func isValid(request: ImageRequest) -> Bool {
        request.url.scheme != "http" && request.url.scheme != "https"
    }
    
    public func load(request: ImageRequest) async -> LoadResult? {
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
                return await image(for: asset, size: request.size)
            }
        } else if let asset = request.asset {
            return await image(for: asset, size: request.size)
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
    
    private func image(for asset: PHAsset, size: ImageRequest.Size) async -> LoadResult? {
        var targetSize: CGSize
        let mode: PHImageContentMode
        if let width = size.width {
            targetSize = CGSize(width: width * screenScale, height: 0)
            if asset.pixelHeight > asset.pixelWidth && asset.pixelWidth > 0 {
                mode = .default
                targetSize.height = CGFloat(asset.pixelHeight) / CGFloat(asset.pixelWidth) * targetSize.width
            } else {
                mode = .aspectFill
            }
            if targetSize.height == 0 {
                if let height = size.height {
                    targetSize.height = height * screenScale
                } else if asset.pixelWidth > 0 {
                    targetSize.height = CGFloat(asset.pixelHeight) / CGFloat(asset.pixelWidth) * targetSize.width
                } else {
                    targetSize.height = targetSize.width
                }
            }
        } else {
            targetSize = PHImageManagerMaximumSize
            mode = .default
        }
        
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.resizeMode = .exact
        options.deliveryMode = .highQualityFormat
        options.version = .current
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: mode, options: options) { image, _ in
                if let image {
                    continuation.resume(returning: .image(image))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
