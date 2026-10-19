//
//  NetworkLoader.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/10.
//

import Foundation

public class NetworkLoader: NSObject {
    private struct DownloadKey: Hashable, Sendable {
        let url: URL
        let reload: Bool
    }

    private static let sharedDownloads = SharedTaskStore<DownloadKey, Data>()
    private let session: URLSession
    private let downloads: SharedTaskStore<DownloadKey, Data>

    public override init() {
        session = .shared
        downloads = Self.sharedDownloads
        super.init()
    }

    public init(session: URLSession) {
        self.session = session
        downloads = SharedTaskStore()
        super.init()
    }
}

extension NetworkLoader: DataLoader {
    public func isValid(request: ImageRequest) -> Bool {
        request.url.scheme == "http" || request.url.scheme == "https"
    }
    
    public func load(request: ImageRequest) async throws -> LoadResult? {
        try await loadResource(request: request, useCachedData: true).result
    }
}

extension NetworkLoader: ResourceLoader {
    func loadResource(request: ImageRequest) async throws -> LoadedResource? {
        try await loadResource(request: request, useCachedData: true)
    }

    private func loadResource(request: ImageRequest, useCachedData: Bool) async throws -> LoadedResource {
        try Task.checkCancellation()
        let disk = request.context.disk
        let useDisk = disk.isEnabled(for: request)
        if useCachedData, useDisk, case .data(let data) = disk.load(request) {
            try Task.checkCancellation()
            return LoadedResource(result: .data(data), invalidateCachedData: {
                self.invalidate(data, for: request)
            }, reload: {
                try await self.loadResource(request: request, useCachedData: false)
            })
        }

        let session = session
        let url = request.url
        let key = DownloadKey(url: url, reload: !useCachedData)
        let data = try await downloads.value(for: key) {
            let urlRequest = URLRequest(url: url, cachePolicy: useCachedData ? .useProtocolCachePolicy : .reloadIgnoringLocalCacheData)
            let (data, response) = try await session.data(for: urlRequest)
            if let response = response as? HTTPURLResponse,
               !(200..<300).contains(response.statusCode) {
                throw IKError.invalidHTTPStatus(response.statusCode)
            }
            return data
        }
        try Task.checkCancellation()
        if useDisk {
            disk.store(data, for: request)
        }
        logDebug("did load: \(request.key), data: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
        return LoadedResource(result: .data(data), invalidateCachedData: {
            self.invalidate(data, for: request)
        })
    }

    private func invalidate(_ data: Data, for request: ImageRequest) {
        if request.context.disk.isEnabled(for: request) {
            request.context.disk.remove(request, matching: data)
        }
        let urlRequest = URLRequest(url: request.url)
        if let cache = session.configuration.urlCache,
           cache.cachedResponse(for: urlRequest)?.data == data {
            cache.removeCachedResponse(for: urlRequest)
        }
    }
}
