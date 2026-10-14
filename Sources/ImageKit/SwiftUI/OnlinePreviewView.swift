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
        let loader: URLImageLoader
        let thumbnail: URLImageLoader?
        
        @MainActor public init(url: URL,
                               id: String? = nil,
                               liveVideo: [Item] = [],
                               name: String = "",
                               menus: [MenuItem] = [],
                               thumbnail: URLImageLoader? = nil) {
            self.url = url
            self.id = id ?? url.id
            self.liveVideo = liveVideo
            self.name = name
            self.menus = menus
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
    @State private var showControls = true
    @State private var showFullName = false
    private let onMenu: ((MenuItem, Item.ID) -> Void)?
    
    public init(state: Source, onMenu: ((MenuItem, Item.ID) -> Void)? = nil) {
        _state = .init(initialValue: state)
        self.onMenu = onMenu
    }
    
    @Environment(\.dismiss) private var dismiss
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

    public var body: some View {
        ZStack {
            Color.black.opacity(opacity).ignoresSafeArea()
            
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
            .offset(y: offset)
            .scaleEffect(1 - (offset / 1000))
            .ignoresSafeArea()
            
            if showControls && !isZooming {
                controllerView
            }
        }
        .presentationBackground(.clear)
        .preferredColorScheme(.dark)
        #if os(iOS)
        .statusBarHidden(!showControls || isZooming)
        .persistentSystemOverlays(showControls && !isZooming ? .automatic : .hidden)
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
                    if isZooming {
                        dismissDragBlocked = true
                    }
                    guard !dismissDragBlocked else { return }
                    if abs(value.translation.height) > abs(value.translation.width), value.translation.height > 0 {
                        offset = value.translation.height
                        opacity = Double(1 - (offset / 500))
                    }
                }
                .onEnded { _ in
                    guard !dismissDragBlocked, !isZooming, offset > 0 else { return }
                    if offset > 150 {
                        dismiss()
                    } else {
                        withAnimation(.spring()) {
                            offset = 0
                            opacity = 1.0
                        }
                    }
                },
            including: isZooming ? .subviews : .all
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
                ControllButton(systemName: "xmark") {
                    dismiss()
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
                    ControllButton(systemName: menu.systemName) {
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
            onMenu?(menu, item.id)
            dismiss()
        }
    }
    
    private func removeCurrentItem() {
        guard let item = currentItem,
              let index = state.items.firstIndex(where: { $0.id == item.id }) else {
            dismiss()
            return
        }
        zoomedItemIDs.remove(item.id)
        state.items.remove(at: index)
        if state.items.isEmpty {
            dismiss()
            return
        }
        let nextIndex = min(index, state.items.count - 1)
        state.currentID = state.items[nextIndex].id
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString.md5 }
}

@available(iOS 17.0, macOS 14.0, *)
private struct ControllButton: View {
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
    
    @ViewBuilder private var previewContent: some View {
        #if os(iOS)
        if let image = displayImage {
            ImagePreviewZoomView(image: image, livePhoto: hasOriginal ? result.livePhoto : nil,
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
    }
    
    private var isThumbnailSuccess: Bool {
        if case .success = thumbnailResult.value {
            return true
        }
        return false
    } 
}
