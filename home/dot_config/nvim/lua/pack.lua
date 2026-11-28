-- [[ Managing plugins with `vim.pack` ]]
-- `vim.pack` is Neovim's builtin plugin manager (see `:help vim.pack`, `:help vim.pack-examples`).
-- There is no `:Lazy` command: everything is a plain Lua call.
--
--  Add     put `vim.pack.add { 'https://github.com/owner/repo' }` in a plugin file (or, for a lazy-loaded
--          one, a spec in `lua/custom/plugins/`) and restart Nvim: it is cloned at the revision from
--          `nvim-pack-lock.json`, or at its `version` (a branch, tag, commit or `vim.version.range`)
--  Update  `:lua vim.pack.update()` downloads updates and opens a review buffer in a new tabpage:
--          `:write` applies them, `:quit` discards them. Then `:restart`.
--          Just look, without downloading: `:lua vim.pack.update(nil, { offline = true })`
--  Remove  delete its `vim.pack.add` spec, `:restart`, then `:lua vim.pack.del { 'plugin-name' }`
--          (removes it from disk and from the lockfile). Inactive plugins:
--          `:lua =vim.iter(vim.pack.get()):filter(function(p) return not p.active end):map(function(p) return p.spec.name end):totable()`
--  Restore `nvim-pack-lock.json` (commit it!) pins every plugin's revision. A fresh machine installs exactly
--          those on startup; to move an existing one back to the lockfile (e.g. after `git checkout` of it):
--          `:lua vim.pack.update(nil, { target = 'lockfile' })`, then review and `:write`
--
--  Plugins are installed on the very first start, which can take a minute. Some need a build step after install/update
--  (below, see `:help vim.pack-events`).

local function run_build(name, cmd, cwd)
  local result = vim.system(cmd, { cwd = cwd }):wait()
  if result.code ~= 0 then
    local stderr = result.stderr or ''
    local stdout = result.stdout or ''
    local output = stderr ~= '' and stderr or stdout
    if output == '' then output = 'No output from build command.' end
    vim.notify(('Build failed for %s:\n%s'):format(name, output), vim.log.levels.ERROR)
  end
end

-- This autocommand runs after a plugin is installed or updated and
--  runs the appropriate build command for that plugin if necessary.
--
-- See `:help vim.pack-events`
vim.api.nvim_create_autocmd('PackChanged', {
  callback = function(ev)
    local name = ev.data.spec.name
    local kind = ev.data.kind
    if kind ~= 'install' and kind ~= 'update' then return end

    if name == 'telescope-fzf-native.nvim' and vim.fn.executable 'make' == 1 then
      run_build(name, { 'make' }, ev.data.path)
      return
    end

    if name == 'LuaSnip' then
      if vim.fn.has 'win32' ~= 1 and vim.fn.executable 'make' == 1 then run_build(name, { 'make', 'install_jsregexp' }, ev.data.path) end
      return
    end

    if name == 'nvim-treesitter' then
      if not ev.data.active then vim.cmd.packadd 'nvim-treesitter' end
      vim.cmd 'TSUpdate'
      return
    end
  end,
})

-- vim: ts=2 sts=2 sw=2 et
