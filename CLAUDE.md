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