vim.api.nvim_create_autocmd(
  'PackChanged',
  {
    callback = function(ev)
      local name, kind = ev.data.spec.name, ev.data.kind
      if name == 'avante.nvim' and (kind == 'install' or kind == 'update') then
        -- Use `make BUILD_FROM_SOURCE=true` to build from source
        vim.system({ 'make' }, { cwd = ev.data.path }):wait()
      end
    end
  }
)

vim.pack.add({
  {
    src='https://github.com/yetone/avante.nvim',
    version='main'  -- default
  },

  -- Deps
  'https://github.com/nvim-lua/plenary.nvim',
  'https://github.com/MunifTanjim/nui.nvim',

  -- Optional deps
  'https://github.com/MeanderingProgrammer/render-markdown.nvim',
  'https://github.com/hrsh7th/nvim-cmp',
  'https://github.com/nvim-tree/nvim-web-devicons', -- or 'echasnovski/mini.icons'
  'https://github.com/HakonHarnes/img-clip.nvim',
  'https://github.com/zbirenbaum/copilot.lua',
  'https://github.com/folke/snacks.nvim', -- for modern input UI
})

-- Config customizations
require('avante').setup({})
