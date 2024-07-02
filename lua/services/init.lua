local api = vim.api
local CONSTANT = require('../constant')
local json_service = require('../json')

-- Get JSON for Vault
-- type: ("vaults", "settings")
function getVaultJSON(type)
	local path = vim.fn.expand(CONSTANT.FILE_PATH)
	local file = io.open(path, 'r')

	if file then
		local content = file:read('*a')

		local success, json = pcall(vim.json.decode, content)

		if success then
			for key, value in pairs(json) do
				if key == type then
					return value
				end
			end
			return json
		end
	end

	return nil
end


-- Write to file if either there is no json file or it is empty.
function writeToEmptyJSONFile()
	local res = {
		paths = {},
		settings = CONSTANT.DEFAULT_SETTING
	}

	local path = vim.fn.expand(CONSTANT.FILE_PATH)
	local write_file = io.open(path, 'w')
	local json_str = vim.json.encode(res)
	if json_str ~= nil then
		json_str = json_service.format_json(json_str)
	end
	write_file:write(json_str)
	write_file:close()

	return res
end

return {
	writeToEmptyJSONFile=writeToEmptyJSONFile,
	getVaultJSON=getVaultJSON
}
