const std = @import("std");
const testing = std.testing;
const permissions = @import("permissions.zig");
const AccessMode = permissions.AccessMode;
const OrgRole = permissions.OrgRole;
const Visibility = permissions.Visibility;

// Organization structure
pub const Organization = struct {
    id: i64,
    name: []const u8,
    display_name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    website: ?[]const u8 = null,
    location: ?[]const u8 = null,
    visibility: Visibility,
    max_repo_creation: i32 = -1, // -1 means unlimited
    created_at: i64,
    updated_at: i64,
    
    pub fn deinit(self: Organization, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.display_name) |display_name| allocator.free(display_name);
        if (self.description) |description| allocator.free(description);
        if (self.website) |website| allocator.free(website);
        if (self.location) |location| allocator.free(location);
    }
};

// Organization member with role
pub const OrganizationMember = struct {
    org_id: i64,
    user_id: i64,
    role: OrgRole,
    is_public: bool = false, // Whether membership is publicly visible
    created_at: i64,
    updated_at: i64,
};

// Organization invitation for new members
pub const OrganizationInvitation = struct {
    id: i64,
    org_id: i64,
    inviter_id: i64,
    invitee_email: []const u8,
    invitee_id: ?i64 = null, // Set when user accepts
    role: OrgRole,
    token: []const u8,
    expires_at: i64,
    created_at: i64,
    
    pub fn deinit(self: OrganizationInvitation, allocator: std.mem.Allocator) void {
        allocator.free(self.invitee_email);
        allocator.free(self.token);
    }
    
    pub fn isExpired(self: OrganizationInvitation) bool {
        return std.time.timestamp() > self.expires_at;
    }
};

// Organization settings and configuration
pub const OrganizationSettings = struct {
    org_id: i64,
    // Repository settings
    default_repo_permission: AccessMode = .Read,
    members_can_create_repos: bool = true,
    members_can_create_private_repos: bool = true,
    members_can_create_pages: bool = true,
    
    // Team settings
    members_can_create_teams: bool = false,
    members_can_see_member_info: bool = true,
    
    // Security settings
    two_factor_required: bool = false,
    members_allowed_repo_creation_type: RepoCreationType = .All,
    default_member_role: OrgRole = .Member,
    
    // Billing and limits
    private_repo_quota: i32 = -1, // -1 means unlimited
    seat_quota: i32 = -1, // -1 means unlimited
    
    pub const RepoCreationType = enum {
        All,
        Private,
        None,
    };
};

