const std = @import("std");
const testing = std.testing;
const permissions = @import("permissions.zig");
const AccessMode = permissions.AccessMode;
const UnitType = permissions.UnitType;

// Repository unit configuration
pub const RepositoryUnit = struct {
    id: i64,
    repo_id: i64,
    unit_type: UnitType,
    access_mode: AccessMode,
};

// Unit access manager for fine-grained repository feature control
pub const UnitAccessManager = struct {
    allocator: std.mem.Allocator,
    repository_units: std.ArrayList(RepositoryUnit),
    
    pub fn init(allocator: std.mem.Allocator) UnitAccessManager {
        return UnitAccessManager{
            .allocator = allocator,
            .repository_units = std.ArrayList(RepositoryUnit).init(allocator),
        };
    }
    
    pub fn deinit(self: *UnitAccessManager) void {
        self.repository_units.deinit();
    }
    
    pub fn setRepositoryUnitAccess(self: *UnitAccessManager, repo_id: i64, unit_type: UnitType, access_mode: AccessMode) !void {
        // Check if unit access already exists
        for (self.repository_units.items) |*unit| {
            if (unit.repo_id == repo_id and unit.unit_type == unit_type) {
                unit.access_mode = access_mode;
                return;
            }
        }
        
        // Add new unit access
        const unit_id = @as(i64, @intCast(self.repository_units.items.len + 1));
        const repo_unit = RepositoryUnit{
            .id = unit_id,
            .repo_id = repo_id,
            .unit_type = unit_type,
            .access_mode = access_mode,
        };
        
        try self.repository_units.append(repo_unit);
    }
    
    pub fn getRepositoryUnitAccess(self: *UnitAccessManager, repo_id: i64, unit_type: UnitType) ?AccessMode {
        for (self.repository_units.items) |unit| {
            if (unit.repo_id == repo_id and unit.unit_type == unit_type) {
                return unit.access_mode;
            }
        }
        return null;
    }
    
    pub fn getRepositoryUnits(self: *UnitAccessManager, allocator: std.mem.Allocator, repo_id: i64) ![]RepositoryUnit {
        var repo_units = std.ArrayList(RepositoryUnit).init(allocator);
        errdefer repo_units.deinit();
        
        for (self.repository_units.items) |unit| {
            if (unit.repo_id == repo_id) {
                try repo_units.append(unit);
            }
        }
        
        return repo_units.toOwnedSlice();
    }
    
    pub fn removeRepositoryUnitAccess(self: *UnitAccessManager, repo_id: i64, unit_type: UnitType) void {
        var i: usize = 0;
        while (i < self.repository_units.items.len) {
            const unit = self.repository_units.items[i];
            if (unit.repo_id == repo_id and unit.unit_type == unit_type) {
                _ = self.repository_units.swapRemove(i);
                return;
            }
            i += 1;
        }
    }
    
    pub fn initializeDefaultUnits(self: *UnitAccessManager, repo_id: i64, visibility: permissions.Visibility) !void {
        // Initialize default unit access based on repository visibility
        const default_access = switch (visibility) {
            .Public => AccessMode.Read,
            .Limited => AccessMode.Read,
            .Private => AccessMode.None,
        };
        
        // Core repository features
        try self.setRepositoryUnitAccess(repo_id, .Code, default_access);
        try self.setRepositoryUnitAccess(repo_id, .Issues, default_access);
        try self.setRepositoryUnitAccess(repo_id, .PullRequests, default_access);
        try self.setRepositoryUnitAccess(repo_id, .Wiki, default_access);
        
        // Advanced features (typically more restricted)
        try self.setRepositoryUnitAccess(repo_id, .Projects, .None);
        try self.setRepositoryUnitAccess(repo_id, .Actions, .None);
        try self.setRepositoryUnitAccess(repo_id, .Packages, .None);
        try self.setRepositoryUnitAccess(repo_id, .Settings, .None); // Admin only
    }
    
    pub fn checkUnitEnabled(self: *UnitAccessManager, repo_id: i64, unit_type: UnitType) bool {
        if (self.getRepositoryUnitAccess(repo_id, unit_type)) |access_mode| {
            return access_mode != .None;
        }
        return false;
    }
    
    pub fn getEnabledUnits(self: *UnitAccessManager, allocator: std.mem.Allocator, repo_id: i64) ![]UnitType {
        var enabled_units = std.ArrayList(UnitType).init(allocator);
        errdefer enabled_units.deinit();
        
        for (self.repository_units.items) |unit| {
            if (unit.repo_id == repo_id and unit.access_mode != .None) {
                try enabled_units.append(unit.unit_type);
            }
        }
        
        return enabled_units.toOwnedSlice();
    }
    
    pub fn buildUnitAccessMap(self: *UnitAccessManager, repo_id: i64) std.EnumMap(UnitType, AccessMode) {
        var unit_map = std.EnumMap(UnitType, AccessMode){};
        
        for (self.repository_units.items) |unit| {
            if (unit.repo_id == repo_id) {
                unit_map.put(unit.unit_type, unit.access_mode);
            }
        }
        
        return unit_map;
    }
    
    pub fn validateUnitAccess(self: *UnitAccessManager, repo_id: i64, unit_type: UnitType, user_access: AccessMode) bool {
        if (self.getRepositoryUnitAccess(repo_id, unit_type)) |required_access| {
            return user_access.atLeast(required_access);
        }
        
        // If no specific unit access is defined, allow access
        return true;
    }
};

