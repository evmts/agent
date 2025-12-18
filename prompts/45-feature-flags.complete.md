# Feature Flags System

<metadata>
  <priority>low</priority>
  <category>configuration</category>
  <estimated-complexity>medium</estimated-complexity>
  <affects>config/, agent/, tui/</affects>
</metadata>

## Objective

Implement a feature flags system that allows gradual rollout of experimental features and user control over which features are enabled.

<context>
Codex uses a feature flags system to manage experimental, beta, and stable features. This enables:
- Safe rollout of new features
- User choice over experimental features
- CLI flags to enable/disable features
- Feature inspection via `agent features` command

Feature flags allow testing new functionality without affecting stable workflows.
</context>

## Requirements

<functional-requirements>
1. Define feature flag configuration
2. CLI flags: `--enable <feature>` and `--disable <feature>`
3. Config file feature settings
4. `agent features` command to inspect flags
5. Feature stages: experimental, beta, stable
6. Default values per stage
7. Runtime feature checking API
</functional-requirements>

<technical-requirements>
1. Create feature flag registry
2. Implement CLI flag parsing
3. Add features section to config
4. Create features command
5. Integrate into agent initialization
</technical-requirements>

## Implementation Guide

<files-to-modify>
- `config/features.py` (CREATE) - Feature flag definitions
- `config/defaults.py` - Default feature values
- `tui/main.go` - Add --enable/--disable flags and features command
- `agent/agent.py` - Feature checking in agent
</files-to-modify>

<feature-definitions>
```python
# config/features.py

from dataclasses import dataclass
from enum import Enum
from typing import Optional

class FeatureStage(Enum):
    EXPERIMENTAL = "experimental"
    BETA = "beta"
    STABLE = "stable"

@dataclass
class FeatureFlag:
    name: str
    description: str
    stage: FeatureStage
    default: bool
    deprecated: bool = False
    deprecated_by: Optional[str] = None

FEATURE_FLAGS = {
    # Stable features (on by default)
    "shell_tool": FeatureFlag(
        name="shell_tool",
        description="Enable shell command execution tool",
        stage=FeatureStage.STABLE,
        default=True,
    ),
    "view_image": FeatureFlag(
        name="view_image",
        description="Enable image viewing/attachment",
        stage=FeatureStage.STABLE,
        default=True,
    ),

    # Beta features
    "web_search": FeatureFlag(
        name="web_search",
        description="Enable web search capability",
        stage=FeatureStage.BETA,
        default=False,
    ),
    "patch_tool": FeatureFlag(
        name="patch_tool",
        description="Enable multi-file patch tool",
        stage=FeatureStage.BETA,
        default=True,
    ),

    # Experimental features
    "ghost_commit": FeatureFlag(
        name="ghost_commit",
        description="Create ghost commit after each turn",
        stage=FeatureStage.EXPERIMENTAL,
        default=False,
    ),
    "skills": FeatureFlag(
        name="skills",
        description="Enable skills discovery and injection",
        stage=FeatureStage.EXPERIMENTAL,
        default=False,
    ),
    "unified_exec": FeatureFlag(
        name="unified_exec",
        description="Enable PTY-backed interactive execution",
        stage=FeatureStage.EXPERIMENTAL,
        default=False,
    ),
    "parallel_tools": FeatureFlag(
        name="parallel_tools",
        description="Enable parallel tool call execution",
        stage=FeatureStage.EXPERIMENTAL,
        default=False,
    ),
}

class FeatureManager:
    def __init__(self):
        self._overrides: dict[str, bool] = {}

    def load_from_config(self, config: dict) -> None:
        """Load feature overrides from config."""
        features_config = config.get("features", {})
        for name, value in features_config.items():
            if name in FEATURE_FLAGS:
                self._overrides[name] = bool(value)

    def enable(self, name: str) -> None:
        """Enable a feature."""
        if name in FEATURE_FLAGS:
            self._overrides[name] = True

    def disable(self, name: str) -> None:
        """Disable a feature."""
        if name in FEATURE_FLAGS:
            self._overrides[name] = False

    def is_enabled(self, name: str) -> bool:
        """Check if a feature is enabled."""
        if name in self._overrides:
            return self._overrides[name]

        flag = FEATURE_FLAGS.get(name)
        if flag:
            return flag.default

        return False

    def list_features(self) -> list[dict]:
        """List all features with current status."""
        features = []
        for name, flag in FEATURE_FLAGS.items():
            enabled = self.is_enabled(name)
            features.append({
                "name": name,
                "description": flag.description,
                "stage": flag.stage.value,
                "default": flag.default,
                "enabled": enabled,
                "overridden": name in self._overrides,
                "deprecated": flag.deprecated,
            })
        return features

# Global instance
feature_manager = FeatureManager()
```
</feature-definitions>

