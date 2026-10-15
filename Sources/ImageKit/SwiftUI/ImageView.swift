//
//  ImageView.swift
//  ImageKit
//
//  Created by qhc_m@qq.com on 2022/7/28.
//

import SwiftUI
import PhotosUI

public enum ImagePhase: Sendable {
    case empty
    case success(KKImage)
    case failure(any Error)
    
    var imageSize: CGSize? {
        if case .success(let image) = self {
            return image.size
        }
        return nil
    }
    
    @ViewBuilder func buildView(loader: any ImageLoading) -> some View {
        buildView(request: loader.request)
    }

    @ViewBuilder func buildView(request: ImageRequest) -> some View {
        switch self {
        case .success(let image):
            #if os(iOS)
            if request.context.isDisplay() {
                iOSImageView(image, request: request)
            } else {
                Text(image.images == nil ? request.url.lastPathComponent : "gif")
                    .frame(width: request.size.width, height: request.size.height ?? image.size.height / KKScreen.main.scale)
                    .border(color: .green)
            }
            #else
            buildImageView(image, request: request)
            #endif
        case .empty:
            ProgressView()
                .frame(width: request.size.width, height: request.size.defaultHeight)
                .border(color: .gray)
        case .failure:
            Text("error")
                .frame(width: request.size.width, height: request.size.defaultHeight)
                .border(color: .red)
        }
    }
}

#if os(iOS)
@ViewBuilder func iOSImageView(_ image: KKImage, request: ImageRequest) -> some View {
    if image.images != nil {
        GenericView<AutoResizeImageView> {
            AutoResizeImageView(size: CGSize(width: request.size.width ?? image.size.width,
                                            height: request.size.height ?? image.size.height))
        } updater: { view in
            view.image = image
            view.contentMode = request.mode == .fit ? .scaleAspectFit : .scaleAspectFill
            view.updateSize(CGSize(width: request.size.width ?? image.size.width,
                                   height: request.size.height ?? image.size.height))
        }
        .frame(width: request.size.width, height: request.size.height)
        .clipped()
        .contentShape(Rectangle())
    } else {
        buildImageView(image, request: request)
    }
}
#endif

func buildImageView(_ image: KKImage, loader: any ImageLoading) -> some View {
    buildImageView(image, request: loader.request)
}

private func buildImageView(_ image: KKImage, request: ImageRequest) -> some View {
    image.swiftUIView
        .resizable()
        .aspectRatio(contentMode: request.mode)
        .frame(width: request.size.width, height: request.size.height)
        .clipped()
}

public final class ImageResult: ObservableObject {
    @Published public var value: ImagePhase = .empty
    @Published public var livePhoto: PHLivePhoto? = nil
    @Published public internal(set) var livePhotoLoading = false
    @Published public internal(set) var livePhotoError: (any Error)? = nil
    var requestID: PHLivePhotoRequestID? = nil
    public init() { }
}

public protocol ImageLoading {
    var request: ImageRequest { get }
    var result: ImageResult { get }
    func loadImage() async
    func cancel()
}

public extension ImageLoading {
    func cancel() { }
}

public struct ImageView: View {
    public init(loader: any ImageLoading) {
        source = .loader(loader)
    }

    public init(request: ImageRequest) {
        source = .request(request)
    }
    
    public init(url: URL, size: ImageRequest.Size) {
        self.init(request: ImageRequest(url, size: size))
    }
    
    private let source: ImageViewSource
    public var body: some View {
        ImageCustomView(source: source) {
            $0.buildView(loader: $1)
        }
    }
}

public struct ImageCustomView<Content>: View where Content: View {
    public init(loader: any ImageLoading,
                @ViewBuilder content: @escaping (ImagePhase, any ImageLoading) -> Content) {
        self.init(source: .loader(loader), content: content)
    }

    public init(loader: any ImageLoading,
                @ViewBuilder content: @escaping (ImagePhase) -> Content) {
        self.init(loader: loader) { phase, _ in content(phase) }
    }

    public init(request: ImageRequest,
                @ViewBuilder content: @escaping (ImagePhase) -> Content) {
        self.init(source: .request(request)) { phase, _ in content(phase) }
    }
    
    public init(url: URL,
                size: ImageRequest.Size,
                @ViewBuilder content: @escaping (ImagePhase, any ImageLoading) -> Content) {
        self.init(source: .request(ImageRequest(url, size: size)), content: content)
    }

