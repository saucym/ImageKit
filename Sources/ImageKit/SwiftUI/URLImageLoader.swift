//
//  URLImageLoader.swift
//  ImageKit
//
//  Created by qhc_m@qq.com on 2022/7/28.
//

import SwiftUI
import Photos

public final class URLImageLoader: ImageLoading, Equatable {
    public static func == (lhs: URLImageLoader, rhs: URLImageLoader) -> Bool {
        ImageLoadingID(request: lhs.request) == ImageLoadingID(request: rhs.request)
            && lhs.liveVideo.map { ImageLoadingID(request: $0) } == rhs.liveVideo.map { ImageLoadingID(request: $0) }
    }

    public let result = ImageResult()
    public let request: ImageRequest
    public let liveVideo: ImageRequest?
    private let state = LoadingState()

    @MainActor public init(_ request: ImageRequest, liveVideo: ImageRequest? = nil) {
        self.request = request
        self.liveVideo = liveVideo
        do {
            if let image = try request.cachedImage() {
                result.value = .success(image)
            }
        } catch {
            result.value = .failure(error)
        }
        loadCachedLivePhoto()
    }

    deinit {
        _ = state.cancel()
    }

    @MainActor public func loadImage() async {
        await loadImage(expectedLiveToken: nil)
    }

    @MainActor private func loadImage(expectedLiveToken: UUID?) async {
        guard !Task.isCancelled,
              let token = state.beginImage(expectedLiveToken: expectedLiveToken) else { return }
        let task = Task { [request] in try await request.send() }
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
        } onCancel: { [state] in
            state.cancelImage(token)
        }
    }

    public func cancel() {
        let token = state.cancel()
        let result = result
        Task { @MainActor [state, result] in
            state.publishLive(token) {
                result.livePhotoLoading = false
            }
        }
    }
}

extension URLImageLoader {
    @MainActor func loadLivePhoto() {
        guard let liveVideo else { return }
        let token = state.beginLive()
        state.publishLive(token) {
            result.livePhotoLoading = true
            result.livePhotoError = nil
        }
        let task = Task { @MainActor [weak self, request, state, result] in
            defer { state.finishLiveTask(token) }
            if request.url.scheme == "ph" {
                let localIdentifier = request.url.absoluteString.replacingOccurrences(of: "ph://", with: "")
                self?.fetchLivePhoto(localIdentifier: localIdentifier, token: token)
            } else {
                do {
                    let resources = try await LivePhotoResources.prepare(image: request, video: liveVideo)
                    guard !Task.isCancelled, state.isLiveCurrent(token), let self else { return }
                    self.requestLivePhoto(resources: resources, token: token, allowsImageFallback: true)
                } catch is CancellationError {
                    state.publishLive(token) { result.livePhotoLoading = false }
                } catch {
                    guard !Task.isCancelled else { return }
                    await self?.failLivePhoto(error, token: token)
                }
            }
        }
        state.attachLive(task, token: token)
    }

    @MainActor private func loadCachedLivePhoto() {
        guard let liveVideo, request.url.scheme != "ph" else { return }
        let token = state.beginLive()
        let task = Task { @MainActor [weak self, request, state, result] in
            defer { state.finishLiveTask(token) }
            do {
                guard let resources = try await LivePhotoResources.cached(image: request, video: liveVideo),
                      !Task.isCancelled, state.isLiveCurrent(token), let self else { return }
                state.publishLive(token) { result.livePhotoLoading = true }
                self.requestLivePhoto(resources: resources, token: token, allowsImageFallback: false)
            } catch is CancellationError {
            } catch {
                state.publishLive(token) { result.livePhotoError = error }
            }
        }
        state.attachLive(task, token: token)
    }

    @MainActor private func requestLivePhoto(resources: LivePhotoResources, token: UUID, allowsImageFallback: Bool) {
        guard state.isLiveCurrent(token) else { return }
        let requestID = PHLivePhoto.request(withResourceFileURLs: resources.urls,
                                            placeholderImage: nil,
                                            targetSize: .zero,
                                            contentMode: .aspectFit) { [weak self, resources] livePhoto, info in
            let isDegraded = info[PHLivePhotoInfoIsDegradedKey] as? Bool ?? false
            let isCancelled = info[PHLivePhotoInfoCancelledKey] as? Bool ?? false
            let error = info[PHLivePhotoInfoErrorKey] as? Error
            Task { @MainActor [weak self] in
                guard let self, self.state.isLiveCurrent(token) else { return }
                if isCancelled {
                    self.state.finishLivePhoto(token) {
                        self.result.livePhotoLoading = false
                    }
                    return
                }
                if let error {
                    await self.failLivePhoto(error, token: token, allowsImageFallback: allowsImageFallback)
                    return
                }
                if let livePhoto, !isDegraded {
                    resources.retain(for: livePhoto)
                    self.state.finishLivePhoto(token) {
                        self.result.livePhoto = livePhoto
                        self.result.livePhotoError = nil
                        self.result.livePhotoLoading = false
                    }
                } else if !isDegraded {
                    await self.failLivePhoto(LivePhotoResourceError.photoUnavailable, token: token, allowsImageFallback: allowsImageFallback)
                }
            }
        }
        state.attachLivePhoto(requestID, token: token)
    }

    @MainActor private func failLivePhoto(_ error: Error, token: UUID, allowsImageFallback: Bool = true) async {
        state.finishLivePhoto(token) {
            result.livePhotoError = error
            result.livePhotoLoading = false
        }
        guard allowsImageFallback else { return }
        if case .success = result.value { return }
        await loadImage(expectedLiveToken: token)
    }

    @MainActor private func fetchLivePhoto(localIdentifier: String, token: UUID) {
        guard !Task.isCancelled, state.isLiveCurrent(token) else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject, asset.mediaSubtypes.contains(.photoLive) else {
            state.finishLivePhoto(token) {
                result.livePhotoLoading = false
                result.livePhotoError = LivePhotoResourceError.assetUnavailable
            }
            return
        }
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let requestID = PHImageManager.default().requestLivePhoto(for: asset,
                                                                 targetSize: .zero,
                                                                 contentMode: .aspectFit,
                                                                 options: options) { [weak self] livePhoto, info in
            let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
            let isCancelled = info?[PHImageCancelledKey] as? Bool ?? false
            let error = info?[PHImageErrorKey] as? Error
            Task { @MainActor [weak self] in
                guard let self, self.state.isLiveCurrent(token) else { return }
                if isCancelled {
                    self.state.finishLivePhoto(token) { self.result.livePhotoLoading = false }
                    return
                }
                if let error {
                    await self.failLivePhoto(error, token: token)
                    return
                }
                guard !isDegraded else { return }
                if let livePhoto {
                    self.state.finishLivePhoto(token) {
                        self.result.livePhoto = livePhoto
                        self.result.livePhotoError = nil
                        self.result.livePhotoLoading = false
                    }
                } else {
                    await self.failLivePhoto(LivePhotoResourceError.photoUnavailable, token: token)
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

    func finishLivePhoto(_ token: UUID, _ publish: () -> Void) {
        locked {
            guard liveToken == token else { return }
            livePhotoID = nil
            assetPhotoID = nil
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
