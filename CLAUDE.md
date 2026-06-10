# Claude Code Guide

## Git Workflow

### Always Commit Working Code
- **Frequent Commits**: After completing any working feature or fix, immediately commit with a descriptive message
- **Before Major Changes**: Always commit current working state before starting new features
- **Easy Rollback**: Use git to quickly revert if something breaks
- **Branch Strategy**: Create branches for experimental features

### Git Commands to Use
```bash
# Commit current working state
git add .
git commit -m "Working: marker search improvements"

# Create branch for new feature  
git checkout -b feature-name

# Quick status check
git status

# Revert if needed
git checkout -- filename
git reset --hard HEAD
```

## Best Practices for Working with Claude

### Getting Quality Results
- **Request Thoughtful Analysis**: Ask Claude to "think through this problem thoroughly before writing any code" or "create a detailed plan first" to get more thoughtful responses.
- **Ask for Clarity**: If unsure about the task, have Claude ask clarifying questions rather than making assumptions.
- **Break Down Large Tasks**: For complex projects, ask Claude to break down tasks into smaller components or help you structure the approach.
- **Seek Architecture Insights**: Ask Claude to "explain the architectural considerations" when starting a new feature.
- **Request Plans**: Have Claude create and get approval for a plan before implementing complex features.

### Code Quality Guidelines
- **File Comprehension**: Have Claude read entire files to understand the complete context.
- **Incremental Development**: Commit working code after completing logical milestones.
- **Modern Library Usage**: Ask Claude to check current documentation for libraries with changing interfaces.
- **Proper Error Handling**: Ensure Claude implements robust error handling in all code.
- **Code Organization**: Request modular code with appropriate file separation and clear naming.
- **Readability Focus**: Emphasize that code should be optimized for readability.
- **Complete Implementation**: Claude should fully implement features, not provide "dummy" implementations.

### Problem Solving Approach
- **Root Cause Analysis**: When facing issues, ask Claude to identify the underlying cause rather than trying random solutions.
- **Architectural Thinking**: Request Claude to consider system design implications before implementation.
- **Edge Case Consideration**: Ask Claude to proactively identify and address edge cases.
- **Build Verification**: Have Claude explain how to verify the code works as expected.

## Specific Commands
To get Claude to approach problems more systematically:

1. "Before writing any code, please analyze this problem thoroughly."
2. "Create a detailed plan that addresses potential edge cases for this feature."
3. "Explain the architectural implications of implementing this feature."
4. "Walk me through your thought process on solving this problem."
5. "Consider alternative approaches and explain the trade-offs between them."

## UI/UX Work
When requesting interface design:
- Ask Claude to focus on both aesthetics and usability
- Request attention to interaction patterns and micro-interactions
- Specify platform-specific guidelines you want to follow

Remember: Claude excels when given clear direction and specific requirements while also being asked to apply critical thinking to problems.

## blitz-ios

This project is opened in **Blitz**, a web-based iOS development IDE with integrated simulator streaming. The user sees a live simulator view in their browser alongside your code. Blitz manages the build pipeline, simulator lifecycle, and dev servers — you focus on writing code.

### Important: What Blitz Manages (Do NOT Do These Manually)

- **Do not start the iOS simulator** — Blitz boots and manages it

- **Do not modify build settings or signing** — managed by Blitz

### MCP Tools (`blitz-ios`)

The `blitz-ios` MCP server (`.mcp.json`) lets you control the iOS simulator and query project state. Use these tools to test your changes autonomously.

**Simulator interaction:**
- `device_action` — Perform a single action: `tap`, `swipe`, `button` (HOME/LOCK/SIRI), `input-text`, `key`, `key-sequence`. Supports `describe_after` to capture screen state after the action.
- `device_actions` — Execute multiple actions in sequence (batch). Same action types, with optional `describe_after` at the end.
- `describe_screen` — Get the full UI element hierarchy (element types, labels, positions, frames). Use this to understand what's on screen before interacting.
- `describe_point` — Get the UI element at specific (x, y) coordinates.

**Project state and logs:**
- `get_project_state` — Get runtime status, project type, dev server URLs/ports, error state, and simulator UDID. Call with `projectDir` set to your current working directory.
- `query_server_logs` — Query server-side logs (sources: `vite`, `metro`, `ios-build`, `backend`, `runtime`). Supports filtering by level, source, timestamp, and search text.
- `query_backend_logs` — Query application-level backend logs (console.log/error from user code).
- `list_issues` — Get issues filed by the user via Blitz's visual issue tracker. Issues are pinned to screen locations and include UI element metadata.

### Testing Workflow

After making code changes:
1. Wait briefly for hot reload / rebuild
2. Use `describe_screen` to verify the UI updated as expected
3. Use `device_action` to interact (tap buttons, enter text, navigate)
4. Use `describe_screen` again to verify the result
5. Check `query_server_logs` if something looks wrong

### Issue Tracking

Users can file visual issues by tapping directly on the simulator stream in Blitz. These issues include the screen coordinates, a description, and metadata about the tapped UI element. Use `list_issues` to see open issues and fix them.
