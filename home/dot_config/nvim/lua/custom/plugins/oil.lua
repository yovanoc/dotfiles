-- Oil's README advises against lazy-loading it, so it is set up at startup (cheap: ~2 ms)
return {
  'stevearc/oil.nvim',
  config = function()
    require('oil').setup {
      -- Directories keep opening in Neo-tree (kickstart/plugins/neo-tree.lua); Oil is for `:Oil` / <leader>o
      default_file_explorer = false,
    }
    vim.keymap.set('n', '<leader>o', '<cmd>Oil<cr>', { desc = '[O]il: edit the parent directory' })
  end,
}
