#!/bin/bash
# Test script to validate permission preservation in dclaude patch command
# This creates test files with various permissions and verifies they're preserved

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect platform for cross-platform compatibility
OS_TYPE="$(uname -s)"

# Cross-platform function to get file permissions
get_permissions() {
  local file="$1"
  case "$OS_TYPE" in
    Darwin*)
      stat -f '%OLp' "$file"
      ;;
    Linux*)
      stat -c '%a' "$file"
      ;;
    *)
      echo "Unsupported OS: $OS_TYPE" >&2
      exit 1
      ;;
  esac
}

# Cross-platform function to copy file with permissions
copy_with_permissions() {
  local source="$1"
  local dest="$2"
  cp "$source" "$dest"
  chmod "$(get_permissions "$source")" "$dest"
}

echo "Testing permission preservation on $OS_TYPE..."
echo ""

# Create temporary test directories
TEST_SOURCE=$(mktemp -d)
TEST_DEST=$(mktemp -d)

cleanup() {
  rm -rf "$TEST_SOURCE" "$TEST_DEST"
}
trap cleanup EXIT

# Create test files with various permissions
echo "Creating test files with different permissions..."
echo "test content" > "$TEST_SOURCE/regular_file.txt"
echo "#!/bin/bash" > "$TEST_SOURCE/executable.sh"
echo "#!/usr/bin/env python3" > "$TEST_SOURCE/script.py"
echo "readonly content" > "$TEST_SOURCE/readonly.txt"

# Set different permissions
chmod 644 "$TEST_SOURCE/regular_file.txt"     # rw-r--r--
chmod 755 "$TEST_SOURCE/executable.sh"        # rwxr-xr-x
chmod 750 "$TEST_SOURCE/script.py"            # rwxr-x---
chmod 444 "$TEST_SOURCE/readonly.txt"         # r--r--r--

echo "Source file permissions:"
ls -l "$TEST_SOURCE" | tail -n +2

# Copy files using the same method as dclaude patch command
echo ""
echo "Copying files with permission preservation..."
for file in regular_file.txt executable.sh script.py readonly.txt; do
  copy_with_permissions "$TEST_SOURCE/$file" "$TEST_DEST/$file"
done

echo ""
echo "Destination file permissions:"
ls -l "$TEST_DEST" | tail -n +2

# Verify permissions match
echo ""
echo "Verification:"
ALL_MATCH=true

for file in regular_file.txt executable.sh script.py readonly.txt; do
  SOURCE_PERMS=$(get_permissions "$TEST_SOURCE/$file")
  DEST_PERMS=$(get_permissions "$TEST_DEST/$file")

  if [ "$SOURCE_PERMS" == "$DEST_PERMS" ]; then
    echo -e "${GREEN}✓${NC} $file: $SOURCE_PERMS matches"
  else
    echo -e "${RED}✗${NC} $file: source=$SOURCE_PERMS, dest=$DEST_PERMS (MISMATCH)"
    ALL_MATCH=false
  fi
done

echo ""
if [ "$ALL_MATCH" = true ]; then
  echo -e "${GREEN}All permissions preserved correctly!${NC}"
  exit 0
else
  echo -e "${RED}Some permissions were not preserved!${NC}"
  exit 1
fi
