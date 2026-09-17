#!/data/data/com.termux/files/usr/bin/bash

import "@/utils/log"
import "@/utils/version"
import "@/utils/uninstall"

LOG_FILE="$CORE_CACHE/install_lang.log"

# ===== UV INSTALL PATHS =====
# Primary: native Termux package (aarch64 bionic build) — no proot/glibc needed.
# Fallback: official static-musl binary (verified to run on Android bionic).
UV_FALLBACK_BIN_DIR="$HOME/.local/bin"
UV_FALLBACK_DL_DIR="${CORE_DATA:-$HOME/.local/share/core-termux-data}/uv"
UV_XDG_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
UV_CONFIG_FILE="$UV_XDG_CONFIG/uv/uv.toml"
UV_CONFIG_MARKER="# core-termux: Termux-compatible uv settings"
UV_PATH_MARKER="# core-termux: uv PATH"

# ===== MODE DETECTION =====

_uv_is_pkg() {
  dpkg -s uv 2>/dev/null | grep -q "Status: install ok installed"
}

_uv_is_bin() {
  [ -x "$UV_FALLBACK_BIN_DIR/uv" ]
}

# Resolve the uv command (current shell or static-binary fallback).
_uv_uv_cmd() {
  if command -v uv &>/dev/null; then
    echo "uv"
  else
    echo "$UV_FALLBACK_BIN_DIR/uv"
  fi
}

# ===== VERSION DETECTION =====

_get_uv_remote_version() {
  _get_remote_github_version "astral-sh/uv"
}

_get_uv_remote_version_silent() {
  curl -fsSL "https://api.github.com/repos/astral-sh/uv/releases/latest" 2>/dev/null |
    grep '"tag_name":' | head -1 | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
}

_uv_installed_version() {
  local cmd
  cmd="$(_uv_uv_cmd)"
  "$cmd" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# ===== PKG INSTALL (primary) =====

_install_uv_pkg() {
  loading "Installing uv (Termux package)" _install_uv_pkg_impl
}

_install_uv_pkg_impl() {
  if ! yes | pkg install uv &>>"$LOG_FILE"; then
    log_error "Failed to install uv from Termux repositories"
    return 1
  fi
  return 0
}

_uninstall_uv_pkg() {
  loading "Uninstalling uv (Termux package)" _uninstall_uv_pkg_impl
}

_uninstall_uv_pkg_impl() {
  if ! pkg uninstall uv -y &>>"$LOG_FILE"; then
    log_error "Failed to uninstall uv"
    return 1
  fi
  return 0
}

_update_uv_pkg() {
  loading "Updating uv" _update_uv_pkg_impl
}

_update_uv_pkg_impl() {
  mkdir -p "$(dirname "$LOG_FILE")"
  yes | pkg upgrade uv -y &>>"$LOG_FILE"
}

# ===== STATIC BINARY INSTALL (fallback) =====

_uv_install_deps() {
  local deps=("curl" "tar")
  local dep

  for dep in "${deps[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
      if ! yes | pkg install "$dep" &>>"$LOG_FILE"; then
        log_error "Failed to install $dep"
        return 1
      fi
    fi
  done
  return 0
}

_download_uv_bin() {
  local version="$1"
  loading "Downloading uv v${version} (static musl binary)" _download_uv_bin_impl "$version"
}

_download_uv_bin_impl() {
  local version="$1"
  local arch

  case "$(uname -m)" in
  aarch64 | arm64)
    arch="aarch64"
    ;;
  x86_64 | amd64)
    arch="x86_64"
    ;;
  *)
    log_error "No official uv static binary for $(uname -m)"
    return 1
    ;;
  esac

  local url="https://github.com/astral-sh/uv/releases/download/${version}/uv-${arch}-unknown-linux-musl.tar.gz"
  local extract="$UV_FALLBACK_DL_DIR/uv-${arch}-unknown-linux-musl"

  rm -rf "$extract"
  if ! mkdir -p "$UV_FALLBACK_DL_DIR" "$UV_FALLBACK_BIN_DIR" &>>"$LOG_FILE"; then
    log_error "Failed to create directories for uv"
    return 1
  fi

  if ! curl -fSL -o "$UV_FALLBACK_DL_DIR/uv.tar.gz" "$url" &>>"$LOG_FILE"; then
    log_error "Failed to download uv v${version}"
    return 1
  fi

  if ! tar -xzf "$UV_FALLBACK_DL_DIR/uv.tar.gz" -C "$UV_FALLBACK_DL_DIR" &>>"$LOG_FILE"; then
    log_error "Failed to extract uv"
    return 1
  fi
  rm -f "$UV_FALLBACK_DL_DIR/uv.tar.gz"

  if [ ! -f "$extract/uv" ]; then
    log_error "uv binary not found after extraction"
    return 1
  fi

  cp "$extract/uv" "$UV_FALLBACK_BIN_DIR/uv"
  cp "$extract/uvx" "$UV_FALLBACK_BIN_DIR/uvx"
  chmod 755 "$UV_FALLBACK_BIN_DIR/uv" "$UV_FALLBACK_BIN_DIR/uvx"
  rm -rf "$extract"
  return 0
}

