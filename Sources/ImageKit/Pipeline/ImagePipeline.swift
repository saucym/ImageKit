import Foundation

extension ImageRequest {
    public actor Context {
        public static let `default` = Context()
        nonisolated let cacheIdentity = UUID()
        public nonisolated let disk: DiskCache
        public nonisolated let decoders: [ImageDecoder]
        public nonisolated let caches: [ImageCache]
        public nonisolated let processors: [ImageProcessor]
        public nonisolated let loaders: [DataLoader]
        #if DEBUG
        let tag: Int // 1: hidden image
        #endif
        private let tasks = SharedTaskStore<TaskKey, KKImage>()
        public init(disk: DiskCache = .init(),
                    decoders: [ImageDecoder] = [SystemDecoder()],
                    caches: [ImageCache] = [MemoryCache.shared],
                    processors: [ImageProcessor] = [GrayProcessor(), PredrawnProcessor()],
                    loaders: [DataLoader] = [LocalLoader(), NetworkLoader()],
                    tag: Int = 0) {
            self.disk = disk
            self.decoders = decoders
            self.caches = caches
            self.processors = processors
            self.loaders = loaders
            #if DEBUG
            self.tag = tag
            #endif
        }

        private struct TaskKey: Hashable, Sendable {
            let output: OutputKey
            let caches: Int
        }

        fileprivate func image(for request: ImageRequest) async throws -> KKImage {
            try Task.checkCancellation()
            if let cached = try await request.cachedImage() {
                try Task.checkCancellation()
                return cached
            }
            let key = TaskKey(output: request.outputKey, caches: request.caches.rawValue)
            let image = try await tasks.value(for: key) {
                try await request.loadImage()
            }
            try Task.checkCancellation()
            return image
        }
    }
}

extension ImageRequest {
    func decode(data: Data) throws -> KKImage {
        for decoder in context.decoders where decoder.isValid(request: self) {
            return try decoder.decode(request: self, data: data)
        }
        throw IKError.decoderIsEmpty
    }
    
    @MainActor func cachedImage() throws -> KKImage? {
        for cache in context.caches where cache.isValid(request: self) {
            if let image = try cache.image(for: self) {
                return image
            }
        }
        return nil
    }
    
    @MainActor func cache(image: KKImage) {
        for cache in context.caches where cache.isValid(request: self) {
            cache.cache(image, for: self)
        }
    }
    
    func process(_ input: KKImage) -> KKImage {
        var image = input
        #if os(iOS)
        if animation == .firstFrame, let first = input.images?.first {
            image = first
        }
        #endif
        for processor in context.processors where processor.isValid(request: self) {
            image = processor.process(request: self, input: image)
        }
        return image
    }
    
    func load() async throws -> LoadResult {
        try await loadResource().result
    }

    private func loadResource() async throws -> LoadedResource {
        for loader in context.loaders where loader.isValid(request: self) {
            try Task.checkCancellation()
            if let resourceLoader = loader as? any ResourceLoader {
                if let resource = try await resourceLoader.loadResource(request: self) {
                    return resource
                }
            } else if let result = try await loader.loadResult(request: self) {
                return LoadedResource(result: result)
            }
        }
        throw IKError.loaderIsEmpty
    }

    private func decodeResource(_ resource: LoadedResource, allowsReload: Bool = true) async throws -> KKImage {
        try Task.checkCancellation()
        switch resource.result {
        case .image(let image):
            return image
        case .data(let data):
            do {
                return try decode(data: data)
            } catch {
                try Task.checkCancellation()
                if case IKError.decoderIsEmpty = error { throw error }
                if error is CancellationError { throw error }
                resource.invalidateCachedData?()
                guard allowsReload, let reload = resource.reload else { throw error }
                let reloaded = try await reload()
                return try await decodeResource(reloaded, allowsReload: false)
            }
        }
    }

    private func loadImage() async throws -> KKImage {
        if let cached = try await cachedImage() {
            try Task.checkCancellation()
            return cached
        }
        let resource = try await loadResource()
        let image = try await decodeResource(resource)
        try Task.checkCancellation()
        let processed = process(image)
        try Task.checkCancellation()
        await cache(image: processed)
        return processed
    }
}

extension ImageRequest {
    public func send() async throws -> KKImage {
        try await context.image(for: self)
    }
}
