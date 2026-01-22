#!/bin/bash
# install.sh - Code Intelligence MCP Server Installer
#
# Usage:
#   ./install.sh [options]
#
# Options:
#   --global        Install globally (requires sudo on Linux)
#   --local         Install to current project only (default)
#   --with-hook     Install Claude Code hook for automatic context injection
#   --skip-deps     Skip dependency installation
#   --help          Show this help
#
# CON-PUB-003: 安装方式统一为 git clone + ./install.sh

set -euo pipefail

VERSION="0.2.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

show_help() {
    cat << EOF
Code Intelligence MCP Server Installer v${VERSION}

Usage:
  ./install.sh [options]

Options:
  --global        Install globally (symlink to /usr/local/bin)
  --local         Install to current project only (default)
  --with-hook     Install Claude Code hook for automatic context injection
  --skip-deps     Skip npm dependency installation
  --help          Show this help

Requirements:
  - Node.js >= 18.0.0
  - npm
  - bash
  - ripgrep (rg)
  - jq

Examples:
  ./install.sh                 # Local install
  ./install.sh --global        # Global install
  ./install.sh --with-hook     # Install with Claude Code hook
  ./install.sh --global --with-hook  # Global install with hook
EOF
}

# Default values
INSTALL_MODE="local"
SKIP_DEPS=false
INSTALL_HOOK=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --global)
            INSTALL_MODE="global"
            shift
            ;;
        --local)
            INSTALL_MODE="local"
            shift
            ;;
        --with-hook)
            INSTALL_HOOK=true
            shift
            ;;
        --skip-deps)
            SKIP_DEPS=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check Node.js version
check_node() {
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed. Please install Node.js >= 18.0.0"
        exit 1
    fi

    local node_version
    node_version=$(node -v | sed 's/v//')
    local major_version
    major_version=$(echo "$node_version" | cut -d. -f1)

    if [[ "$major_version" -lt 18 ]]; then
        log_error "Node.js version $node_version is too old. Please install Node.js >= 18.0.0"
        exit 1
    fi

    log_ok "Node.js $node_version detected"
}

# Check required tools
check_dependencies() {
    local missing=()

    if ! command -v npm &> /dev/null; then
        missing+=("npm")
    fi

    if ! command -v rg &> /dev/null; then
        log_warn "ripgrep (rg) not found. Some features may not work."
    else
        log_ok "ripgrep detected"
    fi

    if ! command -v jq &> /dev/null; then
        log_warn "jq not found. Some features may not work."
    else
        log_ok "jq detected"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        exit 1
    fi
}

# Install npm dependencies
install_npm_deps() {
    if [[ "$SKIP_DEPS" == true ]]; then
        log_info "Skipping npm dependency installation"
        return
    fi

    log_info "Installing npm dependencies..."
    cd "$SCRIPT_DIR"
    npm install --quiet
    log_ok "npm dependencies installed"
}

# Build TypeScript
build_typescript() {
    log_info "Building TypeScript..."
    cd "$SCRIPT_DIR"
    npm run build --quiet
    log_ok "TypeScript build completed"
}

# Make scripts executable
setup_permissions() {
    log_info "Setting up permissions..."
    chmod +x "${SCRIPT_DIR}/bin/ci-search"
    chmod +x "${SCRIPT_DIR}/bin/code-intelligence-mcp"
    chmod +x "${SCRIPT_DIR}/scripts/"*.sh 2>/dev/null || true
    chmod +x "${SCRIPT_DIR}/hooks/"*.sh 2>/dev/null || true
    log_ok "Permissions set"
}

# Global install (symlink)
install_global() {
    log_info "Installing globally..."

    local bin_dir="/usr/local/bin"
    local need_sudo=false

    # Check if we need sudo
    if [[ ! -w "$bin_dir" ]]; then
        need_sudo=true
        log_info "Need sudo to install to $bin_dir"
    fi

    local ln_cmd="ln -sf"
    if [[ "$need_sudo" == true ]]; then
        ln_cmd="sudo ln -sf"
    fi

    $ln_cmd "${SCRIPT_DIR}/bin/code-intelligence-mcp" "${bin_dir}/code-intelligence-mcp"
    $ln_cmd "${SCRIPT_DIR}/bin/ci-search" "${bin_dir}/ci-search"

    log_ok "Installed to $bin_dir"
    log_info "Commands available: code-intelligence-mcp, ci-search"
}