_update_uv_bin() {
  loading "Updating uv (static binary)" _update_uv_bin_impl
}

_update_uv_bin_impl() {
  local version
  version="$(_get_uv_remote_version_silent)"
  if [ -z "$version" ]; then
    log_error "Failed to fetch latest uv version"
    return 1
  fi

  rm -f "$UV_FALLBACK_BIN_DIR/uv" "$UV_FALLBACK_BIN_DIR/uvx"
  _uv_install_deps || return 1
  _download_uv_bin_impl "$version" || return 1
  _uv_setup_path
  _uv_write_config
  return 0
}

# ===== PATH SETUP (static binary mode only) =====

_uv_setup_path() {
  # Ensure the current session finds the fallback binaries
  case ":$PATH:" in
  *":$UV_FALLBACK_BIN_DIR:"*) ;;
  *) export PATH="$UV_FALLBACK_BIN_DIR:$PATH" ;;
  esac

  # Priority: .zshrc > .bashrc > .bash_profile > .profile
  local rc_file=""
  local path_line='export PATH="$HOME/.local/bin:$PATH"'

  if [ -f "$HOME/.zshrc" ]; then
    rc_file="$HOME/.zshrc"
  elif [ -f "$HOME/.bashrc" ]; then
    rc_file="$HOME/.bashrc"
  elif [ -f "$HOME/.bash_profile" ]; then
    rc_file="$HOME/.bash_profile"
  elif [ -f "$HOME/.profile" ]; then
    rc_file="$HOME/.profile"
  else
    rc_file="$HOME/.bashrc"
    touch "$rc_file"
  fi

  # Idempotent: only add if the exact line is not already present
  if grep -qxF "$path_line" "$rc_file" 2>/dev/null; then
    return 0
  fi

  # Ensure the file ends with a newline before appending
  local last_char
  last_char="$(tail -c 1 "$rc_file" 2>/dev/null || echo "")"
  if [ -n "$last_char" ] && [ "$last_char" != $'\n' ]; then
    echo "" >>"$rc_file"
  fi

  echo "$UV_PATH_MARKER" >>"$rc_file"
  echo "$path_line" >>"$rc_file"
  log_info "Added uv PATH to $(basename "$rc_file")"
  return 0
}

_uv_remove_path() {
  local rc_file

  for rc_file in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    if [ -f "$rc_file" ] && grep -qF "$UV_PATH_MARKER" "$rc_file" 2>/dev/null; then
      sed -i "/$UV_PATH_MARKER/d" "$rc_file"
      sed -i '/^export PATH="\$HOME\/.local\/bin:\$PATH"$/d' "$rc_file"
    fi
  done
  return 0
}

# ===== TERMUX COMPATIBILITY CONFIG =====
#
# uv's managed CPython builds (python-build-standalone) target glibc/musl and
# do not run on Android bionic. The settings below make uv fully Termux-
# compatible: it always uses Termux's native Python and never fetches a
# managed interpreter, and it avoids hardlinks (unsupported on Android FUSE).

