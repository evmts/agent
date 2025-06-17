import SwiftUI
import AppKit
import Foundation

// Parse command line arguments
func parseCommandLineArguments() -> String? {
    if CommandLine.arguments.count <= 1 {
        return nil
    }
    let path = CommandLine.arguments[1]
    
    let absolutePath: String
    if path.hasPrefix("/") {
        absolutePath = path
    } else if path.hasPrefix("~") {
        absolutePath = NSString(string: path).expandingTildeInPath
    } else {
        absolutePath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path).path
    }
    
    var isDirectory: ObjCBool = false
    if !FileManager.default.fileExists(atPath: absolutePath, isDirectory: &isDirectory) {
        fputs("Error: Directory '\(path)' does not exist\n", stderr)
        exit(1)
    }
    if !isDirectory.boolValue {
        fputs("Error: '\(path)' is not a directory\n", stderr)
        exit(1)
    } 
    return absolutePath
}

var initialDirectory: String? = parseCommandLineArguments()

let app = NSApplication.shared
app.setActivationPolicy(.regular)
PlueApp.main()
