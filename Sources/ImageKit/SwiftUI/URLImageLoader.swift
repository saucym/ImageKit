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
        ImageLoadingID(request: lhs.request) == ImageLoadingID(request: rhs.request)
            && lhs.liveVideo.map { ImageLoadingID(request: $0) } == rhs.liveVideo.map { ImageLoadingID(request: $0) }
    }

    public var result: ImageResult = .init()
    public let request: ImageRequest
    public let liveVideo: ImageRequest?
    private let state = LoadingState()

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
        await loadImage(expectedLiveToken: nil)
    }

    @MainActor private func loadImage(expectedLiveToken: UUID?) async {
        guard !Task.isCancelled,
              let token = state.beginImage(expectedLiveToken: expectedLiveToken) else { return }
        let task = Task { try await request.send() }
        state.attachImage(task, token: token)
        defer { state.finishImage(token) }
        await withTaskCancellationHandler {
            do {
                let image = try await task.value
                guard !Task.isCancelled else { return }
                state.publishImage(token) {
                    result.value = .success(image)
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                state.publishImage(token) {
                    result.value = .failure(error)
                }
            }
        } onCancel: {
            state.cancelImage(token)
        }
    }

    public func cancel() {
        let token = state.cancel()
        let result = result
        Task { @MainActor in
            state.publishLive(token) {
                result.livePhotoLoading = false
                result.requestID = nil
            }
        }
    }
}

extension URLImageLoader {
    @MainActor func loadLivePhoto() {
        guard let liveVideo else { return }
        let token = state.beginLive()
        result.livePhotoLoading = true
        let task = Task { @MainActor in
            defer { state.finishLiveTask(token) }
            if request.url.scheme == "ph" {
                let localIdentifier = request.url.absoluteString.replacingOccurrences(of: "ph://", with: "")
                fetchLivePhoto(localIdentifier: localIdentifier, token: token)
            } else {
                _ = await NetworkLoader().load(request: request)
                guard !Task.isCancelled, state.isLiveCurrent(token) else { return }
                _ = await NetworkLoader().load(request: liveVideo)
                guard !Task.isCancelled, state.isLiveCurrent(token) else { return }
                requestLivePhoto(token: token)
            }
        }
        state.attachLive(task, token: token)
    }

    @MainActor func syncLoadLivePhoto() {
        guard liveVideo != nil else { return }
        requestLivePhoto(token: state.beginLive())
    }

    @MainActor private func requestLivePhoto(token: UUID) {
        guard let liveVideo, state.isLiveCurrent(token) else { return }
        let resourceURLs = [request.localPath(), liveVideo.localPath()]
        let requestID = PHLivePhoto.request(withResourceFileURLs: resourceURLs,
                                            placeholderImage: nil,
                                            targetSize: .zero,
                                            contentMode: .aspectFit) { livePhoto, info in
            let isDegraded = info[PHLivePhotoInfoIsDegradedKey] as? Bool ?? false
            Task { @MainActor in
                guard state.isLiveCurrent(token) else { return }
                if let livePhoto, !isDegraded {
                    state.publishLive(token) {
                        result.livePhoto = livePhoto
                        result.livePhotoLoading = false
                    }
                } else if !isDegraded {
                    state.publishLive(token) { result.livePhotoLoading = false }
                    await loadImage(expectedLiveToken: token)
                }
            }
        }
        result.requestID = requestID
        state.attachLivePhoto(requestID, token: token)
    }

    @MainActor private func fetchLivePhoto(localIdentifier: String, token: UUID) {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject, asset.mediaSubtypes.contains(.photoLive) else {
            state.publishLive(token) { result.livePhotoLoading = false }
            return
        }
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let requestID = PHImageManager.default().requestLivePhoto(for: asset,
                                                                 targetSize: .zero,
                                                                 contentMode: .aspectFit,
                                                                 options: options) { livePhoto, info in
            let isDegraded = info?[PHLivePhotoInfoIsDegradedKey] as? Bool ?? false
            Task { @MainActor in
                guard !isDegraded else { return }
                state.publishLive(token) {
                    result.livePhoto = livePhoto
                    result.livePhotoLoading = false
                }
            }
        }
        state.attachAssetPhoto(requestID, token: token)
    }
}

private final class LoadingState: @unchecked Sendable {
    // Cancellation handlers can run off the main actor; publication and invalidation must be atomic.
    private let lock = NSRecursiveLock()
    private var imageToken = UUID()
    private var liveToken = UUID()
    private var imageTask: Task<KKImage, Error>?
    private var liveTask: Task<Void, Never>?
    private var livePhotoID: PHLivePhotoRequestID?
    private var assetPhotoID: PHImageRequestID?

    func beginImage(expectedLiveToken: UUID?) -> UUID? {
        locked {
            if let expectedLiveToken, liveToken != expectedLiveToken { return nil }
            imageTask?.cancel()
            imageToken = UUID()
            imageTask = nil
            return imageToken
        }
    }

    func attachImage(_ task: Task<KKImage, Error>, token: UUID) {
        locked {
            if imageToken == token {
                imageTask = task
            } else {
                task.cancel()
            }
        }
    }

    func publishImage(_ token: UUID, _ publish: () -> Void) {
        locked {
            guard imageToken == token else { return }
            imageTask = nil
            publish()
        }
    }

    func cancelImage(_ token: UUID) {
        locked {
            guard imageToken == token else { return }
            imageToken = UUID()
            imageTask?.cancel()
            imageTask = nil
        }
    }

    func finishImage(_ token: UUID) {
        locked {
            guard imageToken == token else { return }
            imageTask = nil
        }
    }

    func beginLive() -> UUID {
        locked {
            cancelLive()
            return liveToken
        }
    }

    func attachLive(_ task: Task<Void, Never>, token: UUID) {
        locked {
            if liveToken == token {
                liveTask = task
            } else {
                task.cancel()
            }
        }
    }

    func finishLiveTask(_ token: UUID) {
        locked {
            guard liveToken == token else { return }
            liveTask = nil
        }
    }

    func attachLivePhoto(_ requestID: PHLivePhotoRequestID, token: UUID) {
        locked {
            if liveToken == token {
                livePhotoID = requestID
            } else {
                PHLivePhoto.cancelRequest(withRequestID: requestID)
            }
        }
    }

    func attachAssetPhoto(_ requestID: PHImageRequestID, token: UUID) {
        locked {
            if liveToken == token {
                assetPhotoID = requestID
            } else {
                PHImageManager.default().cancelImageRequest(requestID)
            }
        }
    }

    func isLiveCurrent(_ token: UUID) -> Bool {
        locked { liveToken == token }
    }

    func publishLive(_ token: UUID, _ publish: () -> Void) {
        locked {
            guard liveToken == token else { return }
            publish()
        }
    }

    func cancel() -> UUID {
        locked {
            imageToken = UUID()
            imageTask?.cancel()
            imageTask = nil
            cancelLive()
            return liveToken
        }
    }

    private func cancelLive() {
        liveToken = UUID()
        liveTask?.cancel()
        liveTask = nil
        if let livePhotoID {
            PHLivePhoto.cancelRequest(withRequestID: livePhotoID)
            self.livePhotoID = nil
        }
        if let assetPhotoID {
            PHImageManager.default().cancelImageRequest(assetPhotoID)
            self.assetPhotoID = nil
        }
    }

    private func locked<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
