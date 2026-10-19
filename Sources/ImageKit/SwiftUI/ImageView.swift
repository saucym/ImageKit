//
//  ImageView.swift
//  ImageKit
//
//  Created by qhc_m@qq.com on 2022/7/28.
//

import SwiftUI

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
        ImageCustomView(source: source) { phase, loader in
            ImagePhaseContent(phase: phase, request: loader.request)
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

private struct ImagePhaseContent: View {
    let phase: ImagePhase
    let request: ImageRequest

    var body: some View {
        switch phase {
        case .success(let image):
            #if os(iOS)
            if request.context.displaysImages {
                RequestedImageContent(image: image, request: request)
            } else {
                Text(image.images == nil ? request.url.lastPathComponent : "gif")
                    .frame(width: request.size.width,
                           height: request.size.height ?? image.size.height / KKScreen.main.scale)
                    .debugBorder(.green)
            }
            #else
            RequestedImageContent(image: image, request: request)
            #endif
        case .empty:
            ProgressView()
                .frame(width: request.size.width, height: request.size.defaultHeight)
                .debugBorder(.gray)
        case .failure:
            Text("error")
                .frame(width: request.size.width, height: request.size.defaultHeight)
                .debugBorder(.red)
        }
    }
}

private struct RequestedImageContent: View {
    let image: KKImage
    let request: ImageRequest

    var body: some View {
        #if os(iOS)
        if image.images != nil {
            GenericView<AnimatedImageView> {
                AnimatedImageView(size: displaySize)
            } updater: { view in
                if view.image !== image { view.image = image }
                view.contentMode = request.mode == .fit ? .scaleAspectFit : .scaleAspectFill
                view.updateSize(displaySize)
            }
            .frame(width: request.size.width, height: request.size.height)
            .clipped()
            .contentShape(Rectangle())
        } else {
            staticImage
        }
        #else
        staticImage
        #endif
    }

    private var staticImage: some View {
        image.swiftUIView
            .resizable()
            .aspectRatio(contentMode: request.mode)
            .frame(width: request.size.width, height: request.size.height)
            .clipped()
    }

    #if os(iOS)
    private var displaySize: CGSize {
        CGSize(width: request.size.width ?? image.size.width,
               height: request.size.height ?? image.size.height)
    }
    #endif
}

private extension View {
    func debugBorder(_ color: Color) -> some View {
        #if DEBUG
        border(color)
        #else
        self
        #endif
    }
}

private extension ImageRequest.Context {
    nonisolated var displaysImages: Bool {
        #if DEBUG
        tag != 1
        #else
        true
        #endif
    }
}

#if os(iOS)
import UIKit

private final class AnimatedImageView: UIImageView {
    private var size: CGSize

    init(size: CGSize) {
        self.size = size
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var intrinsicContentSize: CGSize {
        size
    }

    func updateSize(_ size: CGSize) {
        guard self.size != size else { return }
        self.size = size
        invalidateIntrinsicContentSize()
    }
}
#endif
