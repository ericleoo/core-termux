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
  _opencode2_ensure_glibc || return 1

  return 0
}

_opencode2_ensure_glibc() {
  if [ -x "/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1" ]; then
    return 0
  fi
  log_info "Installing glibc for OpenCode2..."
  if [[ ! -f $PREFIX/etc/apt/sources.list.d/glibc.list ]]; then
    if ! yes | pkg install glibc-repo &>>"$LOG_FILE"; then
      log_warn "Failed to install glibc-repo, continuing anyway"
    fi
  fi
  if [[ ! -f $PREFIX/glibc/lib/libc.so.6 ]]; then
    if ! yes | pkg install glibc &>>"$LOG_FILE"; then
      log_warn "Failed to install glibc, opencode2 may fail to run"
      return 1
    fi
  fi
  return 0
}

_install_opencode2_bun() {
  loading "Installing OpenCode2" _install_opencode2_bun_impl
}

_install_opencode2_bun_impl() {
  # Try standard bun/npm install first
  if _install_pkg_fallback "@opencode-ai/cli@next"; then
    _opencode2_ensure_path
    # If binary is already functional, just ensure wrapper and succeed
    if _opencode2_verify_binary; then
      _opencode2_create_wrapper || _opencode2_link_binary || true
      return 0
    fi
    # Bun reported success but binary missing/broken (common on Android os mismatch) -> fall through to Android workaround
    log_warn "Standard install produced no functional binary, trying Android workaround..."
  else
    log_warn "Standard bun/npm install failed, trying Android workaround..."
  fi

  if ! _opencode2_install_android_npm; then
    log_error "Failed to install OpenCode2"
    return 1
  fi

  _opencode2_ensure_path
  _opencode2_create_wrapper || _opencode2_link_binary || log_warn "opencode2 binary not found in expected locations — try restarting shell or check install log"

  if ! _opencode2_verify_binary; then
    log_warn "opencode2 installed but verification failed — check $LOG_FILE"
  fi

  return 0
}

_opencode2_install_android_npm() {
  _ensure_npm || return 1
  _opencode2_ensure_glibc || true

  local arch
  arch="$(uname -m 2>/dev/null)"
  case "$arch" in
    aarch64|arm64) arch="arm64" ;;
    x86_64|amd64|x64) arch="x64" ;;
    *) arch="arm64" ;;
  esac

  log_info "Installing @opencode-ai/cli@next for linux-$arch (Android workaround)..."
  # Use --force to bypass os mismatch (android vs linux) and --ignore-scripts to avoid failing postinstall
  if ! npm install -g "@opencode-ai/cli@next" --force --ignore-scripts --os=linux --cpu="$arch" --no-audit --no-fund &>>"$LOG_FILE"; then
    log_warn "npm install with --os=linux failed, retrying without platform override..."
    if ! npm install -g "@opencode-ai/cli@next" --force --ignore-scripts --no-audit --no-fund &>>"$LOG_FILE"; then
      return 1
    fi
  fi

  _opencode2_copy_platform_binary || return 1
  return 0
}

_opencode2_copy_platform_binary() {
  local cli_dir="$PREFIX/lib/node_modules/@opencode-ai/cli"
  local src=""

  # Platform binary is nested under cli/node_modules after global install with --ignore-scripts
  src="$(find "$cli_dir/node_modules" "$PREFIX/lib/node_modules" 2>/dev/null -type f -name "opencode2" -size +5M -print 2>/dev/null | head -1)"
  if [ -z "$src" ]; then
    src="$(find "$HOME/.cache" "$HOME/.bun" 2>/dev/null -type f -name "opencode2" -size +5M -print 2>/dev/null | head -1)"
  fi
  if [ -z "$src" ] || [ ! -f "$src" ]; then
    log_error "Platform binary not found after npm install (searched $cli_dir)"
    return 1
  fi

  mkdir -p "$cli_dir/bin"
  if ! cp -f "$src" "$cli_dir/bin/opencode2" 2>>"$LOG_FILE"; then
    log_error "Failed to copy opencode2 binary"
    return 1
  fi
  cp -f "$src" "$cli_dir/bin/opencode2.exe" 2>>"$LOG_FILE" || true
  chmod +x "$cli_dir/bin/opencode2" "$cli_dir/bin/opencode2.exe" 2>>"$LOG_FILE" || true

  _opencode2_patch_execpath || true
  return 0
}

