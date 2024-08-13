local api = vim.api

local CHAR_H = '─'
local CHAR_V = '│'

local CHAR_TL = '╭'
local CHAR_TR = '╮'

local CHAR_BL = '╰'
local CHAR_BR = '╯'


function center(str, length, char)
	-- Cast numbers to string
	str = tostring(str)

    if #str >= length then
        return str
    else
        local padding = length - #str
        local left_padding = math.floor(padding / 2)
        local right_padding = padding - left_padding
        return string.rep(char, left_padding) .. str .. string.rep(char, right_padding)
    end
end

-- Close window and buffer if it exists
function close_window(win, buf)
	win = win or nil
	buf = buf or nil

	-- Delete if window is valid
	if win and api.nvim_win_is_valid(win) then
		api.nvim_win_close(win, true)
	end

	-- Delete if buffer is valid
	if buf and api.nvim_buf_is_valid(buf) then
		api.nvim_buf_delete(buf, { force = true })
	end
end

function create_new_window(str, old_win_info) 
	local buffer = api.nvim_create_buf(false, true)
	local border_buf = api.nvim_create_buf(false, true)

	api.nvim_buf_set_option(buffer, 'filetype', 'json')
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
	local border_lines = { CHAR_TL .. center(bottom_text, win_width, CHAR_H) .. CHAR_TR }
	local middle_line = CHAR_V .. string.rep(' ', win_width) .. CHAR_V

	for i=1, win_height do
		table.insert(border_lines, middle_line)
	end

	local border_win = api.nvim_open_win(border_buf, true, border_opts)

	local win = api.nvim_open_win(buffer, true, opts)

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

	table.insert(border_lines, CHAR_BL .. center(str, win_width, CHAR_H) .. CHAR_BR)
	api.nvim_buf_set_lines(border_buf, 0, -1, false, border_lines)

	api.nvim_command('au BufWipeout <buffer> exe "silent bwipeout! "' .. border_buf)

	vim.keymap.set('n', '<LeftMouse>', function() close_window(win, buffer) end, { buffer = true, silent = true })
	vim.keymap.set('n', '<Esc>', function() close_window(win, buffer) end, { buffer = true, silent = true })

	return {
		buffer = buffer,
		window = win
	}
end


return {
	center = center,
	create_new_window=create_new_window,
	close_window=close_window,
}
