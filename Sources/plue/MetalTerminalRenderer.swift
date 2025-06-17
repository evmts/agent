import MetalKit
import CoreText

// MARK: - Metal Terminal Renderer
class MetalTerminalRenderer: NSObject {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    
    // Pipeline states
    private var backgroundPipelineState: MTLRenderPipelineState!
    private var textPipelineState: MTLRenderPipelineState!
    private var cursorPipelineState: MTLRenderPipelineState!
    private var selectionPipelineState: MTLRenderPipelineState!
    
    // Vertex buffer
    private var vertexBuffer: MTLBuffer!
    
    // Font rendering
    private let font: NSFont
    private var fontAtlas: FontAtlas!
    private var atlasTexture: MTLTexture!
    
    // Terminal dimensions
    private var viewportSize: SIMD2<Float> = .zero
    private var cellSize: CGSize = .zero
    
    // Colors
    private let colorPalette = TerminalColorPalette()
    
    init?(metalDevice: MTLDevice, font: NSFont) {
        self.device = metalDevice
        self.font = font
        
        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.commandQueue = commandQueue
        
        // Try to load the shader library from the bundle
        do {
            let metalURL = Bundle.main.url(forResource: "default", withExtension: "metallib")
            if let metalURL = metalURL {
                self.library = try device.makeLibrary(URL: metalURL)
            } else {
                // Fallback to default library
                guard let library = device.makeDefaultLibrary() else {
                    return nil
                }
                self.library = library
            }
        } catch {
            print("Failed to load Metal library: \(error)")
            return nil
        }
        
        super.init()
        
        if !setupPipelines() || !setupBuffers() || !setupFontAtlas() {
            return nil
        }
    }
    
    // MARK: - Setup
    
    private func setupPipelines() -> Bool {
        // Vertex descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 2
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 4
        
        // Background pipeline
        let backgroundDescriptor = MTLRenderPipelineDescriptor()
        backgroundDescriptor.vertexFunction = library.makeFunction(name: "terminalVertexShader")
        backgroundDescriptor.fragmentFunction = library.makeFunction(name: "terminalBackgroundFragment")
        backgroundDescriptor.vertexDescriptor = vertexDescriptor
        backgroundDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        backgroundDescriptor.colorAttachments[0].isBlendingEnabled = true
        backgroundDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        backgroundDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        
        do {
            backgroundPipelineState = try device.makeRenderPipelineState(descriptor: backgroundDescriptor)
        } catch {
            print("Failed to create background pipeline state: \(error)")
            return false
        }
        
        // Text pipeline
        let textDescriptor = MTLRenderPipelineDescriptor()
        textDescriptor.vertexFunction = library.makeFunction(name: "terminalVertexShader")
        textDescriptor.fragmentFunction = library.makeFunction(name: "terminalTextFragment")
        textDescriptor.vertexDescriptor = vertexDescriptor
        textDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        textDescriptor.colorAttachments[0].isBlendingEnabled = true
        textDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        textDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        
        do {
            textPipelineState = try device.makeRenderPipelineState(descriptor: textDescriptor)
        } catch {
            print("Failed to create text pipeline state: \(error)")
            return false
        }
        
        // Cursor pipeline
        let cursorDescriptor = MTLRenderPipelineDescriptor()
        cursorDescriptor.vertexFunction = library.makeFunction(name: "terminalVertexShader")
        cursorDescriptor.fragmentFunction = library.makeFunction(name: "terminalCursorFragment")
        cursorDescriptor.vertexDescriptor = vertexDescriptor
        cursorDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        cursorDescriptor.colorAttachments[0].isBlendingEnabled = true
        cursorDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        cursorDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        
        do {
            cursorPipelineState = try device.makeRenderPipelineState(descriptor: cursorDescriptor)
        } catch {
            print("Failed to create cursor pipeline state: \(error)")
            return false
        }
        
        // Selection pipeline
        let selectionDescriptor = MTLRenderPipelineDescriptor()
        selectionDescriptor.vertexFunction = library.makeFunction(name: "terminalVertexShader")
        selectionDescriptor.fragmentFunction = library.makeFunction(name: "terminalSelectionFragment")
        selectionDescriptor.vertexDescriptor = vertexDescriptor
        selectionDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        selectionDescriptor.colorAttachments[0].isBlendingEnabled = true
        selectionDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        selectionDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        
        do {
            selectionPipelineState = try device.makeRenderPipelineState(descriptor: selectionDescriptor)
        } catch {
            print("Failed to create selection pipeline state: \(error)")
            return false
        }
        
        return true
    }
    