# Byte-patch the bundled resolver inside the compiled Bun binary:
#   process.execPath -> process.argv[0]  (same length, offsets preserved)
# Why: under the Termux glibc wrapper, /proc/self/exe is the LOADER file, so
# opencode's background-service spawn ([execPath, "serve", "--service"])
# becomes `ld-linux-aarch64.so.1 serve ...` -> exit 127. With argv[0] the
# spawn goes through this package's bun shim instead. Never use patchelf on
# these binaries: any section move corrupts Bun's embedded module table.
_opencode2_patch_execpath() {
  local patched=0 f
  for f in \
    "$PREFIX/lib/node_modules/@opencode-ai/cli/bin/opencode2" \
    "$PREFIX/lib/node_modules/@opencode-ai/cli/bin/opencode2.exe" \
    "$PREFIX/lib/node_modules/@opencode-ai/cli/node_modules/@opencode-ai/cli-linux-arm64/bin/opencode2"
  do
    [ -f "$f" ] || continue
    if LC_ALL=C grep -qF 'process.execPath' "$f" 2>/dev/null; then
      if LC_ALL=C sed -i -b 's/process\.execPath/process.argv[0] /g' "$f" 2>>"$LOG_FILE"; then
        log_ok "Patched execPath resolver in ${f##*/bin/} ($f)"
      else
        log_warn "Failed to patch $f (wrapper self-heal will retry at launch)"
      fi
    fi
    patched=1
  done
  mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/opencode2"
  touch "${XDG_CACHE_HOME:-$HOME/.cache}/opencode2/.execpath-stamp" 2>/dev/null || true
  return 0
}

# Installs a `bun` shim that catches opencode2's internal service spawn:
#   bun /$bunfs/root/opencode2 serve --service
# "/$bunfs/root/*" is the compiled binary's virtual entry path and only
# resolves inside its own embedded filesystem, so we strip it and route the
# CLI verb back into our glibc-aware wrapper.
_opencode2_ensure_bun_shim() {
  local shim_dir="${XDG_CACHE_HOME:-$HOME/.cache}/opencode2/shim"
  mkdir -p "$shim_dir"
  cat > "$shim_dir/bun" <<SHIM_EOF
#!/data/data/com.termux/files/usr/bin/bash
while [ \$# -gt 0 ]; do
  case "\$1" in '/\$bunfs/'*) shift ;; *) break ;; esac
done
case "\$1" in
  serve|run|upgrade|--version)
    exec "$PREFIX/bin/opencode2" "\$@" ;;
esac
if command -v bun &>/dev/null; then
  exec "\$(command -v bun)" "\$@"
fi
exit 127
SHIM_EOF
  chmod +x "$shim_dir/bun"
  return 0
}

_opencode2_ensure_path() {
  local bun_bin_dir="/data/data/com.termux/files/home/.cache/.bun/bin"
  case ":$PATH:" in
  *":$bun_bin_dir:"*) ;;
  *) export PATH="$bun_bin_dir:$PATH" ;;
  esac
}

