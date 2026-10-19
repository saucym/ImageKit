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
    
    public func load(request: ImageRequest) async throws -> LoadResult? {
        try Task.checkCancellation()
        let result: LoadResult?
        if request.url.isFileURL {
            result = .data(try Data(contentsOf: request.url))
        } else if request.url.scheme == "ph" {
            let localIdentifier = request.url.absoluteString.replacingOccurrences(of: "ph://", with: "")
            await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            try Task.checkCancellation()
            if let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject {
                result = try await image(for: asset, size: request.size)
            } else {
                result = nil
            }
        } else if let asset = request.asset {
            result = try await image(for: asset, size: request.size)
        } else if request.url.pathExtension.lowercased() == "gif" {
            if let path = Bundle.main.path(forResource: request.url.absoluteString, ofType: nil) {
                result = .data(try Data(contentsOf: URL(fileURLWithPath: path)))
            } else {
                result = nil
            }
        } else if let image = KKImage(named: request.url.absoluteString) {
            result = .image(image)
        } else {
            result = nil
        }
        try Task.checkCancellation()
        return result
    }
    
    private func image(for asset: PHAsset, size: ImageRequest.Size) async throws -> LoadResult? {
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
        let state = PhotoRequestState()
        let manager = PHImageManager.default()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard state.register(continuation) else { return }
                let requestID = manager.requestImage(for: asset, targetSize: targetSize, contentMode: mode, options: options) { image, info in
                    if info?[PHImageCancelledKey] as? Bool == true {
                        state.finish(.failure(CancellationError()))
                    } else if let error = info?[PHImageErrorKey] as? Error {
                        state.finish(.failure(error))
                    } else if info?[PHImageResultIsDegradedKey] as? Bool != true {
                        state.finish(.success(image.map(LoadResult.image)))
                    }
                }
                state.setRequestID(requestID, manager: manager)
            }
        } onCancel: {
            state.cancel(manager: manager)
        }
    }
}

private final class PhotoRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<LoadResult?, Error>?
    private var requestID: PHImageRequestID?
    private var isFinished = false

    func register(_ continuation: CheckedContinuation<LoadResult?, Error>) -> Bool {
        lock.lock()
        if isFinished {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func setRequestID(_ requestID: PHImageRequestID, manager: PHImageManager) {
        lock.lock()
        self.requestID = requestID
        let isFinished = isFinished
        lock.unlock()
        if isFinished {
            manager.cancelImageRequest(requestID)
        }
    }

    func finish(_ result: Result<LoadResult?, Error>) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func cancel(manager: PHImageManager) {
        finish(.failure(CancellationError()))
        lock.lock()
        let requestID = requestID
        lock.unlock()
        if let requestID {
            manager.cancelImageRequest(requestID)
        }
    }
}
