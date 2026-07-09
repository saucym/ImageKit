//
//  DiskCache.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/24.
//

import Foundation

public struct DiskCache: Hashable {
    public let dir: URL
    private let splitSubDir: Bool
    
    public init(_ customDir: URL? = nil, splitSubDir: Bool = true) {
        dir = customDir ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ImageKit")
        self.splitSubDir = splitSubDir
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                logInfo("DiskCache.error:\(error)")
            }
        }
    }
}

extension DiskCache: DataLoader {
    public func isValid(request: ImageRequest) -> Bool {
        request.caches.contains(.disk)
    }
    
    public func load(request: ImageRequest) async -> LoadResult? {
        let url = localPath(request)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        let videoSuffix: Set = ["gif", "mp4", "mov"]
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
    public func localPath(_ key: String) -> URL {
        if splitSubDir {
            let subName = key.prefix(2)
            return dir
                .appendingPathComponent(String(subName))
                .appendingPathComponent(key)
        }
        return dir.appendingPathComponent(key)
    }
    
    public func localPath(_ request: ImageRequest) -> URL {
        localPath(request.key)
    }
    
    public func cache(data: Data, for request: ImageRequest) {
        guard !data.isEmpty else { return }
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
