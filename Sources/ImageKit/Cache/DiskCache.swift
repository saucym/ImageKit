//
//  DiskCache.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/24.
//

import Foundation

/// Disk-backed raw data storage for network downloads.
/// Not an `ImageCache` (decoded images live in memory) and not a `DataLoader`
/// (loaders decide *where* to fetch; this only persists bytes).
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
    
    public func isEnabled(for request: ImageRequest) -> Bool {
        request.caches.contains(.disk)
    }
    
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
    
    public func load(_ request: ImageRequest) -> LoadResult? {
        let url = localPath(request)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        let binarySuffix: Set = ["gif", "mp4", "mov"]
        if binarySuffix.contains(url.pathExtension.lowercased()) {
            do {
                return .data(try Data(contentsOf: url))
            } catch {
                logInfo(error)
                return nil
            }
        }
        if let image = KKImage(contentsOfFile: url.path) {
            return .image(image)
        }
        return nil
    }
    
    public func store(_ data: Data, for request: ImageRequest) {
        guard !data.isEmpty else { return }
        let url = localPath(request)
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            try data.write(to: url)
        } catch {
            logInfo("DiskCache.store.error:\(error)")
        }
    }
}
