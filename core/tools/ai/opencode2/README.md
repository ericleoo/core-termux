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
