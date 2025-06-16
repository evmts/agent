import Foundation

// Import unified terminal C functions
@_silgen_name("terminal_init") 
func terminal_init() -> Int32

@_silgen_name("terminal_start") 
func terminal_start() -> Int32

@_silgen_name("terminal_stop") 
func terminal_stop()

@_silgen_name("terminal_write") 
func terminal_write(_ data: UnsafePointer<UInt8>, _ len: Int) -> Int

@_silgen_name("terminal_read") 
func terminal_read(_ buffer: UnsafeMutablePointer<UInt8>, _ bufferLen: Int) -> Int

@_silgen_name("terminal_send_text") 
func terminal_send_text(_ text: UnsafePointer<CChar>)

@_silgen_name("terminal_deinit") 
func terminal_deinit()

/// Unified Terminal - Production PTY implementation
class Terminal: ObservableObject {
    static let shared = Terminal()
    
    @Published var output: String = ""
    @Published var isRunning: Bool = false
    
    private let readQueue = DispatchQueue(label: "com.plue.macos.pty.read", qos: .utility)
    private var isReading = false
    private let bufferSize = 4096
    
    private init() {}
    
    /// Initialize the terminal
    func initialize() -> Bool {
        let result = terminal_init()
        if result == 0 {
            print("Terminal initialized successfully")
            return true
        } else {
            print("Failed to initialize terminal")
            return false
        }
    }
    
    /// Start the terminal process
    func start() -> Bool {
        guard !isRunning else { return true }
        
        let result = terminal_start()
        if result == 0 {
            isRunning = true
            startReadingOutput()
            print("Terminal started")
            return true
        } else {
            print("Failed to start terminal")
            return false
        }
    }
    
    /// Stop the terminal
    func stop() {
        isReading = false
        terminal_stop()
        isRunning = false
        print("Terminal stopped")
    }
    
    /// Send text to the terminal
    func sendText(_ text: String) {
        guard isRunning else { return }
        
        text.withCString { cString in
            terminal_send_text(cString)
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
            
            print("Terminal read thread started")
            
            while self.isReading && self.isRunning {
                let bytesRead = terminal_read(buffer, self.bufferSize)
                
                if bytesRead > 0 {
                    print("Terminal read \(bytesRead) bytes")
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
                    print("Error reading from terminal: \(bytesRead)")
                    break
                }
            }
            
            print("Terminal read thread exiting")
        }
    }
    
    deinit {
        stop()
        terminal_deinit()
    }
}