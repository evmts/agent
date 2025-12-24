# Fix Path Traversal Vulnerability in Runner Tools

## Priority: CRITICAL | Security

## Problem

File operation tools use `os.path.normpath()` instead of `os.path.realpath()`, allowing symlink-based path traversal attacks.

**Affected files:**
- `runner/src/tools/read_file.py:42-44`
- `runner/src/tools/write_file.py:45-47`
- `runner/src/tools/list_files.py` (check if affected)
- `runner/src/tools/grep.py` (check if affected)

**Attack vector:**
1. Agent creates symlink: `ln -s /etc/passwd /workspace/link`
2. Agent reads: `read_file(path="link")` → reads `/etc/passwd`

## Task

1. **Audit all file operation tools:**
   - Read each file in `runner/src/tools/`
   - Identify all path validation logic
   - Document current validation approach

2. **Fix read_file.py:**
   ```python
   # Before (vulnerable)
   full_path = os.path.normpath(os.path.join("/workspace", path))
   if not full_path.startswith("/workspace"):
       return "Error: path traversal not allowed"

   # After (secure)
   full_path = os.path.realpath(os.path.join("/workspace", path))
   if not full_path.startswith("/workspace/"):  # Note trailing slash!
       return "Error: path traversal not allowed"
   ```

3. **Fix write_file.py:**
   - Same pattern as read_file.py
   - Ensure parent directory validation for new files
   - Block writes to symlinks pointing outside workspace

4. **Fix list_files.py:**
   - Validate directory path with realpath
   - Don't follow symlinks when listing (use `os.scandir` with `follow_symlinks=False`)

5. **Fix grep.py:**
   - Validate search path with realpath
   - Use `--no-follow` or equivalent to avoid symlink following

6. **Create shared validation utility:**
   ```python
   # runner/src/tools/path_utils.py
   def validate_workspace_path(path: str, workspace: str = "/workspace") -> tuple[bool, str]:
       """Returns (is_valid, resolved_path or error_message)"""
       ...
   ```

7. **Write comprehensive tests:**
   - Test `../` traversal: `read_file(path="../etc/passwd")`
   - Test symlink escape: create symlink, read through it
   - Test double encoding: `%2e%2e%2f` patterns
   - Test null byte injection: `file.txt\x00.png`
   - Test absolute paths: `read_file(path="/etc/passwd")`

8. **Add integration tests in E2E:**
   - Create workflow that attempts path traversal
   - Verify it fails with clear error message

## Acceptance Criteria

- [ ] All tools use `os.path.realpath()` for path validation
- [ ] Symlink attacks are blocked
- [ ] Clear error messages for rejected paths
- [ ] Unit tests cover all attack vectors
- [ ] E2E test verifies sandboxing works
