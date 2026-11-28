-- Linting

require('lazyload').add {
  plugins = { 'https://github.com/mfussenegger/nvim-lint' },
  event = 'VeryLazy',
  config = function()
    local lint = require 'lint'
    lint.linters_by_ft = {
      markdown = { 'markdownlint' }, -- Installed by mason (see `ensure_installed` in lspconfig.lua)
      typescript = { 'eslint_d' },
      typescriptreact = { 'eslint_d' },
    }

    -- To allow other plugins to add linters to require('lint').linters_by_ft,
    -- instead set linters_by_ft like this:
    -- lint.linters_by_ft = lint.linters_by_ft or {}
    -- lint.linters_by_ft['markdown'] = { 'markdownlint' }
    --
    -- However, note that this will enable a set of default linters,
    -- which will cause errors unless these tools are available:
    -- {
    --   clojure = { "clj-kondo" },
    --   dockerfile = { "hadolint" },
    --   inko = { "inko" },
    --   janet = { "janet" },
    --   json = { "jsonlint" },
    --   markdown = { "vale" },
    --   rst = { "vale" },
    --   ruby = { "ruby" },
    --   terraform = { "tflint" },
    --   text = { "vale" }
    -- }
    --
    -- You can disable the default linters by setting their filetypes to nil:
    -- lint.linters_by_ft['clojure'] = nil
    -- lint.linters_by_ft['dockerfile'] = nil
    -- lint.linters_by_ft['inko'] = nil
    -- lint.linters_by_ft['janet'] = nil
    -- lint.linters_by_ft['json'] = nil
    -- lint.linters_by_ft['markdown'] = nil
    -- lint.linters_by_ft['rst'] = nil
    -- lint.linters_by_ft['ruby'] = nil
    -- lint.linters_by_ft['terraform'] = nil
    -- lint.linters_by_ft['text'] = nil

    -- Only run linters whose executable exists. `try_lint` raises "ENOENT" on every BufEnter/InsertLeave otherwise
    -- (e.g. before mason finished installing `eslint_d`), which shows up as recurring errors.
    local function try_lint()
      local available = vim.tbl_filter(function(name)
        local linter = lint.linters[name]
        local cmd = type(linter) == 'table' and linter.cmd
        if type(cmd) == 'function' then cmd = cmd() end
        return type(cmd) ~= 'string' or vim.fn.executable(cmd) == 1
      end, lint.linters_by_ft[vim.bo.filetype] or {})
      if #available > 0 then lint.try_lint(available) end
    end

    -- Create autocommand which carries out the actual linting
    -- on the specified events.
    local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
    vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
      group = lint_augroup,
      callback = function()
        -- Only run the linter in buffers that you can modify in order to
        -- avoid superfluous noise, notably within the handy LSP pop-ups that
        -- describe the hovered symbol using Markdown.
        if vim.bo.modifiable then try_lint() end
      end,
    })
    if vim.bo.modifiable then try_lint() end -- the current buffer was entered before this loaded
  end,
}
