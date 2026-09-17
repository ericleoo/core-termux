#!/data/data/com.termux/files/usr/bin/bash

import "@/utils/log"
import "@/utils/version"
import "@/utils/uninstall"
import "@/tools/db/turso/proot-env"

LOG_FILE="$CORE_CACHE/install_db.log"

# Why proot-distro and not glibc+proot (Cline's lighter path)?
# ---------------------------------------------------------
# Turso ships only Darwin + glibc Linux binaries. The Linux_arm64
# build is a Go binary whose ELF header references /lib/ld-linux-
# aarch64.so.1 (the glibc loader) AND hardcoded paths like
# /usr/share/lib/zoneinfo and /lib/time/zoneinfo.zip that the
# Termux glibc package does not ship. Go binaries also refuse to
# be repacked with patchelf ("virtual address space underrun")
# because Go uses a fixed-size ELF header.
#
# Cline CLI works under glibc+proot only because it ships as a
# Bun-packed ARM64 binary whose ELF is patchelf-friendly. Turso's
# Go runtime is not.
#
# Conclusion: the only viable path on Termux is to run Turso
# inside a real glibc Linux userland via proot-distro. The host
# $PREFIX/bin/turso wrapper forwards every invocation there.

_turso_run_upstream_install() {
	_turso_proot_login bash -lc '
		set -e
		export DEBIAN_FRONTEND=noninteractive

		# The bare proot-distro ubuntu rootfs ships WITHOUT ca-certificates.
		# The Turso CLI (a Go binary) talks to https://api.turso.tech and
		# fails with "x509: certificate signed by unknown authority" if the
		# bundle is missing. Install + refresh before running the upstream
		# installer so the installer can also curl get.tur.so without TLS
		# errors.
		apt-get update -qq >/tmp/apt-update.log 2>&1 || {
			echo "apt-get update failed:"
			cat /tmp/apt-update.log
			exit 1
		}
		apt-get install -y -qq curl ca-certificates >/tmp/apt-install.log 2>&1 || {
			echo "apt-get install failed:"
			cat /tmp/apt-install.log
			exit 1
		}
		update-ca-certificates >/dev/null 2>&1 || true

		curl -sSfL "https://get.tur.so/install.sh" | bash >/tmp/turso-install.log 2>&1
		rc=$?
		echo "---"
		tail -n 40 /tmp/turso-install.log
		exit $rc
	'
}

_turso_install_impl() {
	mkdir -p "$(dirname "$LOG_FILE")"

	_turso_ensure_proot_env || return 1

	log_info "Running upstream Turso installer inside proot-distro"
	if _turso_run_upstream_install &>>"$LOG_FILE"; then
		:
	else
		log_error "Upstream Turso installer failed (see $LOG_FILE)"
		return 1
	fi

	_turso_install_wrapper || return 1
	log_success "Turso installed and wrapped at $PREFIX/bin/turso"
	return 0
}

install_turso() {
	if _turso_installed_via_proot && "$PREFIX/bin/turso" --version &>>"$LOG_FILE"; then
		# Heal the proot env too: the bare ubuntu rootfs ships
		# without ca-certificates, which silently breaks Turso's
		# HTTPS calls (https://api.turso.tech returns "x509:
		# certificate signed by unknown authority"). A reinstall
		# would fix it, but users rarely rerun install after first
		# success — this branch is their only escape hatch.
		log_info "Turso is already installed; ensuring proot CA bundle is present"
		_turso_proot_login bash -lc '
			set -e
			export DEBIAN_FRONTEND=noninteractive
			if ! [ -f /etc/ssl/certs/ca-certificates.crt ]; then
				apt-get update -qq >/dev/null 2>&1 || true
				apt-get install -y -qq ca-certificates >/dev/null 2>&1 || true
				update-ca-certificates >/dev/null 2>&1 || true
			fi
		' &>>"$LOG_FILE" || true
		log_info "Turso is already installed"
		return 2
	fi

	# Surface *why* proot-distro is required up front, before we
	# spend bandwidth provisioning the Ubuntu rootfs. If the user
	# has no idea what proot-distro is, this line is the explanation.
	log_info "Turso on Termux requires a glibc Linux userland (proot-distro ubuntu)"

	loading "Installing Turso" _turso_install_impl
}

_turso_uninstall_impl() {
	mkdir -p "$(dirname "$LOG_FILE")"

	_turso_remove_wrapper
	log_success "Removed host wrapper $PREFIX/bin/turso"

	if command -v proot-distro &>/dev/null && _turso_proot_installed; then
		_turso_proot_login bash -lc '
			set -e
			# Upstream installer drops the binary at $HOME/.turso/turso.
			# The wrapper maps the host $HOME, so the actual binary lives
			# at /root/.turso inside proot.
			if [ -f /root/.turso/turso ]; then
				rm -f /root/.turso/turso /root/.turso/sqld
			fi
		' &>>"$LOG_FILE"
		log_success "Removed Turso binary from ubuntu proot"
	else
		log_info "Skipped proot cleanup (proot-distro or ubuntu not present)"
	fi
}

uninstall_turso() {
	if ! _turso_installed_via_proot; then
		log_info "Turso is not installed"
		return 2
	fi

	# Auth tokens live at ~/.turso on the *host* (the wrapper maps
	# $HOME from outside proot), so removing the wrapper does not
	# lose the user's `turso auth login` session — we surface that
	# path explicitly and let the user decide.
	confirm_remove_configs "Turso" "$HOME/.turso"

	log_info "Uninstalling Turso..."
	mkdir -p "$(dirname "$LOG_FILE")"

	_turso_uninstall_impl || return 1
	log_success "Turso uninstalled"
	return 0
}

_turso_update_do() {
	mkdir -p "$(dirname "$LOG_FILE")"

	if ! command -v proot-distro &>/dev/null || ! _turso_proot_installed; then
		log_error "Cannot update Turso: proot-distro ubuntu not provisioned"
		return 1
	fi

	# Update strategy:
	# Update strategy:
	# 1. Refresh apt + ensure ca-certificates (needed for Turso's
	#    TLS calls to api.turso.tech; see _turso_run_upstream_install).
	# 2. Re-run the upstream installer — it's idempotent and replaces
	#    the older binary in place at /root/.turso/turso.
	_turso_proot_login bash -lc '
		set -e
		export DEBIAN_FRONTEND=noninteractive
		apt-get update -qq >/dev/null 2>&1 || true
		apt-get install -y -qq curl ca-certificates >/dev/null 2>&1 || true
		update-ca-certificates >/dev/null 2>&1 || true
		curl -sSfL "https://get.tur.so/install.sh" | bash >/tmp/turso-update.log 2>&1
	' &>>"$LOG_FILE" || {
		log_error "Turso update failed (see $LOG_FILE)"
		return 1
	}

	# Belt-and-braces: if the wrapper vanished (e.g. partial install),
	# rewrite it.
	[[ -x "$PREFIX/bin/turso" ]] || _turso_install_wrapper
	log_success "Turso updated"
}

_turso_update_impl() {
	loading "Updating Turso" _turso_update_do
}

update_turso() {
	_check_update_needed "Turso" \
		"$(_turso_installed_version)" \
		"$(_get_remote_github_version "tursodatabase/turso-cli")" \
		_turso_update_impl
}

reinstall_turso() {
	if _turso_installed_via_proot; then
		uninstall_turso
	fi
	install_turso
}