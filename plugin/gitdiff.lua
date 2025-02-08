if vim.g.loaded_your_plugin_name then
	return
end
vim.g.loaded_your_plugin_name = true

-- Set up any commands or autocommands here
vim.api.nvim_create_user_command("HelloPlugin", function()
	require("gitdiff").hello()
end, {})
