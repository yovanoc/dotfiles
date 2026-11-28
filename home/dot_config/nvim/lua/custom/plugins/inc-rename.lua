return {
  'smjonas/inc-rename.nvim',
  cmd = 'IncRename',
  keys = { { '<leader>rn', ':IncRename ', desc = 'Incremental [R]e[n]ame' } },
  config = function() require('inc_rename').setup() end,
}
