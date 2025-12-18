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
