//
//  Log.swift
//  ImageKit
//

import Foundation

func logInfo(fileName: String = #file, funcName: String = #function, lineNum: Int = #line, _ items: Any..., separator: String = " ") {
    let stringItems = items.map { String(describing: $0) }
    let combinedString = stringItems.joined(separator: separator)
    print("[\((fileName as NSString).lastPathComponent):\(lineNum), \(funcName)]: \(combinedString)")
}

func logDebug(fileName: String = #file, funcName: String = #function, lineNum: Int = #line, _ text: @autoclosure () -> String) {
    #if DEBUG
    print("[\((fileName as NSString).lastPathComponent):\(lineNum), \(funcName)]: \(text())")
    #endif
}
