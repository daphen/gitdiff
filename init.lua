local M = {}
local Popup = require("nui.popup")
local Layout = require("nui.layout")

-- Function to get files with merge conflicts
local function get_conflict_files()
	local files = vim.fn.systemlist("git diff --name-only --diff-filter=U")
	-- Remove any ANSI escape sequences and trim whitespace
	local result = {}
	for _, file in ipairs(files) do
		-- Clean up the filename by removing ANSI codes and trimming
		file = file:gsub("\27%[[0-9;]*m", ""):gsub("^%s*(.-)%s*$", "%1")
		if file ~= "" then
			table.insert(result, { file = file, text = file })
		end
	end
	return result
end

-- Function to get conflict chunks from a file
local function get_conflict_chunks(filepath)
	-- Check if file exists
	if vim.fn.filereadable(filepath) == 0 then
		vim.notify("Cannot read file: " .. filepath, vim.log.levels.ERROR)
		return {}
	end

	local content = vim.fn.readfile(filepath)
	local chunks = {}
	local current_chunk = { ours = {}, theirs = {} }
	local in_conflict = false
	local section = nil

	for _, line in ipairs(content) do
		if line:match("^<<<<<<< ") then
			in_conflict = true
			section = "ours"
		elseif line:match("^=======$") and in_conflict then
			section = "theirs"
		elseif line:match("^>>>>>>> ") and in_conflict then
			in_conflict = false
			section = nil
			table.insert(chunks, current_chunk)
			current_chunk = { ours = {}, theirs = {} }
		elseif in_conflict and section then
			table.insert(current_chunk[section], line)
		end
	end

	return chunks
end