_opencode2_verify_binary() {
  # Check wrapper or real binary works
  if [ -x "$PREFIX/bin/opencode2" ]; then
    if timeout 5 "$PREFIX/bin/opencode2" --version &>/dev/null; then
      return 0
    fi
  fi
  if command -v opencode2 &>/dev/null; then
    if timeout 5 opencode2 --version &>/dev/null; then
      return 0
    fi
  fi
  # Check real binary via glibc directly
  local real=""
  for p in \
    "$PREFIX/lib/node_modules/@opencode-ai/cli/bin/opencode2" \
    "$PREFIX/lib/node_modules/@opencode-ai/cli/bin/opencode2.exe" \
    "$HOME/.cache/.bun/bin/opencode2"
  do
    if [ -f "$p" ]; then
      local sz
      sz=$(stat -c%s "$p" 2>/dev/null || stat -f%z "$p" 2>/dev/null || echo 0)
      if [ "$sz" -gt 1000000 ]; then
        real="$p"
        break
      fi
    fi
  done
  if [ -n "$real" ] && [ -x "/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1" ]; then
    if timeout 5 /data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1 --library-path /data/data/com.termux/files/usr/glibc/lib "$real" --version &>/dev/null; then
      return 0
    fi
  elif [ -n "$real" ]; then
    if timeout 5 "$real" --version &>/dev/null; then
      return 0
    fi
  fi
  return 1
}

_opencode2_create_wrapper() {
  local real=""
  # Prefer npm global binary (most reliable on Android)
  for p in \
    "$PREFIX/lib/node_modules/@opencode-ai/cli/bin/opencode2" \
    "$PREFIX/lib/node_modules/@opencode-ai/cli/bin/opencode2.exe" \
    "$HOME/.cache/.bun/bin/opencode2" \
    "$HOME/.cache/.bun/bin/opencode2.exe"
  do
    if [ -f "$p" ]; then
      local sz
      sz=$(stat -c%s "$p" 2>/dev/null || stat -f%z "$p" 2>/dev/null || echo 0)
      if [ "$sz" -gt 1000000 ]; then
        real="$p"
        break
      fi
    fi
  done
  if [ -z "$real" ]; then
    real="$(find "$PREFIX/lib/node_modules" "$HOME/.cache" "$HOME/.bun" 2>/dev/null -type f -name "opencode2" -size +5M -print 2>/dev/null | head -1)"
  fi
  if [ -z "$real" ] || [ ! -f "$real" ]; then
    # Fallback to link-based resolution
    return 1
  fi

  # Create glibc-aware wrapper at $PREFIX/bin/opencode2 (remove stale symlink first)
  if [ -L "$PREFIX/bin/opencode2" ]; then
    rm -f "$PREFIX/bin/opencode2"
  fi
  mkdir -p "$PREFIX/bin"
  cat > "$PREFIX/bin/opencode2" <<'WRAPPER_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# opencode2 launcher for Termux (glibc build via termux-glibc repo).
#
# Why --argv0: opencode's TUI starts its background server by re-executing
# its CLI entry, and under `ld-linux-aarch64.so.1 <binary>` that resolves to
# loader/virtual paths a child cannot execute. This wrapper (a) keeps the
# bundled execPath resolver pointed at process.argv[0] via a same-length
# byte patch (re-applied after updates), and (b) sets argv[0] to THIS
# wrapper so spawned children re-enter here, where they are routed through
# the glibc loader correctly. A `bun` shim (see _opencode2_ensure_bun_shim)
# additionally catches spawns shaped like:
#   bun /$bunfs/root/opencode2 serve --service
unset LD_PRELOAD
unset LD_LIBRARY_PATH
export GODEBUG=netdns=cgo
export SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem
SELF="__SELF_PATH__"

DBGLOG="${XDG_CACHE_HOME:-$HOME/.cache}/opencode2/wrapper.log"
[ -n "$OPENCODE2_WRAPPER_DEBUG" ] && { mkdir -p "${DBGLOG%/*}"; echo "$(date +%T) cmd:[$0] args:[$*]" >>"$DBGLOG"; }
export PATH="${XDG_CACHE_HOME:-$HOME/.cache}/opencode2/shim:$PATH"

# When re-entered as a spawned child, older chains could leak loader flags
# into argv ("--library-path <dir> <bin>"); strip them defensively.
if [ "$1" = "--library-path" ]; then
  shift 3
fi

REAL=""
for p in \
  "__NPM_DIR__/lib/node_modules/@opencode-ai/cli/bin/opencode2" \
  "__NPM_DIR__/lib/node_modules/@opencode-ai/cli/bin/opencode2.exe" \
  "/data/data/com.termux/files/home/.cache/.bun/bin/opencode2" \
  "/data/data/com.termux/files/home/.cache/.bun/bin/opencode2.exe"
do
  [ "$p" = "$0" ] && continue
  if [ -f "$p" ] && [ -x "$p" ]; then
    sz=$(stat -c%s "$p" 2>/dev/null || stat -f%z "$p" 2>/dev/null || echo 0)
    if [ "$sz" -gt 1000000 ]; then
      REAL="$p"
      break
    fi
  fi
done
if [ -z "$REAL" ]; then
  REAL=$(find __NPM_DIR__/lib/node_modules /data/data/com.termux/files/home/.cache -type f -name "opencode2" -size +10M ! -path "*/bin/opencode2" 2>/dev/null | head -1)
fi
if [ -z "$REAL" ] || [ ! -f "$REAL" ]; then
  echo "opencode2: binary not found. Try: core reinstall ai --opencode2" >&2
  exit 127
fi

# Self-heal after updates replace the binary: re-apply the execPath->argv[0]
# byte patch (same-length, in place; never patchelf Bun binaries).
STAMP="${XDG_CACHE_HOME:-$HOME/.cache}/opencode2/.execpath-stamp"
mkdir -p "${STAMP%/*}"
if [ "$REAL" -nt "$STAMP" ]; then
  if LC_ALL=C grep -qF 'process.execPath' "$REAL" 2>/dev/null; then
    LC_ALL=C sed -i -b 's/process\.execPath/process.argv[0] /g' "$REAL" 2>>"$DBGLOG" || true
  fi
  touch "$STAMP" 2>/dev/null
fi

LOADER="__GLIBC_DIR__/ld-linux-aarch64.so.1"
LIBPATH="__GLIBC_DIR__"
if [ -x "$LOADER" ] && [ -f "$REAL" ]; then
  # argv[0] -> this wrapper, so opencode's internal re-exec comes back here.
  exec "$LOADER" --library-path "$LIBPATH" --argv0 "$SELF" "$REAL" "$@"
else
  exec "$REAL" "$@"
fi
WRAPPER_EOF
  # Replace placeholders with actual paths (use | delimiter to avoid escaping /)
  sed -i "s|__SELF_PATH__|$PREFIX/bin/opencode2|g; s|__NPM_DIR__|$PREFIX|g; s|__GLIBC_DIR__|$PREFIX/glibc/lib|g" "$PREFIX/bin/opencode2"
  chmod +x "$PREFIX/bin/opencode2"
  _opencode2_ensure_bun_shim || true
  command -v opencode2 &>/dev/null
}

