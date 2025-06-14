import SwiftUI
import AppKit
import Foundation

// Parse command line arguments
func parseCommandLineArguments() -> String? {
    let arguments = CommandLine.arguments
    
    // If we have a second argument, treat it as a directory path
    if arguments.count > 1 {
        let path = arguments[1]
        
        // Convert to absolute path if needed
        let fileManager = FileManager.default
        let absolutePath: String
        
        if path.hasPrefix("/") {
            absolutePath = path
        } else if path.hasPrefix("~") {
            absolutePath = NSString(string: path).expandingTildeInPath
        } else {
            // Relative path - make it absolute
            absolutePath = fileManager.currentDirectoryPath + "/" + path
        }
        
        // Verify the path exists and is a directory
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: absolutePath, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                return absolutePath
            } else {
                print("Error: '\(path)' is not a directory")
                exit(1)
            }
        } else {
            print("Error: Directory '\(path)' does not exist")
            exit(1)
        }
    }
    
    return nil
}

// Store the initial directory globally so the app can access it
var initialDirectory: String? = parseCommandLineArguments()

// Initialize NSApplication first
let app = NSApplication.shared

// Force the app to behave like a proper GUI app
app.setActivationPolicy(.regular)

// Start the SwiftUI app directly
PlueApp.main()