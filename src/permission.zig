const std = @import("std");
const testing = std.testing;

// Permission error types
pub const PermissionError = error{
    RepositoryNotFound,
    UserNotFound,
    DatabaseError,
    InvalidInput,
    RepositoryArchived, // Write denied to archived repos
    RepositoryMirror, // Write denied to mirrors
    OrganizationPrivate, // Access denied to private org
    UserRestricted, // Restricted user access denied
} || error{OutOfMemory};

// Access mode enumeration with permission levels
pub const AccessMode = enum(u8) {
    None = 0,
    Read = 1,
    Write = 2,
    Admin = 3,
    Owner = 4,

    pub fn atLeast(self: AccessMode, required: AccessMode) bool {
        return @intFromEnum(self) >= @intFromEnum(required);
    }
};

// Test for AccessMode
test "AccessMode.atLeast" {
    // None access tests
    try testing.expect(!AccessMode.None.atLeast(.Read));
    try testing.expect(!AccessMode.None.atLeast(.Write));
    try testing.expect(!AccessMode.None.atLeast(.Admin));
    try testing.expect(!AccessMode.None.atLeast(.Owner));
    try testing.expect(AccessMode.None.atLeast(.None));

    // Read access tests
    try testing.expect(AccessMode.Read.atLeast(.None));
    try testing.expect(AccessMode.Read.atLeast(.Read));
    try testing.expect(!AccessMode.Read.atLeast(.Write));
    try testing.expect(!AccessMode.Read.atLeast(.Admin));
    try testing.expect(!AccessMode.Read.atLeast(.Owner));

    // Write access tests
    try testing.expect(AccessMode.Write.atLeast(.None));
    try testing.expect(AccessMode.Write.atLeast(.Read));
    try testing.expect(AccessMode.Write.atLeast(.Write));
    try testing.expect(!AccessMode.Write.atLeast(.Admin));
    try testing.expect(!AccessMode.Write.atLeast(.Owner));

    // Admin access tests
    try testing.expect(AccessMode.Admin.atLeast(.None));
    try testing.expect(AccessMode.Admin.atLeast(.Read));
    try testing.expect(AccessMode.Admin.atLeast(.Write));
    try testing.expect(AccessMode.Admin.atLeast(.Admin));
    try testing.expect(!AccessMode.Admin.atLeast(.Owner));

    // Owner access tests
    try testing.expect(AccessMode.Owner.atLeast(.None));
    try testing.expect(AccessMode.Owner.atLeast(.Read));
    try testing.expect(AccessMode.Owner.atLeast(.Write));
    try testing.expect(AccessMode.Owner.atLeast(.Admin));
    try testing.expect(AccessMode.Owner.atLeast(.Owner));
}

test "AccessMode ordering" {
    try testing.expect(@intFromEnum(AccessMode.None) < @intFromEnum(AccessMode.Read));
    try testing.expect(@intFromEnum(AccessMode.Read) < @intFromEnum(AccessMode.Write));
    try testing.expect(@intFromEnum(AccessMode.Write) < @intFromEnum(AccessMode.Admin));
    try testing.expect(@intFromEnum(AccessMode.Admin) < @intFromEnum(AccessMode.Owner));
}

// Visibility types for users and organizations
pub const Visibility = enum {
    Public, // Visible to everyone
    Limited, // Visible to signed-in users (not restricted users)
    Private, // Visible only to members
};

test "Visibility enum values" {
    const public_vis = Visibility.Public;
    const limited_vis = Visibility.Limited;
    const private_vis = Visibility.Private;

    // Test that we can compare visibility types
    try testing.expect(public_vis == Visibility.Public);
    try testing.expect(limited_vis == Visibility.Limited);
    try testing.expect(private_vis == Visibility.Private);
    try testing.expect(public_vis != limited_vis);
    try testing.expect(limited_vis != private_vis);
    try testing.expect(public_vis != private_vis);
}

// Repository unit types for fine-grained permissions
pub const UnitType = enum {
    Code,
    Issues,
    PullRequests,
    Wiki,
    Projects,
    Actions,
    Packages,
    Settings,
};

