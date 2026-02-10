import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { render } from "./lib/render";

const ROOT = resolve(new URL("../..", import.meta.url).pathname);
const PROMPTS = resolve(new URL("./prompts", import.meta.url).pathname);

function readDoc(relativePath: string): string {
  try {
    return readFileSync(resolve(ROOT, relativePath), "utf8");
  } catch {
    return `[Could not read ${relativePath}]`;
  }
}

function readPrompt(filename: string): string {
  try {
    return readFileSync(resolve(PROMPTS, filename), "utf8");
  } catch {
    return `[Could not read prompt: ${filename}]`;
  }
}

// Project-level docs (still read from root)
const claudeMd = readDoc("CLAUDE.md");
const folderStructure = readPrompt("folder-structure.md");

// Governance docs (from docs/)
const specPrecedence = readDoc("docs/spec-precedence.md");
const specIndex = readDoc("docs/spec-index.md");
const mvpScope = readDoc("docs/mvp-scope.md");

// Modular prompt pieces (existing)
const alwaysGreen = readPrompt("always-green.md");
const zigRules = readPrompt("zig-rules.md");
const swiftRules = readPrompt("swift-rules.md");
const ghosttyPatterns = readPrompt("ghostty-patterns.md");
const architecture = readPrompt("architecture.md");
const gitRules = readPrompt("git-rules.md");
const securityPosture = readPrompt("eng/security-posture.md");

// Design spec (granular files in design/)
const designPrinciples = readPrompt("design/principles.md");
const designSystemTokens = readPrompt("design/system-tokens.md");
const designComponents = readPrompt("design/components.md");
const designChatWindow = readPrompt("design/chat-window.md");
const designIdeWindow = readPrompt("design/ide-window.md");
const designOverlays = readPrompt("design/overlays.md");
const designCrossWindow = readPrompt("design/cross-window.md");
const designSettings = readPrompt("design/settings.md");
const designKeyboardShortcuts = readPrompt("design/keyboard-shortcuts.md");
const designStateAndMisc = readPrompt("design/state-and-misc.md");

// Engineering spec (granular files in eng/)
const engGoalsConstraints = readPrompt("eng/goals-constraints.md");
const engRepoBuild = readPrompt("eng/repo-build.md");
const engCodeOrganization = readPrompt("eng/code-organization.md");
const engStateArchitecture = readPrompt("eng/state-architecture.md");
const engWindowManagement = readPrompt("eng/window-management.md");
const engChatImplementation = readPrompt("eng/chat-implementation.md");
const engIdeImplementation = readPrompt("eng/ide-implementation.md");
const engEditorSubsystem = readPrompt("eng/editor-subsystem.md");
const engTerminalSubsystem = readPrompt("eng/terminal-subsystem.md");
const engAiIntegration = readPrompt("eng/ai-integration.md");
const engJjIntegration = readPrompt("eng/jj-integration.md");
const engSkillsSystem = readPrompt("eng/skills-system.md");
const engWebApp = readPrompt("eng/web-app.md");
const engDesignSystemImpl = readPrompt("eng/design-system-impl.md");
const engKeyboardInput = readPrompt("eng/keyboard-input.md");
const engTesting = readPrompt("eng/testing.md");
const engMigration = readPrompt("eng/migration.md");
const engImplementationPhases = readPrompt("eng/implementation-phases.md");

// Component functions for MDX rendering
const SpecPrecedence = () => specPrecedence;
const SpecIndex = () => specIndex;
const MvpScope = () => mvpScope;
const AlwaysGreen = () => alwaysGreen;
const Architecture = () => architecture;
const SecurityPosture = () => securityPosture;
const ZigRules = () => zigRules;
const SwiftRules = () => swiftRules;
const GhosttyPatterns = () => ghosttyPatterns;
const GitRules = () => gitRules;
const FolderStructure = () => `## Folder Structure\n\n${folderStructure}`;
const ClaudeMd = () => `## Project Conventions (CLAUDE.md)\n\n${claudeMd}`;

// Design spec components
const DesignPrinciples = () => designPrinciples;
const DesignSystemTokens = () => designSystemTokens;
const DesignComponents = () => designComponents;
const DesignChatWindow = () => designChatWindow;
const DesignIdeWindow = () => designIdeWindow;
const DesignOverlays = () => designOverlays;
const DesignCrossWindow = () => designCrossWindow;
const DesignSettings = () => designSettings;
const DesignKeyboardShortcuts = () => designKeyboardShortcuts;
const DesignStateAndMisc = () => designStateAndMisc;

// Engineering spec components
const EngGoalsConstraints = () => engGoalsConstraints;
const EngRepoBuild = () => engRepoBuild;
const EngCodeOrganization = () => engCodeOrganization;
const EngStateArchitecture = () => engStateArchitecture;
const EngWindowManagement = () => engWindowManagement;
const EngChatImplementation = () => engChatImplementation;
const EngIdeImplementation = () => engIdeImplementation;
const EngEditorSubsystem = () => engEditorSubsystem;
const EngTerminalSubsystem = () => engTerminalSubsystem;
const EngAiIntegration = () => engAiIntegration;
const EngJjIntegration = () => engJjIntegration;
const EngSkillsSystem = () => engSkillsSystem;
const EngWebApp = () => engWebApp;
const EngDesignSystemImpl = () => engDesignSystemImpl;
const EngKeyboardInput = () => engKeyboardInput;
const EngTesting = () => engTesting;
const EngMigration = () => engMigration;
const EngImplementationPhases = () => engImplementationPhases;

// Import the MDX template
import SystemPromptMdx from "./prompts/system-prompt.mdx";

// Render the MDX to plain text using shared render utility
export const SYSTEM_PROMPT = render(SystemPromptMdx, {
  components: {
    SpecPrecedence,
    SpecIndex,
    MvpScope,
    AlwaysGreen,
    Architecture,
    SecurityPosture,
    ZigRules,
    SwiftRules,
    GhosttyPatterns,
    GitRules,
    FolderStructure,
    ClaudeMd,
    // Design spec
    DesignPrinciples,
    DesignSystemTokens,
    DesignComponents,
    DesignChatWindow,
    DesignIdeWindow,
    DesignOverlays,
    DesignCrossWindow,
    DesignSettings,
    DesignKeyboardShortcuts,
    DesignStateAndMisc,
    // Engineering spec
    EngGoalsConstraints,
    EngRepoBuild,
    EngCodeOrganization,
    EngStateArchitecture,
    EngWindowManagement,
    EngChatImplementation,
    EngIdeImplementation,
    EngEditorSubsystem,
    EngTerminalSubsystem,
    EngAiIntegration,
    EngJjIntegration,
    EngSkillsSystem,
    EngWebApp,
    EngDesignSystemImpl,
    EngKeyboardInput,
    EngTesting,
    EngMigration,
    EngImplementationPhases,
  },
});
