//
//  Platform.swift
//  
//
//  Created by qhc_m@qq.com on 2024/1/13.
//

import SwiftUI

#if os(OSX)

import AppKit

public typealias KKPoint = NSPoint
public typealias KKFont = NSFont
public typealias KKColor = NSColor
public typealias KKImage = NSImage
public typealias KKEdgeInsets = NSEdgeInsets
public typealias KKScreen = NSScreen
public typealias KKTableView = NSTableView
public typealias KKTextView = NSTextView
public typealias KKScrollView = NSScrollView
public typealias KKImageView = NSImageView
public typealias KKPanGestureRecognizer = NSPanGestureRecognizer
public typealias KKBezierPath = NSBezierPath
public typealias KKTapGestureRecognizer = NSClickGestureRecognizer
public typealias KKGestureRecognizer = NSGestureRecognizer
public typealias KKGestureRecognizerDelegate = NSGestureRecognizerDelegate

public typealias KKView = NSView
public typealias KKViewController = NSViewController
public typealias KKViewRepresentable = NSViewRepresentable
public typealias KKViewControllerRepresentable = NSViewControllerRepresentable
extension NSImage: @unchecked Sendable { }

#else

import UIKit

public typealias KKPoint = CGPoint
public typealias KKFont = UIFont
public typealias KKColor = UIColor
public typealias KKImage = UIImage
public typealias KKEdgeInsets = UIEdgeInsets
public typealias KKScreen = UIScreen
public typealias KKTableView = UITableView
public typealias KKScrollView = UIScrollView
public typealias KKTextView = UITextView
public typealias KKImageView = UIImageView
public typealias KKPanGestureRecognizer = UIPanGestureRecognizer
public typealias KKBezierPath = UIBezierPath
public typealias KKTapGestureRecognizer = UITapGestureRecognizer
public typealias KKGestureRecognizer = UIGestureRecognizer
public typealias KKGestureRecognizerDelegate = UIGestureRecognizerDelegate

public typealias KKView = UIView
public typealias KKViewController = UIViewController
public typealias KKViewRepresentable = UIViewRepresentable
public typealias KKViewControllerRepresentable = UIViewControllerRepresentable

#endif

struct GenericView<ViewType: KKView>: KKViewRepresentable {
    init(viewSource: @escaping () -> ViewType, updater: @escaping (ViewType) -> () = { _ in }) {
        self.viewSource = viewSource
        self.updater = updater
    }
    
    let viewSource: () -> ViewType
    let updater: (ViewType) -> ()
    func makeUIView(context: Context) -> ViewType { viewSource() }
    func makeNSView(context: Context) -> ViewType { viewSource() }
    func updateUIView(_ uiView: ViewType, context: Context) { updater(uiView) }
    func updateNSView(_ nsView: ViewType, context: Context) { updater(nsView) }
}

extension KKImage {
    var swiftUIView: Image {
        #if os(OSX)
        Image(nsImage: self)
        #else
        Image(uiImage: self)
        #endif
    }
}

extension KKImage {
    static func scaledFrom(_ originalImage: KKImage, to size: CGSize, rect: CGRect) -> KKImage? {
        #if os(iOS)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        originalImage.draw(in: rect)
        let bitImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return bitImage
        #else
        let image = KKImage(size: size)
        image.lockFocus()
        originalImage.draw(at: .zero, from: .init(origin: .zero, size: size), operation: .sourceOver, fraction: 1)
        image.unlockFocus()
        if let data = image.tiffRepresentation {
            return KKImage(data: data)
        }
        return nil
        #endif
    }
}

#if os(OSX)
extension KKImage {
    convenience init?(data: Data, scale: CGFloat) {
        self.init(data: data)
    }
    
    convenience init(cgImage: CGImage, scale: CGFloat) {
        self.init(cgImage: cgImage, size: .init(width: cgImage.width, height: cgImage.height))
    }
    
    var cgImage: CGImage? {
        return cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    
    var scale: CGFloat {
        return 1
    }
}
#endif
