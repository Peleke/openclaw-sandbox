#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Usage
usage() {
    echo "Usage: $0 <version>"
    echo ""
    echo "Example: $0 0.4.0"
    echo ""
    echo "This script will:"
    echo "  1. Validate version format (semver)"
    echo "  2. Check you're on main branch"
    echo "  3. Check working directory is clean"
    echo "  4. Verify CHANGELOG.md has entry"
    echo "  5. Commit, tag, and push"
    echo ""
    echo "GitHub Actions will then create the release."
    exit 1
}

# Validate semver format
validate_version() {
    local version=$1
    if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}Error: Invalid version format '$version'${NC}"
        echo "Expected: MAJOR.MINOR.PATCH (e.g., 0.4.0)"
        exit 1
    fi
}

# Check branch
check_branch() {
    local branch
    branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ $branch != "main" ]]; then
        echo -e "${YELLOW}Warning: You're on branch '$branch', not 'main'${NC}"
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Check working directory
check_clean() {
    if [[ -n $(git status --porcelain) ]]; then
        echo -e "${RED}Error: Working directory is not clean${NC}"
        echo "Commit or stash your changes first."
        git status --short
        exit 1
    fi
}

# Check CHANGELOG has entry
check_changelog() {
    local version=$1
    if ! grep -q "## \[$version\]" CHANGELOG.md; then
        echo -e "${YELLOW}CHANGELOG.md doesn't have an entry for [$version]${NC}"
        echo ""
        echo "Please add release notes. Opening CHANGELOG.md..."
        echo ""
        ${EDITOR:-vim} CHANGELOG.md

        # Re-check after editing
        if ! grep -q "## \[$version\]" CHANGELOG.md; then
            echo -e "${RED}Error: Still no CHANGELOG entry for [$version]${NC}"
            exit 1
        fi
    fi
    echo -e "${GREEN}CHANGELOG.md has entry for [$version]${NC}"
}

# Update CHANGELOG links
update_changelog_links() {
    local version=$1
    local prev_version
    prev_version=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "")

    # Update Unreleased link to compare against new version
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|\[Unreleased\]:.*|[Unreleased]: https://github.com/Peleke/openclaw-sandbox/compare/v$version...HEAD|" CHANGELOG.md
    else
        sed -i "s|\[Unreleased\]:.*|[Unreleased]: https://github.com/Peleke/openclaw-sandbox/compare/v$version...HEAD|" CHANGELOG.md
    fi

    # Add new version link if not present
    if ! grep -q "^\[$version\]:" CHANGELOG.md; then
        if [[ -n "$prev_version" ]]; then
            local link="[$version]: https://github.com/Peleke/openclaw-sandbox/compare/v$prev_version...v$version"
        else
            local link="[$version]: https://github.com/Peleke/openclaw-sandbox/releases/tag/v$version"
        fi

        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "/^\[Unreleased\]:/a\\
$link
" CHANGELOG.md
        else
            sed -i "/^\[Unreleased\]:/a$link" CHANGELOG.md
        fi
    fi
}

# Main
main() {
    if [[ $# -ne 1 ]]; then
        usage
    fi

    local version=$1

    echo "=========================================="
    echo "  openclaw-sandbox release script"
    echo "=========================================="
    echo ""

    # Validations
    validate_version "$version"
    check_branch
    check_clean

    # Check and update changelog
    check_changelog "$version"
    update_changelog_links "$version"

    # Show diff if changelog was updated
    if [[ -n $(git status --porcelain CHANGELOG.md) ]]; then
        echo ""
        echo "CHANGELOG.md updated:"
        git diff CHANGELOG.md
        echo ""
    fi

    # Confirm
    echo -e "Ready to release ${GREEN}v$version${NC}"
    read -p "Tag and push? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting."
        git checkout -- CHANGELOG.md 2>/dev/null || true
        exit 1
    fi

    # Commit changelog if modified
    if [[ -n $(git status --porcelain CHANGELOG.md) ]]; then
        git add CHANGELOG.md
        git commit -m "docs: update CHANGELOG for v$version"
    fi

    # Tag
    git tag -a "v$version" -m "Release v$version"

    # Push
    echo ""
    echo -e "${GREEN}Pushing to origin...${NC}"
    git push origin main
    git push origin "v$version"

    echo ""
    echo -e "${GREEN}=========================================="
    echo "  Release v$version initiated!"
    echo "==========================================${NC}"
    echo ""
    echo "GitHub Actions will create the release."
    echo "Monitor: https://github.com/Peleke/openclaw-sandbox/actions"
}

main "$@"