# Local install (add to PATH suggestion)
install_local() {
    log_info "Local installation completed"
    log_info ""
    log_info "To use the commands, add this to your shell profile:"
    log_info "  export PATH=\"${SCRIPT_DIR}/bin:\$PATH\""
    log_info ""
    log_info "Or run directly:"
    log_info "  ${SCRIPT_DIR}/bin/ci-search \"your query\""
}

# Install Claude Code hook
install_hook() {
    log_info "Installing Claude Code hook..."

    local claude_dir="$HOME/.claude"
    local hooks_dir="$claude_dir/hooks"
    local settings_file="$claude_dir/settings.json"
    local hook_source="${SCRIPT_DIR}/hooks/context-inject-global.sh"
    local hook_dest="${hooks_dir}/context-inject-global.sh"

    # Check if hook source exists
    if [[ ! -f "$hook_source" ]]; then
        log_error "Hook script not found: $hook_source"
        return 1
    fi

    # Create hooks directory
    mkdir -p "$hooks_dir"
    log_ok "Hooks directory ready: $hooks_dir"

    # Copy hook script
    cp "$hook_source" "$hook_dest"
    chmod +x "$hook_dest"
    log_ok "Hook script installed: $hook_dest"

    # Update settings.json
    if [[ -f "$settings_file" ]]; then
        # Backup existing settings
        cp "$settings_file" "${settings_file}.backup.$(date +%Y%m%d%H%M%S)"
        log_info "Backed up existing settings.json"

        # Check if hooks already configured
        if grep -q '"hooks"' "$settings_file"; then
            if grep -q 'context-inject-global.sh' "$settings_file"; then
                log_ok "Hook already configured in settings.json"
            else
                log_warn "settings.json already has hooks configured."
                log_warn "Please manually add the following hook configuration:"
                echo ""
                cat << 'HOOK_CONFIG'
{
  "type": "command",
  "command": "~/.claude/hooks/context-inject-global.sh",
  "timeout": 5000
}
HOOK_CONFIG
                echo ""
            fi
        else
            # Add hooks configuration using jq if available
            if command -v jq &>/dev/null; then
                jq '. + {
                    "hooks": {
                        "UserPromptSubmit": [
                            {
                                "matcher": "",
                                "hooks": [
                                    {
                                        "type": "command",
                                        "command": "~/.claude/hooks/context-inject-global.sh",
                                        "timeout": 5000
                                    }
                                ]
                            }
                        ]
                    }
                }' "$settings_file" > "${settings_file}.tmp" && mv "${settings_file}.tmp" "$settings_file"
                log_ok "Updated settings.json with hook configuration"
            else
                log_warn "jq not found. Please manually update $settings_file"
            fi
        fi
    else
        # Create new settings.json
        cat > "$settings_file" << 'EOF'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/context-inject-global.sh",
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
EOF
        log_ok "Created settings.json with hook configuration"
    fi

    echo ""
    log_ok "Hook installation completed!"
    log_info "The hook will automatically inject code context when you use Claude Code."
    log_info ""
    log_info "Features enabled:"
    log_info "  - Automatic code snippet injection"
    log_info "  - Hotspot file detection"
    log_info "  - Index status display"
    log_info "  - MCP tool suggestions"
}

# Main
main() {
    echo "Code Intelligence MCP Server Installer v${VERSION}"
    echo "================================================="
    echo ""

    check_node
    check_dependencies
    install_npm_deps
    build_typescript
    setup_permissions

    if [[ "$INSTALL_MODE" == "global" ]]; then
        install_global
    else
        install_local
    fi

    # Install hook if requested
    if [[ "$INSTALL_HOOK" == true ]]; then
        echo ""
        install_hook
    fi

    echo ""
    log_ok "Installation completed!"
    echo ""
    echo "Quick test:"
    echo "  ci-search --version"
    echo "  code-intelligence-mcp --version"

    if [[ "$INSTALL_HOOK" == false ]]; then
        echo ""
        log_info "Tip: Run with --with-hook to enable automatic context injection"
    fi
}

main "$@"
