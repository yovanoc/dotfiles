# dotfiles

Personal macOS configuration managed with [chezmoi](https://www.chezmoi.io/).

The repository root is the Git checkout. `.chezmoiroot` points chezmoi at
`home/`, which contains only the desired files for `$HOME`. `Brewfile` remains
the package source of truth, while chezmoi runs its install script when the
manifest changes.

## Bootstrap

```bash
git clone git@github.com:yovanoc/dotfiles.git ~/dotfiles
cd ~/dotfiles
./scripts/install.sh
```

If Homebrew and chezmoi are already installed:

```bash
./dot diff
./dot apply
```

## Daily management

```bash
./dot diff       # preview changes
./dot apply      # apply the source state
./dot update     # pull and apply the latest repository state
./dot verify     # confirm the destination matches the source state
./dot managed    # list managed targets
```

Edit configuration in `home/`, not through files in `$HOME`. Chezmoi replaces
the old Stow links with regular managed files and keeps machine setup scripts
idempotent through `run_onchange_` and `run_once_` source entries.

Private keys, agent state, caches, sockets, and runtime databases stay outside
the chezmoi source state. Worktrees remain ordinary Git worktrees managed by
`scripts/new-worktree.sh`.
