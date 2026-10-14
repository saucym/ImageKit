//
//  NetworkLoader.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/10.
//

import Foundation

public class NetworkLoader: NSObject {
    private static let sharedDownloads = SharedTaskStore<URL, Data>()
    private let session: URLSession
    private let downloads: SharedTaskStore<URL, Data>

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
    
    public func load(request: ImageRequest) async -> LoadResult? {
        do {
            return try await loadResult(request: request)
        } catch {
            logInfo(request.url, error.localizedDescription)
            return nil
        }
    }

    public func loadResult(request: ImageRequest) async throws -> LoadResult? {
        try Task.checkCancellation()
        let disk = request.context.disk
        let useDisk = disk.isEnabled(for: request)
        if useDisk, let cached = disk.load(request) {
            try Task.checkCancellation()
            return cached
        }

        let session = session
        let url = request.url
        let data = try await downloads.value(for: url) {
            let (data, response) = try await session.data(from: url)
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
        return .data(data)
    }
}
