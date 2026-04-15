//
//  NetworkLoader.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/10.
//

import Foundation

public class NetworkLoader: NSObject { }

extension NetworkLoader: LoaderProtocol {
    public func isValid(request: ImageRequest) -> Bool {
        return request.url.scheme == "http" || request.url.scheme == "https"
    }
    
    public func loadFor(request: ImageRequest) async -> ResultItem? {
        let needCache = request.context.disk.isValid(request: request)
        if needCache, let res = await request.context.disk.loadFor(request: request) {
            return res
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: request.url)
            if needCache {
                request.context.disk.cache(data: data, for: request)
            }
            logDebug("did load: \(request.key), data: \(data.count)")
            return .data(data)
        } catch {
            logInfo(request.url, error.localizedDescription)
        }
        return nil
    }
}
