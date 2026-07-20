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
    
    private var currentItem: Item? {
        guard let currentID = state.currentID else { return state.items.first }
        return state.items.first { $0.id == currentID } ?? state.items.first
    }
    
    public var body: some View {
        ZStack {
            Color.black.opacity(opacity).ignoresSafeArea()
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(state.items) { item in
                        ZoomableImageCell(item: item) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showControls.toggle()
                            }
                        }
                        .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $state.currentID)
            .scrollTargetBehavior(.viewAligned)
            .offset(y: offset)
            .scaleEffect(1 - (offset / 1000))
            .ignoresSafeArea()
            
            if showControls {
                controllerView
            }
        }
        .presentationBackground(.clear)
        .preferredColorScheme(.dark)
        #if os(iOS)
        .statusBarHidden(!showControls)
        .persistentSystemOverlays(showControls ? .automatic : .hidden)
        #endif
        .alert("文件名", isPresented: $showFullName) {
            Button("好", role: .cancel) {}
        } message: {
            Text(currentItem?.name ?? "")
        }
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    if abs(value.translation.height) > abs(value.translation.width), value.translation.height > 0 {
                        offset = value.translation.height
                        opacity = Double(1 - (offset / 500))
                    }
                }
                .onEnded { value in
                    if value.translation.height > 150 {
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
    let onSingleTap: () -> Void
    var loader: URLImageLoader { item.loader }
    @ObservedObject private var result: ImageResult
    @ObservedObject private var thumbnailResult: ImageResult
    
    init(item: OnlinePreviewView.Item, onSingleTap: @escaping () -> Void) {
        self.item = item
        self.onSingleTap = onSingleTap
        result = item.loader.result
        thumbnailResult = item.thumbnail?.result ?? Self.emptyThumbnailResult
    }
    
    @State private var scale: CGFloat = 1.0
    @GestureState private var gestureScale: CGFloat = 1.0
    
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
    
    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                if let image = displayImage {
                    let totalScale = scale * gestureScale
                    let height = max(proxy.size.width / max(image.size.width, 1) * image.size.height, 1)
                    Group {
                        #if os(iOS)
                        if hasOriginal, let livePhoto = result.livePhoto {
                            LivePhotoView(livePhoto: livePhoto)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "livephoto")
                                        .padding(10)
                                }
                        } else {
                            image.swiftUIView
                                .resizable()
                                .scaledToFit()
                                .overlay(alignment: .bottomTrailing) {
                                    if hasOriginal, item.liveVideo.first != nil {
                                        Button {
                                            loader.loadLivePhoto()
                                        } label: {
                                            if loader.result.livePhotoLoading {
                                                ProgressView()
                                                    .padding(10)
                                            } else {
                                                Image(systemName: "livephoto")
                                                    .padding(10)
                                            }
                                        }
                                        .disabled(loader.result.livePhotoLoading)
                                    }
                                }
                        }
                        #else
                        image.swiftUIView
                            .resizable()
                            .scaledToFit()
                        #endif
                    }
                    .frame(width: proxy.size.width, height: height)
                    .scaleEffect(totalScale)
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            scale = (scale > 1.0) ? 1.0 : 2.5
                        }
                    }
                    .onTapGesture(count: 1) {
                        onSingleTap()
                    }
                    .gesture(
                        MagnifyGesture()
                            .updating($gestureScale) { value, state, _ in
                                state = value.magnification
                            }
                            .onEnded { value in
                                withAnimation(.spring()) {
                                    scale *= value.magnification
                                    scale = min(max(scale, 1.0), scale * 4.0)
                                }
                            }
                    )
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
            }
        }
        .scrollDisabled(scale <= 1.0)
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

#if os(iOS)
struct LivePhotoView: UIViewRepresentable {
    let livePhoto: PHLivePhoto

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.livePhoto = livePhoto
        view.isMuted = false
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        uiView.livePhoto = livePhoto
    }
}
#endif
