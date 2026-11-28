return {
  'goolord/alpha-nvim',
  -- The dashboard only shows when started without arguments (`:Alpha` opens it any time)
  event = vim.fn.argc(-1) == 0 and 'VimEnter' or nil,
  cmd = 'Alpha',
  config = function() require('alpha').setup(require('alpha.themes.dashboard').config) end,
}
