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
    let loader: URLImageLoader?
    init(item: OnlinePreviewView.Item) {
        self.item = item
        switch item {
        case .file(let url, let key):
            loader = URLImageLoader(.init(url.absoluteString, size: .original, key: key))
        case .video:
            loader = nil
        }
    }
    
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
                        if let loader {
                            ImageView(loader: loader)
                        }
                    case .video(let video, _):
                        VideoPlayer(player: video.player)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .scaleEffect(totalScale)
                .onTapGesture(count: 2) {
                    let or: CGFloat
                    if let ps = loader?.result.value.imageSize?.width {
                        let sc = proxy.size.width / ps
                        if sc > 1 {
                            or = sc
                        } else {
                            or = 2.5
                        }
                    } else {
                        or = 2.5
                    }
                    withAnimation(.spring()) {
                        scale = (scale > 1.0) ? 1.0 : or
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
    @State private var isTwoFingerSeeking: Bool = false
    @State private var twoFingerSeekAnchorTime: Double = 0
    @State private var showControls: Bool = true
    @State private var hideControlsTask: DispatchWorkItem?
    @State private var pendingSeekTask: DispatchWorkItem?
    @State private var pendingSeekTime: Double?
    @State private var lastContinuousSeekAt: TimeInterval = 0

    let source: Source
    public init(source: Source) {
        self.source = source
    }
    
    @Environment(\.dismiss) private var dismiss
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1.0

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    private let continuousSeekInterval: TimeInterval = 0.08

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
                    ZStack {
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

                        TwoFingerSeekOverlay(
                            isEnabled: player != nil,
                            onStart: {
                                beginTwoFingerSeek()
                            },
                            onChange: { translationX, width in
                                updateTwoFingerSeek(translationX: translationX, width: width)
                            },
                            onEnd: {
                                endTwoFingerSeek()
                            }
                        )
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
                                        let target = clampedTime(newValue)
                                        currentTime = target
                                        if isSeeking {
                                            seekPlayer(to: target, throttled: true)
                                        }
                                    }
                                ),
                                in: 0...max(duration, 0.1),
                                onEditingChanged: { editing in
                                    isSeeking = editing
                                    if !editing {
                                        seekPlayer(to: currentTime)
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

            if player != nil, isTwoFingerSeeking {
                VStack {
                    Spacer()
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Color.white.opacity(0.18)
                            Color.white
                                .frame(width: max(proxy.size.width * progressFraction, 0))
                        }
                        .frame(height: 1)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
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
        pendingSeekTask?.cancel()
        pendingSeekTask = nil
        pendingSeekTime = nil
        isTwoFingerSeeking = false

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

    private var progressFraction: CGFloat {
        guard duration.isFinite, duration > 0 else { return 0 }
        return CGFloat(min(max(currentTime / duration, 0), 1))
    }

    private func beginTwoFingerSeek() {
        guard player != nil else { return }
        hideControlsTask?.cancel()
        hideControlsTask = nil
        isSeeking = true
        isTwoFingerSeeking = true
        twoFingerSeekAnchorTime = currentTime
    }

    private func updateTwoFingerSeek(translationX: CGFloat, width: CGFloat) {
        guard player != nil else { return }
        let validWidth = max(width, 1)
        let target = clampedTime(twoFingerSeekAnchorTime + duration * Double(translationX / validWidth))
        currentTime = target
        seekPlayer(to: target, throttled: true)
    }

    private func endTwoFingerSeek() {
        guard player != nil else {
            isSeeking = false
            isTwoFingerSeeking = false
            return
        }
        seekPlayer(to: currentTime)
        isSeeking = false
        isTwoFingerSeeking = false
        scheduleControlsAutoHide()
    }

    private func seek(by delta: Double) {
        guard player != nil else { return }
        let targetSeconds = clampedTime(currentTime + delta)
        currentTime = targetSeconds
        seekPlayer(to: targetSeconds)
        scheduleControlsAutoHide()
    }

    private func seekPlayer(to seconds: Double, throttled: Bool = false) {
        guard throttled else {
            pendingSeekTask?.cancel()
            pendingSeekTask = nil
            pendingSeekTime = nil
            performSeek(to: seconds)
            lastContinuousSeekAt = Date().timeIntervalSinceReferenceDate
            return
        }

        pendingSeekTime = seconds
        let now = Date().timeIntervalSinceReferenceDate
        let elapsed = now - lastContinuousSeekAt

        if elapsed >= continuousSeekInterval {
            pendingSeekTask?.cancel()
            pendingSeekTask = nil
            pendingSeekTime = nil
            performSeek(to: seconds)
            lastContinuousSeekAt = now
            return
        }

        pendingSeekTask?.cancel()
        let task = DispatchWorkItem {
            let target = pendingSeekTime ?? seconds
            pendingSeekTask = nil
            pendingSeekTime = nil
            performSeek(to: target)
            lastContinuousSeekAt = Date().timeIntervalSinceReferenceDate
        }
        pendingSeekTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + max(continuousSeekInterval - elapsed, 0.01), execute: task)
    }

    private func performSeek(to seconds: Double) {
        guard let player else { return }
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func clampedTime(_ seconds: Double) -> Double {
        let totalDuration = player?.currentItem?.duration.seconds ?? duration
        let upperBound = totalDuration.isFinite && totalDuration > 0 ? totalDuration : max(seconds, 0)
        return min(max(seconds, 0), upperBound)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

#if os(iOS)
@available(iOS 17.0, macOS 14.0, *)
private struct TwoFingerSeekOverlay: UIViewRepresentable {
    let isEnabled: Bool
    let onStart: () -> Void
    let onChange: (_ translationX: CGFloat, _ width: CGFloat) -> Void
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onStart: onStart, onChange: onChange, onEnd: onEnd)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let recognizer = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        recognizer.minimumNumberOfTouches = 2
        recognizer.maximumNumberOfTouches = 2
        recognizer.cancelsTouchesInView = false
        context.coordinator.recognizer = recognizer
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onStart = onStart
        context.coordinator.onChange = onChange
        context.coordinator.onEnd = onEnd
        context.coordinator.recognizer?.isEnabled = isEnabled
    }

    final class Coordinator: NSObject {
        var onStart: () -> Void
        var onChange: (_ translationX: CGFloat, _ width: CGFloat) -> Void
        var onEnd: () -> Void
        weak var recognizer: UIPanGestureRecognizer?

        init(
            onStart: @escaping () -> Void,
            onChange: @escaping (_ translationX: CGFloat, _ width: CGFloat) -> Void,
            onEnd: @escaping () -> Void
        ) {
            self.onStart = onStart
            self.onChange = onChange
            self.onEnd = onEnd
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            switch recognizer.state {
            case .began:
                onStart()
                onChange(recognizer.translation(in: view).x, view.bounds.width)
            case .changed:
                onChange(recognizer.translation(in: view).x, view.bounds.width)
            case .ended, .cancelled, .failed:
                onEnd()
            default:
                break
            }
        }
    }
}
#else
@available(iOS 17.0, macOS 14.0, *)
private struct TwoFingerSeekOverlay: View {
    let isEnabled: Bool
    let onStart: () -> Void
    let onChange: (_ translationX: CGFloat, _ width: CGFloat) -> Void
    let onEnd: () -> Void

    var body: some View {
        Color.clear.allowsHitTesting(false)
    }
}
#endif