_uv_write_config() {
  if grep -qF "$UV_CONFIG_MARKER" "$UV_CONFIG_FILE" 2>/dev/null; then
    log_info "uv Termux configuration already in place"
    return 0
  fi

  mkdir -p "$(dirname "$UV_CONFIG_FILE")"

  cat >>"$UV_CONFIG_FILE" <<EOF
$UV_CONFIG_MARKER
# Prefer Termux's native (bionic) Python over managed interpreters.
python-preference = "system"
# Never download managed CPython (glibc/musl builds do not run on bionic).
python-downloads = "never"
# Android FUSE does not support hardlinks; copy instead of hardlinking.
link-mode = "copy"
EOF
  log_success "uv configured for Termux ($UV_CONFIG_FILE)"
  return 0
}

_uv_ensure_system_python() {
  if command -v python3 &>/dev/null; then
    return 0
  fi

  loading "Installing Termux Python (for uv)" _uv_ensure_system_python_impl
  return 0
}

_uv_ensure_system_python_impl() {
  if ! yes | pkg install python &>>"$LOG_FILE"; then
    log_warn "Could not install Termux Python; run 'pkg install python' to give uv a native interpreter"
    return 1
  fi
  return 0
}

# ===== MAIN INSTALL =====

install_uv() {
  if command -v uv &>/dev/null || _uv_is_bin; then
    log_info "uv is already installed"
    # Make sure even a pre-existing uv is fully Termux-compatible.
    _uv_ensure_system_python
    _uv_write_config
    return 2
  fi

  log_info "Installing uv..."
  mkdir -p "$(dirname "$LOG_FILE")"

  if ! _install_uv_pkg; then
    log_warn "Termux package unavailable — falling back to official static binary"
    local version
    version="$(_get_uv_remote_version_silent)"
    if [ -z "$version" ]; then
      log_error "Could not resolve latest uv version"
      return 1
    fi
    _uv_install_deps || return 1
    _download_uv_bin "$version" || return 1
    _uv_setup_path
  fi

  _uv_ensure_system_python
  _uv_write_config

  local version
  version="$(_uv_installed_version)"
  if [ -z "$version" ]; then
    log_error "uv verification failed"
    return 1
  fi

  log_success "uv v${version} installed and configured for Termux"
  return 0
}

# ===== UNINSTALL =====

_uninstall_uv_bin() {
  loading "Uninstalling uv (static binary)" _uninstall_uv_bin_impl
}

_uninstall_uv_bin_impl() {
  rm -f "$UV_FALLBACK_BIN_DIR/uv" "$UV_FALLBACK_BIN_DIR/uvx"
  rm -rf "$UV_FALLBACK_DL_DIR"
  _uv_remove_path
  return 0
}

uninstall_uv() {
  if ! _uv_is_pkg && ! _uv_is_bin; then
    log_info "uv is not installed"
    return 2
  fi

  confirm_remove_configs "uv" \
    "$UV_XDG_CONFIG/uv" \
    "$HOME/.local/share/uv" \
    "$HOME/.cache/uv"

  mkdir -p "$(dirname "$LOG_FILE")"

  if _uv_is_pkg; then
    _uninstall_uv_pkg || return 1
  fi
  if _uv_is_bin; then
    _uninstall_uv_bin || return 1
  fi

  log_success "uv uninstalled"
  return 0
}

# ===== UPDATE =====

update_uv() {
  if _uv_is_pkg; then
    _check_update_needed "uv" "$(_get_installed_pkg_version uv "uv")" "$(_get_remote_pkg_version uv)" _update_uv_pkg
    return $?
  fi

  if _uv_is_bin; then
    local installed_ver remote_ver
    installed_ver="$(_uv_installed_version)"
    remote_ver="$(_get_uv_remote_version)"
    _check_update_needed "uv" "$installed_ver" "$remote_ver" _update_uv_bin
    return $?
  fi

  log_info "uv is not installed"
  return 2
}

# ===== REINSTALL =====

reinstall_uv() {
  uninstall_uv
  install_uv
}
