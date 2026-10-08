# dotfiles

Public personal configuration managed with [chezmoi](https://www.chezmoi.io/).

`home/` is the source of truth. Only files deliberately added there are
managed; chezmoi does not copy the rest of `$HOME` automatically.

Managed configuration currently includes:

- `Brewfile`
- zsh, tmux, and Git configuration
- Neovim at `home/dot_config/nvim`
- the reviewed agent configuration at `home/dot_agents`
- selected Pi files: settings, subagents, roles, coordinator policy, fallback,
  RTK/quota extensions, public instructions and theme
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

### Update global agent skills

```bash
./scripts/update-skills.sh
```

Runs `npx skills update --global`, imports `~/.agents/skills` and its lockfile,
rebuilding the chezmoi skills subtree so deleted files disappear from the repo too.
Home is authoritative for this import; review uncommitted source-only edits first.
Review `git diff` and `git status` before committing; it does not apply or commit.

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
subagents, roles, coordinator policy, fallback, RTK/quota extensions, public
instructions and the theme are managed.
Auth tokens, sessions, caches, repositories, npm packages, and logs remain
local. See [Pi model fallback](docs/model-fallback.md) for the managed routing
and update procedure.

## Testing Pi extensions

Pi provides its SDK at runtime; this repository has no dependency installation
or development-link setup. Run the quota fixtures, or test through the installed
Pi loader with fake credentials and mocked HTTP:

```bash
node scripts/test-pi-quota-status.mjs
node scripts/test-pi-quota-status.mjs --runtime \
  "$(brew --prefix pi-coding-agent)/libexec/lib/node_modules/@earendil-works/pi-coding-agent"
```

These checks do not apply configuration or contact quota/inference endpoints.
Editor typing: the root `tsconfig.json` maps the SDK, `typebox`, Node types and
`@narumitw/pi-usage` types straight to the installed Homebrew Pi and `~/.pi`
packages (assumes Homebrew's `/opt/homebrew` prefix and a `~/dotfiles` checkout;
edit the paths otherwise). No repository `node_modules`, dependency manifest,
lockfile, copies or fake declarations are used. Open the repository root in
VS Code; if diagnostics are stale, run **TypeScript: Restart TS Server**.
**TypeScript: Go to Project Configuration** should open this root `tsconfig.json`.
Check it with `node /opt/homebrew/lib/node_modules/typescript/bin/tsc -p . --noEmit`.

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
