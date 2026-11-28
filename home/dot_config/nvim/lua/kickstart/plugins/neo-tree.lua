-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

local load = require('lazyload').add {
  plugins = {
    'https://github.com/nvim-lua/plenary.nvim',
    'https://github.com/MunifTanjim/nui.nvim',
    { src = 'https://github.com/nvim-neo-tree/neo-tree.nvim', version = vim.version.range '3' },
  },
  cmd = 'Neotree',
  config = function()
    require('neo-tree').setup {
      filesystem = {
        window = {
          mappings = {
            ['\\'] = 'close_window',
          },
        },
      },
    }
  end,
}

vim.keymap.set('n', '\\', function()
  load()
  vim.cmd 'Neotree reveal'
end, { desc = 'NeoTree reveal', silent = true })

-- `nvim some/dir` should open Neo-tree (it takes over directory buffers instead of netrw), so load it right away
if vim.fn.argc(-1) == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1 then load() end