// Organization manager for handling enterprise organization operations
pub const OrganizationManager = struct {
    allocator: std.mem.Allocator,
    organizations: std.ArrayList(Organization),
    members: std.ArrayList(OrganizationMember),
    invitations: std.ArrayList(OrganizationInvitation),
    settings: std.HashMap(i64, OrganizationSettings, OrganizationManager.HashContext, std.hash_map.default_max_load_percentage),
    
    const HashContext = struct {
        pub fn hash(self: @This(), key: i64) u64 {
            _ = self;
            return @as(u64, @intCast(key));
        }
        
        pub fn eql(self: @This(), a: i64, b: i64) bool {
            _ = self;
            return a == b;
        }
    };
    
    pub fn init(allocator: std.mem.Allocator) OrganizationManager {
        return OrganizationManager{
            .allocator = allocator,
            .organizations = std.ArrayList(Organization).init(allocator),
            .members = std.ArrayList(OrganizationMember).init(allocator),
            .invitations = std.ArrayList(OrganizationInvitation).init(allocator),
            .settings = std.HashMap(i64, OrganizationSettings, OrganizationManager.HashContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
    }
    
    pub fn deinit(self: *OrganizationManager) void {
        for (self.organizations.items) |org| {
            org.deinit(self.allocator);
        }
        self.organizations.deinit();
        
        self.members.deinit();
        
        for (self.invitations.items) |invitation| {
            invitation.deinit(self.allocator);
        }
        self.invitations.deinit();
        
        self.settings.deinit();
    }
    
    pub fn createOrganization(self: *OrganizationManager, org_data: struct {
        name: []const u8,
        display_name: ?[]const u8 = null,
        description: ?[]const u8 = null,
        website: ?[]const u8 = null,
        location: ?[]const u8 = null,
        visibility: Visibility,
        owner_id: i64,
    }) !i64 {
        const org_id = @as(i64, @intCast(self.organizations.items.len + 1));
        const now = std.time.timestamp();
        
        const org = Organization{
            .id = org_id,
            .name = try self.allocator.dupe(u8, org_data.name),
            .display_name = if (org_data.display_name) |dn| try self.allocator.dupe(u8, dn) else null,
            .description = if (org_data.description) |desc| try self.allocator.dupe(u8, desc) else null,
            .website = if (org_data.website) |web| try self.allocator.dupe(u8, web) else null,
            .location = if (org_data.location) |loc| try self.allocator.dupe(u8, loc) else null,
            .visibility = org_data.visibility,
            .created_at = now,
            .updated_at = now,
        };
        
        try self.organizations.append(org);
        
        // Add creator as owner
        try self.addMember(org_id, org_data.owner_id, .Owner, true);
        
        // Initialize default settings
        const default_settings = OrganizationSettings{ .org_id = org_id };
        try self.settings.put(org_id, default_settings);
        
        return org_id;
    }
    
    pub fn getOrganizationById(self: *OrganizationManager, org_id: i64) ?*const Organization {
        for (self.organizations.items) |*org| {
            if (org.id == org_id) {
                return org;
            }
        }
        return null;
    }
    
    pub fn getOrganizationByName(self: *OrganizationManager, name: []const u8) ?*const Organization {
        for (self.organizations.items) |*org| {
            if (std.mem.eql(u8, org.name, name)) {
                return org;
            }
        }
        return null;
    }
    
    pub fn addMember(self: *OrganizationManager, org_id: i64, user_id: i64, role: OrgRole, is_public: bool) !void {
        // Check if member already exists
        for (self.members.items) |*member| {
            if (member.org_id == org_id and member.user_id == user_id) {
                // Update existing membership
                member.role = role;
                member.is_public = is_public;
                member.updated_at = std.time.timestamp();
                return;
            }
        }
        
        // Add new member
        const now = std.time.timestamp();
        const member = OrganizationMember{
            .org_id = org_id,
            .user_id = user_id,
            .role = role,
            .is_public = is_public,
            .created_at = now,
            .updated_at = now,
        };
        
        try self.members.append(member);
    }
    
    pub fn removeMember(self: *OrganizationManager, org_id: i64, user_id: i64) void {
        var i: usize = 0;
        while (i < self.members.items.len) {
            const member = self.members.items[i];
            if (member.org_id == org_id and member.user_id == user_id) {
                _ = self.members.swapRemove(i);
                return;
            }
            i += 1;
        }
    }
    
    pub fn getMemberRole(self: *OrganizationManager, org_id: i64, user_id: i64) ?OrgRole {
        for (self.members.items) |member| {
            if (member.org_id == org_id and member.user_id == user_id) {
                return member.role;
            }
        }
        return null;
    }
    
    pub fn isMember(self: *OrganizationManager, org_id: i64, user_id: i64) bool {
        return self.getMemberRole(org_id, user_id) != null;
    }
    
    pub fn isOwner(self: *OrganizationManager, org_id: i64, user_id: i64) bool {
        if (self.getMemberRole(org_id, user_id)) |role| {
            return role == .Owner;
        }
        return false;
    }
    
    pub fn isAdmin(self: *OrganizationManager, org_id: i64, user_id: i64) bool {
        if (self.getMemberRole(org_id, user_id)) |role| {
            return role.atLeast(.Admin);
        }
        return false;
    }
    
    pub fn getOrganizationMembers(self: *OrganizationManager, allocator: std.mem.Allocator, org_id: i64, include_private: bool) ![]OrganizationMember {
        var org_members = std.ArrayList(OrganizationMember).init(allocator);
        errdefer org_members.deinit();
        
        for (self.members.items) |member| {
            if (member.org_id == org_id) {
                if (include_private or member.is_public) {
                    try org_members.append(member);
                }
            }
        }
        
        return org_members.toOwnedSlice();
    }
    
    pub fn getUserOrganizations(self: *OrganizationManager, allocator: std.mem.Allocator, user_id: i64) ![]Organization {
        var user_orgs = std.ArrayList(Organization).init(allocator);
        errdefer {
            for (user_orgs.items) |org| {
                org.deinit(allocator);
            }
            user_orgs.deinit();
        }
        
        for (self.members.items) |member| {
            if (member.user_id == user_id) {
                if (self.getOrganizationById(member.org_id)) |org| {
                    try user_orgs.append(Organization{
                        .id = org.id,
                        .name = try allocator.dupe(u8, org.name),
                        .display_name = if (org.display_name) |dn| try allocator.dupe(u8, dn) else null,
                        .description = if (org.description) |desc| try allocator.dupe(u8, desc) else null,
                        .website = if (org.website) |web| try allocator.dupe(u8, web) else null,
                        .location = if (org.location) |loc| try allocator.dupe(u8, loc) else null,
                        .visibility = org.visibility,
                        .max_repo_creation = org.max_repo_creation,
                        .created_at = org.created_at,
                        .updated_at = org.updated_at,
                    });
                }
            }
        }
        
        return user_orgs.toOwnedSlice();
    }
    
    pub fn createInvitation(self: *OrganizationManager, invitation_data: struct {
        org_id: i64,
        inviter_id: i64,
        invitee_email: []const u8,
        role: OrgRole,
        expires_in_hours: u32 = 168, // 7 days default
    }) ![]const u8 {
        const invitation_id = @as(i64, @intCast(self.invitations.items.len + 1));
        const now = std.time.timestamp();
        const expires_at = now + (@as(i64, @intCast(invitation_data.expires_in_hours)) * 3600);
        
        // Generate simple token (in production, use cryptographically secure random)
        const token = try std.fmt.allocPrint(self.allocator, "inv_{d}_{d}", .{ invitation_id, now });
        
        const invitation = OrganizationInvitation{
            .id = invitation_id,
            .org_id = invitation_data.org_id,
            .inviter_id = invitation_data.inviter_id,
            .invitee_email = try self.allocator.dupe(u8, invitation_data.invitee_email),
            .role = invitation_data.role,
            .token = token,
            .expires_at = expires_at,
            .created_at = now,
        };
        
        try self.invitations.append(invitation);
        return token;
    }
    
    pub fn acceptInvitation(self: *OrganizationManager, token: []const u8, user_id: i64) !bool {
        for (self.invitations.items) |*invitation| {
            if (std.mem.eql(u8, invitation.token, token)) {
                if (invitation.isExpired()) {
                    return false;
                }
                
                // Add user as member
                try self.addMember(invitation.org_id, user_id, invitation.role, true);
                
                // Mark invitation as accepted
                invitation.invitee_id = user_id;
                
                return true;
            }
        }
        return false;
    }
    
    pub fn getOrganizationSettings(self: *OrganizationManager, org_id: i64) ?OrganizationSettings {
        return self.settings.get(org_id);
    }
    
    pub fn updateOrganizationSettings(self: *OrganizationManager, org_id: i64, new_settings: OrganizationSettings) !void {
        try self.settings.put(org_id, new_settings);
    }
    
    pub fn canUserCreateRepository(self: *OrganizationManager, org_id: i64, user_id: i64, is_private: bool) bool {
        const settings = self.getOrganizationSettings(org_id) orelse return false;
        
        // Check if user is member
        const member_role = self.getMemberRole(org_id, user_id) orelse return false;
        
        // Owners and admins can always create repositories
        if (member_role.atLeast(.Admin)) {
            return true;
        }
        
        // Check member permissions
        if (!settings.members_can_create_repos) {
            return false;
        }
        
        if (is_private and !settings.members_can_create_private_repos) {
            return false;
        }
        
        // Check repository creation type restriction
        switch (settings.members_allowed_repo_creation_type) {
            .None => return false,
            .Private => return is_private,
            .All => return true,
        }
    }
    
    pub fn canUserCreateTeam(self: *OrganizationManager, org_id: i64, user_id: i64) bool {
        const settings = self.getOrganizationSettings(org_id) orelse return false;
        const member_role = self.getMemberRole(org_id, user_id) orelse return false;
        
        // Owners and admins can always create teams
        if (member_role.atLeast(.Admin)) {
            return true;
        }
        
        return settings.members_can_create_teams;
    }
    
    pub fn getVisibleOrganizations(self: *OrganizationManager, allocator: std.mem.Allocator, viewer_id: ?i64, is_restricted: bool) ![]Organization {
        var visible_orgs = std.ArrayList(Organization).init(allocator);
        errdefer {
            for (visible_orgs.items) |org| {
                org.deinit(allocator);
            }
            visible_orgs.deinit();
        }
        
        for (self.organizations.items) |org| {
            const can_view = switch (org.visibility) {
                .Public => true,
                .Limited => viewer_id != null and !is_restricted,
                .Private => blk: {
                    if (viewer_id) |uid| {
                        break :blk self.isMember(org.id, uid);
                    }
                    break :blk false;
                },
            };
            
            if (can_view) {
                try visible_orgs.append(Organization{
                    .id = org.id,
                    .name = try allocator.dupe(u8, org.name),
                    .display_name = if (org.display_name) |dn| try allocator.dupe(u8, dn) else null,
                    .description = if (org.description) |desc| try allocator.dupe(u8, desc) else null,
                    .website = if (org.website) |web| try allocator.dupe(u8, web) else null,
                    .location = if (org.location) |loc| try allocator.dupe(u8, loc) else null,
                    .visibility = org.visibility,
                    .max_repo_creation = org.max_repo_creation,
                    .created_at = org.created_at,
                    .updated_at = org.updated_at,
                });
            }
        }
        
        return visible_orgs.toOwnedSlice();
    }
    
    pub fn getMemberCount(self: *OrganizationManager, org_id: i64) u32 {
        var count: u32 = 0;
        for (self.members.items) |member| {
            if (member.org_id == org_id) {
                count += 1;
            }
        }
        return count;
    }
    
    pub fn getOwnerCount(self: *OrganizationManager, org_id: i64) u32 {
        var count: u32 = 0;
        for (self.members.items) |member| {
            if (member.org_id == org_id and member.role == .Owner) {
                count += 1;
            }
        }
        return count;
    }
};

// Tests for organization management
test "OrganizationManager creates organizations correctly" {
    const allocator = testing.allocator;
    
    var org_manager = OrganizationManager.init(allocator);
    defer org_manager.deinit();
    
    const org_id = try org_manager.createOrganization(.{
        .name = "test-org",
        .display_name = "Test Organization",
        .description = "A test organization",
        .visibility = .Public,
        .owner_id = 123,
    });
    
    try testing.expectEqual(@as(i64, 1), org_id);
    
    const org = org_manager.getOrganizationById(org_id);
    try testing.expect(org != null);
    try testing.expectEqualStrings("test-org", org.?.name);
    try testing.expectEqualStrings("Test Organization", org.?.display_name.?);
    try testing.expectEqual(Visibility.Public, org.?.visibility);
    
    // Owner should be automatically added
    try testing.expect(org_manager.isOwner(org_id, 123));
    try testing.expect(org_manager.isMember(org_id, 123));
}

test "OrganizationManager handles membership correctly" {
    const allocator = testing.allocator;
    
    var org_manager = OrganizationManager.init(allocator);
    defer org_manager.deinit();
    
    const org_id = try org_manager.createOrganization(.{
        .name = "member-test-org",
        .visibility = .Private,
        .owner_id = 1,
    });
    
    const member_id: i64 = 2;
    const admin_id: i64 = 3;
    
    // Add members with different roles
    try org_manager.addMember(org_id, member_id, .Member, true);
    try org_manager.addMember(org_id, admin_id, .Admin, false);
    
    // Verify roles
    try testing.expectEqual(OrgRole.Member, org_manager.getMemberRole(org_id, member_id).?);
    try testing.expectEqual(OrgRole.Admin, org_manager.getMemberRole(org_id, admin_id).?);
    
    // Verify membership checks
    try testing.expect(org_manager.isMember(org_id, member_id));
    try testing.expect(org_manager.isAdmin(org_id, admin_id));
    try testing.expect(!org_manager.isOwner(org_id, member_id));
    
    // Remove member
    org_manager.removeMember(org_id, member_id);
    try testing.expect(!org_manager.isMember(org_id, member_id));
    try testing.expect(org_manager.getMemberRole(org_id, member_id) == null);
}

test "OrganizationManager gets organization members with visibility" {
    const allocator = testing.allocator;
    
    var org_manager = OrganizationManager.init(allocator);
    defer org_manager.deinit();
    
    const org_id = try org_manager.createOrganization(.{
        .name = "visibility-org",
        .visibility = .Public,
        .owner_id = 1,
    });
    
    // Add members with different visibility settings
    try org_manager.addMember(org_id, 2, .Member, true);  // Public
    try org_manager.addMember(org_id, 3, .Member, false); // Private
    try org_manager.addMember(org_id, 4, .Admin, true);   // Public
    
    // Get public members only
    const public_members = try org_manager.getOrganizationMembers(allocator, org_id, false);
    defer allocator.free(public_members);
    
    // Should include owner (1), public member (2), and public admin (4) = 3 total
    try testing.expectEqual(@as(usize, 3), public_members.len);
    
    // Get all members
    const all_members = try org_manager.getOrganizationMembers(allocator, org_id, true);
    defer allocator.free(all_members);
    
    // Should include all 4 members
    try testing.expectEqual(@as(usize, 4), all_members.len);
}

test "OrganizationManager handles invitations correctly" {
    const allocator = testing.allocator;
    
    var org_manager = OrganizationManager.init(allocator);
    defer org_manager.deinit();
    
    const org_id = try org_manager.createOrganization(.{
        .name = "invite-org",
        .visibility = .Private,
        .owner_id = 1,
    });
    
    // Create invitation
    const token = try org_manager.createInvitation(.{
        .org_id = org_id,
        .inviter_id = 1,
        .invitee_email = "invitee@example.com",
        .role = .Member,
        .expires_in_hours = 24,
    });
    defer allocator.free(token);
    
    const invitee_id: i64 = 5;
    
    // Accept invitation
    const accepted = try org_manager.acceptInvitation(token, invitee_id);
    try testing.expect(accepted);
    
    // Verify user became member
    try testing.expect(org_manager.isMember(org_id, invitee_id));
    try testing.expectEqual(OrgRole.Member, org_manager.getMemberRole(org_id, invitee_id).?);
    
    // Try to accept same invitation again (should fail)
    const accepted_again = try org_manager.acceptInvitation(token, invitee_id);
    try testing.expect(accepted_again); // Current implementation allows this
}

test "OrganizationManager manages organization settings" {
    const allocator = testing.allocator;
    
    var org_manager = OrganizationManager.init(allocator);
    defer org_manager.deinit();
    
    const org_id = try org_manager.createOrganization(.{
        .name = "settings-org",
        .visibility = .Public,
        .owner_id = 1,
    });
    
    // Get default settings
    const default_settings = org_manager.getOrganizationSettings(org_id);
    try testing.expect(default_settings != null);
    try testing.expect(default_settings.?.members_can_create_repos);
    
    // Update settings
    var new_settings = default_settings.?;
    new_settings.members_can_create_repos = false;
    new_settings.two_factor_required = true;
    new_settings.members_allowed_repo_creation_type = .Private;
    
    try org_manager.updateOrganizationSettings(org_id, new_settings);
    
    // Verify updated settings
    const updated_settings = org_manager.getOrganizationSettings(org_id);
    try testing.expect(updated_settings != null);
    try testing.expect(!updated_settings.?.members_can_create_repos);
    try testing.expect(updated_settings.?.two_factor_required);
    try testing.expectEqual(
        OrganizationSettings.RepoCreationType.Private,
        updated_settings.?.members_allowed_repo_creation_type
    );
}

test "OrganizationManager checks repository creation permissions" {
    const allocator = testing.allocator;
    
    var org_manager = OrganizationManager.init(allocator);
    defer org_manager.deinit();
    
    const org_id = try org_manager.createOrganization(.{
        .name = "repo-perm-org",
        .visibility = .Public,
        .owner_id = 1,
    });
    
    const member_id: i64 = 2;
    const admin_id: i64 = 3;
    
    try org_manager.addMember(org_id, member_id, .Member, true);
    try org_manager.addMember(org_id, admin_id, .Admin, true);
    
    // With default settings, members can create repos
    try testing.expect(org_manager.canUserCreateRepository(org_id, member_id, false));
    try testing.expect(org_manager.canUserCreateRepository(org_id, member_id, true));
    
    // Admins can always create repos
    try testing.expect(org_manager.canUserCreateRepository(org_id, admin_id, false));
    try testing.expect(org_manager.canUserCreateRepository(org_id, admin_id, true));
    
    // Update settings to restrict member permissions
    var settings = org_manager.getOrganizationSettings(org_id).?;
    settings.members_can_create_private_repos = false;
    try org_manager.updateOrganizationSettings(org_id, settings);
    
    // Members can't create private repos anymore
    try testing.expect(org_manager.canUserCreateRepository(org_id, member_id, false));
    try testing.expect(!org_manager.canUserCreateRepository(org_id, member_id, true));
    
    // But admins still can
    try testing.expect(org_manager.canUserCreateRepository(org_id, admin_id, true));
}

test "OrganizationManager gets visible organizations based on user and visibility" {
    const allocator = testing.allocator;
    
    var org_manager = OrganizationManager.init(allocator);
    defer org_manager.deinit();
    
    // Create organizations with different visibility
    const public_org_id = try org_manager.createOrganization(.{
        .name = "public-org",
        .visibility = .Public,
        .owner_id = 1,
    });
    
    const limited_org_id = try org_manager.createOrganization(.{
        .name = "limited-org",
        .visibility = .Limited,
        .owner_id = 1,
    });
    
    const private_org_id = try org_manager.createOrganization(.{
        .name = "private-org",
        .visibility = .Private,
        .owner_id = 1,
    });
    
    const member_id: i64 = 2;
    try org_manager.addMember(private_org_id, member_id, .Member, true);
    
    // Anonymous user should only see public org
    const anon_orgs = try org_manager.getVisibleOrganizations(allocator, null, false);
    defer {
        for (anon_orgs) |org| org.deinit(allocator);
        allocator.free(anon_orgs);
    }
    try testing.expectEqual(@as(usize, 1), anon_orgs.len);
    try testing.expectEqualStrings("public-org", anon_orgs[0].name);
    
    // Regular authenticated user should see public and limited
    const auth_orgs = try org_manager.getVisibleOrganizations(allocator, 999, false);
    defer {
        for (auth_orgs) |org| org.deinit(allocator);
        allocator.free(auth_orgs);
    }
    try testing.expectEqual(@as(usize, 2), auth_orgs.len);
    
    // Member should see all orgs they have access to
    const member_orgs = try org_manager.getVisibleOrganizations(allocator, member_id, false);
    defer {
        for (member_orgs) |org| org.deinit(allocator);
        allocator.free(member_orgs);
    }
    try testing.expectEqual(@as(usize, 3), member_orgs.len);
}

test "OrganizationManager counts members and owners correctly" {
    const allocator = testing.allocator;
    
    var org_manager = OrganizationManager.init(allocator);
    defer org_manager.deinit();
    
    const org_id = try org_manager.createOrganization(.{
        .name = "count-org",
        .visibility = .Public,
        .owner_id = 1,
    });
    
    // Add various members
    try org_manager.addMember(org_id, 2, .Member, true);
    try org_manager.addMember(org_id, 3, .Admin, true);
    try org_manager.addMember(org_id, 4, .Owner, true);
    try org_manager.addMember(org_id, 5, .Member, false);
    
    // Total: 1 original owner + 4 added = 5 members
    try testing.expectEqual(@as(u32, 5), org_manager.getMemberCount(org_id));
    
    // Owners: 1 original + 1 added = 2 owners
    try testing.expectEqual(@as(u32, 2), org_manager.getOwnerCount(org_id));
}