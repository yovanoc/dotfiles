-- autopairs
-- https://github.com/windwp/nvim-autopairs

require('lazyload').add {
  plugins = { 'https://github.com/windwp/nvim-autopairs' },
  event = 'VeryLazy',
  config = function() require('nvim-autopairs').setup {} end,
}
