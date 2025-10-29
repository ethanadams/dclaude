#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse options
NO_CACHE=false
QUIET=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --no-cache)
      NO_CACHE=true
      shift
      ;;
    --quiet|-q)
      QUIET=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Build the dclaude Docker image."
      echo ""
      echo "Options:"
      echo "  --no-cache    Build without using cache"
      echo "  --quiet, -q   Suppress build output"
      echo "  --help, -h    Show this help message"
      exit 0
      ;;
    *)
      echo -e "${RED}Error: Unknown option $1${NC}"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

echo -e "${GREEN}Building dclaude Docker image...${NC}"

# Build command
BUILD_CMD="docker build -t dclaude"

if [ "$NO_CACHE" = true ]; then
  BUILD_CMD="$BUILD_CMD --no-cache"
  echo -e "${YELLOW}Building without cache${NC}"
fi

if [ "$QUIET" = true ]; then
  BUILD_CMD="$BUILD_CMD --quiet"
fi

BUILD_CMD="$BUILD_CMD ."

# Execute build
if $BUILD_CMD; then
  echo -e "${GREEN}Build completed successfully!${NC}"
else
  echo -e "${RED}Build failed!${NC}"
  exit 1
fi