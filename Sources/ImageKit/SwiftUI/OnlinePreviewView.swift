//
//  OnlinePreviewView.swift
//  ImageKit
//
//  Created by qhc_m@qq.com on 2026/3/26.
//

import SwiftUI
import PhotosUI
import AVKit
#if os(iOS)
import UIKit
#endif

@available(iOS 17.0, macOS 14.0, *)
public struct OnlinePreviewView: View {
    public struct Item: Identifiable, Equatable {
        public let url: URL
        public let id: String
        public let liveVideo: [Item]
        public var name: String
        public var menus: [MenuItem]
        public let pixelSize: CGSize?
        let loader: URLImageLoader
        let thumbnail: URLImageLoader?
        
        @MainActor public init(url: URL,
                               id: String? = nil,
                               liveVideo: [Item] = [],
                               name: String = "",
                               menus: [MenuItem] = [],
                               thumbnail: URLImageLoader? = nil,
                               pixelSize: CGSize? = nil) {
            self.url = url
            self.id = id ?? url.id
            self.liveVideo = liveVideo
            self.name = name
            self.menus = menus
            self.pixelSize = pixelSize
            self.thumbnail = thumbnail
            self.loader = URLImageLoader(
                .init(url, size: .original, key: self.id),
                liveVideo: liveVideo.first.map { .init($0.url, size: .original, key: $0.id) }
            )
        }
    }
    
    public enum MenuItem: Hashable {
        case favorite(Bool)
        case delete
        case jumpToOriginalDir
        
        public var systemName: String {
            switch self {
            case .favorite(let bool): bool ? "star.fill" : "star"
            case .delete: "trash"
            case .jumpToOriginalDir: "folder"
            }
        }
        
        var isFavorite: Bool {
            if case .favorite = self {
                true
            } else {
                false
            }
        }
    }
    
    public struct Source: Equatable, Identifiable {
        public var id: String { currentID ?? "" }
        public var currentID: Item.ID?
        public var items: [Item]
        
        public init(current: Item.ID, items: [Item]) {
            self.items = items
            self.currentID = current
        }
    }
    
    @State private var state: Source
    @State private var showControls: Bool
    @State private var showFullName = false
    private let onMenu: ((MenuItem, Item.ID) -> Void)?
    private let zoom: ImagePreviewZoomModel?
    #if os(iOS)
    @State private var hero: HeroState?
    @State private var contentOpacity: Double
    @State private var dimOpacity: Double
    @State private var containerFrame = CGRect.zero
    @State private var isDismissing = false
    @State private var closeFollowUp: (() -> Void)?
    #endif
    
