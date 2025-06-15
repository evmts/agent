import Foundation

// Import mini terminal C functions
@_silgen_name("mini_terminal_init") 
func mini_terminal_init() -> Int32

@_silgen_name("mini_terminal_start") 
func mini_terminal_start() -> Int32

@_silgen_name("mini_terminal_stop") 
func mini_terminal_stop()

@_silgen_name("mini_terminal_write") 
func mini_terminal_write(_ text: UnsafePointer<CChar>) -> Int32

@_silgen_name("mini_terminal_read") 
func mini_terminal_read(_ buffer: UnsafeMutablePointer<UInt8>, _ size: Int) -> Int

@_silgen_name("mini_terminal_send_command") 
func mini_terminal_send_command(_ cmd: UnsafePointer<CChar>) -> Int32

/// Mini Terminal - Simplified terminal emulator
class MiniTerminal: ObservableObject {
    static let shared = MiniTerminal()
    
    @Published var output: String = ""
    @Published var isRunning: Bool = false
    
    private let readQueue = DispatchQueue(label: "com.plue.terminal.read", qos: .utility)
    
    private init() {}
    
    /// Initialize the terminal
    func initialize() -> Bool {
        let result = mini_terminal_init()
        if result == 0 {
            print("Mini terminal initialized successfully")
            return true
        } else {
            print("Failed to initialize mini terminal")
            return false
        }
    }
    
    /// Start the terminal process
    func start() -> Bool {
        guard !isRunning else { return true }
        
        let result = mini_terminal_start()
        if result == 0 {
            isRunning = true
            startReadingOutput()
            print("Mini terminal started")
            return true
        } else {
            print("Failed to start mini terminal")
            return false
        }
    }
    
    /// Stop the terminal
    func stop() {
        stopReadingOutput()
        mini_terminal_stop()
        isRunning = false
        print("Mini terminal stopped")
    }
    
    /// Send text to the terminal
    func sendText(_ text: String) {
        guard isRunning else { return }
        
        text.withCString { cString in
            let result = mini_terminal_write(cString)
            if result != 0 {
                print("Failed to write to terminal")
            }
        }
    }
    
    /// Send a command to the terminal (adds newline)
    func sendCommand(_ command: String) {
        guard isRunning else { return }
        
        command.withCString { cString in
            let result = mini_terminal_send_command(cString)
            if result != 0 {
                print("Failed to send command to terminal")
            }
        }
    }
    
    /// Clear the output
    func clearOutput() {
        output = ""
    }
    
    // Private methods
    
    private func startReadingOutput() {
        print("MiniTerminal: startReadingOutput() - starting read thread")
        // Create a dedicated read thread like Ghostty
        readQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Continuous read loop on background thread
            while self.isRunning {
                let bufferSize = 4096
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                defer { buffer.deallocate() }
                
                let bytesRead = mini_terminal_read(buffer, bufferSize)
                
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
                } else {
                    // No data available, sleep briefly to avoid busy loop
                    Thread.sleep(forTimeInterval: 0.01) // 10ms
                }
            }
            
            print("MiniTerminal: read thread exiting")
        }
    }
    
    private func stopReadingOutput() {
        // No timer to stop anymore, the read thread will exit when isRunning becomes false
    }
}