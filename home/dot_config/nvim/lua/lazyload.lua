-- Minimal lazy-loading on top of the builtin `vim.pack` (there is no lazy.nvim here).
--
-- Plugins are always registered (and installed when missing) with `vim.pack.add`, but kept off the
-- 'runtimepath' until a trigger fires, then `:packadd`ed. No trigger => loaded right away.
-- Updating/removing plugins is plain `vim.pack`, see the top of `lua/pack.lua`.
--
--   local load = require('lazyload').add {
--     plugins = { 'https://github.com/org/dep', { src = 'https://github.com/org/main', version = 'main' } },
--     event = 'VeryLazy', -- any autocommand event(s); 'VeryLazy' = once the UI is up (not fired in headless Nvim)
--     ft = 'lua', -- filetype(s)
--     cmd = 'MyCommand', -- stub command(s): load the plugin, then re-run the real command
--     keys = { { '<leader>x', rhs, desc = '...', mode = { 'n', 'v' } } }, -- stub mappings, `rhs` is mapped once loaded
--     lazy = true, -- no trigger: loads only when the returned `load` is called
--     init = function() end, -- runs now, before anything is loaded
--     config = function() end, -- runs right after the plugins were loaded
--   }
--   load() -- idempotent, loads it now

local M = {}

local added = {} ---@type table<string, true>

local function list(v)
  if v == nil then return {} end
  return type(v) == 'table' and not v.src and v or { v }
end

local function name_of(p)
  if type(p) == 'table' and p.name then return p.name end
  return ((type(p) == 'table' and p.src or p):gsub('%.git$', ''):match '[^/]+$')
end

---@class lazyload.Spec
---@field plugins (string|vim.pack.Spec)[] dependencies first, the main plugin last
---@field event? string|string[]
---@field ft? string|string[]
---@field cmd? string|string[]
---@field lazy? boolean
---@field keys? table[]
---@field init? fun()
---@field config? fun()

---@param spec lazyload.Spec
---@return fun() load
function M.add(spec)
  local fresh, names = {}, {}
  for _, p in ipairs(spec.plugins) do
    local name = name_of(p)
    names[#names + 1] = name
    if not added[name] then
      added[name] = true
      fresh[#fresh + 1] = p
    end
  end
  -- A no-op `load` keeps plugins off the 'runtimepath' until `:packadd` below
  if #fresh > 0 then vim.pack.add(fresh, { load = function() end }) end

  local done, undo = false, {}
  local function load()
    if done then return end
    for _, f in ipairs(undo) do
      f()
    end
    local ok, err = pcall(function()
      for _, name in ipairs(names) do
        -- `:packadd!` during startup (as vim.pack's own default `load`), plain `:packadd` afterwards
        vim.cmd.packadd { vim.fn.escape(name, ' '), bang = vim.v.vim_did_init ~= 1, magic = { file = false } }
      end
      if spec.config then spec.config() end
    end)
    done = ok -- on failure `load()` can be called again (packadd is idempotent)
    if not ok then
      vim.notify(('Failed to load %s:\n%s'):format(names[#names], err), vim.log.levels.ERROR)
      return
    end
    for _, key in ipairs(list(spec.keys)) do
      if key[2] then vim.keymap.set(key.mode or 'n', key[1], key[2], { desc = key.desc, silent = key.silent, expr = key.expr }) end
    end
  end

  if spec.init then spec.init() end

  local events, fts, cmds, keys = list(spec.event), list(spec.ft), list(spec.cmd), list(spec.keys)
  if #events + #fts + #cmds + #keys == 0 and not spec.lazy then
    load()
    return load
  end

  local group = vim.api.nvim_create_augroup('lazyload-' .. names[#names], { clear = true })
  undo[#undo + 1] = function() pcall(vim.api.nvim_del_augroup_by_id, group) end

  ---@param event string
  ---@param pattern? string|string[]
  local function on(event, pattern)
    vim.api.nvim_create_autocmd(event, {
      group = group,
      pattern = pattern,
      once = true,
      callback = function(ev)
        load()
        -- The plugin's own autocommands for this event were created too late to run: replay it for this buffer
        if vim.api.nvim_buf_is_valid(ev.buf) then
          vim.api.nvim_buf_call(ev.buf, function() vim.api.nvim_exec_autocmds(event, { pattern = ev.match, modeline = false }) end)
        end
      end,
    })
  end

  for _, event in ipairs(events) do
    if event == 'VeryLazy' then
      local function later() vim.schedule(load) end
      if vim.v.vim_did_enter == 1 then
        later()
      else
        vim.api.nvim_create_autocmd('UIEnter', { group = group, once = true, callback = later })
      end
    else
      on(event)
    end
  end
  if #fts > 0 then on('FileType', fts) end

  for _, cmd in ipairs(cmds) do
    vim.api.nvim_create_user_command(cmd, function(o)
      load() -- replaces this stub with the plugin's own command
      vim.cmd { cmd = cmd, args = o.fargs, bang = o.bang, mods = o.smods, range = o.range > 0 and { o.line1, o.line2 } or nil }
    end, { nargs = '*', bang = true, range = true })
    undo[#undo + 1] = function() pcall(vim.api.nvim_del_user_command, cmd) end
  end

  for _, key in ipairs(keys) do
    for _, mode in ipairs(list(key.mode or 'n')) do
      vim.keymap.set(mode, key[1], function()
        load() -- replaces this stub with the real mapping
        vim.api.nvim_feedkeys(vim.keycode(key[1]), 'm', false)
      end, { desc = key.desc })
      undo[#undo + 1] = function() pcall(vim.keymap.del, mode, key[1]) end
    end
  end

  return load
end

return M
