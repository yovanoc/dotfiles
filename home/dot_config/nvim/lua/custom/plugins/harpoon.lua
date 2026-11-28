-- <leader>a adds the file, <leader>1..4 jump to the first four files, <C-e> opens the list.
-- (<C-h/j/k/l> belong to vim-tmux-navigator.)
local function harpoon() return require 'harpoon' end

local function select(n) return function() harpoon():list():select(n) end end

local function telescope_list()
  vim.cmd.packadd 'telescope.nvim' -- harpoon's list is shown with it; its own spec still sets it up when it lazily loads
  local conf = require('telescope.config').values
  local file_paths = {}
  for _, item in ipairs(harpoon():list().items) do
    table.insert(file_paths, item.value)
  end

  require('telescope.pickers')
    .new({}, {
      prompt_title = 'Harpoon',
      finder = require('telescope.finders').new_table { results = file_paths },
      previewer = conf.file_previewer {},
      sorter = conf.generic_sorter {},
    })
    :find()
end

return {
  'ThePrimeagen/harpoon',
  branch = 'harpoon2',
  dependencies = { 'nvim-lua/plenary.nvim' },
  keys = {
    { '<leader>a', function() harpoon():list():add() end, desc = 'H[a]rpoon: add file' },
    { '<C-e>', telescope_list, desc = 'Harpoon: open list' },
    { '<leader>1', select(1), desc = 'Harpoon: file 1' },
    { '<leader>2', select(2), desc = 'Harpoon: file 2' },
    { '<leader>3', select(3), desc = 'Harpoon: file 3' },
    { '<leader>4', select(4), desc = 'Harpoon: file 4' },
    -- Toggle previous & next buffers stored within Harpoon list
    { '<C-S-P>', function() harpoon():list():prev() end, desc = 'Harpoon: previous file' },
    { '<C-S-N>', function() harpoon():list():next() end, desc = 'Harpoon: next file' },
  },
  config = function() harpoon():setup() end,
}
