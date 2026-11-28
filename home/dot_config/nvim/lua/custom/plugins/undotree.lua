return {
  'jiaoshijie/undotree',
  -- Everything not set here uses the plugin's defaults (see `:help undotree-configuration`)
  config = function() require('undotree').setup { ignore_filetype = { 'undotree', 'undotreeDiff', 'qf', 'TelescopePrompt', 'spectre_panel', 'tsplayground' } } end,
  keys = { -- load the plugin only when using it's keybinding:
    { '<leader>u', "<cmd>lua require('undotree').toggle()<cr>" },
  },
}