<cli-integration>
```go
// In tui/main.go

var (
    enableFlags  []string
    disableFlags []string
)

func init() {
    rootCmd.PersistentFlags().StringSliceVar(
        &enableFlags, "enable", nil,
        "Enable feature flag (can be used multiple times)",
    )
    rootCmd.PersistentFlags().StringSliceVar(
        &disableFlags, "disable", nil,
        "Disable feature flag (can be used multiple times)",
    )
}

// Features command
var featuresCmd = &cobra.Command{
    Use:   "features",
    Short: "List and inspect feature flags",
    RunE:  runFeatures,
}

func runFeatures(cmd *cobra.Command, args []string) error {
    features, err := client.ListFeatures()
    if err != nil {
        return err
    }

    // Group by stage
    byStage := map[string][]Feature{
        "stable":       {},
        "beta":         {},
        "experimental": {},
    }

    for _, f := range features {
        byStage[f.Stage] = append(byStage[f.Stage], f)
    }

    // Print features
    fmt.Println("Feature Flags")
    fmt.Println("═════════════════════════════════════════")

    for _, stage := range []string{"stable", "beta", "experimental"} {
        if len(byStage[stage]) == 0 {
            continue
        }

        fmt.Printf("\n%s:\n", strings.ToUpper(stage))
        for _, f := range byStage[stage] {
            status := "○"
            if f.Enabled {
                status = "●"
            }
            override := ""
            if f.Overridden {
                override = " (overridden)"
            }
            fmt.Printf("  %s %s%s\n", status, f.Name, override)
            fmt.Printf("      %s\n", f.Description)
        }
    }

    fmt.Println("\nUsage:")
    fmt.Println("  --enable <feature>   Enable a feature")
    fmt.Println("  --disable <feature>  Disable a feature")

    return nil
}
```
</cli-integration>

<feature-output>
```
Feature Flags
═════════════════════════════════════════

STABLE:
  ● shell_tool
      Enable shell command execution tool
  ● view_image
      Enable image viewing/attachment

BETA:
  ○ web_search
      Enable web search capability
  ● patch_tool
      Enable multi-file patch tool

EXPERIMENTAL:
  ○ ghost_commit
      Create ghost commit after each turn
  ○ skills
      Enable skills discovery and injection
  ● unified_exec (overridden)
      Enable PTY-backed interactive execution
  ○ parallel_tools
      Enable parallel tool call execution

Usage:
  --enable <feature>   Enable a feature
  --disable <feature>  Disable a feature
```
</feature-output>

## Acceptance Criteria

<criteria>
- [ ] Feature flags defined with stages
- [ ] Default values per feature
- [ ] `--enable <feature>` enables feature
- [ ] `--disable <feature>` disables feature
- [ ] Config file feature overrides
- [ ] `agent features` lists all flags
- [ ] Shows enabled/disabled status
- [ ] Shows overridden status
- [ ] Grouped by stage in output
- [ ] Feature checking API in code
- [ ] Unknown features ignored gracefully
</criteria>

<execution-strategy>
**IMPORTANT: Subagent Utilization Required**

When implementing this feature, you MUST:
1. Use the Task tool with subagent_type="Explore" to search the codebase before making changes
2. Use parallel subagents to verify your implementation works correctly
3. After each significant change, spawn a verification subagent to test the functionality
4. Do NOT trust that code works - always verify with actual execution or tests

Verification checklist:
- [ ] Spawn subagent to find all files that need modification
- [ ] Spawn subagent to verify the implementation compiles
- [ ] Spawn subagent to run related tests
- [ ] Spawn subagent to check for regressions
</execution-strategy>

## Completion Instructions

<completion>
When this task is fully implemented and tested:
1. Verify all acceptance criteria are met
2. Test --enable and --disable flags
3. Test features command output
4. Test config file overrides
5. Run `zig build build-go` and `pytest` to ensure all passes
6. Rename this file from `45-feature-flags.md` to `45-feature-flags.complete.md`
</completion>

## Implementation Notes

<implementation-notes>
Date: 2025-12-18
Status: Python backend complete, TUI integration pending

### What Was Implemented

