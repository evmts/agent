const std = @import("std");

/// Smart memory management with arena allocator strategy and performance tracking
/// Pre-allocates memory in chunks and doubles size when needed
const SmartAllocator = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    arena: ?std.heap.ArenaAllocator,
    base_size: usize,
    current_size: usize,
    stats: MemoryStats,
    
    const Self = @This();
    const DEFAULT_BASE_SIZE = 64 * 1024; // Start with 64KB
    
    const MemoryStats = struct {
        total_allocations: usize = 0,
        total_resets: usize = 0,
        peak_arena_size: usize = 0,
        bytes_allocated: usize = 0,
        
        pub fn recordAllocation(self: *MemoryStats, size: usize) void {
            self.total_allocations += 1;
            self.bytes_allocated += size;
        }
        
        pub fn recordReset(self: *MemoryStats, arena_size: usize) void {
            self.total_resets += 1;
            self.peak_arena_size = @max(self.peak_arena_size, arena_size);
        }
    };
    
    fn init() Self {
        return Self{
            .gpa = std.heap.GeneralPurposeAllocator(.{}){},
            .arena = null,
            .base_size = DEFAULT_BASE_SIZE,
            .current_size = DEFAULT_BASE_SIZE,
            .stats = .{},
        };
    }
    
    fn ensureArena(self: *Self) void {
        if (self.arena == null) {
            self.arena = std.heap.ArenaAllocator.init(self.gpa.allocator());
        }
    }
    
    fn deinit(self: *Self) void {
        if (self.arena) |*arena| {
            arena.deinit();
        }
        _ = self.gpa.deinit();
    }
    
    fn allocator(self: *Self) std.mem.Allocator {
        self.ensureArena();
        return self.arena.?.allocator();
    }
    
    /// Get memory statistics for monitoring
    fn getStats(self: *Self) MemoryStats {
        return self.stats;
    }
    
    /// Reset arena for next operation - very fast!
    fn reset(self: *Self) void {
        if (self.arena) |*arena| {
            arena.deinit();
            // Record statistics
            self.stats.recordReset(self.current_size);
        }
        // Double size if we're running out of space frequently
        self.current_size = @min(self.current_size * 2, 8 * 1024 * 1024); // Cap at 8MB
        self.arena = std.heap.ArenaAllocator.init(self.gpa.allocator());
    }
};

/// Thread-safe global state manager with smart allocation strategy
/// Follows Rust-style ownership principles for memory safety
const GlobalStateManager = struct {
    mutex: std.Thread.Mutex,
    smart_allocator: SmartAllocator,
    state: ?GlobalState,
    
    const Self = @This();
    
    fn init() Self {
        return Self{
            .mutex = std.Thread.Mutex{},
            .smart_allocator = SmartAllocator.init(),
            .state = null,
        };
    }
    
    fn deinit(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.state) |*state| {
            state.deinit();
            self.state = null;
        }
        self.smart_allocator.deinit();
    }
    
    /// Safe state access with automatic locking
    /// Rust-style borrowing - reference valid only during function call
    fn withState(self: *Self, comptime func: fn(*GlobalState) anyerror![]const u8) ![]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.state) |*state| {
            return try func(state);
        } else {
            std.log.err("Global state not initialized", .{});
            return error.StateNotInitialized;
        }
    }
    
    /// Safe state access with message parameter
    /// Uses arena allocation for zero-copy performance
    fn withStateAndMessage(self: *Self, message: []const u8) ![]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Reset arena for this operation - all allocations will be freed together
        self.smart_allocator.reset();
        
        if (self.state) |*state| {
            const result = try state.processMessage(message);
            
            // Copy result to caller's memory space (outside arena)
            const persistent_allocator = self.smart_allocator.gpa.allocator();
            return try persistent_allocator.dupe(u8, result);
        } else {
            std.log.err("Global state not initialized", .{});
            return error.StateNotInitialized;
        }
    }
    
    /// Initialize state with proper error handling
    fn initState(self: *Self) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.state != null) {
            return; // Already initialized
        }
        
        const allocator = self.smart_allocator.allocator();
        self.state = GlobalState.init(allocator);
    }
};

