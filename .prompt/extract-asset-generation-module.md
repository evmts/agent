# Extract Asset Generation Module

## Priority: Medium

## Problem
The `GenerateAssetsStep` implementation in `build.zig` is quite large (lines 6-141, ~135 lines) for a build script. This makes the build script harder to read and maintain, and the asset generation logic could be reused elsewhere.

## Current State
- Asset generation logic is embedded directly in `build.zig`
- The `GenerateAssetsStep` struct and its methods take up significant space
- MIME type detection is also embedded in the build script

## Expected Solution

1. **Create a new module** `src/build_utils/asset_generator.zig`:
   ```zig
   const std = @import("std");

   pub const AssetGenerator = struct {
       allocator: std.mem.Allocator,
       dist_path: []const u8,
       out_path: []const u8,

       pub fn init(allocator: std.mem.Allocator, dist_path: []const u8, out_path: []const u8) AssetGenerator {
           // Move constructor logic here
       }

       pub fn generate(self: *AssetGenerator) !void {
           // Move generation logic here
       }

       fn getMimeType(filename: []const u8) []const u8 {
           // Move MIME type detection here
       }
   };
   ```

2. **Create build step wrapper** that uses the extracted module:
   ```zig
   const GenerateAssetsStep = struct {
       step: std.Build.Step,
       generator: AssetGenerator,

       fn init(b: *std.Build, dist_path: []const u8, out_path: []const u8) *GenerateAssetsStep {
           // Simplified constructor
       }

       fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
           // Simple delegation to generator.generate()
       }
   };
   ```

3. **Update build.zig** to use the extracted module

## Files to Create/Modify
- **Create**: `src/build_utils/asset_generator.zig` (new module)
- **Modify**: `build.zig` (simplify by using the extracted module)

## Benefits
- Cleaner, more readable `build.zig`
- Reusable asset generation logic
- Better separation of concerns
- Easier to test asset generation logic independently

## Testing
- Move existing MIME type tests to the new module
- Add tests for the asset generation logic
- Ensure build process still works correctly
- Verify generated assets are identical to current output

## Migration Strategy
1. Create the new module with existing logic
2. Update build.zig to use the new module
3. Test that asset generation works identically
4. Add additional tests for the extracted module