# Fix Build Script Error Handling

## Priority: High

## Problem
The `GenerateAssetsStep.init()` function in `build.zig` uses `@panic("OOM")` for memory allocation failures, which is not appropriate for build scripts that should handle errors gracefully.

## Current Code (Line 12)
```zig
const self = b.allocator.create(GenerateAssetsStep) catch @panic("OOM");
```

## Expected Solution
Replace the panic with proper error handling:

```zig
const self = try b.allocator.create(GenerateAssetsStep);
```

## Rationale
- Build scripts should fail gracefully with meaningful error messages
- Using `try` allows the build system to handle the error appropriately
- Panics in build scripts provide poor user experience
- This follows Zig's philosophy of explicit error handling

## Files to Modify
- `build.zig` (line 12 in the `GenerateAssetsStep.init` function)

## Testing
- Run `zig build` to ensure the build still works correctly
- Test with low memory conditions to verify proper error propagation
- Ensure asset generation still functions as expected

## Additional Notes
This change makes the build script more robust and provides better error reporting when memory allocation fails during the build process.