local api = vim.api

local CHAR_H = '─'
local CHAR_V = '│'

local CHAR_TL = '╭'
local CHAR_TR = '╮'

local CHAR_BL = '╰'
local CHAR_BR = '╯'


function center(str, width, top)
	if str == nil or str == '' then
		str = ''
	end

	width = width - 2
	local left = math.floor(width / 2) - math.floor(string.len(str) / 2)
	local right = math.floor(width / 2) - math.floor(string.len(str) / 2)

	local left_char = CHAR_BL
	local right_char = CHAR_BR
	if top == true then
		left_char = CHAR_TL
		right_char = CHAR_TR
	end

	if width % 2 == 0 and string.len(str) % 2 == 0 then
		return left_char .. string.rep('─', left) .. str .. string.rep('─', right) .. right_char
	end

	if width % 2 == 0 and string.len(str) % 2 == 1 then
		return left_char .. string.rep('─', left - 1) .. str .. string.rep('─', right) .. right_char
	end

	if width % 2 == 1 and string.len(str) % 2 == 0 then
		return left_char .. string.rep('─', left) .. str .. string.rep('─', right + 1) .. right_char
	end

	return left_char .. string.rep('─', left) .. str .. string.rep('─', right) .. right_char
end


function create_new_buffer() 
	local buffer = api.nvim_create_buf(false, true)
	local border_buf = api.nvim_create_buf(false, true)

	api.nvim_buf_set_option(buffer, 'bufhidden', 'wipe')
	api.nvim_buf_set_option(buffer, 'filetype', 'nvim-oldfile')
	api.nvim_buf_set_option(buffer, "buftype", "acwrite")
	api.nvim_buf_set_option(buffer, "bufhidden", "delete")


	local width = api.nvim_get_option("columns")
	local height = api.nvim_get_option("lines")

	local win_height = math.ceil(height * 0.3 - 4)
	local win_width = math.ceil(width * 0.6)
	local row = math.ceil((height - win_height) / 2 - 1)
	local col = math.ceil((width - win_width) / 2)

	local border_opts = {
		style = "minimal",
		relative = "editor",
		width = win_width + 2,
		height = win_height + 2,
		row = row - 1,
		col = col - 1
	}

	local opts = {
		style = "minimal",
		relative = "editor",
		width = win_width,
		height = win_height,
		row = row,
		col = col
	}

	bottom_text = ""
	local border_lines = { center(bottom_text, win_width + 2, true) }
	local middle_line = '│' .. string.rep(' ', win_width) .. '│'

	for i=1, win_height do
		table.insert(border_lines, middle_line)
	end

	local border_win = api.nvim_open_win(border_buf, true, border_opts)

	win = api.nvim_open_win(buffer, true, opts)

	api.nvim_win_set_option(win, 'winhighlight', 'Normal:NormalFloat')

	-- Set the border color
	vim.cmd("highlight NormalFloat guibg=black guifg=white")

	-- Set the background color
	vim.cmd("highlight NormalFloat guibg=black guifg=white")

	-- Set the text color
	vim.cmd("highlight NormalFloat guibg=black guifg=white")

	api.nvim_win_set_option(win, 'cursorline', true) -- this highlights the line with the cursor on it
	api.nvim_win_set_option(win, "number", true)
	api.nvim_win_set_option(win, 'wrap', false)

	api.nvim_command('au BufWipeout <buffer> exe "silent bwipeout! "' .. border_buf)

	table.insert(border_lines, center('Vault 9' .. "", win_width + 2, false))
	api.nvim_buf_set_lines(border_buf, 0, -1, false, border_lines)

	vim.keymap.set('n', '<LeftMouse>', function() close_window(win, buf, old_win_info) end, { buffer = true, silent = true })

	return buffer
end


return {
	center = center,
	create_new_buffer=create_new_buffer,
}
