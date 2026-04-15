//
//  OnlinePreviewView.swift
//  ImageKit
//
//  Created by qhc_m@qq.com on 2026/3/26.
//

import SwiftUI
import AVKit
#if os(iOS)
import UIKit
#endif

@available(iOS 17.0, macOS 14.0, *)
public struct OnlinePreviewView: View {
    public struct Item: Identifiable, Equatable {
        public let url: URL
        public let id: String
        public let videoURL: URL?
        public init(url: URL, id: String? = nil, videoURL: URL? = nil) {
            self.url = url
            self.id = id ?? url.id
            self.videoURL = videoURL
        }
    }
    
    public struct Source: Equatable, Identifiable {
        public var id: String { currentID ?? "" }
        var currentID: Item.ID?
        let items: [Item]
        public init(current: Item.ID, items: [Item]) {
            self.items = items
            self.currentID = current
        }
    }
    
    @State private var state: Source
    public init(state: Source) {
        _state = .init(initialValue: state)
    }
    
    @Environment(\.dismiss) private var dismiss
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1.0
    
    public var body: some View {
        ZStack {
            Color.black.opacity(opacity).ignoresSafeArea()
            
            // 外层 ScrollView：处理左右翻页
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(state.items) { item in
                        ZoomableImageCell(item: item)
                            .containerRelativeFrame(.horizontal) // 撑满屏幕宽
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $state.currentID)
            .scrollTargetBehavior(.viewAligned) // 像 TabView 一样的翻页感
            .offset(y: offset)
            .scaleEffect(1 - (offset / 1000))
        }
        .ignoresSafeArea()
        .presentationBackground(.clear)
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    if abs(value.translation.height) > abs(value.translation.width), value.translation.height > 0 {
                        offset = value.translation.height
                        opacity = Double(1 - (offset / 500))
                    }
                }
                .onEnded { value in
                    let dy = value.translation.height
                    if dy > 150 {
                        dismiss()
                    } else {
                        withAnimation(.spring()) {
                            offset = 0
                            opacity = 1.0
                        }
                    }
                }
        )
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString.md5 }
}

@available(iOS 17.0, macOS 14.0, *)
private struct ZoomableImageCell: View {
    let item: OnlinePreviewView.Item
    let loader: URLImageLoader
    @ObservedObject private var result: ImageResultObservableObject
    init(item: OnlinePreviewView.Item) {
        self.item = item
        loader = URLImageLoader(.init(item.url, size: .original, key: item.id))
        result = loader.result
    }
    
    // 1. 当前稳定的缩放倍数
    @State private var scale: CGFloat = 1.0
    // 2. 手势进行中的临时缩放增量
    @GestureState private var gestureScale: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                switch result.value {
                case .success(let image):
                    let totalScale = scale * gestureScale
                    Group {
                        #if os(iOS)
                        iOSImageView(image, loader: loader)
                        #else
                        buildImageView(image, loader: loader)
                        #endif
                    }
                    .frame(width: proxy.size.width, height: proxy.size.width / image.size.width * image.size.height)
                    .scaleEffect(totalScale)
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            scale = (scale > 1.0) ? 1.0 : 2.5
                        }
                    }
                    .gesture(
                        MagnifyGesture()
                            .updating($gestureScale) { value, state, _ in
                                state = value.magnification
                            }
                            .onEnded { value in
                                withAnimation(.spring()) {
                                    scale *= value.magnification
                                    // 限制缩放范围：最小 1 倍，最大 4 倍
                                    scale = min(max(scale, 1.0), scale * 4.0)
                                }
                            }
                    )
                case .empty:
                    ProgressView()
                        .frame(width: loader.request.size.width, height: loader.request.size.defaultHeight)
                        .border(color: .gray)
                case .failure:
                    Text("error")
                        .frame(width: loader.request.size.width, height: loader.request.size.defaultHeight)
                        .border(color: .red)
                }
            }
        }
        // 实现可以拖动查看图片边缘
        .scrollDisabled(scale <= 1.0)
        .task(id: "\(loader.request.size)-\(loader.request.processors.rawValue)") {
            if case .success = result.value { } else {
                await loader.loadImage()
            }
        }
    }
}
