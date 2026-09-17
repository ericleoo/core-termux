# Turso

Edge SQLite platform with a managed CLI for databases, replicas, and shell access

**Package:** turso (managed via proot-distro ubuntu)
**Author:** DevCoreX
**Repository:** https://github.com/DevCoreXOfficial/core-termux
**Official:** https://docs.turso.tech
**Type:** Database (proot-distro)
**License:** MIT

## Description

Turso is a SQLite-compatible edge database platform built on libSQL.
Its CLI manages databases, replicas, auth tokens, and offers an
interactive SQL shell.

The upstream `Linux_arm64` release is a glibc Go binary. It cannot
run natively on Termux (Android's Bionic libc) and is also not
compatible with the lighter "glibc + proot" path that core-termux
uses for Cline CLI:

- Turso's Go binary references glibc paths that the Termux glibc
  package does not ship (`/usr/share/lib/zoneinfo`,
  `/lib/time/zoneinfo.zip`).
- Go binaries refuse `patchelf --set-interpreter` with "virtual
  address space underrun" because Go uses a fixed-size ELF header.

So `core install db --turso` provisions an Ubuntu proot environment
via `proot-distro` and installs Turso there, then exposes a
`turso` wrapper on the host `$PATH` that forwards every call into
the proot. From the user's perspective, the CLI behaves identically
to a native install.

## Dependencies

- `proot-distro` (auto-installed)
- ~200 MB for the ubuntu proot rootfs (one-time)

## Install

```bash
core install db --turso
```

## Uninstall

```bash
core uninstall db --turso
```

## Update

```bash
core update db --turso
```

## Notes

- First-time install downloads the ubuntu rootfs and the Turso CLI
  (~70 MB). Subsequent installs are idempotent.
- The wrapper at `$PREFIX/bin/turso` invokes the upstream binary by
  absolute path (`/root/.turso/turso` inside Ubuntu). This avoids
  infinite recursion: proot-distro bind-mounts `$PREFIX/bin` into
  `/usr/bin`, so a bare `turso` would resolve back to the wrapper
  itself and proot-distro would refuse with "in a proot session".
- The bare proot-distro ubuntu rootfs ships without `ca-certificates`,
  which silently breaks Turso's HTTPS calls. `core install db --turso`
  installs the bundle inside proot as part of both first-time install
  and the "already installed" heal path, so `turso auth login` works
  out of the box.
- The wrapper at `$PREFIX/bin/turso` forwards the working directory,
  stdin/stdout/stderr, and exit codes to the proot binary.
- Auth tokens live at `~/.turso` on the **host** (the wrapper always
  binds `$HOME` from outside proot), so uninstalling the wrapper does
  not lose your `turso auth login` session.
- `turso shell`, `turso db create`, `turso db show`, and the local
  `sqld` server all work transparently.
- For `turso auth login`, paste the device-code URL the CLI prints
  into any browser — no extra Termux-side setup is needed.