test "UnitType enum values" {
    // Test all unit types are distinct
    const all_units = [_]UnitType{
        .Code,
        .Issues,
        .PullRequests,
        .Wiki,
        .Projects,
        .Actions,
        .Packages,
        .Settings,
    };

    // Verify all units are unique
    for (all_units, 0..) |unit1, i| {
        for (all_units[i + 1 ..]) |unit2| {
            try testing.expect(unit1 != unit2);
        }
    }

    // Test we can iterate over all values
    var count: usize = 0;
    inline for (std.meta.fields(UnitType)) |_| {
        count += 1;
    }
    try testing.expectEqual(@as(usize, 8), count);
}

// Permission struct with unit-level access control
pub const Permission = struct {
    access_mode: AccessMode,
    units: ?std.EnumMap(UnitType, AccessMode),
    everyone_access_mode: std.EnumMap(UnitType, AccessMode), // For signed-in users
    anonymous_access_mode: std.EnumMap(UnitType, AccessMode), // For anonymous users

    pub fn unitAccessMode(self: *const Permission, unit_type: UnitType) AccessMode {
        // Admin/Owner mode overrides unit-specific permissions
        if (self.access_mode.atLeast(.Admin)) {
            return self.access_mode;
        }

        // If units map is null (admin override), return general access
        if (self.units == null) {
            return self.access_mode;
        }

        // Get unit-specific permission or fall back to general access
        const unit_mode = self.units.?.get(unit_type) orelse self.access_mode;
        const everyone_mode = self.everyone_access_mode.get(unit_type) orelse .None;
        const anonymous_mode = self.anonymous_access_mode.get(unit_type) orelse .None;

        // Return the maximum of all applicable modes
        var max_mode = unit_mode;
        if (@intFromEnum(everyone_mode) > @intFromEnum(max_mode)) {
            max_mode = everyone_mode;
        }
        if (@intFromEnum(anonymous_mode) > @intFromEnum(max_mode)) {
            max_mode = anonymous_mode;
        }
        return max_mode;
    }

    pub fn canAccess(self: *const Permission, unit_type: UnitType, required_mode: AccessMode) bool {
        return self.unitAccessMode(unit_type).atLeast(required_mode);
    }

    pub fn canRead(self: *const Permission, unit_type: UnitType) bool {
        return self.canAccess(unit_type, .Read);
    }

    pub fn canWrite(self: *const Permission, unit_type: UnitType) bool {
        return self.canAccess(unit_type, .Write);
    }
};

test "Permission unit access with admin override" {
    // Admin should have full access regardless of unit settings
    var units = std.EnumMap(UnitType, AccessMode).initFull(.None);
    units.put(.Code, .Read);

    const perm = Permission{
        .access_mode = .Admin,
        .units = units,
        .everyone_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
        .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
    };

    // Admin should have admin access to all units
    try testing.expectEqual(AccessMode.Admin, perm.unitAccessMode(.Code));
    try testing.expectEqual(AccessMode.Admin, perm.unitAccessMode(.Issues));
    try testing.expect(perm.canWrite(.Code));
    try testing.expect(perm.canWrite(.Issues));
}

test "Permission unit access with null units (admin override)" {
    const perm = Permission{
        .access_mode = .Owner,
        .units = null,
        .everyone_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
        .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
    };

    // Owner with null units should have owner access to all
    try testing.expectEqual(AccessMode.Owner, perm.unitAccessMode(.Code));
    try testing.expectEqual(AccessMode.Owner, perm.unitAccessMode(.Issues));
}

test "Permission unit access normal user" {
    var units = std.EnumMap(UnitType, AccessMode).initFull(.None);
    units.put(.Code, .Read);
    units.put(.Issues, .Write);

    const perm = Permission{
        .access_mode = .Read,
        .units = units,
        .everyone_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
        .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
    };

    // Check specific unit permissions
    try testing.expectEqual(AccessMode.Read, perm.unitAccessMode(.Code));
    try testing.expectEqual(AccessMode.Write, perm.unitAccessMode(.Issues));
    try testing.expectEqual(AccessMode.None, perm.unitAccessMode(.Wiki));

    // Check access methods
    try testing.expect(perm.canRead(.Code));
    try testing.expect(!perm.canWrite(.Code));
    try testing.expect(perm.canWrite(.Issues));
    try testing.expect(!perm.canRead(.Wiki));
}

