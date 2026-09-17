# uv

Extremely fast Python package installer and Python toolchain, written in Rust

**Package:** uv
**Author:** DevCoreX
**Repository:** https://github.com/DevCoreXOfficial/core-termux
**Official:** https://docs.astral.sh/uv/
**Type:** Language tool (pkg)
**License:** MIT

## Description

uv is an extremely fast Python package installer and resolver. It replaces `pip`, `pipenv`, `poetry`, and `virtualenv` with a single tool, and can install Python itself. On Termux it is installed as a native `aarch64` bionic package, so no proot or glibc is required.

## Termux compatibility

The installer configures uv for a fully Termux-native setup:

- **Native binary** — installed from the Termux repositories (bionic build), no proot/glibc layer. If the package is unavailable, the official static-musl binary is used as a fallback (verified to run on bionic).
- **System Python** — `python-preference = "system"` makes uv use Termux's native Python instead of downloading managed CPython.
- **No managed CPython** — `python-downloads = "never"`. Managed CPython builds target glibc/musl and do not run on Android bionic, so uv is configured to never fetch them.
- **Copy linking** — `link-mode = "copy"` avoids hardlinks, which Android FUSE does not support.
- **Python bootstrap** — if Termux Python is missing, the installer adds it automatically so uv always has a working native interpreter.

Settings are written to `~/.config/uv/uv.toml` (or `$XDG_CONFIG_HOME/uv/uv.toml`).

## Dependencies

- Installed via pkg (native Termux package)
- Requires `python` (Termux) for interpreter-based workflows — installed automatically if missing

## Install

```bash
core install lang --uv
```

## Uninstall

```bash
core uninstall lang --uv
```

## Update

```bash
core update lang --uv
```

## Notes

- Commands: `uv`, `uvx`
- uv 0.12.x from Termux repositories
- `uv venv`, `uv pip`, `uv run` and `uvx` use Termux's native Python
- Use `uv python install` only for interpreters that exist natively — managed CPython is intentionally disabled on Termux