// Unit type utilities
pub const UnitTypeHelpers = struct {
    pub fn isCodeUnit(unit_type: UnitType) bool {
        return unit_type == .Code;
    }
    
    pub fn isIssueUnit(unit_type: UnitType) bool {
        return unit_type == .Issues or unit_type == .PullRequests;
    }
    
    pub fn isContentUnit(unit_type: UnitType) bool {
        return unit_type == .Wiki or unit_type == .Projects;
    }
    
    pub fn isAdvancedUnit(unit_type: UnitType) bool {
        return unit_type == .Actions or unit_type == .Packages;
    }
    
    pub fn isAdminUnit(unit_type: UnitType) bool {
        return unit_type == .Settings;
    }
    
    pub fn getUnitDisplayName(unit_type: UnitType) []const u8 {
        return switch (unit_type) {
            .Code => "Repository",
            .Issues => "Issues",
            .PullRequests => "Pull Requests",
            .Wiki => "Wiki",
            .Projects => "Projects",
            .Actions => "Actions",
            .Packages => "Packages",
            .Settings => "Settings",
        };
    }
    
    pub fn getUnitDescription(unit_type: UnitType) []const u8 {
        return switch (unit_type) {
            .Code => "Access to repository code and commits",
            .Issues => "View and manage issues",
            .PullRequests => "View and manage pull requests",
            .Wiki => "Access to repository wiki",
            .Projects => "Access to project boards",
            .Actions => "Access to GitHub Actions workflows",
            .Packages => "Access to package registry",
            .Settings => "Repository administration settings",
        };
    }
    
    pub fn getDefaultUnitAccess(unit_type: UnitType, repo_visibility: permissions.Visibility) AccessMode {
        if (isAdminUnit(unit_type)) {
            return .None; // Settings always require admin
        }
        
        if (isAdvancedUnit(unit_type)) {
            return .None; // Advanced features disabled by default
        }
        
        return switch (repo_visibility) {
            .Public => .Read,
            .Limited => .Read,
            .Private => .None,
        };
    }
    
    pub fn getRequiredAccessForAction(unit_type: UnitType, action: []const u8) AccessMode {
        // Determine required access level based on unit type and action
        if (std.mem.eql(u8, action, "read") or std.mem.eql(u8, action, "view")) {
            return .Read;
        }
        
        if (std.mem.eql(u8, action, "create") or std.mem.eql(u8, action, "comment")) {
            return if (unit_type == .Issues or unit_type == .PullRequests) .Read else .Write;
        }
        
        if (std.mem.eql(u8, action, "edit") or std.mem.eql(u8, action, "update")) {
            return .Write;
        }
        
        if (std.mem.eql(u8, action, "delete") or std.mem.eql(u8, action, "admin")) {
            return if (isAdminUnit(unit_type)) .Admin else .Write;
        }
        
        if (std.mem.eql(u8, action, "configure") or std.mem.eql(u8, action, "manage")) {
            return .Admin;
        }
        
        return .Read; // Default to read for unknown actions
    }
};

// Tests for unit access management
test "UnitAccessManager sets and gets repository unit access" {
    const allocator = testing.allocator;
    
    var unit_manager = UnitAccessManager.init(allocator);
    defer unit_manager.deinit();
    
    const repo_id: i64 = 123;
    
    // Set unit access
    try unit_manager.setRepositoryUnitAccess(repo_id, .Issues, .Write);
    try unit_manager.setRepositoryUnitAccess(repo_id, .Wiki, .Read);
    try unit_manager.setRepositoryUnitAccess(repo_id, .Settings, .Admin);
    
    // Verify access levels
    try testing.expectEqual(
        AccessMode.Write,
        unit_manager.getRepositoryUnitAccess(repo_id, .Issues).?
    );
    try testing.expectEqual(
        AccessMode.Read,
        unit_manager.getRepositoryUnitAccess(repo_id, .Wiki).?
    );
    try testing.expectEqual(
        AccessMode.Admin,
        unit_manager.getRepositoryUnitAccess(repo_id, .Settings).?
    );
    
    // Non-existent unit should return null
    try testing.expect(unit_manager.getRepositoryUnitAccess(repo_id, .Code) == null);
}

