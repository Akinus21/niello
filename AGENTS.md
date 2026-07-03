# Agent Guidelines

## Commit and Push Workflow

1. **Make all changes via commits** - Never push directly to main
2. **Push commits to origin/main** - The CI pipeline will automatically build
3. **Commit messages should be clear** - Describe what was changed and why

## Build Process

- CI builds on push to `main` branch
- Containerfile defines the build process
- No manual build steps required - CI handles everything

## Before Committing

- Verify changes compile/build correctly
- Ensure no syntax errors in shell scripts
- Test that Containerfile changes use valid syntax (no heredocs with backslash continuations)