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
                        buildImageView(image)
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

@available(iOS 17.0, macOS 14.0, *)
public struct OnlinePreviewVideoView: View {
    public struct Source: Equatable, Identifiable {
        public var id: URL { url }
        let url: URL
        let name: String
        public init(url: URL, name: String) {
            self.url = url
            self.name = name
        }
    }
    
    private let player: AVPlayer
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
        player = AVPlayer(url: source.url)
    }
    
    @Environment(\.dismiss) private var dismiss
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1.0
    
    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    private let continuousSeekInterval: TimeInterval = 0.08
    
    public var body: some View {
        ZStack {
            Color.black.opacity(opacity).ignoresSafeArea()
            
            VideoPlayer(player: player)
                .allowsHitTesting(false) // 禁用点击，原生控制栏就不会因为点击而弹出
                .offset(y: offset)
                .scaleEffect(1 - (offset / 1000))
            
            GeometryReader { proxy in
                ZStack {
                    Color.clear
                        .contentShape(Rectangle())
                    
                    TwoFingerSeekOverlay(
                        isEnabled: true,
                        isDoubleTapEnabled: !showControls,
                        onSingleTap: {
                            toggleControls()
                        },
                        onLeftDoubleTap: {
                            seek(by: -15)
                        },
                        onRightDoubleTap: {
                            seek(by: 15)
                        },
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
            }
            .ignoresSafeArea()
            
            if showControls {
                controllerView
            }
            
            if isTwoFingerSeeking {
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
            guard !isSeeking else { return }
            let now = player.currentTime().seconds
            if now.isFinite {
                currentTime = now
            }
            
            let total = player.currentItem?.duration.seconds ?? 0
            if total.isFinite && total > 0 {
                duration = total
            }
        }
        .onAppear {
            startPlayback()
        }
        .onDisappear {
            pausePlayback(keepControlsVisible: true)
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
                        pausePlayback(keepControlsVisible: true)
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
    
    @ViewBuilder private var controllerView: some View {
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
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
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
    
    private func startPlayback() {
        let current = player.currentTime().seconds
        let targetTime: Double
        if playbackPosition > 0 {
            targetTime = playbackPosition
        } else if current.isFinite, current >= 0 {
            targetTime = current
        } else {
            targetTime = 0
        }
        
        if abs(current - targetTime) > 0.25 {
            let startTime = CMTime(seconds: targetTime, preferredTimescale: 600)
            player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        
        self.duration = player.currentItem?.duration.seconds.isFinite == true ? player.currentItem?.duration.seconds ?? 0 : 0
        self.currentTime = targetTime
        self.isPlaying = true
        self.showControls = true
        player.play()
        scheduleControlsAutoHide()
    }
    
    private func pausePlayback(keepControlsVisible: Bool) {
        hideControlsTask?.cancel()
        hideControlsTask = nil
        pendingSeekTask?.cancel()
        pendingSeekTask = nil
        pendingSeekTime = nil
        isTwoFingerSeeking = false
        
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
        self.isPlaying = false
        self.showControls = keepControlsVisible
    }
    
    private func togglePlayback() {
        if isPlaying {
            pausePlayback(keepControlsVisible: true)
        } else {
            startPlayback()
        }
    }
    
    private func toggleControls() {
        let shouldShow = !showControls
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls = shouldShow
        }
        
        if shouldShow {
            scheduleControlsAutoHide()
        } else {
            hideControlsTask?.cancel()
            hideControlsTask = nil
        }
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
        hideControlsTask?.cancel()
        hideControlsTask = nil
        isSeeking = true
        isTwoFingerSeeking = true
        twoFingerSeekAnchorTime = currentTime
    }
    
    private func updateTwoFingerSeek(translationX: CGFloat, width: CGFloat) {
        let validWidth = max(width, 1)
        let target = clampedTime(twoFingerSeekAnchorTime + duration * Double(translationX / validWidth))
        currentTime = target
        seekPlayer(to: target, throttled: true)
    }
    
    private func endTwoFingerSeek() {
        seekPlayer(to: currentTime)
        isSeeking = false
        isTwoFingerSeeking = false
        scheduleControlsAutoHide()
    }
    
    private func seek(by delta: Double) {
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
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    private func clampedTime(_ seconds: Double) -> Double {
        let totalDuration = player.currentItem?.duration.seconds ?? duration
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
    let isDoubleTapEnabled: Bool
    let onSingleTap: () -> Void
    let onLeftDoubleTap: () -> Void
    let onRightDoubleTap: () -> Void
    let onStart: () -> Void
    let onChange: (_ translationX: CGFloat, _ width: CGFloat) -> Void
    let onEnd: () -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            isDoubleTapEnabled: isDoubleTapEnabled,
            onSingleTap: onSingleTap,
            onLeftDoubleTap: onLeftDoubleTap,
            onRightDoubleTap: onRightDoubleTap,
            onStart: onStart,
            onChange: onChange,
            onEnd: onEnd
        )
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
        
        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.cancelsTouchesInView = false
        context.coordinator.singleTapRecognizer = singleTap
        view.addGestureRecognizer(singleTap)
        
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        context.coordinator.doubleTapRecognizer = doubleTap
        view.addGestureRecognizer(doubleTap)
        
        singleTap.require(toFail: doubleTap)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.isDoubleTapEnabled = isDoubleTapEnabled
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onLeftDoubleTap = onLeftDoubleTap
        context.coordinator.onRightDoubleTap = onRightDoubleTap
        context.coordinator.onStart = onStart
        context.coordinator.onChange = onChange
        context.coordinator.onEnd = onEnd
        context.coordinator.recognizer?.isEnabled = isEnabled
        context.coordinator.singleTapRecognizer?.isEnabled = isEnabled
        context.coordinator.doubleTapRecognizer?.isEnabled = isEnabled
    }
    
    final class Coordinator: NSObject {
        var isDoubleTapEnabled: Bool
        var onSingleTap: () -> Void
        var onLeftDoubleTap: () -> Void
        var onRightDoubleTap: () -> Void
        var onStart: () -> Void
        var onChange: (_ translationX: CGFloat, _ width: CGFloat) -> Void
        var onEnd: () -> Void
        weak var recognizer: UIPanGestureRecognizer?
        weak var singleTapRecognizer: UITapGestureRecognizer?
        weak var doubleTapRecognizer: UITapGestureRecognizer?
        
        init(
            isDoubleTapEnabled: Bool,
            onSingleTap: @escaping () -> Void,
            onLeftDoubleTap: @escaping () -> Void,
            onRightDoubleTap: @escaping () -> Void,
            onStart: @escaping () -> Void,
            onChange: @escaping (_ translationX: CGFloat, _ width: CGFloat) -> Void,
            onEnd: @escaping () -> Void
        ) {
            self.isDoubleTapEnabled = isDoubleTapEnabled
            self.onSingleTap = onSingleTap
            self.onLeftDoubleTap = onLeftDoubleTap
            self.onRightDoubleTap = onRightDoubleTap
            self.onStart = onStart
            self.onChange = onChange
            self.onEnd = onEnd
        }
        
        @objc func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onSingleTap()
        }
        
        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard isDoubleTapEnabled,
                  recognizer.state == .ended,
                  let view = recognizer.view
            else { return }
            
            let x = recognizer.location(in: view).x
            let width = view.bounds.width
            guard width > 0 else { return }
            
            if x < width * 0.5 {
                onLeftDoubleTap()
            } else {
                onRightDoubleTap()
            }
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
    let isDoubleTapEnabled: Bool
    let onSingleTap: () -> Void
    let onLeftDoubleTap: () -> Void
    let onRightDoubleTap: () -> Void
    let onStart: () -> Void
    let onChange: (_ translationX: CGFloat, _ width: CGFloat) -> Void
    let onEnd: () -> Void

    var body: some View {
        Color.clear.allowsHitTesting(false)
    }
}
#endif
