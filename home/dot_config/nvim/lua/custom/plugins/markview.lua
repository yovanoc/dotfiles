-- Renders markdown in the buffer (replaces render-markdown.nvim). Loaded at startup on purpose: it
-- only registers autocommands/commands, and lazy-loading it would miss the first markdown buffer.
return {
  'OXY2DEV/markview.nvim',
}
