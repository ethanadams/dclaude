#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Image name
IMAGE_NAME="dclaude"

# Helper functions
error() {
  echo -e "${RED}Error: $1${NC}" >&2
  exit 1
}

success() {
  echo -e "${GREEN}$1${NC}"
}

info() {
  echo -e "${BLUE}$1${NC}"
}

warn() {
  echo -e "${YELLOW}$1${NC}"
}

check_env_vars() {
  local required_vars=("$@")
  for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
      error "$var environment variable is not set."
    fi
  done
}

validate_container_name() {
  if [ -z "$1" ]; then
    error "Container name is required"
  fi
}

check_docker_image() {
  if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    error "Docker image '$IMAGE_NAME' not found. Run ./build.sh first."
  fi
}

COMMAND=$1
[ $# -gt 0 ] && shift

case $COMMAND in
  run)
    validate_container_name "$1"
    check_env_vars "DCLAUDE_CLONE_PATH_PREFIX" "DCLAUDE_REPO_PATH"
    check_docker_image

    # Ensure .dclaude.json exists
    if [ ! -f "$HOME/.dclaude.json" ]; then
      info "Creating $HOME/.dclaude.json..."
      echo '{}' > "$HOME/.dclaude.json"
    fi

    CONTAINER_NAME=$1
    BRANCH_NAME=$1
    shift

    # Parse optional --from flag
    SOURCE_BRANCH="main"
    while [ $# -gt 0 ]; do
      case "$1" in
        --from)
          if [ -z "$2" ]; then
            error "--from flag requires a branch name argument"
          fi
          SOURCE_BRANCH="$2"
          shift 2
          ;;
        *)
          error "Unknown option: $1"
          ;;
      esac
    done

    CLONE_PATH="$DCLAUDE_CLONE_PATH_PREFIX/$BRANCH_NAME"

    # Setup repository clone
    if [ ! -d "$CLONE_PATH" ]; then
      # Create branch in original repository first
      if [ ! -d "$DCLAUDE_REPO_PATH/.git" ]; then
        error "Original repository not found at $DCLAUDE_REPO_PATH"
      fi

      # Verify source branch exists and has no uncommitted changes
      if ! git -C "$DCLAUDE_REPO_PATH" rev-parse --verify "$SOURCE_BRANCH" >/dev/null 2>&1; then
        error "Source branch '$SOURCE_BRANCH' not found in original repository"
      fi

      # Check out source branch temporarily to check for changes
      CURRENT_BRANCH=$(git -C "$DCLAUDE_REPO_PATH" rev-parse --abbrev-ref HEAD)
      if [ "$CURRENT_BRANCH" != "$SOURCE_BRANCH" ]; then
        # Check if current branch has uncommitted changes before switching
        if ! git -C "$DCLAUDE_REPO_PATH" diff --quiet || ! git -C "$DCLAUDE_REPO_PATH" diff --cached --quiet; then
          error "Current branch '$CURRENT_BRANCH' has uncommitted changes. Please commit or stash them before creating a new container."
        fi
        info "Checking out $SOURCE_BRANCH branch to verify clean state..."
        git -C "$DCLAUDE_REPO_PATH" checkout "$SOURCE_BRANCH"
      fi

      # Check for uncommitted changes in source branch
      if ! git -C "$DCLAUDE_REPO_PATH" diff --quiet || ! git -C "$DCLAUDE_REPO_PATH" diff --cached --quiet; then
        error "Source branch '$SOURCE_BRANCH' has uncommitted changes. Please commit or stash them first."
      fi

      # Check for untracked/ignored files in source branch
      UNTRACKED_FILES=$(git -C "$DCLAUDE_REPO_PATH" ls-files --others)
      if [ -n "$UNTRACKED_FILES" ]; then
        warn "Source branch '$SOURCE_BRANCH' has untracked files:"
        echo "$UNTRACKED_FILES" | head -20
        if [ $(echo "$UNTRACKED_FILES" | wc -l) -gt 20 ]; then
          info "... and $(( $(echo "$UNTRACKED_FILES" | wc -l) - 20 )) more files"
        fi
        echo ""
        warn "These files will be removed with 'git clean -fdx' to ensure a clean branch"
        echo -n "Do you want to proceed with cleaning? [y/N] "
        read -r response
        case "$response" in
          [yY][eE][sS]|[yY])
            info "Running: git clean -fdx"
            if ! git -C "$DCLAUDE_REPO_PATH" clean -fdx; then
              error "Failed to clean untracked files from $SOURCE_BRANCH branch"
            fi
            success "Untracked files cleaned"
            ;;
          *)
            warn "Skipping clean. Branch will be created with untracked files present."
            ;;
        esac
      fi

      # Create branch from source branch
      if ! git -C "$DCLAUDE_REPO_PATH" rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
        info "Creating branch $BRANCH_NAME from $SOURCE_BRANCH..."
        git -C "$DCLAUDE_REPO_PATH" branch "$BRANCH_NAME" "$SOURCE_BRANCH"
        success "Branch $BRANCH_NAME created in original repository from $SOURCE_BRANCH"
      else
        info "Branch $BRANCH_NAME already exists in original repository"
      fi

      # Return to original branch if we switched
      if [ "$CURRENT_BRANCH" != "$SOURCE_BRANCH" ]; then
        git -C "$DCLAUDE_REPO_PATH" checkout "$CURRENT_BRANCH"
      fi

      # Clone from the local branch in the original repo (no --depth since it's local)
      # Disable autocrlf to preserve line endings exactly as they are
      info "Cloning from local branch $BRANCH_NAME into $CLONE_PATH..."
      if ! git clone --config core.autocrlf=false --branch "$BRANCH_NAME" "$DCLAUDE_REPO_PATH" "$CLONE_PATH"; then
        error "Failed to clone from local repository"
      fi

      info "Re-initializing git repository in $CLONE_PATH..."
      # Save tracked file list to a temp file before re-initializing
      TEMP_FILE_LIST=$(mktemp)
      git -C "$CLONE_PATH" ls-files > "$TEMP_FILE_LIST"
      EXPECTED_FILE_COUNT=$(wc -l < "$TEMP_FILE_LIST" | tr -d ' ')

      rm -rf "$CLONE_PATH/.git"

      # Backup original .gitattributes and create a temporary one to prevent normalization
      GITATTRIBUTES_BACKUP=""
      if [ -f "$CLONE_PATH/.gitattributes" ]; then
        GITATTRIBUTES_BACKUP="$CLONE_PATH/.gitattributes.dclaude.backup"
        mv "$CLONE_PATH/.gitattributes" "$GITATTRIBUTES_BACKUP"
      fi

      git -C "$CLONE_PATH" init
      # Disable all line ending conversions to preserve files exactly as they are
      git -C "$CLONE_PATH" config core.autocrlf false
      git -C "$CLONE_PATH" config core.eol lf
      git -C "$CLONE_PATH" config core.safecrlf false
      git -C "$CLONE_PATH" checkout -b main

      # Create temporary .gitattributes that treats all files as binary (no normalization)
      echo "* -text" > "$CLONE_PATH/.gitattributes"

      # Add all files from the list (use -f to override .gitignore for files that need it)
      # Process file directly with while-read to avoid subshell issues
      # Note: Use [ -L ] to detect symlinks, even broken ones
      while IFS= read -r file; do
        if [ -n "$file" ]; then
          # Check if file exists (including symlinks, even broken ones)
          if [ -e "$CLONE_PATH/$file" ] || [ -L "$CLONE_PATH/$file" ]; then
            git -C "$CLONE_PATH" add -f -- "$file" 2>/dev/null || true
          fi
        fi
      done < "$TEMP_FILE_LIST"

      # Clean up temp file
      rm -f "$TEMP_FILE_LIST"

      # Restore original .gitattributes before committing
      if [ -n "$GITATTRIBUTES_BACKUP" ] && [ -f "$GITATTRIBUTES_BACKUP" ]; then
        mv "$GITATTRIBUTES_BACKUP" "$CLONE_PATH/.gitattributes"
        # Add the restored .gitattributes to the commit
        git -C "$CLONE_PATH" add -f .gitattributes
      else
        # Remove the temporary .gitattributes if there wasn't an original one
        rm -f "$CLONE_PATH/.gitattributes"
      fi

      git -C "$CLONE_PATH" commit -m "Initial commit"

      # Verify that clone matches the original branch
      CLONE_FILE_COUNT=$(git -C "$CLONE_PATH" ls-files | wc -l | tr -d ' ')
      BRANCH_FILE_COUNT=$(git -C "$DCLAUDE_REPO_PATH" ls-tree -r --name-only "$BRANCH_NAME" | wc -l | tr -d ' ')

      if [ "$CLONE_FILE_COUNT" -eq "$BRANCH_FILE_COUNT" ]; then
        success "Repository initialized successfully (synced with $BRANCH_NAME in original repo)"
        info "Verified: $CLONE_FILE_COUNT files in sync"
      else
        warn "File count mismatch: clone has $CLONE_FILE_COUNT files, branch has $BRANCH_FILE_COUNT files"
        warn "This may be expected if the repository has broken symlinks"
      fi
    else
      warn "Directory $CLONE_PATH already exists. Using existing clone."
    fi

    # Handle container lifecycle
    if [ "$(docker ps -q -f name=^${CONTAINER_NAME}$)" ]; then
      info "Attaching to running container $CONTAINER_NAME..."
      docker attach "$CONTAINER_NAME"
    elif [ "$(docker ps -aq -f name=^${CONTAINER_NAME}$)" ]; then
      info "Starting and attaching to existing container $CONTAINER_NAME..."
      docker start "$CONTAINER_NAME"
      docker attach "$CONTAINER_NAME"
    else
      info "Creating and starting new container $CONTAINER_NAME..."
      docker run -it --name "$CONTAINER_NAME" \
        -v "$HOME/.dclaude:/home/dclaude/.claude" \
        -v "$HOME/.dclaude.json:/home/dclaude/.claude.json" \
        -v "$CLONE_PATH:/src" \
        "$IMAGE_NAME" bash
    fi
    ;;
  rm)
    validate_container_name "$1"
    CONTAINER_NAME=$1

    if [ ! "$(docker ps -aq -f name=^${CONTAINER_NAME}$)" ]; then
      warn "Container $CONTAINER_NAME does not exist"
      exit 0
    fi

    info "Removing container $CONTAINER_NAME..."
    if docker rm -f "$CONTAINER_NAME"; then
      success "Container removed successfully"
    else
      error "Failed to remove container"
    fi
    ;;
  clean)
    validate_container_name "$1"
    check_env_vars "DCLAUDE_CLONE_PATH_PREFIX"

    CONTAINER_NAME=$1
    CLONE_PATH="$DCLAUDE_CLONE_PATH_PREFIX/$CONTAINER_NAME"

    # Remove container if it exists
    if [ "$(docker ps -aq -f name=^${CONTAINER_NAME}$)" ]; then
      info "Removing container $CONTAINER_NAME..."
      docker rm -f "$CONTAINER_NAME" || warn "Failed to remove container (may not exist)"
    else
      warn "Container $CONTAINER_NAME does not exist"
    fi

    # Remove clone directory if it exists
    if [ -d "$CLONE_PATH" ]; then
      info "Deleting repository at $CLONE_PATH..."
      if rm -rf "$CLONE_PATH"; then
        success "Cleanup completed successfully"
      else
        error "Failed to delete repository"
      fi
    else
      warn "Directory $CLONE_PATH does not exist"
      success "Cleanup completed"
    fi
    ;;
  patch)
    validate_container_name "$1"
    check_env_vars "DCLAUDE_REPO_PATH" "DCLAUDE_CLONE_PATH_PREFIX"

    BRANCH_NAME=$1
    REPO_PATH=$DCLAUDE_REPO_PATH
    CLONE_PATH="$DCLAUDE_CLONE_PATH_PREFIX/$BRANCH_NAME"

    # Validate paths
    if [ ! -d "$CLONE_PATH" ]; then
      error "Clone directory $CLONE_PATH does not exist"
    fi

    if [ ! -d "$REPO_PATH/.git" ]; then
      error "Target repository $REPO_PATH is not a git repository"
    fi

    # Find the initial commit in the clone
    INITIAL_COMMIT=$(git -C "$CLONE_PATH" rev-list --max-parents=0 HEAD)
    if [ -z "$INITIAL_COMMIT" ]; then
      error "Could not find initial commit in $CLONE_PATH"
    fi

    # Stage all changes including new files BEFORE checking
    info "Staging all changes in $CLONE_PATH..."
    git -C "$CLONE_PATH" add -A

    # Commit staged changes to ensure working directory matches git state
    if ! git -C "$CLONE_PATH" diff --cached --quiet; then
      info "Committing staged changes in $CLONE_PATH..."
      git -C "$CLONE_PATH" commit -m "Staging changes for patch" --allow-empty
    fi

    # Note: We don't check if current state equals initial state, because
    # we need to sync even if they're the same (e.g., file created then deleted).
    # The target might still have intermediate states that need to be cleaned up.

    # Handle branch creation/switching
    BASE_BRANCH="main"
    if ! git -C "$REPO_PATH" rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
      info "Branch $BRANCH_NAME does not exist. Creating it..."
      git -C "$REPO_PATH" fetch origin || warn "Failed to fetch from origin"
      if git -C "$REPO_PATH" rev-parse --verify origin/main >/dev/null 2>&1; then
        git -C "$REPO_PATH" checkout -b "$BRANCH_NAME" origin/main
        BASE_BRANCH="origin/main"
      elif git -C "$REPO_PATH" rev-parse --verify main >/dev/null 2>&1; then
        git -C "$REPO_PATH" checkout -b "$BRANCH_NAME" main
        BASE_BRANCH="main"
      else
        warn "Neither origin/main nor main branch found, creating branch from current HEAD"
        git -C "$REPO_PATH" checkout -b "$BRANCH_NAME"
        BASE_BRANCH="HEAD"
      fi
      success "Branch created successfully"
    else
      info "Branch $BRANCH_NAME already exists. Checking out..."
      git -C "$REPO_PATH" checkout "$BRANCH_NAME"

      # Determine base branch for reset
      if git -C "$REPO_PATH" rev-parse --verify origin/main >/dev/null 2>&1; then
        BASE_BRANCH="origin/main"
      elif git -C "$REPO_PATH" rev-parse --verify main >/dev/null 2>&1; then
        BASE_BRANCH="main"
      else
        warn "Cannot find base branch to reset from"
        BASE_BRANCH=""
      fi
    fi

    # Create backup before destructive operations
    BACKUP_BRANCH="${BRANCH_NAME}.backup.$(date +%s)"
    info "Creating backup branch $BACKUP_BRANCH for rollback safety..."
    if git -C "$REPO_PATH" branch "$BACKUP_BRANCH" 2>/dev/null; then
      success "Backup branch created"
    else
      warn "Failed to create backup branch, continuing without rollback protection"
      BACKUP_BRANCH=""
    fi

    # Reset branch to base to ensure clean state
    if [ -n "$BASE_BRANCH" ] && [ "$BASE_BRANCH" != "HEAD" ]; then
      info "Resetting $BRANCH_NAME to $BASE_BRANCH for clean sync..."
      if ! git -C "$REPO_PATH" reset --hard "$BASE_BRANCH"; then
        if [ -n "$BACKUP_BRANCH" ]; then
          warn "Reset failed. Rolling back to backup..."
          git -C "$REPO_PATH" checkout -f "$BACKUP_BRANCH" 2>/dev/null || true
          git -C "$REPO_PATH" branch -D "$BRANCH_NAME" 2>/dev/null || true
          git -C "$REPO_PATH" branch -m "$BACKUP_BRANCH" "$BRANCH_NAME" 2>/dev/null || true
        fi
        error "Failed to reset branch. Rolled back to previous state."
      fi
    fi

    # Clean all untracked files and directories (except .git)
    info "Removing all files from $REPO_PATH..."
    if ! git -C "$REPO_PATH" clean -fdx; then
      if [ -n "$BACKUP_BRANCH" ]; then
        warn "Clean failed. Rolling back to backup..."
        git -C "$REPO_PATH" checkout -f "$BACKUP_BRANCH" 2>/dev/null || true
        git -C "$REPO_PATH" branch -D "$BRANCH_NAME" 2>/dev/null || true
        git -C "$REPO_PATH" branch -m "$BACKUP_BRANCH" "$BRANCH_NAME" 2>/dev/null || true
      fi
      error "Failed to clean repository. Rolled back to previous state."
    fi

    # Generate and apply patch with rename detection
    info "Generating patch with rename detection from $CLONE_PATH..."

    # Create temporary patch file
    PATCH_FILE=$(mktemp)

    # Generate patch from initial commit to HEAD
    # -M90%: detect renames with 90% similarity threshold
    # -B: detect complete rewrites
    # --binary: include binary file content
    # --full-index: include full blob hashes for binary files
    if ! git -C "$CLONE_PATH" format-patch -M90% -B --binary --full-index "$INITIAL_COMMIT..HEAD" --stdout > "$PATCH_FILE"; then
      rm -f "$PATCH_FILE"
      if [ -n "$BACKUP_BRANCH" ]; then
        warn "Patch generation failed. Rolling back to backup..."
        git -C "$REPO_PATH" checkout -f "$BACKUP_BRANCH" 2>/dev/null || true
        git -C "$REPO_PATH" branch -D "$BRANCH_NAME" 2>/dev/null || true
        git -C "$REPO_PATH" branch -m "$BACKUP_BRANCH" "$BRANCH_NAME" 2>/dev/null || true
      fi
      error "Failed to generate patch. Rolled back to previous state."
    fi

    # Check if patch is empty (no changes)
    if [ ! -s "$PATCH_FILE" ]; then
      info "No changes to apply (patch is empty)"
      rm -f "$PATCH_FILE"

      # Clean up backup branch since we're done
      if [ -n "$BACKUP_BRANCH" ]; then
        info "Cleaning up backup branch..."
        git -C "$REPO_PATH" branch -D "$BACKUP_BRANCH" 2>/dev/null || warn "Failed to delete backup branch"
      fi

      success "No changes to sync"
      exit 0
    else
      info "Applying patch to $REPO_PATH (without committing)..."

      # Apply patch without committing using git apply
      # --3way: use 3-way merge for conflict resolution
      # --index: apply changes to both working tree and index (stages the changes)
      if git -C "$REPO_PATH" apply --3way --index < "$PATCH_FILE"; then
        success "Patch applied successfully with rename detection!"
        info "Changes are staged and ready for you to commit"
        rm -f "$PATCH_FILE"
      else
        warn "Patch application failed. Attempting fallback to file copy method..."

        # Reset back to clean state for fallback
        if [ -n "$BASE_BRANCH" ] && [ "$BASE_BRANCH" != "HEAD" ]; then
          git -C "$REPO_PATH" reset --hard "$BASE_BRANCH" 2>/dev/null || true
          git -C "$REPO_PATH" clean -fdx 2>/dev/null || true
        fi

        rm -f "$PATCH_FILE"

        # Fallback to file copy method (original implementation)
        info "Using file copy method (rename detection will be lost)..."

        # Check if rsync is available, fall back to tar if not
        if command -v rsync >/dev/null 2>&1; then
          # Use rsync for fast bulk copy, excluding .git directory
          # -a: archive mode (preserves permissions, timestamps, symlinks)
          # --exclude: skip .git directory
          if ! rsync -a --exclude='.git' "$CLONE_PATH/" "$REPO_PATH/"; then
            if [ -n "$BACKUP_BRANCH" ]; then
              warn "Copy failed. Rolling back to backup..."
              git -C "$REPO_PATH" checkout -f "$BACKUP_BRANCH" 2>/dev/null || true
              git -C "$REPO_PATH" branch -D "$BRANCH_NAME" 2>/dev/null || true
              git -C "$REPO_PATH" branch -m "$BACKUP_BRANCH" "$BRANCH_NAME" 2>/dev/null || true
            fi
            error "Failed to copy files. Rolled back to previous state."
          fi
        else
          # Fallback to tar for bulk copy if rsync not available
          if ! (cd "$CLONE_PATH" && tar -cf - --exclude='.git' .) | (cd "$REPO_PATH" && tar -xf -); then
            if [ -n "$BACKUP_BRANCH" ]; then
              warn "Copy failed. Rolling back to backup..."
              git -C "$REPO_PATH" checkout -f "$BACKUP_BRANCH" 2>/dev/null || true
              git -C "$REPO_PATH" branch -D "$BRANCH_NAME" 2>/dev/null || true
              git -C "$REPO_PATH" branch -m "$BACKUP_BRANCH" "$BRANCH_NAME" 2>/dev/null || true
            fi
            error "Failed to copy files. Rolled back to previous state."
          fi
        fi

        warn "Fallback file copy completed, but rename history was not preserved"
      fi
    fi

    success "Sync completed successfully!"

    # Clean up backup branch on success
    if [ -n "$BACKUP_BRANCH" ]; then
      info "Cleaning up backup branch..."
      git -C "$REPO_PATH" branch -D "$BACKUP_BRANCH" 2>/dev/null || warn "Failed to delete backup branch"
    fi

    info "Don't forget to review and commit the changes in $REPO_PATH"
    ;;
  diff)
    validate_container_name "$1"
    check_env_vars "DCLAUDE_REPO_PATH" "DCLAUDE_CLONE_PATH_PREFIX"

    BRANCH_NAME=$1
    REPO_PATH=$DCLAUDE_REPO_PATH
    CLONE_PATH="$DCLAUDE_CLONE_PATH_PREFIX/$BRANCH_NAME"

    # Validate paths
    if [ ! -d "$CLONE_PATH" ]; then
      error "Clone directory $CLONE_PATH does not exist"
    fi

    if [ ! -d "$REPO_PATH/.git" ]; then
      error "Target repository $REPO_PATH is not a git repository"
    fi

    # Stage all changes in clone to see complete state
    info "Analyzing changes in $CLONE_PATH..."
    git -C "$CLONE_PATH" add -A

    # Commit staged changes to ensure working directory matches git state
    if ! git -C "$CLONE_PATH" diff --cached --quiet; then
      git -C "$CLONE_PATH" commit -m "Staging changes for diff" --allow-empty
    fi

    # Find the initial commit in the clone
    INITIAL_COMMIT=$(git -C "$CLONE_PATH" rev-list --max-parents=0 HEAD)
    if [ -z "$INITIAL_COMMIT" ]; then
      error "Could not find initial commit in $CLONE_PATH"
    fi

    # Get list of files in original repo (from the branch with same name)
    if ! git -C "$REPO_PATH" rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
      error "Branch $BRANCH_NAME does not exist in original repository. Run './dclaude.sh run $BRANCH_NAME' first."
    fi

    # Use git diff with rename detection to get changes
    # -M90%: detect renames with 90% similarity threshold
    # --name-status: show file status (A=added, D=deleted, M=modified, R=renamed)
    # --find-renames: enable rename detection
    DIFF_OUTPUT=$(git -C "$CLONE_PATH" diff --name-status --find-renames=90% -M90% -B "$INITIAL_COMMIT" HEAD 2>/dev/null)

    # Parse the diff output
    NEW_FILES=""
    DELETED_FILES=""
    MODIFIED_FILES=""
    RENAMED_FILES=""

    while IFS=$'\t' read -r status file1 file2; do
      case "$status" in
        A*)
          NEW_FILES="${NEW_FILES}${file1}"$'\n'
          ;;
        D*)
          DELETED_FILES="${DELETED_FILES}${file1}"$'\n'
          ;;
        M*)
          MODIFIED_FILES="${MODIFIED_FILES}${file1}"$'\n'
          ;;
        R*)
          # Rename detected: status is R### where ### is similarity percentage
          RENAMED_FILES="${RENAMED_FILES}${file1} -> ${file2}"$'\n'
          ;;
        C*)
          # Copy detected
          NEW_FILES="${NEW_FILES}${file2} (copied from ${file1})"$'\n'
          ;;
      esac
    done <<< "$DIFF_OUTPUT"

    # Display summary
    echo ""
    info "=== Diff Summary for container: $BRANCH_NAME ==="
    echo ""

    # Count changes
    if [ -z "$NEW_FILES" ] || [ "$NEW_FILES" = $'\n' ]; then
      NEW_COUNT=0
    else
      NEW_COUNT=$(echo "$NEW_FILES" | grep -c '[^[:space:]]' || echo 0)
    fi

    if [ -z "$DELETED_FILES" ] || [ "$DELETED_FILES" = $'\n' ]; then
      DELETED_COUNT=0
    else
      DELETED_COUNT=$(echo "$DELETED_FILES" | grep -c '[^[:space:]]' || echo 0)
    fi

    if [ -z "$MODIFIED_FILES" ] || [ "$MODIFIED_FILES" = $'\n' ]; then
      MODIFIED_COUNT=0
    else
      MODIFIED_COUNT=$(echo "$MODIFIED_FILES" | grep -c '[^[:space:]]' || echo 0)
    fi

    if [ -z "$RENAMED_FILES" ] || [ "$RENAMED_FILES" = $'\n' ]; then
      RENAMED_COUNT=0
    else
      RENAMED_COUNT=$(echo "$RENAMED_FILES" | grep -c '[^[:space:]]' || echo 0)
    fi

    # Display counts
    if [ $NEW_COUNT -eq 0 ] && [ $DELETED_COUNT -eq 0 ] && [ $MODIFIED_COUNT -eq 0 ] && [ $RENAMED_COUNT -eq 0 ]; then
      success "No changes detected"
      exit 0
    fi

    echo -e "${GREEN}New files: $NEW_COUNT${NC}"
    echo -e "${RED}Deleted files: $DELETED_COUNT${NC}"
    echo -e "${YELLOW}Modified files: $MODIFIED_COUNT${NC}"
    echo -e "${BLUE}Renamed files: $RENAMED_COUNT${NC}"
    echo ""

    # Show renamed files first (most interesting)
    if [ $RENAMED_COUNT -gt 0 ]; then
      echo -e "${BLUE}Renamed files:${NC}"
      echo "$RENAMED_FILES" | while read -r file; do
        [ -n "$file" ] && echo "  R $file"
      done
      echo ""
    fi

    # Show new files
    if [ $NEW_COUNT -gt 0 ]; then
      echo -e "${GREEN}New files:${NC}"
      echo "$NEW_FILES" | while read -r file; do
        [ -n "$file" ] && echo "  + $file"
      done
      echo ""
    fi

    # Show modified files
    if [ $MODIFIED_COUNT -gt 0 ]; then
      echo -e "${YELLOW}Modified files:${NC}"
      echo "$MODIFIED_FILES" | while read -r file; do
        [ -n "$file" ] && echo "  M $file"
      done
      echo ""
    fi

    # Show deleted files
    if [ $DELETED_COUNT -gt 0 ]; then
      echo -e "${RED}Deleted files:${NC}"
      echo "$DELETED_FILES" | while read -r file; do
        [ -n "$file" ] && echo "  - $file"
      done
      echo ""
    fi

    info "Run './dclaude.sh patch $BRANCH_NAME' to apply these changes"
    ;;
  list|ls)
    info "dclaude containers:"
    echo ""

    # Get all containers with dclaude image
    CONTAINERS=$(docker ps -a --filter "ancestor=$IMAGE_NAME" --format "{{.Names}}\t{{.Status}}" 2>/dev/null)

    if [ -z "$CONTAINERS" ]; then
      warn "No dclaude containers found"
      exit 0
    fi

    # Print header
    printf "%-30s %-20s %-15s\n" "CONTAINER" "STATUS" "CLONE"
    printf "%-30s %-20s %-15s\n" "----------" "------" "-----"

    # Print each container
    echo "$CONTAINERS" | while IFS=$'\t' read -r name status; do
      # Determine status color
      if [[ $status == Up* ]]; then
        status_color=$GREEN
      else
        status_color=$YELLOW
      fi

      # Check if clone directory exists
      if [ -n "$DCLAUDE_CLONE_PATH_PREFIX" ] && [ -d "$DCLAUDE_CLONE_PATH_PREFIX/$name" ]; then
        clone_status="${GREEN}Yes${NC}"
      else
        clone_status="${RED}No${NC}"
      fi

      printf "%-30s ${status_color}%-20s${NC} %b\n" "$name" "$status" "$clone_status"
    done
    ;;
  status)
    validate_container_name "$1"
    check_env_vars "DCLAUDE_CLONE_PATH_PREFIX"

    CONTAINER_NAME=$1
    CLONE_PATH="$DCLAUDE_CLONE_PATH_PREFIX/$CONTAINER_NAME"

    info "Status for container: $CONTAINER_NAME"
    echo ""

    # Container status
    if [ "$(docker ps -q -f name=^${CONTAINER_NAME}$)" ]; then
      echo -e "Container: ${GREEN}Running${NC}"
    elif [ "$(docker ps -aq -f name=^${CONTAINER_NAME}$)" ]; then
      echo -e "Container: ${YELLOW}Stopped${NC}"
    else
      echo -e "Container: ${RED}Not found${NC}"
    fi

    # Clone directory status
    if [ -d "$CLONE_PATH" ]; then
      echo -e "Clone directory: ${GREEN}Exists${NC} ($CLONE_PATH)"

      # Check for uncommitted changes (both staged and unstaged)
      if [ -d "$CLONE_PATH/.git" ]; then
        if git -C "$CLONE_PATH" diff --quiet && git -C "$CLONE_PATH" diff --cached --quiet; then
          echo -e "Changes: ${GREEN}Clean${NC}"
        else
          echo -e "Changes: ${YELLOW}Uncommitted changes present${NC}"
        fi
      fi
    else
      echo -e "Clone directory: ${RED}Not found${NC}"
    fi
    ;;
  help|--help|-h)
    echo "dclaude - Dockerized Claude Code Development Environment"
    echo ""
    echo "Usage: $0 <command> [arguments]"
    echo ""
    echo "Commands:"
    echo "  run <name> [--from <branch>]   Start or attach to a container"
    echo "  rm <name>                      Remove a container"
    echo "  clean <name>                   Remove container and its clone directory"
    echo "  diff <name>                    Preview changes with rename detection"
    echo "  patch <name>                   Apply changes (staged, not committed)"
    echo "  list, ls                       List all dclaude containers"
    echo "  status <name>                  Show detailed status of a container"
    echo "  help                           Show this help message"
    echo ""
    echo "Run Options:"
    echo "  --from <branch>   Create the new branch from specified branch (default: main)"
    echo ""
    echo "Environment Variables:"
    echo "  DCLAUDE_CLONE_PATH_PREFIX   Directory prefix for clones (required)"
    echo "  DCLAUDE_REPO_PATH           Path to main repository (required)"
    echo ""
    echo "Examples:"
    echo "  $0 run feature-branch              # Start from main branch"
    echo "  $0 run feature-branch --from dev   # Start from dev branch"
    echo "  $0 list                            # List all containers"
    echo "  $0 diff feature-branch             # Preview changes with renames"
    echo "  $0 patch feature-branch            # Apply changes (staged)"
    echo "  $0 clean feature-branch            # Clean up everything"
    ;;
  *)
    error "Unknown command: $COMMAND"
    echo "Usage: $0 {run|rm|clean|diff|patch|list|status|help} [arguments]"
    echo "Run '$0 help' for more information"
    exit 1
    ;;
esac
