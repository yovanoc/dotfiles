-- [[ Additional Configuration ]]
vim.keymap.set("i", "jj", "<Esc>", {
	desc = "Exit insert mode with jj",
})

vim.keymap.set("n", "<leader>q", "<cmd>q<CR>", {
	desc = "Quit",
})

if vim.fn.has("termguicolors") == 1 then
	vim.opt.termguicolors = true
end
