# dotfiles

Public personal configuration managed with [chezmoi](https://www.chezmoi.io/).

`home/` is the source of truth. Only files deliberately added there are
managed; chezmoi does not copy the rest of `$HOME` automatically.

Managed configuration currently includes:

- `Brewfile`
- zsh, tmux, and Git configuration
- Neovim at `home/dot_config/nvim`
- the reviewed agent configuration at `home/dot_agents`
- selected Pi files: settings, subagents, public instructions, RTK extension,
  and theme
- safe SSH defaults; private hosts stay in `~/.ssh/config.local`
- selected `.config` files and small setup scripts

- `new-worktree` at `home/dot_local/bin`, on `PATH` via `~/.local/bin`

OpenCode is intentionally not managed here. Its live configuration remains
local and outside the source state.

## Bootstrap

```bash
git clone git@github.com:yovanoc/dotfiles.git ~/dotfiles
cd ~/dotfiles
./scripts/install.sh
```

The first run prompts for name, email, and GPG signing key (empty disables
commit signing) and writes the answers to `~/.config/chezmoi/chezmoi.toml`.
That file is per-machine and never committed, so a work machine can use a
different identity from the same repository. It also sets `sourceDir`, so
`chezmoi` commands work from any directory without a `--source` flag.

On a brand-new machine there is no GPG key yet, so answer the signing-key
prompt with an empty value, then create the keys:

```bash
./scripts/new-machine-keys.sh   # SSH + GPG keys, uploaded to GitHub via gh
chezmoi init --prompt           # record the new signing key
chezmoi apply
```

That script is idempotent and never overwrites an existing key, so importing
keys from a backup instead works too: import first, then skip the script.

The installer is interactive. On an existing machine, preview first:

```bash
chezmoi diff
chezmoi apply --interactive
```

Do not use `--force` until you have reviewed every change.

## Daily workflow

```bash
chezmoi diff                         # preview target changes
chezmoi apply --interactive          # accept changes one by one
chezmoi re-add ~/.zshrc              # copy an edited target back into home/
chezmoi verify                       # fail if target and source differ
chezmoi managed                      # list managed targets
chezmoi unmanaged                    # find candidates that are not managed
```

### Adopt configuration manually

The cleaned `~/.agents` tree has been copied to `home/dot_agents` and excludes
macOS metadata files. Review that candidate before committing it publicly.
For future additions, add only the file or subtree you have reviewed.
`--secrets error` makes chezmoi refuse obvious secrets instead of merely
warning:

```bash
chezmoi add --prompt --secrets error ~/.agents/skills/<skill>/SKILL.md
chezmoi add --prompt --secrets error ~/.config/<tool>/config.toml
chezmoi add --prompt --secrets error ~/.ssh/config
```

Do not add future `.agents`, `.pi`, or `.config` content blindly. Pi
credentials (`auth.json`), trust state, caches, sessions, npm dependencies,
repositories, logs, and machine-specific state stay unmanaged. After adding
something, review the generated file under `home/` before committing it.

## How the public/private split works

Chezmoi translates source names into home-directory targets:

- `home/dot_zshrc` → `~/.zshrc`
- `home/private_dot_ssh/private_config` → `~/.ssh/config`
- `home/private_dot_pi/private_agent/settings.json` →
  `~/.pi/agent/settings.json`

The public SSH config includes `~/.ssh/config.local`. That ignored local file
holds private hosts and machine-specific options. `~/.zshrc` sources
`~/.config/zsh/local.zsh` when it exists, as a hook for machine-specific
shell settings. Neither local file is in the repo.

The `.pi` source is an allowlist, not a copy of the directory: only settings,
subagents, public instructions, the RTK extension, and the theme are managed.
Auth tokens, sessions, caches, repositories, npm packages, and logs remain
local.

## Secrets and private machine state

- `private_` in a chezmoi source name only sets restrictive file permissions;
  it does **not** encrypt the file.
- For a file that genuinely belongs in the repository, configure chezmoi's
  age encryption and add it with `chezmoi add --encrypt`:

  ```bash
  mkdir -p ~/.config/chezmoi
  chezmoi age-keygen -o ~/.config/chezmoi/key.txt
  chezmoi age-keygen -y ~/.config/chezmoi/key.txt
  chezmoi edit-config
  ```

  Set `encryption = "age"` and the generated identity/recipient in the
  config. Keep the age identity outside this repository and commit only the
  resulting `encrypted_...age` source file.
- Never commit SSH or GPG private keys. Generate/import them per machine
  using the system keychain or a password manager. Manage only safe SSH
  configuration and public keys here.
- Keep per-machine values in ignored local files such as
  `~/.ssh/config.local` and `~/.config/zsh/local.zsh`, or use a separate
  private repository.

The public/private boundary is intentional: source entries in `home/` are
shared state; everything else remains unmanaged until explicitly adopted.