    private func setupBuffers() -> Bool {
        // Create vertex buffer for a quad
        let vertices: [Float] = [
            // Position (x, y), TexCoord (u, v)
            0, 0,      0, 0,  // Top-left
            1, 0,      1, 0,  // Top-right
            0, 1,      0, 1,  // Bottom-left
            1, 1,      1, 1,  // Bottom-right
        ]
        
        guard let buffer = device.makeBuffer(bytes: vertices,
                                            length: vertices.count * MemoryLayout<Float>.size,
                                            options: .storageModeShared) else {
            return false
        }
        
        vertexBuffer = buffer
        return true
    }
    
    private func setupFontAtlas() -> Bool {
        fontAtlas = FontAtlas(font: font, device: device)
        
        guard let texture = fontAtlas.createTexture() else {
            return false
        }
        
        atlasTexture = texture
        
        // Calculate cell size based on font metrics
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let sampleSize = NSAttributedString(string: "M", attributes: attributes).size()
        cellSize = CGSize(width: sampleSize.width, height: font.capHeight + font.descender + font.leading)
        
        return true
    }
    
    // MARK: - Rendering
    
    func render(buffer: TerminalBuffer, cursorVisible: Bool, selection: TerminalSelection?, in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        viewportSize = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        
        // Clear background
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0
        )
        
        // Set viewport
        renderEncoder.setViewport(MTLViewport(
            originX: 0, originY: 0,
            width: Double(view.drawableSize.width),
            height: Double(view.drawableSize.height),
            znear: 0, zfar: 1
        ))
        
        // Render cells
        renderCells(buffer: buffer, with: renderEncoder)
        
        // Render selection if any
        if let selection = selection {
            renderSelection(selection, buffer: buffer, with: renderEncoder)
        }
        
