//
//  NetworkLoader.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/10.
//

import Foundation

public class NetworkLoader: NSObject { }

extension NetworkLoader: DataLoader {
    public func isValid(request: ImageRequest) -> Bool {
        request.url.scheme == "http" || request.url.scheme == "https"
    }
    
    public func load(request: ImageRequest) async -> LoadResult? {
        let disk = request.context.disk
        let useDisk = disk.isEnabled(for: request)
        if useDisk, let cached = disk.load(request) {
            return cached
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: request.url)
            if useDisk {
                disk.store(data, for: request)
            }
            logDebug("did load: \(request.key), data: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
            return .data(data)
        } catch {
            logInfo(request.url, error.localizedDescription)
        }
        return nil
    }
}
