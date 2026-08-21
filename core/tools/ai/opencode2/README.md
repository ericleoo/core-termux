# OpenCode2

Next-generation OpenCode — preview channel (`@opencode-ai/cli@next`).

**Package:** @opencode-ai/cli@next  
**Author:** DevCoreX  
**Repository:** https://github.com/DevCoreXOfficial/core-termux  
**Official:** https://opencode.ai  
**Type:** AI coding agent (bun global package)  
**License:** MIT
**Binary:** `opencode2`

## Description

OpenCode2 is the preview / next channel of [OpenCode](https://opencode.ai) (`opencode`). It tracks the `@next` dist-tag of `@opencode-ai/cli` so you can run the upcoming version side-by-side with the stable `opencode` binary (which is installed from GitHub releases). Useful for testing new features before they hit stable.

Normally installable via:

```bash
bun add -g @opencode-ai/cli@next  # provides `opencode2`
```

Core-Termux wraps that with dependency handling and `core` lifecycle commands.

## Dependencies

- bun (installed automatically via `_ensure_bun`)
- git, ripgrep

## Install

```bash
core install ai --opencode2
```

## Uninstall

```bash
core uninstall ai --opencode2
```

## Update

```bash
core update ai --opencode2
```

Checks `opencode2 --version` against the `@next` dist-tag on the npm registry.

## Notes

- Installed globally via `bun add -g @opencode-ai/cli@next` (falls back to `npm install -g` if bun is unavailable).
- Binary name is `opencode2` — does not conflict with stable `opencode`.
- Shares config locations with `opencode` (`~/.config/opencode`, `~/.local/share/opencode`); uninstall will prompt before removing them.

## Termux / Android technical notes

The shipped binary is a glibc-linked Bun-compiled ELF. On Termux it cannot
execute directly (ELF interpreter `/lib/ld-linux-aarch64.so.1` does not
exist), so core-termux launches it via the termux-glibc loader
(`$PREFIX/glibc/lib/ld-linux-aarch64.so.1 --library-path …`). That breaks
opencode2's background-service bootstrap, which re-executes its own CLI
entry (`… serve --service`) and resolves that entry to loader-internal
paths (`/proc/self/exe` = the loader file; `/$bunfs/root/opencode2` = the
compiled binary's virtual module path). The child then dies with
exit 127 / `Module not found`.

The install therefore applies three coordinated fixes (all handled
automatically by `install.sh` / the generated `$PREFIX/bin/opencode2`):

1. **Byte patch (same-length, in place)** — the bundled JS resolver inside
   the binary is changed from `process.execPath` to `process.argv[0]`
   (identical byte length, so Bun's embedded module table stays intact).
   The wrapper re-applies it after every update (stamp file in
   `~/.cache/opencode2/`).
2. **`--argv0` launch** — the loader starts the app with `argv[0]` pointing
   at the wrapper script, so any self re-exec re-enters the wrapper and gets
   routed through the loader correctly.
3. **`bun` shim** (`~/.cache/opencode2/shim/`, prepended to PATH inside the
   wrapper) — catches the internal `bun /$bunfs/root/opencode2 serve
   --service` spawn, strips the virtual path, and routes the CLI verb into
   the wrapper. Any other `bun` invocation is forwarded untouched.

Never `patchelf` these binaries: moving the ELF interpreter string shifts
sections and corrupts Bun's embedded module table (instant segfault).
