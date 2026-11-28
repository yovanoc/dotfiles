-- Every other file in this directory returns one lazy.nvim-style spec (or a list of them, or nil to skip):
--
--   {
--     'owner/repo',               -- GitHub repo, or a full URL
--     dependencies = { 'owner/dep' },
--     branch = 'main', version = '*',  -- optional: `branch`/`version` is passed to vim.pack as `version`
--     event = 'VeryLazy', ft = 'lua', cmd = 'MyCmd',
--     keys = { { '<leader>x', '<cmd>MyCmd<cr>', mode = { 'n', 'v' }, desc = '...' } },
--     init = function() end,      -- runs at startup
--     config = function() end,    -- runs once the plugin is loaded (or `opts` + `main`: `require(main).setup(opts)`)
--   }
--
-- No `event`/`ft`/`cmd`/`keys` means: load at startup. Specs are loaded in sorted filename order.
-- See `lua/lazyload.lua` for how the triggers work.

local function src(repo) return repo:match '^https?://' and repo or 'https://github.com/' .. repo end

---@param spec table
local function add(spec)
  local plugins = {}
  for _, dep in ipairs(type(spec.dependencies) == 'string' and { spec.dependencies } or spec.dependencies or {}) do
    plugins[#plugins + 1] = src(dep)
  end
  local version = spec.branch or (spec.version ~= '*' and spec.version or nil)
  plugins[#plugins + 1] = version and { src = src(spec[1]), version = version } or src(spec[1])

  local config = spec.config
  if not config and spec.opts then
    local main = spec.main or spec[1]:match '[^/]+$'
    config = function() require(main).setup(spec.opts) end
  end

  require('lazyload').add {
    plugins = plugins,
    event = spec.event,
    ft = spec.ft,
    cmd = spec.cmd,
    keys = spec.keys,
    init = spec.init,
    config = config,
  }
end

local dir = vim.fs.joinpath(vim.fn.stdpath 'config', 'lua', 'custom', 'plugins')
local files = vim.fn.glob(vim.fs.joinpath(dir, '*.lua'), false, true)
table.sort(files)
for _, file in ipairs(files) do
  local name = vim.fs.basename(file):gsub('%.lua$', '')
  if name ~= 'init' then
    local specs = require('custom.plugins.' .. name)
    if type(specs) == 'table' then
      for _, spec in ipairs(type(specs[1]) == 'string' and { specs } or specs) do
        add(spec)
      end
    end
  end
end
