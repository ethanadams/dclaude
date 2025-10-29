# Gemini Workspace

This workspace is designed to facilitate development with the dclaude project. It provides a set of scripts to manage the development environment, including building the Docker image, running containers, and managing code changes.

## Prerequisites

Before you begin, ensure you have the following installed:
- Docker
- Git

You also need to set the following environment variables:
- `DCLAUDE_REPO_PATH`: The local path to your original git repository where changes will be synced (required).
- `DCLAUDE_CLONE_PATH_PREFIX`: The local path prefix where isolated clones will be created (e.g., `/tmp/dclaude`) (required).
- `DCLAUDE_REPO_URL`: The URL of the remote repository (e.g., `git@github.com:storj/infra.git`) (optional, only needed for `unshallow` command).

## Scripts

### `build.sh`

This script builds the Docker image for the dclaude environment.

**Usage:**
```bash
./build.sh
```

### `dclaude.sh`

This script is the main entry point for managing the development environment. It has several commands:

#### `run <container-name>`

This command starts or attaches to a container. It will:
1.  Create a new branch in your original repository (from local main) if it doesn't already exist.
2.  Clone from that branch in your local repository into a new directory at `$DCLAUDE_CLONE_PATH_PREFIX/<container-name>`.
3.  Re-initialize a new git repository in the cloned directory with careful preservation of line endings.
4.  Start a new container or attach to an existing one with the given name.
5.  Mount the cloned repository into the container at `/src`.

**Usage:**
```bash
./dclaude.sh run my-dev-container
```

#### `rm <container-name>`

This command removes a container.

**Usage:**
```bash
./dclaude.sh rm my-dev-container
```

#### `clean <container-name>`

This command removes a container and deletes the corresponding cloned repository.

**Usage:**
```bash
./dclaude.sh clean my-dev-container
```

#### `patch <container-name>`

This command syncs the complete file state from the container to the corresponding branch in your local repository at `$DCLAUDE_REPO_PATH`.

**How it works:**
1. Stages and commits all changes in the container
2. Creates a backup branch for rollback safety
3. Checks out the target branch in your local repository
4. Resets the branch to origin/main (or main) for a clean state
5. Removes all files from the working directory
6. Copies all files from the container's current state using rsync (or tar)
7. Removes the backup branch on success

This ensures the target repository exactly matches the container, properly handling file additions, modifications, deletions, and renames. If any operation fails, it automatically rolls back to the backup branch.

**Usage:**
```bash
./dclaude.sh patch my-dev-container
```

#### `list` or `ls`

Lists all dclaude containers with their status and clone directory information.

**Usage:**
```bash
./dclaude.sh list
```

#### `status <container-name>`

Shows detailed status information for a specific container including container status, clone directory status, and git status.

**Usage:**
```bash
./dclaude.sh status my-dev-container
```

#### `help`

Displays usage information and available commands.

**Usage:**
```bash
./dclaude.sh help
```

#### `diff <container-name>`

Previews changes between the container's repository and the corresponding branch in your original repository without applying them. This is a read-only command that shows what would be changed if you run the `patch` command.

**What it shows:**
- Count of new, deleted, and modified files
- List of all affected files with status indicators (+ for new, - for deleted, M for modified)
- Comparison against the branch in your original repository (not origin/main)
- Uses git tree SHA comparison for efficient detection

**Usage:**
```bash
./dclaude.sh diff my-dev-container
```

#### `unshallow <container-name>`

Replaces the local clone with a full clone from the remote repository. This is useful when you need to access the full remote git history, run `git log`, `git blame`, or other commands that require complete history.

**Process:**
1. Backs up your current work
2. Removes the local clone
3. Creates a new full clone from `DCLAUDE_REPO_URL` (remote, not local)
4. Re-initializes the git repository
5. Restores all your modified and untracked files

**Important:**
- Requires `DCLAUDE_REPO_URL` environment variable to be set
- The container must be stopped before running this command
- Requires network access

**Usage:**
```bash
./dclaude.sh unshallow my-dev-container
```

## Dockerfile

The `Dockerfile` sets up the development environment with:
- Go 1.24.9
- Node.js 20 LTS (from NodeSource)
- Helm 3.14.0
- Claude Code CLI
- Additional tools: curl, vim, git

The working directory is set to `/src`.

## Typical Workflow

Here's a typical development workflow using dclaude:

1. **Start a new development session:**
   ```bash
   ./dclaude.sh run feature-branch
   ```
   This creates a branch in your original repository and clones it to an isolated directory.

2. **Work inside the container:**
   - The container automatically starts Claude Code
   - Make changes, implement features, experiment
   - All changes are isolated to the container

3. **Exit the container:**
   - Press `Ctrl+D` or type `exit`
   - The container stops but preserves all your changes

4. **Resume work later:**
   ```bash
   ./dclaude.sh run feature-branch
   ```
   This reattaches to the existing container with all your changes intact.

5. **Preview changes before applying:**
   ```bash
   ./dclaude.sh diff feature-branch
   ```
   Review what files will be added, modified, or deleted.

6. **Apply changes to your main repository:**
   ```bash
   ./dclaude.sh patch feature-branch
   ```
   This syncs all changes to a new branch in your original repository.

7. **Review and commit in your original repository:**
   ```bash
   cd $DCLAUDE_REPO_PATH
   git status
   git add .
   git commit -m "Add feature implementation"
   git push origin feature-branch
   ```

8. **Clean up when finished:**
   ```bash
   ./dclaude.sh clean feature-branch
   ```
   This removes both the container and the cloned repository.

## Advanced Usage

### Working with Full Git History

