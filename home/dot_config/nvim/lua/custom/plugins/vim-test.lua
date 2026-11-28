-- Mappings live under <leader>t (shared with gitsigns/LSP toggles: <leader>tb, <leader>tw, <leader>th)
return {
  'vim-test/vim-test',
  dependencies = { 'preservim/vimux' },
  cmd = { 'TestNearest', 'TestFile', 'TestSuite', 'TestLast', 'TestVisit' },
  keys = {
    { '<leader>tn', '<cmd>TestNearest<cr>', desc = '[T]est [N]earest' },
    { '<leader>tf', '<cmd>TestFile<cr>', desc = '[T]est [F]ile' },
    { '<leader>ts', '<cmd>TestSuite<cr>', desc = '[T]est [S]uite' },
    { '<leader>tl', '<cmd>TestLast<cr>', desc = '[T]est [L]ast' },
    { '<leader>tv', '<cmd>TestVisit<cr>', desc = '[T]est [V]isit last test file' },
  },
  init = function() vim.g['test#strategy'] = 'vimux' end,
}