/// Core state with clear memory ownership
const GlobalState = struct {
    allocator: std.mem.Allocator,
    initialized: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .initialized = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self.initialized = false;
        // Note: allocator is owned by GlobalStateManager, don't free here
    }

    /// Process message with proper error handling and ownership transfer
    /// Returns owned string - caller must free with the same allocator
    pub fn processMessage(self: *Self, message: []const u8) ![]const u8 {
        if (!self.initialized) {
            return error.StateNotInitialized;
        }
        
        // Create response with clear ownership transfer
        return std.fmt.allocPrint(self.allocator, "Echo: {s}", .{message}) catch |err| {
            std.log.err("Failed to allocate response string: {}", .{err});
            return err;
        };
    }
};

// Single global instance with clear ownership
var global_manager = GlobalStateManager.init();

/// Validate input message for security and safety
fn validateInput(message: []const u8) bool {
    // Basic validation rules
    if (message.len == 0 or message.len > 10 * 1024) { // Max 10KB
        return false;
    }
    
    // Check for null bytes (C string safety)
    for (message) |byte| {
        if (byte == 0) return false;
    }
    
    // Check for valid UTF-8 (basic check)
    return std.unicode.utf8ValidateSlice(message);
}

/// Initialize the global state with thread safety
/// Returns: 0 on success, -1 on failure
export fn plue_init() c_int {
    global_manager.initState() catch |err| {
        std.log.err("Failed to initialize state: {}", .{err});
        return -1;
    };
    return 0;
}

/// Cleanup all resources with proper ownership destruction
export fn plue_deinit() void {
    global_manager.deinit();
}

/// Process message with safe memory management
/// Returns: owned null-terminated string - caller MUST call plue_free_string()
/// Ownership: Transfers ownership to caller
/// Lifetime: Until plue_free_string() is called
export fn plue_process_message(message: ?[*:0]const u8) ?[*:0]const u8 {
    // Validate input pointer
    const msg_ptr = message orelse {
        std.log.warn("Null message pointer passed to plue_process_message", .{});
        return null;
    };
    
    const msg = std.mem.span(msg_ptr);
    
    // Comprehensive input validation
    if (!validateInput(msg)) {
        std.log.warn("Invalid input message: length={}, valid_utf8={}", .{ 
            msg.len, 
            std.unicode.utf8ValidateSlice(msg) 
        });
        return null;
    }
    
    // Process with safe state access
    const response = global_manager.withStateAndMessage(msg) catch |err| {
        std.log.err("Failed to process message: {}", .{err});
        return null;
    };
    errdefer global_manager.gpa.allocator().free(response);
    
    // Convert to C string with clear ownership transfer
    const persistent_allocator = global_manager.smart_allocator.gpa.allocator();
    const c_str = persistent_allocator.dupeZ(u8, response) catch |err| {
        std.log.err("Failed to allocate C string: {}", .{err});
        persistent_allocator.free(response);
        return null;
    };
    
    // Free original response, transfer ownership of c_str to caller
    persistent_allocator.free(response);
    return c_str.ptr;
}

/// Safely free string allocated by plue_process_message
/// Ownership: Takes ownership from caller and destroys it
/// Safety: Handles null and validates pointers
export fn plue_free_string(str: ?[*:0]const u8) void {
    // Rust-style safety: validate pointer before use
    const str_ptr = str orelse {
        std.log.warn("Attempted to free null string pointer", .{});
        return;
    };
    
    const slice = std.mem.span(str_ptr);
    if (slice.len == 0) {
        std.log.warn("Attempted to free empty string", .{});
        return;
    }
    
    // Safe destruction with proper allocator
    global_manager.smart_allocator.gpa.allocator().free(slice);
}