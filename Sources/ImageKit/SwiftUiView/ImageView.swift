//
//  ImageView.swift
//  SimpKit
//
//  Created by qhc_m@qq.com on 2022/7/28.
//

import SwiftUI
import PhotosUI

public enum ImagePhase : Sendable {
    case empty
    case success(KKImage)
    case failure(any Error)
    
    var imageSize: CGSize? {
        if case .success(let image) = self {
            return image.size
        }
        return nil
    }
    
    @ViewBuilder func buildView(loader: ImageLoader) -> some View {
        switch self {
        case .success(let image):
            #if os(iOS)
            if loader.request.context.isDisplay() {
                iOSImageView(image, loader: loader)
            } else {
                Text(loader.request.isGif == false ? "\(loader.request.url.lastPathComponent)" : "gif")
                    .frame(width: loader.request.size.width, height: loader.request.size.height ?? image.size.height / KKScreen.main.scale)
                    .border(color: .green)
            }
            #else
            buildImageView(image, loader: loader)
            #endif
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

#if os(iOS)
@ViewBuilder func iOSImageView(_ image: KKImage, loader: ImageLoader) -> some View {
    if loader.request.isGif != false {
        GenericView<AutoResizeImageView> {
            let size = CGSize(width: loader.request.size.width ?? image.size.width, height: loader.request.size.height ?? image.size.height)
            let view = AutoResizeImageView(size: size)
            view.contentMode = .scaleAspectFill
            return view
        } updater: { view in
            view.image = image
        }
        .frame(width: loader.request.size.width, height: loader.request.size.height)
        .clipped()
        .contentShape(Rectangle())
    } else {
        buildImageView(image, loader: loader)
    }
}
#endif

func buildImageView(_ image: KKImage, loader: ImageLoader) -> some View {
    image.swiftUIView
        .resizable()
        .scaledToFill()
        .frame(width: loader.request.size.width, height: loader.request.size.height)
        .clipped()
}

public class ImageResultObservableObject: ObservableObject {
    @Published public var value: ImagePhase = .empty
    @Published public var livePhoto: PHLivePhoto? = nil
    @Published public fileprivate(set) var livePhotoLoading = false
    var requestID: PHLivePhotoRequestID? = nil
    public init() { }
}

extension URLImageLoader {
    func loadLivePhoto() {
        guard let liveVideo else {
            return
        }
        result.livePhotoLoading = true
        weak var res = result
        Task { @MainActor in
            if request.url.scheme == "ph" {
                let localIdentifier = request.url.absoluteString.replacingOccurrences(of: "ph://", with: "")
                fetchLivePhoto(with: localIdentifier, targetSize: .zero) { live, info in
                    if let live {
                        result.livePhoto = live
                        result.livePhotoLoading = false
                    }
                }
            } else {
                await NetworkLoader().loadFor(request: request)
                await NetworkLoader().loadFor(request: liveVideo)
                syncLoadLivePhoto()
            }
        }
    }
    
    func syncLoadLivePhoto() {
        guard let liveVideo else {
            return
        }
        let videoURL = liveVideo.localPath()
        let imagePath = request.localPath()
        let res = result
        logInfo("will load local live photo: \(liveVideo.key)")
        result.requestID = PHLivePhoto.request(withResourceFileURLs: [imagePath, videoURL], placeholderImage: nil, targetSize: .zero, contentMode: .aspectFit) { result, info in
            let isDegraded = info[PHLivePhotoInfoIsDegradedKey] as? Bool ?? false
            if let result, !isDegraded {
                res.livePhoto = result
                res.livePhotoLoading = false
            }
            if let error = info[PHLivePhotoInfoErrorKey] as? Error {
                logInfo("did load local live photo \(result != nil): \(liveVideo.key), isDegraded: \(isDegraded), error: \(error.localizedDescription)")
            } else {
                logInfo("did load local live photo \(result != nil): \(liveVideo.key), isDegraded: \(isDegraded)")
                if result == nil {
                    Task {
                        await self.loadImage()
                    }
                }
            }
        }
    }
    
    private func fetchLivePhoto(with localIdentifier: String, targetSize: CGSize, completion: @escaping (PHLivePhoto?, [AnyHashable: Any]?) -> Void) {
        // 1. 获取 Asset
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        
        guard let asset = result.firstObject else {
            logInfo("未找到对应的 Asset")
            return
        }
        
        // 检查是否为 Live Photo 类型
        guard asset.mediaSubtypes.contains(.photoLive) else {
            logInfo("该资源不是 Live Photo")
            return
        }
        
        // 2. 配置请求参数
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat // 确保获取高质量资源
        options.isNetworkAccessAllowed = true      // 允许从 iCloud 下载资源（真机必备）
        
        // 设置下载进度回调（可选）
        options.progressHandler = { progress, error, stop, info in
            logInfo("iCloud 下载进度: \(progress)")
        }
        
        // 3. 请求 Live Photo
        PHImageManager.default().requestLivePhoto(for: asset,
                                                 targetSize: targetSize,
                                                 contentMode: .aspectFill,
                                                 options: options) { (livePhoto, info) in
            
            // 注意：该回调可能会多次执行
            // 第一次可能返回低清预览图 (isDegraded == true)
            // 第二次返回高清图
            
            completion(livePhoto, info)
        }
    }
}

public protocol ImageLoader {
    var request: ImageRequest { get }
    var result: ImageResultObservableObject { get }
    func loadImage() async
    func cancel()
}

public extension ImageLoader {
    func cancel() {
        logInfo("ImageLoader cancel")
    }
}

public struct ImageView: View {
    public init(loader: ImageLoader) {
        self.loader = loader
    }
    
    public init(url: URL,
                size: ImageRequest.Size) {
        loader = URLImageLoader(.init(url, size: size))
    }
    private let loader: ImageLoader
    public var body: some View {
        ImageCustomView(loader: loader) {
            $0.buildView(loader: $1)
        }
    }
}

public struct ImageCustomView<Content>: View where Content : View {
    public init(loader: ImageLoader,
                @ViewBuilder content: @escaping (ImagePhase, ImageLoader) -> Content) {
        self.loader = loader
        self.content = content
        self.result = loader.result
    }
    
    public init(url: URL,
                size: ImageRequest.Size,
                @ViewBuilder content: @escaping (ImagePhase, ImageLoader) -> Content) {
        let loader = URLImageLoader(.init(url, size: size))
        self.init(loader: loader, content: content)
    }
    
    let loader: ImageLoader
    let content: (ImagePhase, ImageLoader) -> Content
    @ObservedObject var result: ImageResultObservableObject
    public var body: some View {
        content(result.value, loader)
            .task(id: "\(loader.request.size)-\(loader.request.processors.rawValue)") {
                if case .success = result.value { } else {
                    await loader.loadImage()
                }
            }
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
    let size: CGSize
    public init(size: CGSize) {
        self.size = size
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var intrinsicContentSize: CGSize {
        return size
    }
}
#endif