    public init(state: Source,
                zoom: ImagePreviewZoomModel? = nil,
                openingCell: CGRect? = nil,
                onMenu: ((MenuItem, Item.ID) -> Void)? = nil) {
        _state = .init(initialValue: state)
        self.onMenu = onMenu
        self.zoom = zoom
        #if os(iOS)
        let current = state.items.first { $0.id == state.currentID } ?? state.items.first
        let opening = current.flatMap { Self.openingFlight(item: $0, cell: openingCell ?? zoom?.frame(for: $0.id), zoom: zoom) }
        if let opening {
            _hero = .init(initialValue: opening)
            _contentOpacity = .init(initialValue: 0)
            _dimOpacity = .init(initialValue: 0)
            _showControls = .init(initialValue: false)
        } else {
            _hero = .init(initialValue: nil)
            _contentOpacity = .init(initialValue: 0)
            _dimOpacity = .init(initialValue: 0)
            _showControls = .init(initialValue: false)
        }
        #else
        _showControls = .init(initialValue: true)
        #endif
    }
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.imagePreviewDismiss) private var imagePreviewDismiss
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1.0
    @State private var zoomedItemIDs = Set<Item.ID>()
    @State private var dismissDragBlocked = false
    @GestureState private var dismissDragActive = false
    
    private var currentItem: Item? {
        guard let currentID = state.currentID else { return state.items.first }
        return state.items.first { $0.id == currentID } ?? state.items.first
    }
    
    private var isZooming: Bool {
        guard let item = currentItem else { return false }
        return zoomedItemIDs.contains(item.id)
    }

    private var blocksDismissDrag: Bool {
        #if os(iOS)
        isZooming || hero != nil || isDismissing
        #else
        isZooming
        #endif
    }

    private var presentedContentOpacity: Double {
        #if os(iOS)
        contentOpacity
        #else
        1
        #endif
    }

    private var backdropOpacity: Double {
        #if os(iOS)
        dimOpacity * opacity
        #else
        opacity
        #endif
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(backdropOpacity).ignoresSafeArea()
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(state.items) { item in
                        ZoomableImageCell(item: item, onZoomChange: { isZoomed in
                            if isZoomed {
                                zoomedItemIDs.insert(item.id)
                                if item.id == currentItem?.id {
                                    if dismissDragActive {
                                        dismissDragBlocked = true
                                    }
                                    offset = 0
                                    opacity = 1.0
                                }
                            } else {
                                zoomedItemIDs.remove(item.id)
                            }
                        }) {
                            guard !isZooming else { return }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showControls.toggle()
                            }
                        }
                        .containerRelativeFrame([.horizontal, .vertical])
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $state.currentID)
            .scrollTargetBehavior(.viewAligned)
            #if os(iOS)
            .environment(\.allowsPreviewReveal, hero == nil && !isDismissing)
            #endif
            .offset(y: offset)
            .scaleEffect(1 - (offset / 1000))
            .opacity(presentedContentOpacity)
            .allowsHitTesting(presentedContentOpacity > 0.9)
            .ignoresSafeArea()

            #if os(iOS)
            if let hero {
                GeometryReader { proxy in
                    let container = proxy.frame(in: .global)
                    if container.width > 1, container.height > 1 {
                        PreviewHeroRepresentable(
                            image: hero.image,
                            sourceCell: hero.cell.offsetBy(dx: -container.minX, dy: -container.minY),
                            dragOffset: hero.dragOffset,
                            layoutSize: hero.layoutSize,
                            from: hero.kind == .opening ? 0 : 1,
                            to: hero.kind == .opening ? 1 : 0,
                            duration: hero.kind == .opening ? 0.42 : 0.22,
                            dimPeak: hero.dimPeak,
                            onSettled: heroSettled
                        )
                        .id(hero.token)
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            #endif
            
            if showControls && !isZooming {
                controllerView
            }
        }
        #if os(iOS)
        .overlay {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { containerFrame = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in
                        containerFrame = frame
                    }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .onAppear {
            guard !isDismissing else { return }
            if hero == nil {
                withAnimation(.easeOut(duration: 0.22)) {
                    dimOpacity = 1
                    contentOpacity = 1
                } completion: {
                    guard !isDismissing else { return }
                    withAnimation(.easeOut(duration: 0.16)) {
                        showControls = true
                    }
                }
            } else {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    guard case .opening = hero?.kind, !isDismissing else { return }
                    heroSettled()
                }
            }
        }
        #endif
        .presentationBackground(.clear)
        .preferredColorScheme(.dark)
        #if os(iOS)
        .statusBarHidden(!showControls || isZooming || hero != nil || isDismissing)
        .persistentSystemOverlays(showControls && !isZooming && hero == nil && !isDismissing ? .automatic : .hidden)
        #endif
        .alert("文件名", isPresented: $showFullName) {
            Button("好", role: .cancel) {}
        } message: {
            Text(currentItem?.name ?? "")
        }
        .simultaneousGesture(
            DragGesture()
                .updating($dismissDragActive) { _, state, _ in
                    state = true
                }
                .onChanged { value in
                    if blocksDismissDrag {
                        dismissDragBlocked = true
                    }
                    guard !dismissDragBlocked, !blocksDismissDrag else { return }
                    if abs(value.translation.height) > abs(value.translation.width), value.translation.height > 0 {
                        offset = value.translation.height
                        opacity = Double(1 - (offset / 500))
                    }
                }
                .onEnded { _ in
                    guard !dismissDragBlocked, !blocksDismissDrag, offset > 0 else { return }
                    if offset > 150 {
                        requestClose()
                    } else {
                        withAnimation(.spring()) {
                            offset = 0
                            opacity = 1.0
                        }
                    }
                },
            including: blocksDismissDrag ? .subviews : .all
        )
        .onChange(of: dismissDragActive) { _, isActive in
            if !isActive {
                dismissDragBlocked = false
            }
        }
    }
    
    @ViewBuilder private var controllerView: some View {
        VStack {
            HStack(spacing: 20) {
                PreviewControlButton(systemName: "xmark") {
                    requestClose()
                }
                Spacer(minLength: 0)
                Text(currentItem?.name ?? "")
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .contentShape(.rect)
                    .onTapGesture {
                        showFullName = true
                    }
                Spacer(minLength: 0)
                ForEach(currentItem?.menus ?? [], id: \.self) { menu in
                    PreviewControlButton(systemName: menu.systemName) {
                        handleMenu(menu)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .frame(minHeight: 44)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.45), Color.black.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            Spacer()
                .allowsHitTesting(false)
        }
        .transition(.opacity)
    }
    
    private func handleMenu(_ menu: MenuItem) {
        guard let item = currentItem else { return }
        switch menu {
        case .favorite(let old):
            if let index = state.items.firstIndex(where: { $0.id == item.id }),
               let menuIndex = state.items[index].menus.firstIndex(where: { $0.isFavorite }) {
                state.items[index].menus[menuIndex] = .favorite(!old)
            }
            onMenu?(menu, item.id)
        case .delete:
            onMenu?(menu, item.id)
            removeCurrentItem()
        case .jumpToOriginalDir:
            let menu = menu
            let id = item.id
            requestClose {
                onMenu?(menu, id)
            }
        }
    }
    
    private func removeCurrentItem() {
        guard let item = currentItem,
              let index = state.items.firstIndex(where: { $0.id == item.id }) else {
            requestClose()
            return
        }
        zoomedItemIDs.remove(item.id)
        state.items.remove(at: index)
        if state.items.isEmpty {
            requestClose()
            return
        }
        let nextIndex = min(index, state.items.count - 1)
        state.currentID = state.items[nextIndex].id
    }

    private func requestClose(then follow: (() -> Void)? = nil) {
        #if os(iOS)
        guard !isDismissing else { return }
        isDismissing = true
        closeFollowUp = follow
        showControls = false
        let itemID = currentItem?.id
        let original = currentItem?.originalBitmap()
        let thumb = currentItem.flatMap { zoom?.previewImage(for: $0.id) } ?? currentItem?.thumbnailBitmap()
        let layoutSize = original == nil ? Self.cropLayoutSize(item: currentItem, image: thumb ?? hero?.image) : hero?.layoutSize
        let flightImage = (layoutSize == nil ? original : nil) ?? thumb ?? original ?? hero?.image
        let dragOffset = offset
        let peak = dimOpacity * opacity
        if let image = flightImage, let itemID, let cell = zoom?.visibleFrame(for: itemID) {
            beginClose(image: image, cell: cell, dragOffset: dragOffset, peak: peak, layoutSize: layoutSize)
            return
        }
        Task { @MainActor in
            let cell: CGRect?
            if let itemID, let zoom {
                cell = await zoom.revealFrame(for: itemID)
            } else {
                cell = nil
            }
            guard !Task.isCancelled, let image = flightImage, let cell else {
                withAnimation(.easeOut(duration: 0.16)) {
                    dimOpacity = 0
                    contentOpacity = 0
                } completion: {
                    self.finishDismiss()
                }
                return
            }
            beginClose(image: image, cell: cell, dragOffset: dragOffset, peak: peak, layoutSize: layoutSize)
        }
        #else
        follow?()
        dismiss()
        #endif
    }

    #if os(iOS)
    private func beginClose(image: UIImage, cell: CGRect, dragOffset: CGFloat, peak: CGFloat, layoutSize: CGSize?) {
        hero = HeroState(kind: .closing, image: image, cell: cell, dragOffset: dragOffset, layoutSize: layoutSize, dimPeak: peak)
        contentOpacity = 0
        dimOpacity = 0
    }

    private static func openingFlight(item: Item, cell: CGRect?, zoom: ImagePreviewZoomModel?) -> HeroState? {
        guard let cell, cell.width > 1, cell.height > 1 else { return nil }
        let thumb = zoom?.previewImage(for: item.id) ?? item.thumbnailBitmap()
        if let thumb, let layout = cropLayoutSize(item: item, image: thumb) {
            return HeroState(kind: .opening, image: thumb, cell: cell, layoutSize: layout)
        }
        let image = item.originalBitmap() ?? thumb
        guard let image else { return nil }
        return HeroState(kind: .opening, image: image, cell: cell)
    }

    private static func cropLayoutSize(item: Item?, image: UIImage?) -> CGSize? {
        guard let item, let image, let full = item.pixelSize,
              ImagePreviewZoomMath.usesCenterCrop(bitmap: image.size, full: full) else { return nil }
        return full
    }
    #endif

    #if os(iOS)
    private func heroSettled() {
        guard let hero else { return }
        switch hero.kind {
        case .opening:
            guard !isDismissing else { return }
            dimOpacity = 1
            contentOpacity = 1
            self.hero = nil
            withAnimation(.easeOut(duration: 0.18)) {
                showControls = true
            }
        case .closing:
            finishDismiss()
        }
    }

    private struct HeroState {
        enum Kind { case opening, closing }
        let token = UUID()
        let kind: Kind
        let image: UIImage
        let cell: CGRect
        var dragOffset: CGFloat = 0
        var layoutSize: CGSize?
        var dimPeak: CGFloat = 1
    }
    #endif

    private func finishDismiss() {
        #if os(iOS)
        let follow = closeFollowUp
        closeFollowUp = nil
        #endif
        if let imagePreviewDismiss {
            imagePreviewDismiss.run()
        } else {
            dismiss()
        }
        #if os(iOS)
        follow?()
        #endif
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString.md5 }
}

@available(iOS 17.0, macOS 14.0, *)
private struct PreviewControlButton: View {
    let systemName: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

@available(iOS 17.0, macOS 14.0, *)
private struct ZoomableImageCell: View {
    private static let emptyThumbnailResult = ImageResult()
    
    let item: OnlinePreviewView.Item
    let onZoomChange: (Bool) -> Void
    let onSingleTap: () -> Void
    var loader: URLImageLoader { item.loader }
    @ObservedObject private var result: ImageResult
    @ObservedObject private var thumbnailResult: ImageResult
    
    init(item: OnlinePreviewView.Item, onZoomChange: @escaping (Bool) -> Void, onSingleTap: @escaping () -> Void) {
        self.item = item
        self.onZoomChange = onZoomChange
        self.onSingleTap = onSingleTap
        result = item.loader.result
        thumbnailResult = item.thumbnail?.result ?? Self.emptyThumbnailResult
    }
    
    #if !os(iOS)
    @State private var scale: CGFloat = 1.0
    @State private var baseScale: CGFloat = 1.0
    @GestureState private var isPinching = false
    #endif
    
    private var displayImage: KKImage? {
        if case .success(let image) = result.value {
            return image
        }
        if item.thumbnail != nil, case .success(let image) = thumbnailResult.value {
            return image
        }
        return nil
    }
    
    private var hasOriginal: Bool {
        if case .success = result.value {
            return true
        }
        return false
    }

    #if os(iOS)
    @Environment(\.allowsPreviewReveal) private var allowsReveal

    private var thumbnailImage: UIImage? {
        guard item.thumbnail != nil, case .success(let image) = thumbnailResult.value else { return nil }
        guard image.size.width > 1, image.size.height > 1 else { return nil }
        return image
    }

    private var holdsCrop: Bool {
        guard let basis = thumbnailImage ?? displayImage, let full = item.pixelSize,
              ImagePreviewZoomMath.usesCenterCrop(bitmap: basis.size, full: full) else { return false }
        return !allowsReveal || !hasOriginal
    }

    private var imageForPreview: UIImage? {
        if holdsCrop, let thumbnailImage {
            return thumbnailImage
        }
        return displayImage
    }

    #endif
    
    @ViewBuilder private var previewContent: some View {
        #if os(iOS)
        if let image = imageForPreview {
            ImagePreviewZoomView(image: image,
                                 cropLayoutSize: holdsCrop ? item.pixelSize : nil,
                                 livePhoto: hasOriginal && allowsReveal ? result.livePhoto : nil,
                                 showsLivePhotoButton: hasOriginal && item.liveVideo.first != nil,
                                 isLoadingLivePhoto: result.livePhotoLoading,
                                 onSingleTap: onSingleTap, onLivePhoto: { loader.loadLivePhoto() },
                                 onZoomChange: onZoomChange)
        } else if case .failure = result.value, item.thumbnail == nil || !isThumbnailSuccess {
            Text("error")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(.white)
                .onTapGesture(perform: onSingleTap)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture(perform: onSingleTap)
        }
        #else
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                if let image = displayImage {
                    let fitScale = min(proxy.size.width / max(image.size.width, 1),
                                       proxy.size.height / max(image.size.height, 1))
                    let size = CGSize(width: image.size.width * fitScale,
                                      height: image.size.height * fitScale)
                    image.swiftUIView
                        .resizable()
                        .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(scale)
                    .frame(width: max(proxy.size.width, size.width * scale),
                           height: max(proxy.size.height, size.height * scale))
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            scale = (scale > 1.0) ? 1.0 : 2.5
                            baseScale = scale
                        }
                    }
                    .onTapGesture(count: 1) {
                        onSingleTap()
                    }
                    .gesture(
                        MagnifyGesture()
                            .updating($isPinching) { _, state, _ in
                                state = true
                            }
                            .onChanged { value in
                                var transaction = Transaction(animation: nil)
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    scale = min(max(baseScale * value.magnification, 1.0), 4.0)
                                }
                            }
                    )
                } else if case .failure = result.value, item.thumbnail == nil || !isThumbnailSuccess {
                    Text("error")
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .foregroundStyle(.white)
                        .onTapGesture(perform: onSingleTap)
                } else {
                    ProgressView()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .onTapGesture(perform: onSingleTap)
                }
            }
            .defaultScrollAnchor(.center)
        }
        .scrollDisabled(isPinching || scale <= 1.0)
        .onChange(of: isPinching) { _, isPinching in
            if !isPinching {
                // 结束或取消时只保存显示值，避免再次叠乘手势倍率。
                baseScale = scale
            }
        }
        .onChange(of: isPinching || scale > 1.0, initial: true) { _, isZoomed in
            onZoomChange(isZoomed)
        }
        .onAppear {
            onZoomChange(isPinching || scale > 1.0)
        }
        .onDisappear {
            onZoomChange(false)
        }
        #endif
    }

    var body: some View {
        previewContent
        .task(id: item.id) {
            if let thumbnail = item.thumbnail {
                if case .success = thumbnail.result.value { } else {
                    await thumbnail.loadImage()
                }
            }
            if case .success = loader.result.value { } else {
                await loader.loadImage()
            }
        }
        .onDisappear {
            loader.cancel()
            item.thumbnail?.cancel()
        }
    }
    
    private var isThumbnailSuccess: Bool {
        if case .success = thumbnailResult.value {
            return true
        }
        return false
    } 
}
