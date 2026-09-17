#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
# proot-env.sh — shared helpers for CLI tools that need a real
# glibc Linux environment on Termux. Turso's official release is
# a Linux_arm64 glibc binary, so it cannot run natively on
# Termux's Bionic libc. We install it inside a proot-distro
# Ubuntu environment and expose a wrapper on the host $PATH.
#
# Public surface:
#   _turso_proot_distro            -> distro name to use (ubuntu)
#   _turso_proot_login [CMD...]     -> run a command inside ubuntu
#   _turso_ensure_proot_env         -> install proot-distro + ubuntu
#   _turso_installed_via_proot      -> true if wrapper + ubuntu exist
#   _turso_wrapper_path             -> host path of the wrapper
#   _turso_install_wrapper          -> write $PREFIX/bin/turso
#   _turso_remove_wrapper           -> delete $PREFIX/bin/turso
#
# This file is sourced by core/tools/db/turso/install.sh.
# Future tools that follow the same pattern (e.g. DBeaver CLI,
# some GitHub-only glibc binaries) can copy this verbatim and
# rename `_turso_` → their tool prefix.
# ============================================================

import "@/utils/log"

_TURSO_PROOT_DISTRO="ubuntu"

# Run a command inside the proot-distro Ubuntu environment.
# Usage: _turso_proot_login [CMD...]
_turso_proot_login() {
	proot-distro login "$_TURSO_PROOT_DISTRO" -- "$@"
}

# Install proot-distro + Ubuntu if missing. No-op otherwise.
_turso_ensure_proot_env() {
	mkdir -p "$(dirname "$LOG_FILE")"

	if ! command -v proot-distro &>/dev/null; then
		log_info "Installing proot-distro (required to run Turso on Termux)"
		if ! yes | pkg install proot-distro &>>"$LOG_FILE"; then
			log_error "Failed to install proot-distro"
			return 1
		fi
		log_success "proot-distro installed"
	fi

	if ! _turso_proot_installed; then
		log_info "Provisioning ${_TURSO_PROOT_DISTRO} proot environment (~200 MB, one-time)"
		if ! proot-distro install "$_TURSO_PROOT_DISTRO" &>>"$LOG_FILE"; then
			log_error "Failed to install ${_TURSO_PROOT_DISTRO} proot"
			return 1
		fi
		log_success "${_TURSO_PROOT_DISTRO} proot installed"
	fi

	return 0
}

# True if the host-side wrapper exists AND the proot env is
# provisioned. We don't probe the upstream binary, because the
# upstream binary lives inside proot where `command -v` from the
# host shell can't see it.
_turso_proot_installed() {
	# `proot-distro list` writes to STDERR (not stdout). It prefixes
	# each distro with "  * " (active marker) or "    " (inactive).
	# Match either to stay robust.
	proot-distro list 2>&1 >/dev/null \
		| grep -qE '^[[:space:]]*\*?[[:space:]]+'"${_TURSO_PROOT_DISTRO}"'$'
}

_turso_installed_via_proot() {
	[[ -x "$PREFIX/bin/turso" ]] && _turso_proot_installed
}

_turso_wrapper_path() {
	echo "$PREFIX/bin/turso"
}

# Write a tiny wrapper at $PREFIX/bin/turso that delegates to the
# binary inside the proot env. The wrapper keeps $PWD, forwards
# stdin/stdout/stderr, and preserves exit codes.
_turso_install_wrapper() {
	local wrapper
	wrapper="$(_turso_wrapper_path)"

	# IMPORTANT: invoke the upstream binary by its absolute path
	# inside Ubuntu (/root/.turso/turso), not by name. proot-distro
	# login bind-mounts $PREFIX/bin into /usr/bin, so a bare `turso`
	# inside Ubuntu resolves back to THIS wrapper, causing infinite
	# recursion and proot-distro's "attempted to run proot-distro in
	# a proot session" refusal.
	cat >"$wrapper" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# core-termux wrapper: forwards to the Turso CLI inside proot-distro
# ubuntu. The upstream Turso release is a glibc Linux binary, so it
# cannot run on Termux's Bionic libc and must execute inside a glibc
# userland.
#
# We MUST invoke the upstream binary by its absolute path inside
# Ubuntu (/root/.turso/turso). proot-distro login bind-mounts
# $PREFIX/bin into /usr/bin, so a bare `turso` would resolve back to
# this wrapper and recurse forever.
exec proot-distro login ubuntu -- /root/.turso/turso "$@"
EOF
	chmod 0755 "$wrapper"
}

# Remove the host-side wrapper. Safe to call multiple times.
_turso_remove_wrapper() {
	local wrapper
	wrapper="$(_turso_wrapper_path)"
	if [[ -e "$wrapper" ]]; then
		rm -f "$wrapper"
	fi
}

# Detect the installed Turso version by running `turso --version`
# through the wrapper. Returns "" if the binary is missing or the
# command fails.
_turso_installed_version() {
	if ! _turso_installed_via_proot; then
		echo ""
		return 1
	fi
	local out
	out=$("$PREFIX/bin/turso" --version 2>/dev/null) || {
		echo ""
		return 1
	}
	# Upstream prints: "Turso CLI v1.0.32"
	echo "$out" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}