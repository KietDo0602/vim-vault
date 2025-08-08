local CONSTANT = require("../constant")
local json = require("lib.dkjson")

local M = {}

--- Writes { vaults = {} } to CONSTANT.FILE_PATH
function M.WriteToEmptyJSONFile()
  local data = { vaults = {} }
  local encoded = json.encode(data, { indent = true })

  -- Ensure directory exists
  vim.fn.mkdir(vim.fn.fnamemodify(CONSTANT.FILE_PATH, ":h"), "p")

  local f = io.open(CONSTANT.FILE_PATH, "w")
  if not f then
    error("Could not open file for writing: " .. CONSTANT.FILE_PATH)
  end
  f:write(encoded)
  f:close()
end

--- Reads and returns decoded JSON from CONSTANT.FILE_PATH
--- @return table|nil Decoded JSON data or nil if file doesn't exist or is invalid
function M.GetVaultJSON()
  local f = io.open(CONSTANT.FILE_PATH, "r")
  if not f then
    return nil  -- File doesn't exist
  end

  local content = f:read("*a")
  f:close()

  local data, _, err = json.decode(content, 1, nil)
  if not data then
    error("Failed to decode JSON: " .. tostring(err))
  end

  return data
end

return M