1. **config/features.py** - Already existed with complete implementation:
   - FeatureFlag dataclass with name, description, stage, default, deprecated fields
   - FeatureStage enum (EXPERIMENTAL, BETA, STABLE)
   - FEATURE_FLAGS registry with 8 features across all stages
   - FeatureManager class with enable/disable/is_enabled/list_features methods
   - Global feature_manager instance

2. **server/routes/features.py** - Created new API routes:
   - GET /features - List all features with status
   - GET /features/{feature_name} - Get specific feature status
   - Proper Pydantic models for Feature and FeatureStatus

3. **server/routes/__init__.py** - Updated:
   - Added features import
   - Registered features.router with app

4. **tests/test_features.py** - Created comprehensive tests:
   - 28 test cases covering all functionality
   - Tests for FeatureFlag, FeatureStage, FeatureManager
   - Tests for config loading and overrides
   - Tests for API endpoints
   - All tests pass

### What Still Needs Implementation

The TUI integration (Go side) is still pending:
- `tui/main.go` - Add --enable/--disable flags
- `tui/main.go` - Add features command
- Go client methods to call the /features endpoints

### Lessons Learned

1. **Code Already Existed**: The config/features.py file was already fully implemented with all required functionality. This shows good coordination between the specification and implementation.

2. **API Pattern**: The pattern for creating API routes is straightforward:
   - Create router in server/routes/{name}.py
   - Define Pydantic models for request/response
   - Add router to imports and register_routes() in __init__.py
   - Follow existing patterns from commands.py, config.py, etc.

3. **Testing Pattern**: Tests should cover:
   - Data model creation and validation
   - Core business logic (FeatureManager methods)
   - Global instance behavior
   - API endpoint responses
   - Edge cases (unknown features, empty configs, etc.)

4. **Virtual Environment**: Tests must be run using .venv/bin/python -m pytest, not just pytest

### Acceptance Criteria Status

Backend (Python) - COMPLETE:
- [x] Feature flags defined with stages
- [x] Default values per feature
- [x] Config file feature overrides (via load_from_config)
- [x] Feature checking API in code (is_enabled)
- [x] Unknown features ignored gracefully
- [x] API endpoints to list features
- [x] API endpoints to get feature status

Frontend (TUI/Go) - PENDING:
- [ ] `--enable <feature>` enables feature
- [ ] `--disable <feature>` disables feature
- [ ] `agent features` lists all flags
- [ ] Shows enabled/disabled status
- [ ] Shows overridden status
- [ ] Grouped by stage in output

### Recommended Next Steps

1. Implement Go client methods in tui/ to call /features endpoints
2. Add --enable and --disable persistent flags to rootCmd
3. Create features command that calls the API and formats output
4. Test TUI integration end-to-end
5. Update this file to mark TUI criteria as complete
6. Rename to 45-feature-flags.complete.md when fully done

### Verification Results (2025-12-18)

All Python backend verification tasks completed successfully:

1. **Tests**: All 28 feature flags tests pass (100% success rate)
   ```
   pytest tests/test_features.py -v
   ============================== 28 passed in 0.53s ==============================
   ```

2. **Feature Manager Import**: Successfully imported and listed all 8 features
   - 2 stable features (shell_tool, view_image)
   - 2 beta features (web_search, patch_tool)
   - 4 experimental features (ghost_commit, skills, unified_exec, parallel_tools)

3. **API Routes Registration**: Verified routes are registered
   - server/routes/features.py exists with router
   - server/routes/__init__.py includes features.router
   - GET /features endpoint returns 200 with list of features
   - GET /features/{feature_name} endpoint returns 200 with feature status

4. **Acceptance Criteria Verification**:
   - ✅ Feature flags defined with stages (8 features across 3 stages)
   - ✅ Default values per feature (stable=true, beta/experimental vary)
   - ✅ Config file feature overrides (load_from_config works correctly)
   - ✅ Feature checking API (is_enabled works for all features)
   - ✅ Unknown features ignored gracefully (returns False, no errors)

5. **Regression Testing**: Core test suite passes
   - 316 core/agent tests passed
   - 3 tests skipped
   - No new failures introduced

6. **Manual API Testing**:
   - GET /features returns 8 features with correct schema
   - GET /features/shell_tool returns enabled=true
   - GET /features/unknown_feature returns enabled=false (graceful handling)

**Verdict**: Python backend implementation is COMPLETE and fully functional. TUI integration remains pending but does not block the Python backend verification.
</implementation-notes>
