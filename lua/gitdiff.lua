local M = {}
local Popup = require("nui.popup")
local Layout = require("nui.layout")

-- Function to get files with merge conflicts
local function get_conflict_files()
	-- First check if we're in a merge state
	local is_merging = vim.fn.filereadable(vim.fn.getcwd() .. "/.git/MERGE_HEAD") == 1
	if not is_merging then
		return {}
	end

	-- Get files with conflicts using git ls-files
	local files = vim.fn.systemlist("git ls-files --unmerged | cut -f2 | sort -u")

	-- Fallback to diff if ls-files doesn't work
	if #files == 0 then
		files = vim.fn.systemlist("git diff --name-only --diff-filter=U")
	end

	local result = {}
	local seen = {}

	for _, file in ipairs(files) do
		-- More comprehensive cleanup of the filename
		file = file
			:gsub("\27%[%d*[mBK]", "") -- Remove common ANSI sequences
			:gsub("\27%([0-9A-Z]", "") -- Remove other escape sequences
			:gsub("[%z\1-\31]", "") -- Remove control characters (null byte and ASCII 1-31)
			:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace

		-- Avoid duplicates
		if file ~= "" and not seen[file] then
			-- Check if the file actually has conflict markers
			local has_conflict_markers = false
			if vim.fn.filereadable(file) == 1 then
				local content = vim.fn.readfile(file)
				for _, line in ipairs(content) do
					if line:match("^<<<<<<< ") then
						has_conflict_markers = true
						break
					end
				end
			end

			-- Only add files that still have conflict markers
			if has_conflict_markers then
				seen[file] = true
				table.insert(result, { file = file, text = file })
			end
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

M.current_layout = nil

-- Global function to force close the merge tool
function M.force_close_merge_tool()
	if M.current_layout and type(M.current_layout.unmount) == "function" then
		M.current_layout:unmount()
		vim.notify("Merge tool forcefully closed", vim.log.levels.INFO)
		M.merge_tool_active = false
		M.current_layout = nil
	end
end

