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

extension URL: @retroactive Identifiable {
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
                    case .file(let url, _):
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
                    case .video(let video, _):
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
    public struct Source: Equatable, Identifiable {
        public var id: URL { url }
        let url: URL
        let name: String
        let cover: URLImageLoader
        public init(url: URL, name: String, cover: URLImageLoader) {
            self.url = url
            self.name = name
            self.cover = cover
        }
    }
    
    @State private var player: AVPlayer?
    @State private var playbackPosition: Double = 0
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isPlaying: Bool = false
    @State private var isSeeking: Bool = false
    @State private var showControls: Bool = true
    @State private var hideControlsTask: DispatchWorkItem?

    let source: Source
    public init(source: Source) {
        self.source = source
    }
    
    @Environment(\.dismiss) private var dismiss
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1.0

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    public var body: some View {
        ZStack {
            Color.black.opacity(opacity).ignoresSafeArea()

            Group {
                if let player {
                    VideoPlayer(player: player)
                        .allowsHitTesting(false) // 禁用点击，原生控制栏就不会因为点击而弹出
                } else {
                    ImageView(loader: source.cover)
                }
            }
            .offset(y: offset)
            .scaleEffect(1 - (offset / 1000))

            if player != nil {
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                seek(by: -15)
                            }

                        Color.clear
                            .contentShape(Rectangle())

                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                seek(by: 15)
                            }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showControls.toggle()
                        }
                        if showControls {
                            scheduleControlsAutoHide()
                        }
                    }
                }
                .ignoresSafeArea()
            }

            if player == nil {
                Button {
                    startPlayback()
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 68, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
            }

            if player != nil, showControls {
                VStack {
                    HStack {
                        Spacer(minLength: 0)
                        Text(source.name)
                            .font(.headline)
                            .lineLimit(1)
                            .foregroundStyle(.white)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    Spacer()

                    VStack(spacing: 10) {
                        HStack(spacing: 16) {
                            Slider(
                                value: Binding(
                                    get: { duration > 0 ? currentTime : 0 },
                                    set: { newValue in
                                        currentTime = newValue
                                    }
                                ),
                                in: 0...max(duration, 0.1),
                                onEditingChanged: { editing in
                                    isSeeking = editing
                                    if !editing, let player {
                                        let target = CMTime(seconds: currentTime, preferredTimescale: 600)
                                        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                                        scheduleControlsAutoHide()
                                    }
                                }
                            )
                            .tint(.white)
                        }

                        HStack {
                            Text(formatTime(currentTime))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.9))
                            Spacer()
                            Text(formatTime(duration))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.0), Color.black.opacity(0.2)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .transition(.opacity)
                
                HStack(spacing: 28) {
                    Button {
                        seek(by: -15)
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(.black.opacity(0.35), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        pauseAndRelease()
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(.black.opacity(0.42), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        seek(by: 15)
                    } label: {
                        Image(systemName: "goforward.15")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(.black.opacity(0.35), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
            }
        }
        .onReceive(ticker) { _ in
            guard let player, !isSeeking else { return }
            let now = player.currentTime().seconds
            if now.isFinite {
                currentTime = now
            }

            let total = player.currentItem?.duration.seconds ?? 0
            if total.isFinite && total > 0 {
                duration = total
            }
        }
        .onDisappear {
            pauseAndRelease()
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
                        pauseAndRelease()
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

    private func startPlayback() {
        let player = AVPlayer(url: source.url)
        if playbackPosition > 0 {
            let startTime = CMTime(seconds: playbackPosition, preferredTimescale: 600)
            player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        self.player = player
        self.duration = player.currentItem?.duration.seconds.isFinite == true ? player.currentItem?.duration.seconds ?? 0 : 0
        self.currentTime = playbackPosition
        self.isPlaying = true
        self.showControls = true
        player.play()
        scheduleControlsAutoHide()
    }

    private func pauseAndRelease() {
        hideControlsTask?.cancel()
        hideControlsTask = nil

        guard let player else { return }
        let current = player.currentTime().seconds
        if current.isFinite, current >= 0 {
            playbackPosition = current
            currentTime = current
        }
        let total = player.currentItem?.duration.seconds ?? 0
        if total.isFinite, total > 0 {
            duration = total
        }

        player.pause()
        self.player = nil
        self.isPlaying = false
        self.showControls = true
    }

    private func scheduleControlsAutoHide() {
        hideControlsTask?.cancel()
        guard isPlaying else { return }
        let task = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls = false
            }
        }
        hideControlsTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
    }

    private func seek(by delta: Double) {
        guard let player else { return }
        let totalDuration = player.currentItem?.duration.seconds ?? duration
        let maxTime = totalDuration.isFinite && totalDuration > 0 ? totalDuration : currentTime + max(delta, 0)
        let targetSeconds = min(max(currentTime + delta, 0), maxTime)
        let target = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        currentTime = targetSeconds
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        scheduleControlsAutoHide()
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
