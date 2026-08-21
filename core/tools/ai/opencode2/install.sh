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

  _opencode2_ensure_path
  _opencode2_link_binary || log_warn "opencode2 binary not found in expected bun/npm locations — try restarting shell or check install log"

  return 0
}

_opencode2_ensure_path() {
  local bun_bin_dir="/data/data/com.termux/files/home/.cache/.bun/bin"
  case ":$PATH:" in
  *":$bun_bin_dir:"*) ;;
  *) export PATH="$bun_bin_dir:$PATH" ;;
  esac
}

_opencode2_link_binary() {
  # If $PREFIX/bin/opencode2 already valid, we're done (fast path)
  if [ -x "$PREFIX/bin/opencode2" ] && [ -f "$PREFIX/bin/opencode2" ]; then
    return 0
  fi

  local bun_bin_dir=""
  if command -v bun &>/dev/null; then
    bun_bin_dir="$(bun pm bin -g 2>/dev/null || echo "")"
  fi
  # bun pm bin -g may not exist / may error — fallback to known dirs
  local candidates=()
  [ -n "$bun_bin_dir" ] && candidates+=("$bun_bin_dir")
  candidates+=("$HOME/.cache/.bun/bin" "$HOME/.bun/bin")

  local d src=""
  for d in "${candidates[@]}"; do
    if [ -f "$d/opencode2" ]; then
      src="$d/opencode2"
      break
    fi
    # some packages ship .exe wrapper (observed bin/opencode2.exe)
    if [ -f "$d/opencode2.exe" ]; then
      src="$d/opencode2.exe"
      break
    fi
  done

  if [ -z "$src" ]; then
    # last resort: search common npm/bun caches
    src="$(find "$HOME/.cache" "$HOME/.bun" "$PREFIX/lib" 2>/dev/null -type f -name "opencode2" -print -quit)"
  fi

  # npm global prefix bin is $PREFIX/bin — already in PATH, check there
  if [ -z "$src" ] && [ -f "$PREFIX/bin/opencode2" ]; then
    return 0
  fi

  if [ -z "$src" ] || [ ! -f "$src" ]; then
    # Still check if binary became available via PATH after _ensure_path (e.g. bun bin exported)
    if command -v opencode2 &>/dev/null; then
      # Create symlink for persistence even if now resolvable via bun bin
      local resolved
      resolved="$(command -v opencode2 2>/dev/null || echo "")"
      if [ -n "$resolved" ] && [ "$resolved" != "$PREFIX/bin/opencode2" ] && [ -f "$resolved" ]; then
        mkdir -p "$PREFIX/bin"
        ln -sf "$resolved" "$PREFIX/bin/opencode2"
        chmod +x "$PREFIX/bin/opencode2" 2>/dev/null || true
      fi
      return 0
    fi
    return 1
  fi

  # Ensure $PREFIX/bin linker — makes binary available even if bun bin not in PATH
  mkdir -p "$PREFIX/bin"
  ln -sf "$src" "$PREFIX/bin/opencode2"
  chmod +x "$PREFIX/bin/opencode2" 2>/dev/null || true

  # Verify
  command -v opencode2 &>/dev/null
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
  # Clean up symlink we may have created in $PREFIX/bin
  if [ -L "$PREFIX/bin/opencode2" ]; then
    local target
    target="$(readlink -f "$PREFIX/bin/opencode2" 2>/dev/null || readlink "$PREFIX/bin/opencode2" 2>/dev/null || echo "")"
    case "$target" in
    *".cache/.bun/bin/"*|*".bun/bin/"*|*".cache/bun/bin/"*|*"/@opencode-ai/"*)
      rm -f "$PREFIX/bin/opencode2"
      ;;
    *)
      # If binary no longer exists via package manager, remove dangling link
      if [ ! -e "$PREFIX/bin/opencode2" ]; then
        rm -f "$PREFIX/bin/opencode2"
      fi
      # Also handle non-symlink shim we created (should be symlink, but be safe)
      if [ -f "$PREFIX/bin/opencode2" ] && ! command -v npm &>/dev/null; then
        :
      fi
      ;;
    esac
  elif [ -f "$PREFIX/bin/opencode2" ] && [ ! -e "$PREFIX/bin/opencode2" ]; then
    rm -f "$PREFIX/bin/opencode2"
  fi
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
  _opencode2_ensure_path
  _opencode2_link_binary || true
  return 0
}

reinstall_opencode2() {
  uninstall_opencode2
  install_opencode2
}