function M.show_merge_tool()
	-- Check if we're in a git repository first
	local is_git_repo_cmd = vim.fn.system("git rev-parse --is-inside-work-tree 2>/dev/null")
	local is_git_repo = is_git_repo_cmd:match("true")
	local is_merging = vim.fn.filereadable(vim.fn.getcwd() .. "/.git/MERGE_HEAD") == 1

	-- Get conflict files first
	local conflict_files = get_conflict_files() or {}

	if not is_git_repo then
		vim.notify("Not in a git repository", vim.log.levels.ERROR)
		return
	end

	if #conflict_files == 0 and is_merging then
		vim.notify("All conflicts are resolved. You can commit the changes.", vim.log.levels.INFO)
		return
	-- If not in a merge state, notify the user
	elseif not is_merging then
		vim.notify("Not currently in a merge state", vim.log.levels.INFO)
		return
	-- If no conflicts found and not in a merge state, nothing to do
	elseif #conflict_files == 0 then
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
	local current_chunks = {}
	local current_chunk_index = 1
	local current_file_path = nil

	-- Function to display current chunk
	local function display_current_chunk()
		if #current_chunks == 0 then
			return
		end

		local chunk = current_chunks[current_chunk_index]
		-- Use Neovim API to set buffer content
		vim.api.nvim_buf_set_lines(popup_one.bufnr, 0, -1, false, chunk.ours)
		vim.api.nvim_buf_set_lines(popup_two.bufnr, 0, -1, false, chunk.theirs)

		-- Update titles with border text
		popup_one.border:set_text(
			"top",
			string.format("Our Changes (%d/%d)", current_chunk_index, #current_chunks),
			"center"
		)
		popup_two.border:set_text(
			"top",
			string.format("Incoming Changes (%d/%d)", current_chunk_index, #current_chunks),
			"center"
		)
	end

	-- Function to add a file to git
	local function git_add_file(filepath)
		if not filepath or filepath == "" then
			return false
		end

		local cmd = "git add " .. vim.fn.shellescape(filepath)
		local result = vim.fn.system(cmd)
		local success = vim.v.shell_error == 0

		if success then
			vim.notify("Added " .. filepath .. " to git index", vim.log.levels.INFO)
		else
			vim.notify("Failed to add " .. filepath .. " to git index: " .. result, vim.log.levels.ERROR)
		end

		return success
	end

	-- Function to refresh the file list
	local function refresh_file_list()
		-- Get updated conflict files
		conflict_files = get_conflict_files() or {}

		-- Update the file list display
		local file_lines = {}
		for _, file in ipairs(conflict_files) do
			table.insert(file_lines, file.text)
		end
		vim.api.nvim_buf_set_lines(file_menu.bufnr, 0, -1, false, file_lines)

		-- If no more conflict files, show a message
		if #conflict_files == 0 then
			vim.notify("All conflicts resolved!", vim.log.levels.INFO)
			-- Clear the diff views
			vim.api.nvim_buf_set_lines(popup_one.bufnr, 0, -1, false, { "All conflicts resolved!" })
			vim.api.nvim_buf_set_lines(popup_two.bufnr, 0, -1, false, { "All conflicts resolved!" })

			-- Add all resolved files to git
			vim.fn.system("git add -u")
			if vim.v.shell_error == 0 then
				vim.notify("All resolved files have been staged with 'git add -u'", vim.log.levels.INFO)
			else
				vim.notify("Failed to stage resolved files", vim.log.levels.ERROR)
			end

			return true
		end
		return false
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

		current_file_path = filepath
		current_chunks = get_conflict_chunks(full_path)
		current_chunk_index = 1

		-- If no more chunks in this file, mark it as resolved
		if #current_chunks == 0 then
			vim.notify("All conflicts in " .. filepath .. " resolved!", vim.log.levels.INFO)

			-- Add the resolved file to git
			git_add_file(filepath)

			-- Refresh the file list to remove this file
			if refresh_file_list() then
				return -- All files resolved
			end

			-- Load the next file if available
			if #conflict_files > 0 then
				load_file(conflict_files[1].file)
			end
			return
		end

		-- Set the filetype for the buffers based on the file extension
		local filetype = vim.filetype.match({ filename = filepath })
		if filetype then
			vim.api.nvim_set_option_value("filetype", filetype, { buf = popup_one.bufnr })
			vim.api.nvim_set_option_value("filetype", filetype, { buf = popup_two.bufnr })
		end

		display_current_chunk()
	end

	-- Mount layout and store reference globally
	layout:mount()
	M.current_layout = layout

	-- Set up file list
	local file_lines = {}
	for _, file in ipairs(conflict_files) do
		table.insert(file_lines, file.text)
	end
	vim.api.nvim_buf_set_lines(file_menu.bufnr, 0, -1, false, file_lines)

	-- Add file selection functionality
	vim.keymap.set("n", "<CR>", function()
		local line = vim.api.nvim_win_get_cursor(file_menu.winid)[1]
		if line <= #conflict_files then
			load_file(conflict_files[line].file)
		end
	end, {
		buffer = file_menu.bufnr,
		noremap = true,
		silent = true,
	})

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

	-- Functions to choose ours or theirs for the current chunk only
	local function choose_ours()
		if #current_chunks == 0 or not current_file_path then
			vim.notify("No conflict chunk selected", vim.log.levels.ERROR)
			return
		end

		-- Read the current file content
		local full_path = vim.fn.getcwd() .. "/" .. current_file_path
		local content = vim.fn.readfile(full_path)

		-- Find and replace the current conflict chunk
		local chunk_count = 0
		local in_conflict = false
		local conflict_start = nil
		local conflict_end = nil

		for i, line in ipairs(content) do
			if line:match("^<<<<<<< ") then
				chunk_count = chunk_count + 1
				if chunk_count == current_chunk_index then
					in_conflict = true
					conflict_start = i
				end
			elseif line:match("^>>>>>>> ") and in_conflict then
				in_conflict = false
				conflict_end = i
			end
		end

		-- Replace the conflict with our content
		if conflict_start and conflict_end then
			local new_content = {}
			for i, line in ipairs(content) do
				if i < conflict_start or i > conflict_end then
					table.insert(new_content, line)
				elseif i == conflict_start then
					-- Insert our content instead of the conflict markers
					for _, l in ipairs(current_chunks[current_chunk_index].ours) do
						table.insert(new_content, l)
					end
				end
			end

			-- Write the modified content back to the file
			vim.fn.writefile(new_content, full_path)
			vim.notify("Applied our version for chunk " .. current_chunk_index, vim.log.levels.INFO)

			-- Reload the file
			load_file(current_file_path)
		else
			vim.notify("Could not locate the current conflict chunk", vim.log.levels.ERROR)
		end
	end

	local function choose_theirs()
		if #current_chunks == 0 or not current_file_path then
			vim.notify("No conflict chunk selected", vim.log.levels.ERROR)
			return
		end

		-- Read the current file content
		local full_path = vim.fn.getcwd() .. "/" .. current_file_path
		local content = vim.fn.readfile(full_path)

		-- Find and replace the current conflict chunk
		local chunk_count = 0
		local in_conflict = false
		local conflict_start = nil
		local conflict_end = nil

		for i, line in ipairs(content) do
			if line:match("^<<<<<<< ") then
				chunk_count = chunk_count + 1
				if chunk_count == current_chunk_index then
					in_conflict = true
					conflict_start = i
				end
			elseif line:match("^>>>>>>> ") and in_conflict then
				in_conflict = false
				conflict_end = i
			end
		end

		-- Replace the conflict with their content
		if conflict_start and conflict_end then
			local new_content = {}
			for i, line in ipairs(content) do
				if i < conflict_start or i > conflict_end then
					table.insert(new_content, line)
				elseif i == conflict_start then
					-- Insert their content instead of the conflict markers
					for _, l in ipairs(current_chunks[current_chunk_index].theirs) do
						table.insert(new_content, l)
					end
				end
			end

			-- Write the modified content back to the file
			vim.fn.writefile(new_content, full_path)
			vim.notify("Applied their version for chunk " .. current_chunk_index, vim.log.levels.INFO)

			-- Reload the file
			load_file(current_file_path)
		else
			vim.notify("Could not locate the current conflict chunk", vim.log.levels.ERROR)
		end
	end

	-- Remove the global emergency escape that's not working

	-- Add keymaps for all popups
	for _, popup in ipairs({ popup_one, popup_two, file_menu }) do
		-- Close with q
		vim.keymap.set("n", "q", function()
			layout:unmount()
			M.merge_tool_active = false
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

		-- Choose ours with 1 or o
		vim.keymap.set("n", "1", choose_ours, {
			buffer = popup.bufnr,
			noremap = true,
			silent = true,
		})
		vim.keymap.set("n", "o", choose_ours, {
			buffer = popup.bufnr,
			noremap = true,
			silent = true,
		})

		-- Choose theirs with 2 or t
		vim.keymap.set("n", "2", choose_theirs, {
			buffer = popup.bufnr,
			noremap = true,
			silent = true,
		})
		vim.keymap.set("n", "t", choose_theirs, {
			buffer = popup.bufnr,
			noremap = true,
			silent = true,
		})

		-- Choose both (combine) with 3 or b
		vim.keymap.set("n", "3", function()
			if #current_chunks == 0 or not current_file_path then
				vim.notify("No conflict chunk selected", vim.log.levels.ERROR)
				return
			end

			-- Read the current file content
			local full_path = vim.fn.getcwd() .. "/" .. current_file_path
			local content = vim.fn.readfile(full_path)

			-- Find and replace the current conflict chunk
			local chunk_count = 0
			local in_conflict = false
			local conflict_start = nil
			local conflict_end = nil

			for i, line in ipairs(content) do
				if line:match("^<<<<<<< ") then
					chunk_count = chunk_count + 1
					if chunk_count == current_chunk_index then
						in_conflict = true
						conflict_start = i
					end
				elseif line:match("^>>>>>>> ") and in_conflict then
					in_conflict = false
					conflict_end = i
				end
			end

			-- Replace the conflict with both contents
			if conflict_start and conflict_end then
				local new_content = {}
				for i, line in ipairs(content) do
					if i < conflict_start or i > conflict_end then
						table.insert(new_content, line)
					elseif i == conflict_start then
						-- Insert both contents instead of the conflict markers
						for _, l in ipairs(current_chunks[current_chunk_index].ours) do
							table.insert(new_content, l)
						end
						for _, l in ipairs(current_chunks[current_chunk_index].theirs) do
							table.insert(new_content, l)
						end
					end
				end

				-- Write the modified content back to the file
				vim.fn.writefile(new_content, full_path)
				vim.notify("Combined both versions for chunk " .. current_chunk_index, vim.log.levels.INFO)

				-- Reload the file
				load_file(current_file_path)
			else
				vim.notify("Could not locate the current conflict chunk", vim.log.levels.ERROR)
			end
		end, {
			buffer = popup.bufnr,
			noremap = true,
			silent = true,
		})

		vim.keymap.set("n", "b", function()
			if #current_chunks == 0 or not current_file_path then
				vim.notify("No conflict chunk selected", vim.log.levels.ERROR)
				return
			end

			-- Read the current file content
			local full_path = vim.fn.getcwd() .. "/" .. current_file_path
			local content = vim.fn.readfile(full_path)

			-- Find and replace the current conflict chunk
			local chunk_count = 0
			local in_conflict = false
			local conflict_start = nil
			local conflict_end = nil

			for i, line in ipairs(content) do
				if line:match("^<<<<<<< ") then
					chunk_count = chunk_count + 1
					if chunk_count == current_chunk_index then
						in_conflict = true
						conflict_start = i
					end
				elseif line:match("^>>>>>>> ") and in_conflict then
					in_conflict = false
					conflict_end = i
				end
			end

			-- Replace the conflict with both contents
			if conflict_start and conflict_end then
				local new_content = {}
				for i, line in ipairs(content) do
					if i < conflict_start or i > conflict_end then
						table.insert(new_content, line)
					elseif i == conflict_start then
						-- Insert both contents instead of the conflict markers
						for _, l in ipairs(current_chunks[current_chunk_index].ours) do
							table.insert(new_content, l)
						end
						for _, l in ipairs(current_chunks[current_chunk_index].theirs) do
							table.insert(new_content, l)
						end
					end
				end

				-- Write the modified content back to the file
				vim.fn.writefile(new_content, full_path)
				vim.notify("Combined both versions for chunk " .. current_chunk_index, vim.log.levels.INFO)

				-- Reload the file
				load_file(current_file_path)
			else
				vim.notify("Could not locate the current conflict chunk", vim.log.levels.ERROR)
			end
		end, {
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

	-- Add file click handler
	vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = file_menu.bufnr,
		callback = function()
			-- Highlight the current line
			vim.api.nvim_buf_clear_namespace(file_menu.bufnr, -1, 0, -1)
			local line = vim.api.nvim_win_get_cursor(file_menu.winid)[1] - 1
			if line < #conflict_files then
				vim.api.nvim_buf_add_highlight(file_menu.bufnr, -1, "Visual", line, 0, -1)
			end
		end,
	})

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

	-- Make sure to clean up when unmounting
	local original_unmount = layout.unmount
	layout.unmount = function(...)
		M.merge_tool_active = false
		M.current_layout = nil
		return original_unmount(...)
	end
end

return M