test "UnitAccessManager updates existing unit access" {
    const allocator = testing.allocator;
    
    var unit_manager = UnitAccessManager.init(allocator);
    defer unit_manager.deinit();
    
    const repo_id: i64 = 456;
    
    // Set initial access
    try unit_manager.setRepositoryUnitAccess(repo_id, .Issues, .Read);
    try testing.expectEqual(
        AccessMode.Read,
        unit_manager.getRepositoryUnitAccess(repo_id, .Issues).?
    );
    
    // Update access
    try unit_manager.setRepositoryUnitAccess(repo_id, .Issues, .Write);
    try testing.expectEqual(
        AccessMode.Write,
        unit_manager.getRepositoryUnitAccess(repo_id, .Issues).?
    );
}

test "UnitAccessManager initializes default units correctly" {
    const allocator = testing.allocator;
    
    var unit_manager = UnitAccessManager.init(allocator);
    defer unit_manager.deinit();
    
    const public_repo_id: i64 = 123;
    const private_repo_id: i64 = 456;
    
    // Initialize defaults for public repository
    try unit_manager.initializeDefaultUnits(public_repo_id, .Public);
    
    // Core features should be readable
    try testing.expectEqual(
        AccessMode.Read,
        unit_manager.getRepositoryUnitAccess(public_repo_id, .Code).?
    );
    try testing.expectEqual(
        AccessMode.Read,
        unit_manager.getRepositoryUnitAccess(public_repo_id, .Issues).?
    );
    
    // Advanced features should be disabled
    try testing.expectEqual(
        AccessMode.None,
        unit_manager.getRepositoryUnitAccess(public_repo_id, .Actions).?
    );
    try testing.expectEqual(
        AccessMode.None,
        unit_manager.getRepositoryUnitAccess(public_repo_id, .Settings).?
    );
    
    // Initialize defaults for private repository
    try unit_manager.initializeDefaultUnits(private_repo_id, .Private);
    
    // All features should be disabled for private repo
    try testing.expectEqual(
        AccessMode.None,
        unit_manager.getRepositoryUnitAccess(private_repo_id, .Code).?
    );
    try testing.expectEqual(
        AccessMode.None,
        unit_manager.getRepositoryUnitAccess(private_repo_id, .Issues).?
    );
}

test "UnitAccessManager checks enabled units" {
    const allocator = testing.allocator;
    
    var unit_manager = UnitAccessManager.init(allocator);
    defer unit_manager.deinit();
    
    const repo_id: i64 = 789;
    
    // Set some units as enabled, others disabled
    try unit_manager.setRepositoryUnitAccess(repo_id, .Code, .Read);
    try unit_manager.setRepositoryUnitAccess(repo_id, .Issues, .Write);
    try unit_manager.setRepositoryUnitAccess(repo_id, .Wiki, .None);
    try unit_manager.setRepositoryUnitAccess(repo_id, .Actions, .None);
    
    // Check enabled status
    try testing.expect(unit_manager.checkUnitEnabled(repo_id, .Code));
    try testing.expect(unit_manager.checkUnitEnabled(repo_id, .Issues));
    try testing.expect(!unit_manager.checkUnitEnabled(repo_id, .Wiki));
    try testing.expect(!unit_manager.checkUnitEnabled(repo_id, .Actions));
    
    // Get enabled units
    const enabled_units = try unit_manager.getEnabledUnits(allocator, repo_id);
    defer allocator.free(enabled_units);
    
    try testing.expectEqual(@as(usize, 2), enabled_units.len);
    
    // Verify enabled units (order might vary)
    var found_code = false;
    var found_issues = false;
    for (enabled_units) |unit_type| {
        if (unit_type == .Code) found_code = true;
        if (unit_type == .Issues) found_issues = true;
    }
    
    try testing.expect(found_code);
    try testing.expect(found_issues);
}

test "UnitAccessManager builds unit access map" {
    const allocator = testing.allocator;
    
    var unit_manager = UnitAccessManager.init(allocator);
    defer unit_manager.deinit();
    
    const repo_id: i64 = 321;
    
    // Set various unit access levels
    try unit_manager.setRepositoryUnitAccess(repo_id, .Code, .Read);
    try unit_manager.setRepositoryUnitAccess(repo_id, .Issues, .Write);
    try unit_manager.setRepositoryUnitAccess(repo_id, .Settings, .Admin);
    
    // Build access map
    const access_map = unit_manager.buildUnitAccessMap(repo_id);
    
    // Verify map contents
    try testing.expectEqual(AccessMode.Read, access_map.get(.Code).?);
    try testing.expectEqual(AccessMode.Write, access_map.get(.Issues).?);
    try testing.expectEqual(AccessMode.Admin, access_map.get(.Settings).?);
    try testing.expectEqual(AccessMode.None, access_map.get(.Wiki).?); // Default
}