_opencode2_link_binary() {
  # Fallback simple symlink for non-Android or when glibc wrapper not needed
  if [ -x "$PREFIX/bin/opencode2" ] && [ -f "$PREFIX/bin/opencode2" ]; then
    # If it's already a wrapper script (contains ld-linux), keep it
    if grep -q "ld-linux" "$PREFIX/bin/opencode2" 2>/dev/null; then
      return 0
    fi
  fi

  local bun_bin_dir=""
  if command -v bun &>/dev/null; then
    bun_bin_dir="$(bun pm bin -g 2>/dev/null || echo "")"
  fi
  local candidates=()
  [ -n "$bun_bin_dir" ] && candidates+=("$bun_bin_dir")
  candidates+=("$HOME/.cache/.bun/bin" "$HOME/.bun/bin")

  local d src=""
  for d in "${candidates[@]}"; do
    if [ -f "$d/opencode2" ]; then
      src="$d/opencode2"
      break
    fi
    if [ -f "$d/opencode2.exe" ]; then
      src="$d/opencode2.exe"
      break
    fi
  done

  if [ -z "$src" ]; then
    src="$(find "$HOME/.cache" "$HOME/.bun" "$PREFIX/lib" 2>/dev/null -type f -name "opencode2" -size +5M -print 2>/dev/null | head -1)"
  fi

  if [ -z "$src" ] && [ -f "$PREFIX/bin/opencode2" ]; then
    return 0
  fi

  if [ -z "$src" ] || [ ! -f "$src" ]; then
    if command -v opencode2 &>/dev/null; then
      local resolved
      resolved="$(command -v opencode2 2>/dev/null || echo "")"
      if [ -n "$resolved" ] && [ "$resolved" != "$PREFIX/bin/opencode2" ] && [ -f "$resolved" ]; then
        mkdir -p "$PREFIX/bin"
        # Prefer wrapper over symlink for glibc binaries
        if [ -x "/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1" ]; then
          _opencode2_create_wrapper
          return $?
        fi
        ln -sf "$resolved" "$PREFIX/bin/opencode2"
        chmod +x "$PREFIX/bin/opencode2" 2>/dev/null || true
      fi
      return 0
    fi
    return 1
  fi

  mkdir -p "$PREFIX/bin"
  if [ -x "/data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1" ]; then
    # Use wrapper for glibc binary
    _opencode2_create_wrapper
  else
    ln -sf "$src" "$PREFIX/bin/opencode2"
    chmod +x "$PREFIX/bin/opencode2" 2>/dev/null || true
  fi
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
  if command -v opencode2 &>/dev/null && _opencode2_verify_binary; then
    log_info "OpenCode2 is already installed"
    return 2
  fi
  # If binary exists but wrapper broken, allow reinstall
  if command -v opencode2 &>/dev/null && ! _opencode2_verify_binary; then
    log_warn "Existing opencode2 binary not functional, reinstalling..."
    rm -f "$PREFIX/bin/opencode2"
  fi

  log_info "Installing OpenCode2..."

  mkdir -p "$(dirname "$LOG_FILE")"

  _opencode2_dependencies || return 1
  _install_opencode2_bun || return 1

  if ! _opencode2_verify_binary; then
    log_warn "opencode2 installed but not yet on PATH — try: export PATH=\"/data/data/com.termux/files/home/.cache/.bun/bin:\$PATH\" && opencode2 --version"
  fi

  log_success "OpenCode2 installed successfully"
  return 0
}

