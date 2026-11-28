-- Owns <C-h/j/k/l> (window/pane focus). <C-\> belongs to toggleterm, so the plugin's "previous pane" mapping is off.
return {
  'christoomey/vim-tmux-navigator',
  cmd = { 'TmuxNavigateLeft', 'TmuxNavigateDown', 'TmuxNavigateUp', 'TmuxNavigateRight', 'TmuxNavigatePrevious', 'TmuxNavigatorProcessList' },
  keys = {
    { '<c-h>', '<cmd>TmuxNavigateLeft<cr>', desc = 'Focus left window/pane' },
    { '<c-j>', '<cmd>TmuxNavigateDown<cr>', desc = 'Focus lower window/pane' },
    { '<c-k>', '<cmd>TmuxNavigateUp<cr>', desc = 'Focus upper window/pane' },
    { '<c-l>', '<cmd>TmuxNavigateRight<cr>', desc = 'Focus right window/pane' },
  },
  init = function() vim.g.tmux_navigator_no_mappings = 1 end,
}
