return {
  'stevearc/oil.nvim',
  cmd = 'Oil',
  keys = { { '<leader>o', '<cmd>Oil<cr>', desc = '[O]il: edit the parent directory' } },
  config = function()
    require('oil').setup {
      -- Directories keep opening in Neo-tree (kickstart/plugins/neo-tree.lua); Oil is for `:Oil` / <leader>o
      default_file_explorer = false,
    }
  end,
}