test "UnitAccessManager validates user access correctly" {
    const allocator = testing.allocator;
    
    var unit_manager = UnitAccessManager.init(allocator);
    defer unit_manager.deinit();
    
    const repo_id: i64 = 654;
    
    // Set unit requirements
    try unit_manager.setRepositoryUnitAccess(repo_id, .Issues, .Write);
    try unit_manager.setRepositoryUnitAccess(repo_id, .Settings, .Admin);
    
    // Test validation
    try testing.expect(unit_manager.validateUnitAccess(repo_id, .Issues, .Write));
    try testing.expect(unit_manager.validateUnitAccess(repo_id, .Issues, .Admin)); // Higher access
    try testing.expect(!unit_manager.validateUnitAccess(repo_id, .Issues, .Read)); // Lower access
    
    try testing.expect(unit_manager.validateUnitAccess(repo_id, .Settings, .Admin));
    try testing.expect(!unit_manager.validateUnitAccess(repo_id, .Settings, .Write));
    
    // Undefined unit should allow access
    try testing.expect(unit_manager.validateUnitAccess(repo_id, .Code, .Read));
}

test "UnitTypeHelpers provides correct classifications" {
    // Test unit type classifications
    try testing.expect(UnitTypeHelpers.isCodeUnit(.Code));
    try testing.expect(!UnitTypeHelpers.isCodeUnit(.Issues));
    
    try testing.expect(UnitTypeHelpers.isIssueUnit(.Issues));
    try testing.expect(UnitTypeHelpers.isIssueUnit(.PullRequests));
    try testing.expect(!UnitTypeHelpers.isIssueUnit(.Code));
    
    try testing.expect(UnitTypeHelpers.isContentUnit(.Wiki));
    try testing.expect(UnitTypeHelpers.isContentUnit(.Projects));
    try testing.expect(!UnitTypeHelpers.isContentUnit(.Issues));
    
    try testing.expect(UnitTypeHelpers.isAdvancedUnit(.Actions));
    try testing.expect(UnitTypeHelpers.isAdvancedUnit(.Packages));
    try testing.expect(!UnitTypeHelpers.isAdvancedUnit(.Code));
    
    try testing.expect(UnitTypeHelpers.isAdminUnit(.Settings));
    try testing.expect(!UnitTypeHelpers.isAdminUnit(.Code));
}

test "UnitTypeHelpers provides correct display information" {
    // Test display names
    try testing.expectEqualStrings("Repository", UnitTypeHelpers.getUnitDisplayName(.Code));
    try testing.expectEqualStrings("Issues", UnitTypeHelpers.getUnitDisplayName(.Issues));
    try testing.expectEqualStrings("Settings", UnitTypeHelpers.getUnitDisplayName(.Settings));
    
    // Test descriptions
    const code_desc = UnitTypeHelpers.getUnitDescription(.Code);
    try testing.expect(std.mem.indexOf(u8, code_desc, "code") != null);
    
    const settings_desc = UnitTypeHelpers.getUnitDescription(.Settings);
    try testing.expect(std.mem.indexOf(u8, settings_desc, "administration") != null);
}

test "UnitTypeHelpers determines required access for actions" {
    // Test read actions
    try testing.expectEqual(AccessMode.Read, UnitTypeHelpers.getRequiredAccessForAction(.Code, "read"));
    try testing.expectEqual(AccessMode.Read, UnitTypeHelpers.getRequiredAccessForAction(.Issues, "view"));
    
    // Test write actions
    try testing.expectEqual(AccessMode.Write, UnitTypeHelpers.getRequiredAccessForAction(.Code, "edit"));
    try testing.expectEqual(AccessMode.Write, UnitTypeHelpers.getRequiredAccessForAction(.Wiki, "update"));
    
    // Test admin actions
    try testing.expectEqual(AccessMode.Admin, UnitTypeHelpers.getRequiredAccessForAction(.Settings, "admin"));
    try testing.expectEqual(AccessMode.Admin, UnitTypeHelpers.getRequiredAccessForAction(.Code, "configure"));
    
    // Test issue-specific actions (can comment with read access)
    try testing.expectEqual(AccessMode.Read, UnitTypeHelpers.getRequiredAccessForAction(.Issues, "comment"));
    try testing.expectEqual(AccessMode.Read, UnitTypeHelpers.getRequiredAccessForAction(.PullRequests, "create"));
    
    // Unknown actions default to read
    try testing.expectEqual(AccessMode.Read, UnitTypeHelpers.getRequiredAccessForAction(.Code, "unknown"));
}