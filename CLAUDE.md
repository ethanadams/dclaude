# dclaude - Dockerized Claude Code Development Environment

## Overview

dclaude is a development workflow tool that enables safe, isolated experimentation with Claude Code (Anthropic's AI coding assistant) using Docker containers. It provides a sandboxed environment where you can leverage Claude's capabilities to make code changes, experiment with modifications, and then selectively apply those changes to your actual repository.

## Purpose

The primary goal of dclaude is to create isolated development environments that:
- Allow Claude Code to work on your codebase without directly modifying your main repository
- Enable experimentation with AI-assisted development in a safe, containerized environment
- Provide an easy workflow to extract and apply successful changes back to your real repository
- Support multiple parallel development sessions with different containers/branches

## How It Works

1. **Create Branch**: Creates a new branch in your original repository from a source branch (default: main, or specify with `--from`)
2. **Clone & Isolate**: Clones from the new branch in your local repository to an isolated directory
3. **Re-initialize**: Sets up a new git repository in the clone to track changes independently
4. **Containerize**: Runs Claude Code inside a Docker container with the cloned repository mounted
5. **Develop**: Work with Claude Code to make changes in the isolated environment
6. **Extract**: Sync the complete state from the container back to the branch in your original repository

## Architecture

```
Your Original Repo (DCLAUDE_REPO_PATH)
         |
         | 1. create branch from source (main/develop/etc)
         v
Branch in Original Repo
         |
         | 2. clone locally
         v
Isolated Clone (DCLAUDE_CLONE_PATH_PREFIX/<container-name>)
         |
         | 3. mount into
         v
Docker Container (with Claude Code)
         |
         | 4. sync changes back
         v
Branch in Original Repo
```

## Prerequisites

**Required Software:**
- Docker
- Git
- Node.js and npm (for Claude Code)

**Required Environment Variables:**
- `DCLAUDE_REPO_PATH`: The local path to your original git repository
- `DCLAUDE_CLONE_PATH_PREFIX`: The local path prefix where isolated clones will be created (e.g., `/tmp/dclaude`)

**Example Configuration:**
```bash
export DCLAUDE_REPO_PATH="/Users/username/projects/infra"
export DCLAUDE_CLONE_PATH_PREFIX="/tmp/dclaude"
```

## Scripts

### build.sh

Builds the Docker image for the dclaude environment with optional parameters.

**Usage:**
```bash
./build.sh [OPTIONS]
```

**Options:**
- `--no-cache`: Build without using Docker cache
- `--quiet`, `-q`: Suppress build output
- `--help`, `-h`: Show help message

**Examples:**
```bash
./build.sh                # Standard build
./build.sh --no-cache     # Rebuild from scratch
./build.sh --quiet        # Build with minimal output
```

The Docker image includes:
- Go 1.24.9
- Node.js 20 LTS
- Helm 3.14.0
- Claude Code CLI
- vim and other development tools

### dclaude.sh

Main management script with the following commands:

#### run <container-name> [--from <branch>]

Starts or attaches to a development container.

**Process:**
1. Checks if currently on a branch other than the source branch with uncommitted changes (errors if found)
2. Switches to source branch (default: main) to verify clean state
3. Prompts to clean untracked files from source branch if any exist (optional)
4. Creates a new branch in your original repository (from the source branch) if it doesn't exist
5. Returns to your original branch
6. Clones from the new branch in your local repository to an isolated directory
7. Re-initializes git repository in the clone with careful preservation of file line endings
8. Creates/starts/attaches to Docker container
9. Mounts the cloned repository at `/src` inside the container
10. Launches Claude Code

**Usage:**
```bash
./dclaude.sh run feature-branch                 # Create from main (default)
./dclaude.sh run feature-branch --from develop  # Create from develop branch
```

**Options:**
- `--from <branch>`: Specify which branch to create the new branch from (default: `main`)

**Safety Checks:**
- **Current branch check**: If you're on a branch with uncommitted changes, the command will error and ask you to commit or stash first
- **Source branch check**: The specified source branch must be clean (no uncommitted changes)
- **Untracked files**: If the source branch has untracked files, you'll be prompted to clean them (optional)

**Note:**
- The container name is used as the branch name in your original repository
- Your `~/.dclaude` directory and `~/.dclaude.json` are mounted into the container (as `/home/dclaude/.claude` and `/home/dclaude/.claude.json` respectively), so Claude Code authentication is preserved while keeping dclaude configurations isolated from your standard Claude Code setup
- The clone is created from your local repository, so it's fast and doesn't require network access
- Only required environment variables: `DCLAUDE_REPO_PATH` and `DCLAUDE_CLONE_PATH_PREFIX`

#### rm <container-name>

Removes a container (keeps the cloned repository).

**Usage:**
```bash
./dclaude.sh rm my-feature
```

#### clean <container-name>

Removes both the container and its cloned repository.

**Usage:**
```bash
./dclaude.sh clean my-feature
```

**Warning:** This deletes all changes in the cloned repository that haven't been patched.

#### diff <container-name>

Previews changes between the container's repository and the corresponding branch in your original repository with intelligent rename detection.

**Process:**
1. Stages and commits all changes in the container to capture the complete state
2. Uses git diff with rename detection (90% similarity threshold) to analyze changes
3. Displays a summary showing:
   - Count of new, renamed, modified, and deleted files
   - List of all affected files with status indicators:
     - `R` for renamed files (shows old -> new)
     - `+` for new files
     - `M` for modified files
     - `-` for deleted files

**Usage:**
```bash
./dclaude.sh diff feature-branch
```

**Note:** This command is read-only and makes no changes to either repository. Use it before running `patch` to preview what changes will be applied, including which files will be detected as renames.

#### patch <container-name>

Syncs changes from the container's repository to the corresponding branch in your original repository using git patches to preserve rename detection and file history. **Changes are staged but not committed**, allowing you to review and create your own commit.

**Process:**
1. Stages and commits all changes in the container (including new, modified, deleted, and renamed files)
2. Creates a backup branch for rollback safety
3. Checks out the target branch in your original repository
4. Resets the target branch to origin/main (or main) for a clean state
5. Removes all tracked and untracked files from the target
6. Generates a git patch with rename detection (90% similarity threshold) and binary file support
7. Applies the patch using `git apply --3way --index` (stages changes without committing)
8. Falls back to file copy method if patch application fails
9. Removes the backup branch on success

This ensures the target repository exactly matches the container state, properly handling:
- New files (added to target)
- Modified files (overwritten in target)
- Deleted files (removed from target)
- **Renamed files (tracked as renames, preserving git history)**
- Binary files (included in patches)

**Safety Features:**
- Creates a backup branch before making destructive changes
- Automatically rolls back to backup if any operation fails
- Uses git-native patch format to preserve history and renames
- Fallback to file copy method if patch conflicts occur
- 3-way merge support for conflict resolution
- **Changes are staged but not committed** - you control the commit message and timing

**Usage:**
```bash
./dclaude.sh patch feature-branch
cd $DCLAUDE_REPO_PATH
git status              # Review staged changes
git commit -m "Your commit message here"
```

**Benefits:**
- **Preserves rename history**: `git log --follow` works correctly on renamed files after you commit
- **Handles conflicts gracefully**: 3-way merge provides conflict markers for manual resolution
- **Binary file support**: Images and other binary files are correctly patched
- **Fallback protection**: Automatically falls back to file copy if patching fails
- **Full control**: You decide when and how to commit the changes

**Note:** If the patch-based approach fails (e.g., due to conflicts), the command will warn you and fall back to the file copy method, which works but loses rename detection. Changes will still be uncommitted in either case.

#### list (or ls)

Lists all dclaude containers with their status and clone directory information.

**Usage:**
```bash
./dclaude.sh list
# or
./dclaude.sh ls
```

**Output:**
- Container name
- Status (Running/Stopped)
- Whether clone directory exists

#### status <container-name>

Shows detailed status information for a specific container.

**Usage:**
```bash
./dclaude.sh status my-feature
```

**Output:**
- Container status (Running/Stopped/Not found)
- Clone directory status
- Git status (clean or uncommitted changes)

#### help

Displays usage information and available commands.

**Usage:**
```bash
./dclaude.sh help
# or
./dclaude.sh --help
./dclaude.sh -h
```

## Typical Workflow

1. **Ensure your current branch is clean:**
   ```bash
   cd $DCLAUDE_REPO_PATH
   git status  # Should show no uncommitted changes
   # If you have changes, commit or stash them first
   git commit -m "Save work"
   # or
   git stash
   ```

2. **Start a new development session:**
   ```bash
   ./dclaude.sh run feature-branch
   # Or, to branch from a different base:
   ./dclaude.sh run feature-branch --from develop
   # If prompted about untracked files in source branch, choose Y to clean or N to skip
   ```

3. **Work with Claude Code inside the container:**
   - Claude Code launches automatically
   - Make changes, implement features, fix bugs
   - All changes are isolated to the container

4. **Exit the container when done:**
   - Press Ctrl+D or type `exit`
   - Container stops but preserves all changes

5. **Preview changes before applying:**
   ```bash
   ./dclaude.sh diff feature-branch
   # Review the output showing renamed, new, modified, and deleted files
   ```

6. **Apply changes to your real repository:**
   ```bash
   ./dclaude.sh patch feature-branch
   # Changes are staged but not committed
   ```

7. **Review and commit in your original repository:**
   ```bash
   cd $DCLAUDE_REPO_PATH
   git status              # See what's staged
   git diff --cached       # Review the actual changes
   git log --follow <renamed-file>  # Verify rename history is preserved
   git commit -m "Add feature implementation"
   ```

8. **Clean up when finished:**
   ```bash
   ./dclaude.sh clean feature-branch
   ```

## Best Practices

1. **Always commit or stash before running new containers** - The `run` command will error if you try to switch branches with uncommitted changes
2. **Use descriptive container names** that match your feature/branch names
3. **Choose the right source branch** - Use `--from` to branch from develop, staging, or any other branch instead of main
4. **Preview before patching** using the `diff` command to see what will change, including renames
5. **Review staged changes** after patching before committing to understand what changed
6. **Verify rename history** with `git log --follow <file>` after committing to ensure history is preserved
7. **Clean up old containers** to save disk space
8. **One feature per container** for easier management and cleaner patches
9. **Keep source branches clean** - Say yes when prompted to clean untracked files for the cleanest starting point

## Benefits

- **Safety**: Changes are isolated from your main repository with automatic backup/rollback
- **Rename Detection**: Git history is preserved for renamed files using patch-based syncing
- **Uncommitted Changes**: Patches are staged but not auto-committed, giving you full control
- **Experimentation**: Try different approaches with Claude without risk
- **Parallel Development**: Run multiple containers for different features
- **Clean History**: Only successful changes make it to your real repository
- **Reproducibility**: Each container starts from a clean state based on your chosen source branch
- **Fast Setup**: Local clones are instant with no network dependency
- **Rollback Protection**: Automatic backup branches allow safe recovery from failed operations
- **Smart Conflict Handling**: 3-way merge support with automatic fallback to file copy if needed

## Limitations

- Requires Docker and sufficient disk space for clones
- Changes must be manually patched back to the original repository
- Container state is lost if Docker images are removed
- Binary files and large assets are duplicated in clones

## Troubleshooting

**Container won't start:**
- Ensure Docker is running
- Check that all required environment variables are set (`DCLAUDE_REPO_PATH`, `DCLAUDE_CLONE_PATH_PREFIX`)
- Verify the Docker image is built: `docker images | grep dclaude`

**Error: "Current branch has uncommitted changes":**
- This happens when trying to run a new container while on a branch with uncommitted work
- Solution: Commit or stash your changes first, or checkout main
- Example: `git commit -m "WIP"` or `git stash`

**Clone directory already exists:**
- The script skips re-cloning if the directory exists
- To start fresh, use `./dclaude.sh clean <container-name>` first

**Patch fails to apply:**
- The system will automatically fall back to file copy method (losing rename detection)
- If manual resolution needed, resolve conflicts in `$DCLAUDE_REPO_PATH` and commit
- Changes are always staged but not committed, giving you control

**Untracked files prompt:**
- If main has untracked files, you'll be prompted to clean them
- Choose Y to clean (recommended for clean starting point)
- Choose N to skip (untracked files will be included in the clone)

## Security

The project includes `.claude/settings.json` with deny patterns to prevent Claude Code from accessing sensitive files such as:
- Environment files (`.env`, `.env.*`)
- Credentials and secrets directories
- SSH keys and certificates
- Cloud provider credentials (AWS, GCloud, Azure)
- API keys and tokens
- Configuration files containing sensitive data

This helps protect sensitive information when working with AI assistants in the containerized environment.

## Directory Structure

```
dclaude/
├── .claude/
│   └── settings.json        # Security settings and deny patterns
├── build.sh                 # Build Docker image
├── dclaude.sh              # Main management script
├── Dockerfile              # Container definition
├── CLAUDE.md              # This file (Claude-specific docs)
├── GEMINI.md              # Alternative documentation
└── .gitignore             # Git ignore rules
```

## Contributing

This is a personal development workflow tool. Modify the scripts to fit your specific needs and workflow preferences.

## License

See the repository license for details.