uninstall_opencode2() {
  _walkie_remove_wrapper opencode2
  if ! command -v opencode2 &>/dev/null && [ ! -f "$PREFIX/bin/opencode2" ]; then
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
  # Remove wrapper/symlink we created in $PREFIX/bin
  rm -f "$PREFIX/bin/opencode2"
  # Also clean up npm global leftover binary copies
  rm -f "$PREFIX/lib/node_modules/@opencode-ai/cli/bin/opencode2" 2>/dev/null || true
  # Remove the bun service-spawn shim and launcher cache state
  rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/opencode2/shim" 2>/dev/null || true
  rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/opencode2/.execpath-stamp" 2>/dev/null || true
  # Keep exe as is? npm will recreate on reinstall. Remove dangling if empty.
  return 0
}

update_opencode2() {
  _check_update_needed "OpenCode2" "$(_get_installed_version opencode2)" "$(_get_remote_opencode2_version)" _update_opencode2
}

_update_opencode2() {
  loading "Updating OpenCode2" _update_opencode2_impl
}

_update_opencode2_impl() {
  # Force reinstall via Android workaround if needed
  if ! _install_pkg_fallback "@opencode-ai/cli@next"; then
    if ! _opencode2_install_android_npm; then
      log_error "Failed to update OpenCode2"
      return 1
    fi
  fi
  # Ensure platform binary copied and wrapper refreshed
  if ! _opencode2_verify_binary; then
    _opencode2_copy_platform_binary 2>/dev/null || true
  fi
  _opencode2_ensure_path
  _opencode2_create_wrapper || _opencode2_link_binary || true
  return 0
}

reinstall_opencode2() {
  uninstall_opencode2
  install_opencode2
}
