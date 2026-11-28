local function gh(repo) return 'https://github.com/' .. repo end

-- Useful plugin to show you pending keybinds.
require('lazyload').add {
  plugins = { gh 'folke/which-key.nvim' },
  event = 'VeryLazy',
  config = function()
    require('which-key').setup {
      -- Delay between pressing a key and opening which-key (milliseconds)
      delay = 0,
      icons = { mappings = vim.g.have_nerd_font },
      -- Document existing key chains
      spec = {
        { '<leader>s', group = '[S]earch', mode = { 'n', 'v' } },
        { '<leader>t', group = '[T]oggle / [T]est' },
        { '<leader>d', group = '[D]ebug' },
        { '<leader>h', group = 'Git [H]unk', mode = { 'n', 'v' } }, -- Enable gitsigns recommended keymaps first
        { 'gr', group = 'LSP Actions', mode = { 'n' } },
      },
    }
  end,
}

-- vim: ts=2 sts=2 sw=2 et
