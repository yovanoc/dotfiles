local function source(repo)
  if repo:match '^https?://' then return repo end
  return 'https://github.com/' .. repo
end

local module_names = {
  ['alpha-nvim'] = 'alpha',
  ['bufferline.nvim'] = 'bufferline',
  ['inc-rename.nvim'] = 'inc_rename',
  ['nvim-ts-context-commentstring'] = 'ts_context_commentstring',
}

local function load_spec(spec)
  if type(spec) ~= 'table' or type(spec[1]) ~= 'string' then return end

  local entries = {}
  local dependencies = spec.dependencies
  if type(dependencies) == 'string' then dependencies = { dependencies } end
  for _, dependency in ipairs(dependencies or {}) do
    if type(dependency) == 'string' then entries[#entries + 1] = { src = source(dependency) } end
  end

  local plugin = { src = source(spec[1]) }
  if spec.branch then plugin.version = spec.branch end
  if spec.version and spec.version ~= '*' then plugin.version = spec.version end
  entries[#entries + 1] = plugin
  vim.pack.add(entries)

  if spec.init then spec.init() end
  if spec.config then
    spec.config(nil, spec.opts or {})
  elseif spec.opts then
    local name = module_names[plugin.src:match '/([^/]+)$'] or plugin.src:match '/([^/]+)$'
    local ok, module = pcall(require, name)
    if ok and type(module.setup) == 'function' then module.setup(spec.opts) end
  end

  for _, mapping in ipairs(spec.keys or {}) do
    if type(mapping) == 'table' and mapping[1] and mapping[2] then
      local opts = {}
      for key, value in pairs(mapping) do
        if type(key) ~= 'number' then opts[key] = value end
      end
      vim.keymap.set('n', mapping[1], mapping[2], opts)
    end
  end
end

local plugins_dir = vim.fs.joinpath(vim.fn.stdpath 'config', 'lua', 'custom', 'plugins')
for file_name, type in vim.fs.dir(plugins_dir, { follow = true }) do
  if (type == 'file' or type == 'link') and file_name:match '%.lua$' and file_name ~= 'init.lua' then
    local module = file_name:gsub('%.lua$', '')
    load_spec(require('custom.plugins.' .. module))
  end
end
