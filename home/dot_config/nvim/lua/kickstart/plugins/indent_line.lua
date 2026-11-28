-- Add indentation guides even on blank lines

-- Enable `lukas-reineke/indent-blankline.nvim`
-- See `:help ibl`
require('lazyload').add {
  plugins = { 'https://github.com/lukas-reineke/indent-blankline.nvim' },
  event = 'VeryLazy',
  config = function() require('ibl').setup {} end,
}