    public init(url: URL,
                size: ImageRequest.Size,
                @ViewBuilder content: @escaping (ImagePhase) -> Content) {
        self.init(request: ImageRequest(url, size: size), content: content)
    }

    fileprivate init(source: ImageViewSource,
                     @ViewBuilder content: @escaping (ImagePhase, any ImageLoading) -> Content) {
        self.source = source
        self.content = content
    }
    
    private let source: ImageViewSource
    private let content: (ImagePhase, any ImageLoading) -> Content
    
    public var body: some View {
        switch source {
        case .request(let request):
            RequestImageContent(request: request, content: content)
        case .loader(let loader):
            LoaderImageContent(loader: loader, content: content)
                .task(id: ImageLoadingID(request: loader.request, result: loader.result)) {
                    if case .success = loader.result.value { return }
                    await withTaskCancellationHandler {
                        await loader.loadImage()
                    } onCancel: {
                        loader.cancel()
                    }
                }
                .onDisappear {
                    loader.cancel()
                }
        }
    }
}

fileprivate enum ImageViewSource {
    case request(ImageRequest)
    case loader(any ImageLoading)
}

struct ImageLoadingID: Hashable {
    private let output: ImageRequest.OutputKey
    private let url: URL
    private let caches: Int
    private let placeholderHeight: CGFloat?
    private let result: ObjectIdentifier?

    init(request: ImageRequest, result: ImageResult? = nil) {
        output = request.outputKey
        url = request.url
        caches = request.caches.rawValue
        placeholderHeight = request.size.defaultHeight
        self.result = result.map(ObjectIdentifier.init)
    }
}

@MainActor
private final class RequestImageState: ObservableObject {
    @Published private(set) var loader: URLImageLoader

    init(request: ImageRequest) {
        loader = URLImageLoader(request)
    }

    func load(_ request: ImageRequest) async {
        if ImageLoadingID(request: loader.request) != ImageLoadingID(request: request) {
            loader.cancel()
            loader = URLImageLoader(request)
        }
        if case .success = loader.result.value { return }
        await loader.loadImage()
    }
}

private struct RequestImageContent<Content: View>: View {
    let request: ImageRequest
    let content: (ImagePhase, any ImageLoading) -> Content
    @StateObject private var state: RequestImageState

    init(request: ImageRequest,
         content: @escaping (ImagePhase, any ImageLoading) -> Content) {
        self.request = request
        self.content = content
        _state = StateObject(wrappedValue: RequestImageState(request: request))
    }

    var body: some View {
        LoaderImageContent(loader: state.loader, content: content)
            .task(id: ImageLoadingID(request: request)) {
                await state.load(request)
            }
            .onDisappear {
                state.loader.cancel()
            }
    }
}

private struct LoaderImageContent<Content: View>: View {
    let loader: any ImageLoading
    let content: (ImagePhase, any ImageLoading) -> Content
    @ObservedObject private var result: ImageResult

    init(loader: any ImageLoading,
         content: @escaping (ImagePhase, any ImageLoading) -> Content) {
        self.loader = loader
        self.content = content
        _result = ObservedObject(wrappedValue: loader.result)
    }

    var body: some View {
        content(result.value, loader)
    }
}

extension View {
    func border(color: KKColor = KKColor(hex: .random(in: 0...0xffffff))) -> some View {
        #if DEBUG
        self.border(Color(color))
        #else
        self
        #endif
    }
}

private extension ImageRequest.Context {
    nonisolated func isDisplay() -> Bool {
        #if DEBUG
        return tag != 1
        #else
        return true
        #endif
    }
}

extension KKColor {
    @objc public convenience init(hex: Int, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF)
        let green = CGFloat((hex >> 8) & 0xFF)
        let blue = CGFloat(hex & 0xFF)
        self.init(red: red / 255.0, green: green / 255.0, blue: blue / 255.0, alpha: alpha)
    }
}

#if canImport(UIKit)
import UIKit

public class AutoResizeImageView: UIImageView {
    private var size: CGSize
    public init(size: CGSize) {
        self.size = size
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var intrinsicContentSize: CGSize {
        size
    }

    fileprivate func updateSize(_ size: CGSize) {
        guard self.size != size else { return }
        self.size = size
        invalidateIntrinsicContentSize()
    }
}
#endif
