import Foundation

// Import PTY terminal C functions
@_silgen_name("pty_terminal_init") 
func pty_terminal_init() -> Int32

@_silgen_name("pty_terminal_start") 
func pty_terminal_start() -> Int32

@_silgen_name("pty_terminal_stop") 
func pty_terminal_stop()

@_silgen_name("pty_terminal_write") 
func pty_terminal_write(_ data: UnsafePointer<UInt8>, _ len: Int) -> Int

@_silgen_name("pty_terminal_read") 
func pty_terminal_read(_ buffer: UnsafeMutablePointer<UInt8>, _ bufferLen: Int) -> Int

@_silgen_name("pty_terminal_send_text") 
func pty_terminal_send_text(_ text: UnsafePointer<CChar>)

@_silgen_name("pty_terminal_resize") 
func pty_terminal_resize(_ cols: UInt16, _ rows: UInt16)

@_silgen_name("pty_terminal_deinit") 
func pty_terminal_deinit()

/// PTY Terminal - Proper pseudo-terminal implementation
class PtyTerminal: ObservableObject {
    static let shared = PtyTerminal()
    
    @Published var output: String = ""
    @Published var isRunning: Bool = false
    
    private let readQueue = DispatchQueue(label: "com.plue.pty.read", qos: .utility)
    private var isReading = false
    private let bufferSize = 4096
    
    private init() {}
    
    /// Initialize the terminal
    func initialize() -> Bool {
        let result = pty_terminal_init()
        if result == 0 {
            print("PTY terminal initialized successfully")
            return true
        } else {
            print("Failed to initialize PTY terminal")
            return false
        }
    }
    
    /// Start the terminal process
    func start() -> Bool {
        guard !isRunning else { return true }
        
        let result = pty_terminal_start()
        if result == 0 {
            isRunning = true
            startReadingOutput()
            print("PTY terminal started")
            return true
        } else {
            print("Failed to start PTY terminal")
            return false
        }
    }
    
    /// Stop the terminal
    func stop() {
        isReading = false
        pty_terminal_stop()
        isRunning = false
        print("PTY terminal stopped")
    }
    
    /// Send text to the terminal
    func sendText(_ text: String) {
        guard isRunning else { return }
        
        text.withCString { cString in
            pty_terminal_send_text(cString)
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
    
    /// Resize the terminal
    func resize(cols: Int, rows: Int) {
        guard isRunning else { return }
        pty_terminal_resize(UInt16(cols), UInt16(rows))
    }
    
    // Private methods
    
    private func startReadingOutput() {
        isReading = true
        readQueue.async { [weak self] in
            guard let self = self else { return }
            
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: self.bufferSize)
            defer { buffer.deallocate() }
            
            while self.isReading && self.isRunning {
                let bytesRead = pty_terminal_read(buffer, self.bufferSize)
                
                if bytesRead > 0 {
                    let data = Data(bytes: buffer, count: bytesRead)
                    if let newOutput = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async {
                            self.output += newOutput
                            
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
                    print("Error reading from PTY: \(bytesRead)")
                    break
                }
            }
            
            print("PTY read thread exiting")
        }
    }
    
    deinit {
        stop()
        pty_terminal_deinit()
    }
}