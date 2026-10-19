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
public struct DiskCache: Hashable, Sendable {
    public let dir: URL
    public let maxSize: Int
    public let maxAge: TimeInterval
    private let splitSubDir: Bool
    private let state: State

    /// Size is measured in bytes and age in seconds. Zero disables disk storage.
    public init(_ customDir: URL? = nil,
                splitSubDir: Bool = true,
                maxSize: Int = 256 * 1024 * 1024,
                maxAge: TimeInterval = 7 * 24 * 60 * 60) {
        dir = customDir ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ImageKit")
        self.splitSubDir = splitSubDir
        self.maxSize = max(maxSize, 0)
        self.maxAge = maxAge.isNaN ? 0 : max(maxAge, 0)
        state = Registry.shared.state(for: dir)
        state.locked {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                logInfo("DiskCache.error:\(error)")
            }
        }
    }

    public static func == (lhs: DiskCache, rhs: DiskCache) -> Bool {
        lhs.dir == rhs.dir && lhs.splitSubDir == rhs.splitSubDir
            && lhs.maxSize == rhs.maxSize && lhs.maxAge == rhs.maxAge
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(dir)
        hasher.combine(splitSubDir)
        hasher.combine(maxSize)
        hasher.combine(maxAge)
    }
    
    public func isEnabled(for request: ImageRequest) -> Bool {
        request.caches.contains(.disk)
    }
    
    public func localPath(_ key: String) -> URL {
        if splitSubDir {
            let subName = key.prefix(2)
            // A custom key can begin with "..", which must not become a parent-directory partition.
            let partition = subName == ".." ? "_" : String(subName)
            return dir
                .appendingPathComponent(partition)
                .appendingPathComponent(key)
        }
        return dir.appendingPathComponent(key)
    }
    
    public func localPath(_ request: ImageRequest) -> URL {
        localPath(request.key)
    }
    
    public func load(_ request: ImageRequest) -> LoadResult? {
        state.locked {
            guard let url = validatedPath(for: request),
                  let attributes = fileAttributes(at: url),
                  attributes[.type] as? FileAttributeType == .typeRegular else { return nil }
            let size = fileSize(in: attributes)
            guard maxSize > 0, maxAge > 0, size <= maxSize,
                  let modified = attributes[.modificationDate] as? Date,
                  Date().timeIntervalSince(modified) < maxAge else {
                removeFile(at: url, size: size)
                return nil
            }
            do {
                return .data(try Data(contentsOf: url))
            } catch {
                logInfo(error)
                return nil
            }
        }
    }
    
    public func store(_ data: Data, for request: ImageRequest) {
        guard !data.isEmpty else { return }
        state.locked {
            guard let url = validatedPath(for: request) else { return }
            let attributes = fileAttributes(at: url)
            if let attributes, attributes[.type] as? FileAttributeType != .typeRegular { return }
            let previousSize = attributes.map(fileSize(in:)) ?? 0
            guard maxSize > 0, maxAge > 0, data.count <= maxSize else {
                if attributes != nil { removeFile(at: url, size: previousSize) }
                return
            }
            do {
                let parent = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: nil)
                try data.write(to: url, options: .atomic)
                if let estimatedSize = state.estimatedSize {
                    state.estimatedSize = max(0, estimatedSize - previousSize) + data.count
                }
                trimIfNeeded(now: Date())
            } catch {
                logInfo("DiskCache.store.error:\(error)")
            }
        }
    }

    public func remove(_ request: ImageRequest) {
        state.locked {
            guard let url = validatedPath(for: request) else { return }
            removeFile(at: url)
        }
    }

    func remove(_ request: ImageRequest, matching data: Data) {
        state.locked {
            guard let url = validatedPath(for: request),
                  let attributes = fileAttributes(at: url),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let current = try? Data(contentsOf: url), current == data else { return }
            removeFile(at: url, size: fileSize(in: attributes))
        }
    }

    public func clear() {
        state.locked {
            guard fileAttributes(at: dir)?[.type] as? FileAttributeType == .typeDirectory else { return }
            do {
                for url in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                    try FileManager.default.removeItem(at: url)
                }
                state.estimatedSize = 0
                state.lastTrim = Date()
            } catch {
                state.estimatedSize = nil
                logInfo("DiskCache.clear.error:\(error)")
            }
        }
    }

    private func validatedPath(for request: ImageRequest) -> URL? {
        let key = request.key
        guard !key.isEmpty, key != ".", key != "..", !key.contains("/"), !key.contains("\\"),
              fileAttributes(at: dir)?[.type] as? FileAttributeType == .typeDirectory else { return nil }
        let url = localPath(request)
        let parent = url.deletingLastPathComponent()
        if parent != dir, let attributes = fileAttributes(at: parent),
           attributes[.type] as? FileAttributeType != .typeDirectory { return nil }
        return url
    }

    private func fileAttributes(at url: URL) -> [FileAttributeKey: Any]? {
        try? FileManager.default.attributesOfItem(atPath: url.path)
    }

    private func fileSize(in attributes: [FileAttributeKey: Any]) -> Int {
        (attributes[.size] as? NSNumber)?.intValue ?? 0
    }

    private func removeFile(at url: URL) {
        guard let attributes = fileAttributes(at: url),
              attributes[.type] as? FileAttributeType == .typeRegular else { return }
        removeFile(at: url, size: fileSize(in: attributes))
    }

    private func removeFile(at url: URL, size: Int) {
        do {
            try FileManager.default.removeItem(at: url)
            if let estimatedSize = state.estimatedSize {
                state.estimatedSize = max(0, estimatedSize - size)
            }
        } catch {
            logInfo("DiskCache.remove.error:\(error)")
        }
    }

    private func trimIfNeeded(now: Date) {
        let exceedsBudget = state.estimatedSize.map { $0 > maxSize } ?? true
        guard fileAttributes(at: dir)?[.type] as? FileAttributeType == .typeDirectory,
              exceedsBudget || now.timeIntervalSince(state.lastTrim) >= 60 else { return }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
        let keySet = Set(keys)
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: keys) else { return }
        var entries = [(url: URL, size: Int, modified: Date)]()
        var total = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keySet) else { continue }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true,
                  let modified = values.contentModificationDate else { continue }
            let size = values.fileSize ?? 0
            if maxAge == 0 || now.timeIntervalSince(modified) >= maxAge {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    total += size
                    logInfo("DiskCache.trim.error:\(error)")
                }
            } else {
                entries.append((url, size, modified))
                total += size
            }
        }
        if total > maxSize {
            for entry in entries.sorted(by: { $0.modified < $1.modified }) {
                guard total > maxSize else { break }
                do {
                    try FileManager.default.removeItem(at: entry.url)
                    total -= entry.size
                } catch {
                    logInfo("DiskCache.trim.error:\(error)")
                }
            }
        }
        state.estimatedSize = total
        state.lastTrim = now
    }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        var estimatedSize: Int?
        var lastTrim = Date.distantPast

        func locked<T>(_ operation: () -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return operation()
        }
    }

    private final class Registry: @unchecked Sendable {
        static let shared = Registry()
        private let lock = NSLock()
        private var states: [String: WeakState] = [:]

        func state(for directory: URL) -> State {
            // URL equality also includes the directory flag, which can change once a new folder exists.
            let key = directory.standardizedFileURL.resolvingSymlinksInPath().path
            lock.lock()
            defer { lock.unlock() }
            if let existing = states[key]?.value { return existing }
            states = states.filter { $0.value.value != nil }
            let state = State()
            states[key] = WeakState(value: state)
            return state
        }
    }

    private struct WeakState {
        weak var value: State?
    }
}