test "Permission with public access modes" {
    const units = std.EnumMap(UnitType, AccessMode).initFull(.None);
    var everyone_access = std.EnumMap(UnitType, AccessMode).initFull(.None);
    var anonymous_access = std.EnumMap(UnitType, AccessMode).initFull(.None);

    // User has no access, but everyone can read code
    everyone_access.put(.Code, .Read);
    // Anonymous users can read issues
    anonymous_access.put(.Issues, .Read);

    const perm = Permission{
        .access_mode = .None,
        .units = units,
        .everyone_access_mode = everyone_access,
        .anonymous_access_mode = anonymous_access,
    };

    // Should get access from everyone/anonymous modes
    try testing.expectEqual(AccessMode.Read, perm.unitAccessMode(.Code));
    try testing.expectEqual(AccessMode.Read, perm.unitAccessMode(.Issues));
    try testing.expectEqual(AccessMode.None, perm.unitAccessMode(.Wiki));
}

// Forward declarations
const DataAccessObject = @import("database/dao.zig");

// Declare loadUserRepoPermission as it will be implemented later
fn loadUserRepoPermission(
    allocator: std.mem.Allocator,
    dao: *DataAccessObject,
    user_id: ?i64,
    repo_id: i64,
) PermissionError!Permission {
    _ = allocator;
    _ = dao;
    _ = user_id;
    _ = repo_id;
    // This will be implemented later
    return Permission{
        .access_mode = .None,
        .units = std.EnumMap(UnitType, AccessMode).initFull(.None),
        .everyone_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
        .anonymous_access_mode = std.EnumMap(UnitType, AccessMode).initFull(.None),
    };
}

// Request-level permission cache
pub const PermissionCache = struct {
    const CacheKey = struct {
        user_id: ?i64,
        repo_id: i64,

        pub fn hash(self: CacheKey) u64 {
            var hasher = std.hash.Wyhash.init(0);
            std.hash.autoHash(&hasher, self.user_id);
            std.hash.autoHash(&hasher, self.repo_id);
            return hasher.final();
        }

        pub fn eql(self: CacheKey, other: CacheKey) bool {
            return self.user_id == other.user_id and self.repo_id == other.repo_id;
        }
    };

    cache: std.HashMap(CacheKey, Permission, std.hash_map.AutoContext(CacheKey), 80),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PermissionCache {
        return .{
            .cache = std.HashMap(CacheKey, Permission, std.hash_map.AutoContext(CacheKey), 80).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PermissionCache) void {
        self.cache.deinit();
    }

    pub fn getOrCompute(
        self: *PermissionCache,
        dao: *DataAccessObject,
        user_id: ?i64,
        repo_id: i64,
    ) !Permission {
        const key = CacheKey{ .user_id = user_id, .repo_id = repo_id };
        if (self.cache.get(key)) |cached| {
            return cached;
        }

        const permission = try loadUserRepoPermission(self.allocator, dao, user_id, repo_id);
        try self.cache.put(key, permission);
        return permission;
    }
};

test "PermissionCache basic operations" {
    const allocator = testing.allocator;
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();

    // Test that cache starts empty
    try testing.expectEqual(@as(usize, 0), cache.cache.count());

    // Test cache key hashing and equality
    const key1 = PermissionCache.CacheKey{ .user_id = 123, .repo_id = 456 };
    const key2 = PermissionCache.CacheKey{ .user_id = 123, .repo_id = 456 };
    const key3 = PermissionCache.CacheKey{ .user_id = 789, .repo_id = 456 };

    try testing.expect(key1.eql(key2));
    try testing.expect(!key1.eql(key3));
    try testing.expectEqual(key1.hash(), key2.hash());
}

test "PermissionCache with null user_id" {
    const allocator = testing.allocator;
    var cache = PermissionCache.init(allocator);
    defer cache.deinit();

    // Test cache keys with null user_id
    const key1 = PermissionCache.CacheKey{ .user_id = null, .repo_id = 123 };
    const key2 = PermissionCache.CacheKey{ .user_id = null, .repo_id = 123 };
    const key3 = PermissionCache.CacheKey{ .user_id = 456, .repo_id = 123 };

    try testing.expect(key1.eql(key2));
    try testing.expect(!key1.eql(key3));
}