# Dotfiles repository

## Layout

- `home/` is the chezmoi source state.
- `.chezmoiroot` makes `home/` the target-state root.
- `Brewfile` is the Homebrew package manifest.
- `scripts/` contains repository-only bootstrap and worktree utilities.

`chezmoi init` writes `sourceDir` into `~/.config/chezmoi/chezmoi.toml`, so
`chezmoi` commands work from any directory without a `--source` flag.

## Commands

- `./scripts/install.sh`: install Homebrew/chezmoi and apply the configuration.
- `chezmoi diff`: preview target changes.
- `chezmoi apply`: apply the source state and setup scripts.
- `chezmoi update`: pull and apply repository updates.
- `chezmoi verify`: confirm the target matches the source state.
- `scripts/new-worktree.sh <branch> [path]`: create a parallel checkout.

Edit files under `home/`, not through `$HOME` targets. Keep private keys,
credentials, caches, sockets, and runtime databases outside the chezmoi source
state. Do not add machine-specific package arrays; update `Brewfile` instead.

After changing shell or setup scripts, run:

```bash
bash -n scripts/*.sh
chezmoi diff
chezmoi verify
```
