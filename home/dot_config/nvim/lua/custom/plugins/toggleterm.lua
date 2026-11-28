return {
  'akinsho/toggleterm.nvim',
  version = '*',
  cmd = { 'ToggleTerm', 'TermExec', 'ToggleTermToggleAll' },
  -- Stubs for the `open_mapping` below, which toggleterm creates itself on load
  keys = { { [[<c-\>]], mode = { 'n', 'i' }, desc = 'Toggle terminal' } },
  config = function()
    require('toggleterm').setup {
      size = 20, -- Size of the terminal window
      open_mapping = [[<c-\>]], -- Keybinding to toggle the terminal
      hide_numbers = true, -- Hide number column in terminal
      shade_filetypes = {},
      shade_terminals = true,
      shading_factor = 2, -- Terminal shading intensity
      start_in_insert = true, -- Start in insert mode
      insert_mappings = true, -- Open terminal with insert mode mappings
      terminal_mappings = true, -- Apply key mappings for terminals
      persist_size = true,
      direction = 'float', -- Terminal type (float, horizontal, vertical)
      close_on_exit = true, -- Close terminal when process exits
      shell = vim.o.shell, -- Shell to use
    }
  end,
}
