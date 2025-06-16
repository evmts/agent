import Foundation

// Import macOS PTY C functions
@_silgen_name("macos_pty_init") 
func macos_pty_init() -> Int32

@_silgen_name("macos_pty_start") 
func macos_pty_start() -> Int32

@_silgen_name("macos_pty_stop") 
func macos_pty_stop()

@_silgen_name("macos_pty_write") 
func macos_pty_write(_ data: UnsafePointer<UInt8>, _ len: Int) -> Int

@_silgen_name("macos_pty_read") 
func macos_pty_read(_ buffer: UnsafeMutablePointer<UInt8>, _ bufferLen: Int) -> Int

@_silgen_name("macos_pty_send_text") 
func macos_pty_send_text(_ text: UnsafePointer<CChar>)

@_silgen_name("macos_pty_deinit") 
func macos_pty_deinit()

/// macOS PTY Terminal - Minimal working PTY implementation
class MacOSPtyTerminal: ObservableObject {
    static let shared = MacOSPtyTerminal()
    
    @Published var output: String = ""
    @Published var isRunning: Bool = false
    
    private let readQueue = DispatchQueue(label: "com.plue.macos.pty.read", qos: .utility)
    private var isReading = false
    private let bufferSize = 4096
    
    private init() {}
    
    /// Initialize the terminal
    func initialize() -> Bool {
        let result = macos_pty_init()
        if result == 0 {
            print("macOS PTY initialized successfully")
            return true
        } else {
            print("Failed to initialize macOS PTY")
            return false
        }
    }
    
    /// Start the terminal process
    func start() -> Bool {
        guard !isRunning else { return true }
        
        let result = macos_pty_start()
        if result == 0 {
            isRunning = true
            startReadingOutput()
            print("macOS PTY started")
            return true
        } else {
            print("Failed to start macOS PTY")
            return false
        }
    }
    
    /// Stop the terminal
    func stop() {
        isReading = false
        macos_pty_stop()
        isRunning = false
        print("macOS PTY stopped")
    }
    
    /// Send text to the terminal
    func sendText(_ text: String) {
        guard isRunning else { return }
        
        text.withCString { cString in
            macos_pty_send_text(cString)
        }
    }
    
    /// Send a command to the terminal (adds newline)
    func sendCommand(_ command: String) {
        sendText(command + "\n")
    }
    
    /// Clear the output
    func clearOutput() {
        output = ""
    }
    
    // Private methods
    
    private func startReadingOutput() {
        isReading = true
        readQueue.async { [weak self] in
            guard let self = self else { return }
            
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: self.bufferSize)
            defer { buffer.deallocate() }
            
            print("macOS PTY read thread started")
            
            while self.isReading && self.isRunning {
                let bytesRead = macos_pty_read(buffer, self.bufferSize)
                
                if bytesRead > 0 {
                    print("macOS PTY read \(bytesRead) bytes")
                    let data = Data(bytes: buffer, count: bytesRead)
                    if let newOutput = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.output += newOutput
                            print("Terminal output now: \(self.output.suffix(100))")
                            
                            // Limit output buffer size
                            if self.output.count > 100000 {
                                let index = self.output.index(self.output.startIndex, offsetBy: 50000)
                                self.output = String(self.output[index...])
                            }
                        }
                    }
                } else if bytesRead == 0 {
                    // No data available, sleep briefly
                    Thread.sleep(forTimeInterval: 0.01) // 10ms
                } else {
                    // Error occurred
                    print("Error reading from macOS PTY: \(bytesRead)")
                    break
                }
            }
            
            print("macOS PTY read thread exiting")
        }
    }
    
    deinit {
        stop()
        macos_pty_deinit()
    }
}