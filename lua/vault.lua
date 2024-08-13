local api = vim.api

local settings = require('settings')
local services = require('services')
local json_service = require('json')
local ui = require('ui-services')
local CONSTANT = require('constant')


local CURRENT_VAULT = nil

-- Show all vaults menu
function open_vault_menu()
	local old_win = api.nvim_get_current_win()
	local cursor_pos = api.nvim_win_get_cursor(0)
	local line_number = cursor_pos[1]
	local column_number = cursor_pos[2]


	local old_win_info = {
		win = old_win,
		line = line_number,
		column = column_number,
	}

	local new = ui.create_new_window('All Vaults', old_win_info)
	local win = new.window
	local buf = new.buffer

	local json_data = services.getVaultJSON("vaults")

	if json_data == nil then
		json_data = services.writeToEmptyJSONFile()
		json_data = services.getVaultJSON("vaults")
	end

	api.nvim_buf_set_lines(buf, 0, -1, false, { 'Vault Number ' .. "|" .. " Vault Path" })

	local index = 1
	for key, value in pairs(json_data) do
		local vaultNumber = value["vaultNumber"]
		local vaultPath = value["vaultPath"]
		api.nvim_buf_set_lines(buf, index, -1, false, { ui.center(vaultNumber, 13, ' ') .. "| " .. vaultPath })
		index = index + 1
	end

	api.nvim_buf_set_option(buf, 'modifiable', false)
end


function create_vault_window()
	local old_win = api.nvim_get_current_win()
	local cursor_pos = api.nvim_win_get_cursor(0)
	local line_number = cursor_pos[1]
	local column_number = cursor_pos[2]


	local old_win_info = {
		win = old_win,
		line = line_number,
		column = column_number,
	}

	local new = ui.create_new_window('All Vaults', old_win_info)
	local win = new.window
	local buf = new.buffer

	local json_data = services.getVaultJSON("vaults")

	if json_data == nil then
		json_data = services.writeToEmptyJSONFile()
		json_data = services.getVaultJSON("vaults")
	end

	api.nvim_buf_set_lines(buf, 0, -1, false, { 'Vault Number ' .. "|" .. " Vault Path" })

	local index = 1
	for key, value in pairs(json_data) do
		local vaultNumber = value["vaultNumber"]
		local vaultPath = value["vaultPath"]
		api.nvim_buf_set_lines(buf, index, -1, false, { ui.center(vaultNumber, 13, ' ') .. "| " .. vaultPath })
		index = index + 1
	end

	api.nvim_buf_set_option(buf, 'modifiable', false)
end



function select_vault()
end

function access_vault(vault_number)
end

function delete_vault(vault_number)
end



-- Show all Files in selected Vault
function open_file_menu()
end

function access_file()
end

function access_current_file()
end

function delete_file()
end



-- Show all Notes inside selected Vault
function open_note_menu()
end

function access_current_note()
end

function access_note()
end

function delete_note()
end


return {
	create_vault_window=create_vault_window,
	open_vault_menu=open_vault_menu,
}
