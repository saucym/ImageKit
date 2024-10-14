//
//  DiskCache.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/24.
//

import Foundation

public struct DiskCache: Hashable {
    public let dir: URL
    public init(_ customDir: URL? = nil) {
        dir = customDir ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ImageKit")
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                logInfo("DiskCache.error:\(error)")
            }
        }
    }
}

extension DiskCache: LoaderProtocol {
    public func isValid(request: ImageRequest) -> Bool {
        return request.caches.contains(.Disk)
    }
    
    public func loadFor(request: ImageRequest) async -> ResultItem? {
        let url = localPath(request)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        let videoSuffix = Set(arrayLiteral: "gif", "mp4", "mov")
        if videoSuffix.contains(url.pathExtension.lowercased()) {
            do {
                let data = try Data(contentsOf: url)
                return .data(data)
            } catch {
                logInfo(error)
            }
        } else if let image = KKImage(contentsOfFile: url.path) {
            return .image(image)
        }
        return nil
    }
}

extension DiskCache {
    public func localPath(_ request: ImageRequest) -> URL {
        if request.context.useSubDir {
            let subName = request.key.prefix(2)
            return self.dir
                .appendingPathComponent(String(subName))
                .appendingPathComponent(request.key)
        }
        return self.dir.appendingPathComponent(request.key)
    }
    
    public func cache(data: Data, for request: ImageRequest) {
        if data.count > 0 {
            let url = localPath(request)
            do {
                let dir = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
                try data.write(to: url)
            } catch {
                logInfo("DiskCache.cache.error:\(error)")
            }
        }
    }
}