        // Render cursor
        if cursorVisible {
            renderCursor(buffer: buffer, with: renderEncoder)
        }
        
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private func renderCells(buffer: TerminalBuffer, with renderEncoder: MTLRenderCommandEncoder) {
        // First pass: render background colors
        renderEncoder.setRenderPipelineState(backgroundPipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBytes(&viewportSize, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
        
        for row in 0..<buffer.rows {
            for col in 0..<buffer.cols {
                let cell = buffer.getCell(row: row, col: col)
                
                // Skip default background
                if cell.backgroundColor == .black { continue }
                
                let rect = cellRect(row: row, col: col)
                var transform = makeTransform(rect: rect)
                
                var color = colorToFloat4(cell.backgroundColor)
                
                renderEncoder.setVertexBytes(&transform, length: MemoryLayout<simd_float4x4>.size, index: 1)
                renderEncoder.setFragmentBytes(&color, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
                renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
        }
        
        // Second pass: render text
        renderEncoder.setRenderPipelineState(textPipelineState)
        renderEncoder.setFragmentTexture(atlasTexture, index: 0)
        
        for row in 0..<buffer.rows {
            for col in 0..<buffer.cols {
                let cell = buffer.getCell(row: row, col: col)
                
                // Skip empty cells
                if cell.character == " " { continue }
                
                guard let glyph = fontAtlas.glyph(for: cell.character) else { continue }
                
                let rect = cellRect(row: row, col: col)
                var transform = makeTransform(rect: rect, texCoords: glyph.texCoords)
                
                var textColor = colorToFloat4(cell.foregroundColor)
                var bgColor = colorToFloat4(cell.backgroundColor)
                
                renderEncoder.setVertexBytes(&transform, length: MemoryLayout<simd_float4x4>.size, index: 1)
                renderEncoder.setFragmentBytes(&textColor, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
                renderEncoder.setFragmentBytes(&bgColor, length: MemoryLayout<SIMD4<Float>>.size, index: 1)
                renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
        }
    }
    
    private func renderCursor(buffer: TerminalBuffer, with renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setRenderPipelineState(cursorPipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBytes(&viewportSize, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
        
        let (row, col) = buffer.cursorPosition
        let rect = cellRect(row: row, col: col)
        var transform = makeTransform(rect: rect)
        
        var cursorColor = SIMD4<Float>(1, 1, 1, 0.8)
        var time = Float(CACurrentMediaTime())
        
        renderEncoder.setVertexBytes(&transform, length: MemoryLayout<simd_float4x4>.size, index: 1)
        renderEncoder.setFragmentBytes(&cursorColor, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        renderEncoder.setFragmentBytes(&time, length: MemoryLayout<Float>.size, index: 1)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
    
    private func renderSelection(_ selection: TerminalSelection, buffer: TerminalBuffer, with renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.setRenderPipelineState(selectionPipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBytes(&viewportSize, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
        
        var selectionColor = SIMD4<Float>(0.5, 0.5, 0.8, 0.3)
        
        for row in selection.startRow...selection.endRow {
            let startCol = row == selection.startRow ? selection.startCol : 0
            let endCol = row == selection.endRow ? selection.endCol : buffer.cols - 1
            
            let rect = CGRect(
                x: CGFloat(startCol) * cellSize.width,
                y: CGFloat(row) * cellSize.height,
                width: CGFloat(endCol - startCol + 1) * cellSize.width,
                height: cellSize.height
            )
            
            var transform = makeTransform(rect: rect)
            
            renderEncoder.setVertexBytes(&transform, length: MemoryLayout<simd_float4x4>.size, index: 1)
            renderEncoder.setFragmentBytes(&selectionColor, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }
    
    // MARK: - Helpers
    
    private func cellRect(row: Int, col: Int) -> CGRect {
        return CGRect(
            x: CGFloat(col) * cellSize.width,
            y: CGFloat(row) * cellSize.height,
            width: cellSize.width,
            height: cellSize.height
        )
    }
    
    private func makeTransform(rect: CGRect, texCoords: CGRect? = nil) -> simd_float4x4 {
        // For now, just return identity - in real implementation this would
        // transform the quad to the correct position
        return simd_float4x4(1)
    }
    
    private func colorToFloat4(_ color: NSColor) -> SIMD4<Float> {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        return SIMD4<Float>(
            Float(rgb.redComponent),
            Float(rgb.greenComponent),
            Float(rgb.blueComponent),
            Float(rgb.alphaComponent)
        )
    }
}

// MARK: - Font Atlas
class FontAtlas {
    private let font: NSFont
    private let device: MTLDevice
    private let atlasSize = 1024
    private var glyphs: [Character: GlyphInfo] = [:]
    
    struct GlyphInfo {
        let texCoords: CGRect
        let size: CGSize
        let offset: CGPoint
    }
    
    init(font: NSFont, device: MTLDevice) {
        self.font = font
        self.device = device
        generateAtlas()
    }
    
    private func generateAtlas() {
        // Generate atlas for ASCII printable characters
        // In a real implementation, this would create a texture atlas
        // with all glyphs rendered using Core Text
    }
    
    func createTexture() -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: atlasSize,
            height: atlasSize,
            mipmapped: false
        )
        
        return device.makeTexture(descriptor: descriptor)
    }
    
    func glyph(for character: Character) -> GlyphInfo? {
        return glyphs[character]
    }
}

// MARK: - Terminal Selection
struct TerminalSelection {
    let startRow: Int
    let startCol: Int
    let endRow: Int
    let endCol: Int
}

// MARK: - Terminal Color Palette
struct TerminalColorPalette {
    let black = NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
    let red = NSColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)
    let green = NSColor(red: 0.0, green: 0.8, blue: 0.0, alpha: 1.0)
    let yellow = NSColor(red: 0.8, green: 0.8, blue: 0.0, alpha: 1.0)
    let blue = NSColor(red: 0.0, green: 0.0, blue: 0.8, alpha: 1.0)
    let magenta = NSColor(red: 0.8, green: 0.0, blue: 0.8, alpha: 1.0)
    let cyan = NSColor(red: 0.0, green: 0.8, blue: 0.8, alpha: 1.0)
    let white = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
    
    let brightBlack = NSColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
    let brightRed = NSColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
    let brightGreen = NSColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
    let brightYellow = NSColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0)
    let brightBlue = NSColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0)
    let brightMagenta = NSColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0)
    let brightCyan = NSColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 1.0)
    let brightWhite = NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    
    let background = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
    let foreground = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
}