function M.show_merge_tool()
	local conflict_files = get_conflict_files()
	if #conflict_files == 0 then
		vim.notify("No files with merge conflicts found", vim.log.levels.INFO)
		return
	end

	-- Create file list menu
	local file_menu = Popup({
		enter = true,
		focusable = true,
		border = {
			style = "single",
			text = {
				top = "Conflict Files",
				top_align = "center",
			},
		},
		buf_options = {
			modifiable = true,
			readonly = false,
		},
	})

	-- Create left popup (our changes)
	local popup_one = Popup({
		enter = false,
		focusable = true,
		border = {
			style = "single",
			text = {
				top = "Our Changes",
				top_align = "center",
			},
		},
		buf_options = {
			modifiable = true,
			readonly = false,
		},
	})

	-- Create right popup (their changes)
	local popup_two = Popup({
		enter = false,
		focusable = true,
		border = {
			style = "single",
			text = {
				top = "Incoming Changes",
				top_align = "center",
			},
		},
		buf_options = {
			modifiable = true,
			readonly = false,
		},
	})

	-- Create the layout with all three components
	local layout = Layout(
		{
			position = "50%",
			size = {
				width = "90%",
				height = "80%",
			},
		},
		Layout.Box({
			Layout.Box(file_menu, { size = "20%" }),
			Layout.Box({
				Layout.Box(popup_one, { size = "50%" }),
				Layout.Box(popup_two, { size = "50%" }),
			}, { dir = "row", size = "80%" }),
		}, { dir = "row" })
	)

	-- Current state
	local current_file = nil
	local current_chunks = {}
	local current_chunk_index = 1

	-- Function to display current chunk
	local function display_current_chunk()
		if #current_chunks == 0 then
			return
		end

		local chunk = current_chunks[current_chunk_index]
		vim.api.nvim_buf_set_lines(popup_one.bufnr, 0, -1, false, chunk.ours)
		vim.api.nvim_buf_set_lines(popup_two.bufnr, 0, -1, false, chunk.theirs)

		-- Update titles
		vim.api.nvim_win_set_config(popup_one.winid, {
			title = string.format("Our Changes (%d/%d)", current_chunk_index, #current_chunks),
		})
		vim.api.nvim_win_set_config(popup_two.winid, {
			title = string.format("Incoming Changes (%d/%d)", current_chunk_index, #current_chunks),
		})
	end

	-- Function to load file conflicts
	local function load_file(filepath)
		if not filepath or filepath == "" then
			vim.notify("Invalid filepath", vim.log.levels.ERROR)
			return
		end

		-- Get the full path
		local full_path = vim.fn.getcwd() .. "/" .. filepath

		if vim.fn.filereadable(full_path) == 0 then
			vim.notify("Cannot read file: " .. full_path, vim.log.levels.ERROR)
			return
		end

		current_file = full_path
		current_chunks = get_conflict_chunks(full_path)
		current_chunk_index = 1
		display_current_chunk()
	end

	-- Mount layout
	layout:mount()

	-- Set up file list
	local file_lines = {}
	for _, file in ipairs(conflict_files) do
		table.insert(file_lines, file.text)
	end
	vim.api.nvim_buf_set_lines(file_menu.bufnr, 0, -1, false, file_lines)

	-- Navigation functions
	local function next_chunk()
		if current_chunk_index < #current_chunks then
			current_chunk_index = current_chunk_index + 1
			display_current_chunk()
		end
	end

	local function prev_chunk()
		if current_chunk_index > 1 then
			current_chunk_index = current_chunk_index - 1
			display_current_chunk()
		end
	end

	local function next_file()
		local line = vim.api.nvim_win_get_cursor(file_menu.winid)[1]
		if line < #conflict_files then
			vim.api.nvim_win_set_cursor(file_menu.winid, { line + 1, 0 })
			load_file(conflict_files[line + 1].file)
		end
	end

	local function prev_file()
		local line = vim.api.nvim_win_get_cursor(file_menu.winid)[1]
		if line > 1 then
			vim.api.nvim_win_set_cursor(file_menu.winid, { line - 1, 0 })
			load_file(conflict_files[line - 1].file)
		end
	end

	-- Track window focus
	local focused_popup = file_menu

	-- Function to switch focus
	local function switch_focus(target_popup)
		if vim.api.nvim_win_is_valid(target_popup.winid) then
			vim.api.nvim_set_current_win(target_popup.winid)
			focused_popup = target_popup
		end
	end

	-- Add keymaps for all popups
	for _, popup in ipairs({ popup_one, popup_two, file_menu }) do
		-- Close with q
		vim.keymap.set("n", "q", function()
			layout:unmount()
		end, {
			buffer = popup.bufnr,
			noremap = true,
			silent = true,
		})

		-- Navigate chunks with j/k
		vim.keymap.set("n", "j", next_chunk, {
			buffer = popup.bufnr,
			noremap = true,
			silent = true,
		})
		vim.keymap.set("n", "k", prev_chunk, {
			buffer = popup.bufnr,
			noremap = true,
			silent = true,
		})

		-- Navigate files with Ctrl+j/k
		vim.keymap.set("n", "<C-j>", next_file, {
			buffer = popup.bufnr,
			noremap = true,
			silent = true,
		})
		vim.keymap.set("n", "<C-k>", prev_file, {
			buffer = popup.bufnr,
			noremap = true,
			silent = true,
		})

		-- Window navigation with Ctrl+h/l
		vim.keymap.set("n", "<C-h>", function()
			if focused_popup == popup_two then
				switch_focus(popup_one)
			elseif focused_popup == popup_one then
				switch_focus(file_menu)
			end
		end, {
			buffer = popup.bufnr,
			noremap = true,
			silent = true,
		})

		vim.keymap.set("n", "<C-l>", function()
			if focused_popup == file_menu then
				switch_focus(popup_one)
			elseif focused_popup == popup_one then
				switch_focus(popup_two)
			end
		end, {
			buffer = popup.bufnr,
			noremap = true,
			silent = true,
		})

		-- Block other Ctrl+direction keys to prevent leaving the popup
		vim.keymap.set("n", "<C-w>", "<Nop>", {
			buffer = popup.bufnr,
			noremap = true,
			silent = true,
		})
	end

	-- Load the first file automatically
	if #conflict_files > 0 then
		load_file(conflict_files[1].file)
		-- Focus the file menu initially
		switch_focus(file_menu)
	end

	-- Add autocmd to prevent focus loss
	vim.api.nvim_create_autocmd("WinLeave", {
		callback = function(ev)
			local leaving_win = ev.window
			-- If leaving one of our popup windows, try to prevent it
			if vim.tbl_contains({ file_menu.winid, popup_one.winid, popup_two.winid }, leaving_win) then
				vim.schedule(function()
					if vim.api.nvim_win_is_valid(focused_popup.winid) then
						vim.api.nvim_set_current_win(focused_popup.winid)
					end
				end)
			end
		end,
	})
end

return M
