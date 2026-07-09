//
//  URLImageLoader.swift
//  ImageKit
//
//  Created by qhc_m@qq.com on 2022/7/28.
//

import SwiftUI
import Photos

public struct URLImageLoader: ImageLoading, Equatable {
    public static func == (lhs: URLImageLoader, rhs: URLImageLoader) -> Bool {
        lhs.request.cacheKey() == rhs.request.cacheKey()
    }
    
    public var result: ImageResult = .init()
    public let request: ImageRequest
    public let liveVideo: ImageRequest?
    
    @MainActor public init(_ request: ImageRequest, liveVideo: ImageRequest? = nil) {
        self.request = request
        self.liveVideo = liveVideo
        do {
            if liveVideo != nil {
                syncLoadLivePhoto()
            } else if let image = try request.cachedImage() {
                result.value = .success(image)
            }
        } catch {
            result.value = .failure(error)
        }
    }
    
    @MainActor public func loadImage() async {
        do {
            let image = try await request.send()
            result.value = .success(image)
        } catch {
            result.value = .failure(error)
            logInfo(error.localizedDescription)
        }
    }
}

extension URLImageLoader {
    func loadLivePhoto() {
        guard let liveVideo else { return }
        result.livePhotoLoading = true
        Task { @MainActor in
            if request.url.scheme == "ph" {
                let localIdentifier = request.url.absoluteString.replacingOccurrences(of: "ph://", with: "")
                fetchLivePhoto(localIdentifier: localIdentifier, targetSize: .zero) { live, _ in
                    if let live {
                        result.livePhoto = live
                        result.livePhotoLoading = false
                    }
                }
            } else {
                _ = await NetworkLoader().load(request: request)
                _ = await NetworkLoader().load(request: liveVideo)
                syncLoadLivePhoto()
            }
        }
    }
    
    func syncLoadLivePhoto() {
        guard let liveVideo else { return }
        let videoURL = liveVideo.localPath()
        let imagePath = request.localPath()
        let res = result
        logInfo("will load local live photo: \(liveVideo.key)")
        result.requestID = PHLivePhoto.request(withResourceFileURLs: [imagePath, videoURL], placeholderImage: nil, targetSize: .zero, contentMode: .aspectFit) { livePhoto, info in
            let isDegraded = info[PHLivePhotoInfoIsDegradedKey] as? Bool ?? false
            if let livePhoto, !isDegraded {
                res.livePhoto = livePhoto
                res.livePhotoLoading = false
            }
            if let error = info[PHLivePhotoInfoErrorKey] as? Error {
                logInfo("did load local live photo \(livePhoto != nil): \(liveVideo.key), isDegraded: \(isDegraded), error: \(error.localizedDescription)")
            } else {
                logInfo("did load local live photo \(livePhoto != nil): \(liveVideo.key), isDegraded: \(isDegraded)")
                if livePhoto == nil {
                    Task {
                        await self.loadImage()
                    }
                }
            }
        }
    }
    
    private func fetchLivePhoto(localIdentifier: String, targetSize: CGSize, completion: @escaping (PHLivePhoto?, [AnyHashable: Any]?) -> Void) {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else {
            logInfo("未找到对应的 Asset")
            return
        }
        guard asset.mediaSubtypes.contains(.photoLive) else {
            logInfo("该资源不是 Live Photo")
            return
        }
        
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.progressHandler = { progress, _, _, _ in
            logInfo("iCloud 下载进度: \(progress)")
        }
        
        PHImageManager.default().requestLivePhoto(for: asset,
                                                  targetSize: targetSize,
                                                  contentMode: .aspectFill,
                                                  options: options) { livePhoto, info in
            completion(livePhoto, info)
        }
    }
}