If you need access to the complete git history (for `git log`, `git blame`, etc.), convert your shallow clone to a full clone:

```bash
# Stop the container first
docker stop my-dev-container

# Convert to full clone
./dclaude.sh unshallow my-dev-container

# Resume work
./dclaude.sh run my-dev-container
```

### Managing Multiple Containers

You can run multiple containers in parallel for different features:

```bash
./dclaude.sh run feature-branch
./dclaude.sh run bugfix-validation
./dclaude.sh run refactor-api
```

List all containers to see their status:

```bash
./dclaude.sh list
```

### Checking Container Status

Get detailed information about a specific container:

```bash
./dclaude.sh status feature-branch
```

This shows:
- Whether the container is running or stopped
- Whether the clone directory exists
- Git status (clean or uncommitted changes)

## Best Practices

1. **Use descriptive container names** that match your feature or branch names for easier tracking.

2. **Preview before patching** using the `diff` command to avoid surprises when applying changes.

3. **Patch frequently** to ensure your work is backed up to your main repository. Don't wait until the end.

4. **One feature per container** for cleaner change management and easier code review.

5. **Clean up old containers** regularly to free up disk space:
   ```bash
   ./dclaude.sh list
   ./dclaude.sh clean old-container-name
   ```

6. **Start with shallow clones** for faster setup. Only use `unshallow` when you actually need the full git history.

## Configuration

### Required Environment Variables

Set these in your shell configuration file (`~/.bashrc`, `~/.zshrc`, etc.):

```bash
export DCLAUDE_REPO_PATH="/path/to/your/local/repo"
export DCLAUDE_CLONE_PATH_PREFIX="/tmp/dclaude"
# Optional: only needed for unshallow command
export DCLAUDE_REPO_URL="git@github.com:your-username/your-repo.git"
```

### Build Options

The `build.sh` script supports several options:

```bash
# Standard build
./build.sh

# Build without cache (useful after Dockerfile changes)
./build.sh --no-cache

# Quiet build (minimal output)
./build.sh --quiet
```

## Troubleshooting

### Docker Image Not Found

**Error:** `Docker image 'dclaude' not found`

**Solution:** Build the Docker image first:
```bash
./build.sh
```

### Failed to Clone Repository

**Error:** `Failed to clone repository`

**Possible causes:**
- Invalid `DCLAUDE_REPO_URL`
- Missing SSH keys or authentication
- Network connectivity issues

**Solution:**
1. Verify the repository URL: `echo $DCLAUDE_REPO_URL`
2. Test SSH access: `ssh -T git@github.com`
3. Check network connectivity

### Container Won't Start

**Error:** Container fails to start or attach

**Solution:**
1. Check Docker is running: `docker info`
2. Verify environment variables are set:
   ```bash
   echo $DCLAUDE_REPO_URL
   echo $DCLAUDE_CLONE_PATH_PREFIX
   echo $DCLAUDE_REPO_PATH
   ```
3. Check for port conflicts or resource limits

### Insufficient Disk Space

**Error:** Clone or container operations fail due to disk space

**Solution:**
1. Check available space: `df -h`
2. Clean up old containers: `./dclaude.sh list` then `./dclaude.sh clean <name>`
3. Clean up Docker system: `docker system prune`

### Unshallow Command Fails

**Error:** `Container is currently running`

**Solution:** Stop the container first:
```bash
docker stop container-name
./dclaude.sh unshallow container-name
```

### Patch Creates Conflicts

**Issue:** Changes conflict with updates in the main repository

**Solution:**
1. Update your main repository: `cd $DCLAUDE_REPO_PATH && git pull`
2. Manually resolve conflicts in the branch created by `patch`
3. Or start with a fresh clone based on the latest main branch

## Security

The project includes `.claude/settings.json` with deny patterns to prevent Claude Code from accessing sensitive files:

- Environment files (`.env`, `.env.*`)
- Credentials and secrets directories
- SSH keys and certificates (`.pem`, `.key`, `id_rsa`, etc.)
- Cloud provider credentials (AWS, GCloud, Azure)
- API keys and tokens
- Kubernetes configs and Docker credentials

These patterns help protect sensitive information when working with AI assistants in the containerized environment.

## Project Structure

```
dclaude/
├── .claude/
│   └── settings.json        # Security settings and deny patterns
├── .gitignore              # Git ignore rules
├── .geminiignore           # Gemini-specific ignore patterns
├── build.sh                # Build Docker image script
├── dclaude.sh              # Main management script
├── test-permissions.sh     # Permission testing utility
├── Dockerfile              # Container definition
├── CLAUDE.md               # Documentation for Claude Code
└── GEMINI.md               # This file - Gemini documentation
```

## Benefits of Using dclaude

- **Isolation:** Changes are completely isolated from your main repository until you explicitly patch them
- **Experimentation:** Try different approaches with AI assistance without risk
- **Parallel Development:** Work on multiple features simultaneously in separate containers
- **Clean History:** Only successful, reviewed changes make it to your main repository
- **Fast Setup:** Local clones are instant with no network dependency
- **Rollback Protection:** Automatic backup branches allow safe recovery from failed operations
- **Safety:** Preview changes before applying them with automatic rollback on failures

## Limitations

- Requires Docker and sufficient disk space
- Changes must be manually patched back to the original repository
- Container state is lost if Docker images are removed
- Binary files and large assets are duplicated in each clone
- Network connectivity required for initial clone and unshallow operations

## Contributing

This is a development workflow tool designed to be customized. Feel free to modify the scripts to fit your specific needs and workflow preferences.

## License

See the repository license for details.
