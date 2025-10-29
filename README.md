# dclaude

> Dockerized Claude Code Development Environment

A development workflow tool that enables safe, isolated experimentation with Claude Code (Anthropic's AI coding assistant) using Docker containers.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Usage](#usage)
  - [Building the Docker Image](#building-the-docker-image)
  - [Managing Containers](#managing-containers)
  - [Working with Changes](#working-with-changes)
- [Workflow](#workflow)
- [Commands Reference](#commands-reference)
- [Best Practices](#best-practices)
- [Architecture](#architecture)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## Overview

dclaude provides isolated development environments where you can leverage Claude Code's capabilities to make code changes, experiment with modifications, and then selectively apply those changes to your actual repository. All work is done inside Docker containers with sandboxed repository clones, ensuring your main repository stays safe.

## Features

- **Isolated Environments**: Work on features in completely isolated Docker containers
- **Safe Experimentation**: Make changes without risk to your main repository with automatic backup/rollback
- **Rename Detection**: Git history is preserved for renamed files using patch-based syncing
- **Uncommitted Changes**: Patches are staged but not auto-committed, giving you full control
- **Fast Setup**: Uses local git clones for instant initialization (no network required)
- **Easy Change Management**: Preview and apply changes with simple commands
- **Parallel Development**: Run multiple containers for different features simultaneously
- **Clean History**: Only successful changes make it to your real repository
- **Branch-First Workflow**: Creates branches upfront for better organization
- **Smart Conflict Handling**: 3-way merge support with automatic fallback

## Prerequisites

**Required Software:**
- Docker
- Git
- Node.js and npm (for Claude Code)

**Required Environment Variables:**
```bash
export DCLAUDE_REPO_PATH="/path/to/your/original/repo"
export DCLAUDE_CLONE_PATH_PREFIX="/tmp/dclaude"
```

## Quick Start

1. **Set up environment variables:**
   ```bash
   export DCLAUDE_REPO_PATH="/path/to/your/repo"
   export DCLAUDE_CLONE_PATH_PREFIX="/tmp/dclaude"
   ```

2. **Build the Docker image:**
   ```bash
   ./build.sh
   ```

3. **Start a development session:**
   ```bash
   ./dclaude.sh run my-feature
   ```

4. **Work with Claude Code** (launches automatically inside the container)

5. **Preview your changes:**
   ```bash
   ./dclaude.sh diff my-feature
   ```

6. **Apply changes to your repository:**
   ```bash
   ./dclaude.sh patch my-feature
   ```

7. **Clean up:**
   ```bash
   ./dclaude.sh clean my-feature
   ```

## Configuration

### Environment Variables

| Variable | Description | Example | Required |
|----------|-------------|---------|----------|
| `DCLAUDE_REPO_PATH` | Your original repository path | `/Users/user/projects/repo` | Yes |
| `DCLAUDE_CLONE_PATH_PREFIX` | Where clones are stored | `/tmp/dclaude` | Yes |

### Claude Code Configuration

Your `~/.dclaude` directory and `~/.dclaude.json` are mounted into containers (as `/home/dclaude/.claude` and `/home/dclaude/.claude.json`), preserving Claude Code authentication while keeping dclaude configurations isolated from your standard Claude Code setup.

## Usage

### Building the Docker Image

```bash
# Standard build
./build.sh

# Rebuild from scratch
./build.sh --no-cache

# Build with minimal output
./build.sh --quiet
```

The Docker image includes:
- Go 1.24.9
- Node.js 20 LTS
- Helm 3.14.0
- Claude Code CLI
- vim and other development tools

### Managing Containers

**Start or attach to a container:**
```bash
./dclaude.sh run <container-name>
```

**List all containers:**
```bash
./dclaude.sh list
# or
./dclaude.sh ls
```

**Check container status:**
```bash
./dclaude.sh status <container-name>
```

**Remove a container (keeps repository):**
```bash
./dclaude.sh rm <container-name>
```

**Remove container and repository:**
```bash
./dclaude.sh clean <container-name>
```

### Working with Changes

**Preview changes:**
```bash
./dclaude.sh diff <container-name>
```

**Apply changes to original repository:**
```bash
./dclaude.sh patch <container-name>
# Changes are staged but not committed - you control the commit
```

## Workflow

### Typical Development Session

1. **Ensure your current branch is clean:**
   ```bash
   cd $DCLAUDE_REPO_PATH
   git status  # Should show no uncommitted changes
   # If you have changes, commit or stash them first
   ```

2. **Start a new development session:**
   ```bash
   ./dclaude.sh run feature-branch
   # If prompted about untracked files, choose Y to clean or N to skip
   ```

3. **Work with Claude Code inside the container:**
   - Claude Code launches automatically
   - Make changes, implement features, fix bugs
   - All changes are isolated to the container

4. **Exit the container when done:**
   - Press `Ctrl+D` or type `exit`
   - Container stops but preserves all changes

5. **Preview changes before applying:**
   ```bash
   ./dclaude.sh diff feature-branch
   # Shows renamed, new, modified, and deleted files
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
   git diff --cached       # Review the changes
   git log --follow <renamed-file>  # Verify rename history
   git commit -m "Add feature implementation"
   ```

8. **Clean up when finished:**
   ```bash
   ./dclaude.sh clean feature-branch
   ```

## Commands Reference

### dclaude.sh

| Command | Description |
|---------|-------------|
| `run <name>` | Start or attach to a development container |
| `rm <name>` | Remove container (keeps repository) |
| `clean <name>` | Remove container and repository |
| `diff <name>` | Preview changes with rename detection |
| `patch <name>` | Apply changes (staged, not committed) |
| `list` / `ls` | List all dclaude containers |
| `status <name>` | Show detailed container status |
| `help` | Display usage information |

### build.sh

| Option | Description |
|--------|-------------|
| `--no-cache` | Build without using Docker cache |
| `--quiet`, `-q` | Suppress build output |
| `--help`, `-h` | Show help message |

## Best Practices

1. **Always commit or stash before running new containers** - The `run` command will error if you try to switch branches with uncommitted changes
2. **Use descriptive container names** that match your feature/branch names
3. **Preview before patching** using the `diff` command to see what will change, including renames
4. **Review staged changes** after patching before committing to understand what changed
5. **Verify rename history** with `git log --follow <file>` after committing to ensure history is preserved
6. **Clean up old containers** to save disk space
7. **One feature per container** for easier management and cleaner patches
8. **Keep main clean** - Say yes when prompted to clean untracked files for the cleanest starting point

## Architecture

```
Your Original Repo (DCLAUDE_REPO_PATH)
         |
         | 1. create branch from main
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

### How It Works

1. **Create Branch**: Creates a new branch in your original repository from local main
2. **Clone & Isolate**: Clones from that branch in your local repository to an isolated directory
3. **Re-initialize**: Sets up a new git repository in the clone to track changes independently
4. **Containerize**: Runs Claude Code inside a Docker container with the cloned repository mounted
5. **Develop**: Work with Claude Code to make changes in the isolated environment
6. **Extract**: Sync the complete state from the container back to the branch in your original repository

## Security

The project includes `.claude/settings.json` with deny patterns to prevent Claude Code from accessing sensitive files such as:
- Environment files (`.env`, `.env.*`)
- Credentials and secrets directories
- SSH keys and certificates
- Cloud provider credentials (AWS, GCloud, Azure)
- API keys and tokens
- Configuration files containing sensitive data

This helps protect sensitive information when working with AI assistants in the containerized environment.

## Troubleshooting

### Container won't start
- Ensure Docker is running
- Check that all required environment variables are set (`DCLAUDE_REPO_PATH`, `DCLAUDE_CLONE_PATH_PREFIX`)
- Verify the Docker image is built: `docker images | grep dclaude`

### Error: "Current branch has uncommitted changes"
- This happens when trying to run a new container while on a branch with uncommitted work
- Solution: Commit or stash your changes first, or checkout main
- Example: `git commit -m "WIP"` or `git stash`

### Clone directory already exists
- The script skips re-cloning if the directory exists
- To start fresh, use `./dclaude.sh clean <container-name>` first

### Patch fails to apply
- The system will automatically fall back to file copy method (losing rename detection)
- If manual resolution needed, resolve conflicts in `$DCLAUDE_REPO_PATH` and commit
- Changes are always staged but not committed, giving you control

### Untracked files prompt
- If main has untracked files, you'll be prompted to clean them
- Choose Y to clean (recommended for clean starting point)
- Choose N to skip (untracked files will be included in the clone)

## Contributing

This is a personal development workflow tool. Feel free to modify the scripts to fit your specific needs and workflow preferences.

## License

See the repository license for details.

---

**Project Structure:**
```
dclaude/
├── .claude/
│   └── settings.json        # Security settings and deny patterns
├── build.sh                 # Build Docker image
├── dclaude.sh              # Main management script
├── Dockerfile              # Container definition
├── README.md               # This file
└── .gitignore             # Git ignore rules
```
