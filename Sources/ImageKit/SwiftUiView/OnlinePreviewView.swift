//
//  OnlinePreviewView.swift
//  ImageKit
//
//  Created by qhc_m@qq.com on 2026/3/26.
//

import SwiftUI
import AVKit

@available(iOS 17.0, macOS 14.0, *)
public struct OnlinePreviewView: View {
    public enum Item: Identifiable, Equatable {
        public var id: String { key }
        case file(URL, key: String)
        case video(Video, key: String)
        
        var key: String {
            switch self {
            case .file(_, let key): key
            case .video(_, let key): key
            }
        }
        
        public struct Video: Equatable {
            let url: URL
            let player: AVPlayer
            public init(url: URL) {
                self.url = url
                self.player = .init(url: url)
            }
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
        .onChange(of: state.currentID) { old, new in
            if let oldItem = state.items.first(where: { $0.id == old }) {
                if case .video(let item, key: _) = oldItem {
                    item.player.pause()
                }
            }
            if let newItem = state.items.first(where: { $0.id == new }) {
                if case .video(let item, key: _) = newItem {
                    item.player.play()
                }
            }
        }
        .onDisappear {
            if let newItem = state.items.first(where: { $0.id == state.currentID }) {
                if case .video(let item, key: _) = newItem {
                    item.player.pause()
                }
            }
        }
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

extension URL: Identifiable {
    public var id: String { absoluteString }
}

@available(iOS 17.0, macOS 14.0, *)
private struct ZoomableImageCell: View {
    let item: OnlinePreviewView.Item
    
    // 1. 当前稳定的缩放倍数
    @State private var scale: CGFloat = 1.0
    // 2. 手势进行中的临时缩放增量
    @GestureState private var gestureScale: CGFloat = 1.0
    
    // 最终计算出的缩放倍数
    var totalScale: CGFloat {
        scale * gestureScale
    }
    
    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Group {
                    switch item {
                    case .file(let url, let key):
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else if phase.error != nil {
                                VStack {
                                    Image(systemName: "exclamationmark.triangle")
                                    Text("图片加载失败")
                                }
                            } else {
                                ProgressView()
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                    case .video(let video, let key):
                        VideoPlayer(player: video.player)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .scaleEffect(totalScale)
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        scale = (scale > 1.0) ? 1.0 : 2.5
                    }
                }
            }
        }
        // 5. 绑定缩放手势 (iOS 17 推荐方式)
        .gesture(
            MagnifyGesture()
                .updating($gestureScale) { value, state, _ in
                    state = value.magnification
                }
                .onEnded { value in
                    withAnimation(.spring()) {
                        scale *= value.magnification
                        // 限制缩放范围：最小 1 倍，最大 4 倍
                        scale = min(max(scale, 1.0), 4.0)
                    }
                }
        )
        // 6. 关键：当缩放大于 1 时，允许 ScrollView 接管手势
        // 从而实现在放大状态下可以拖动查看图片边缘
        .scrollDisabled(totalScale <= 1.0)
    }
}

@available(iOS 17.0, macOS 14.0, *)
public struct OnlinePreviewVideoView: View {
    public struct Source: Hashable, Identifiable {
        public var id: URL { url }
        let url: URL
        let name: String
        public init(url: URL, name: String) {
            self.url = url
            self.name = name
        }
    }
    
    let player: AVPlayer
    let name: String
    public init(source: Source) {
        self.name = source.name
        self.player = .init(url: source.url)
    }
    
    @Environment(\.dismiss) private var dismiss
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1.0
    public var body: some View {
        ZStack {
            Color.black.opacity(opacity).ignoresSafeArea()
            
            VideoPlayer(player: player) {
                VStack(alignment: .leading) {
                    HStack {
                        Spacer()
                        Text(name).lineLimit(1)
                        Spacer()
                    }
                    Spacer()
                }
            }
            .offset(y: offset)
            .scaleEffect(1 - (offset / 1000))
        }
        .onAppear {
            player.play()
        }
        .onDisappear {
            player.pause()
        }
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
