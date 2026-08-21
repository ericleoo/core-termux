#!/data/data/com.termux/files/usr/bin/bash

import "@/utils/log"
import "@/utils/version"
import "@/utils/uninstall"
import "@/tools/lang/bun/install"
import "@/utils/walkie"

LOG_FILE="$CORE_CACHE/install_ai.log"

_opencode2_dependencies() {
  loading "Installing dependencies" _opencode2_dependencies_impl
}

_opencode2_dependencies_impl() {
  declare -A DEPS=(
    ["git"]="git"
    ["ripgrep"]="rg"
  )

  local pkg_name bin_name
  for pkg_name in "${!DEPS[@]}"; do
    bin_name="${DEPS[$pkg_name]}"
    if ! command -v "$bin_name" &>/dev/null; then
      if ! yes | pkg install "$pkg_name" &>>"$LOG_FILE"; then
        log_error "Failed to install $pkg_name"
        return 1
      fi
    fi
  done

  _ensure_bun || return 1

  return 0
}

_install_opencode2_bun() {
  loading "Installing OpenCode2" _install_opencode2_bun_impl
}

_install_opencode2_bun_impl() {
  if ! _install_pkg_fallback "@opencode-ai/cli@next"; then
    log_error "Failed to install OpenCode2"
    return 1
  fi

  return 0
}

# Remote version for @next tag — npm registry dist-tag endpoint
_get_remote_opencode2_version() {
  local version=""
  if command -v npm &>/dev/null; then
    version=$(npm view "@opencode-ai/cli@next" version --loglevel=error 2>/dev/null)
  fi
  if [ -z "$version" ] && command -v curl &>/dev/null; then
    version=$(curl -fsSL "https://registry.npmjs.org/@opencode-ai%2Fcli/next" 2>/dev/null | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
    if [ -z "$version" ]; then
      version=$(curl -fsSL "https://registry.npmjs.org/@opencode-ai/cli" 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('dist-tags',{}).get('next',''))" 2>/dev/null)
    fi
  fi
  echo "$version"
}

install_opencode2() {
  if command -v opencode2 &>/dev/null; then
    log_info "OpenCode2 is already installed"
    return 2
  fi

  log_info "Installing OpenCode2..."

  mkdir -p "$(dirname "$LOG_FILE")"

  _opencode2_dependencies || return 1
  _install_opencode2_bun || return 1

  log_success "OpenCode2 installed successfully"
  return 0
}

uninstall_opencode2() {
  _walkie_remove_wrapper opencode2
  if ! command -v opencode2 &>/dev/null; then
    log_info "OpenCode2 is not installed"
    return 2
  fi

  confirm_remove_configs "OpenCode2" \
    "$HOME/.config/opencode" \
    "$HOME/.local/share/opencode" \
    "$HOME/.local/state/opencode"

  log_info "Uninstalling OpenCode2..."
  mkdir -p "$(dirname "$LOG_FILE")"

  loading "Removing OpenCode2" _uninstall_opencode2_impl

  log_success "OpenCode2 uninstalled"
  return 0
}

_uninstall_opencode2_impl() {
  _uninstall_pkg_fallback "@opencode-ai/cli"
  return 0
}

update_opencode2() {
  _check_update_needed "OpenCode2" "$(_get_installed_version opencode2)" "$(_get_remote_opencode2_version)" _update_opencode2
}

_update_opencode2() {
  loading "Updating OpenCode2" _update_opencode2_impl
}

_update_opencode2_impl() {
  if ! _install_pkg_fallback "@opencode-ai/cli@next"; then
    log_error "Failed to update OpenCode2"
    return 1
  fi
  return 0
}

reinstall_opencode2() {
  uninstall_opencode2
  install_opencode2
}
