# Dotfiles repository

## Layout

- `home/` is the chezmoi source state.
- `.chezmoiroot` makes `home/` the target-state root.
- `Brewfile` is the Homebrew package manifest.
- `dot` is a thin chezmoi wrapper using this checkout as its source directory.
- `scripts/` contains repository-only bootstrap and worktree utilities.

## Commands

- `./scripts/install.sh`: install Homebrew/chezmoi and apply the configuration.
- `./dot diff`: preview target changes.
- `./dot apply`: apply the source state and setup scripts.
- `./dot update`: pull and apply repository updates.
- `./dot verify`: confirm the target matches the source state.
- `scripts/new-worktree.sh <branch> [path]`: create a parallel checkout.

Edit files under `home/`, not through `$HOME` targets. Keep private keys,
credentials, caches, sockets, and runtime databases outside the chezmoi source
state. Do not add machine-specific package arrays; update `Brewfile` instead.

After changing shell or setup scripts, run:

```bash
bash -n dot scripts/*.sh
./dot diff
./dot verify
```
