//
//  DiskLoader.swift
//  ImageKit
//
//  Created by saucymqin on 2018/7/24.
//

import Foundation

public struct DiskLoader: Hashable {
    public let dir: URL
    private let splitSubDir: Bool
    public init(_ customDir: URL? = nil, splitSubDir: Bool = true) {
        dir = customDir ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ImageKit")
        self.splitSubDir = splitSubDir
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                logInfo("DiskLoader.error:\(error)")
            }
        }
    }
}

extension DiskLoader: LoaderProtocol {
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

extension DiskLoader {
    public func localPath(_ key: String, context: ImageRequest.Context) -> URL {
        if splitSubDir {
            let subName = key.prefix(2)
            return self.dir
                .appendingPathComponent(String(subName))
                .appendingPathComponent(key)
        }
        return self.dir.appendingPathComponent(key)
    }
    
    public func localPath(_ request: ImageRequest) -> URL {
        localPath(request.key, context: request.context)
    }
    
    public func cache(data: Data, for request: ImageRequest) {
        if data.count > 0 {
            let url = localPath(request)
            do {
                let dir = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
                try data.write(to: url)
            } catch {
                logInfo("DiskLoader.cache.error:\(error)")
            }
        }
    }
}
