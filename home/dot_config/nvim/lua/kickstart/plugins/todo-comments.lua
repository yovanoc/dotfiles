local function gh(repo) return 'https://github.com/' .. repo end

-- Highlight todo, notes, etc in comments
require('lazyload').add {
  plugins = { gh 'folke/todo-comments.nvim' },
  event = 'VeryLazy',
  config = function() require('todo-comments').setup { signs = false } end,
}

-- vim: ts=2 sts=2 sw=2 et
