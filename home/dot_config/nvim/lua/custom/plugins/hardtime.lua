return {
  'm4xshen/hardtime.nvim',
  dependencies = { 'MunifTanjim/nui.nvim' },
  event = 'VeryLazy',
  cmd = 'Hardtime',
  config = function() require('hardtime').setup {} end,
}
