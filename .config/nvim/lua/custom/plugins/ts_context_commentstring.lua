return {
  'JoosepAlviste/nvim-ts-context-commentstring',
  init = function()
    require('ts_context_commentstring').setup {
      enable_autocmd = false,
    }
  end
}
