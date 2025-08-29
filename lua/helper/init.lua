local H = {}

function H.normalize_path(path)
    if not path or path == "" then
        return ""
    end

    -- Detect if this is a Windows absolute path with drive letter
    local drive_letter = path:match("^([A-Za-z]):[\\/]")
    local is_windows_absolute = drive_letter ~= nil

    -- Detect UNC path (\\server\share)
    local is_unc = path:match("^\\\\") or path:match("^//")

    -- Detect absolute path (starts with / or \)
    local is_absolute = path:match("^[\\/]") or is_windows_absolute or is_unc

    -- Replace all backslashes with forward slashes
    local normalized = path:gsub("\\", "/")

    -- Collapse multiple consecutive slashes, but preserve UNC prefix
    if is_unc then
        -- For UNC paths, keep the leading // and collapse the rest
        normalized = "//" .. normalized:sub(3):gsub("/+", "/")
    else
        normalized = normalized:gsub("/+", "/")
    end

    -- Split path into components
    local components = {}
    for component in normalized:gmatch("[^/]+") do
        table.insert(components, component)
    end

    -- Process relative path components (. and ..)
    local result_components = {}

    for i, component in ipairs(components) do
        if component == "." then
            -- Skip current directory references
        elseif component == ".." then
            -- Handle parent directory
            if #result_components > 0 and result_components[#result_components] ~= ".." then
                -- Remove the last component if it's not ".."
                local last = result_components[#result_components]
                -- Don't go above root or drive letter
                if not (is_windows_absolute and #result_components == 1) then
                    table.remove(result_components)
                end
            elseif not is_absolute then
                -- For relative paths, keep the ".." if we can't resolve it
                table.insert(result_components, "..")
            end
            -- For absolute paths, ".." at root is ignored
        else
            table.insert(result_components, component)
        end
    end

    -- Reconstruct the path
    local result

    if is_unc then
        -- UNC path: //server/share/...
        if #result_components >= 2 then
            result = "//" .. table.concat(result_components, "/")
        else
            result = "//" .. table.concat(result_components, "/")
        end
    elseif is_windows_absolute then
        -- Windows absolute path: C:/...
        result = drive_letter:upper() .. ":/" .. table.concat(result_components, "/", 2)
    elseif is_absolute then
        -- Unix absolute path: /...
        result = "/" .. table.concat(result_components, "/")
    else
        -- Relative path
        if #result_components == 0 then
            result = "."
        else
            result = table.concat(result_components, "/")
        end
    end

    -- Clean up edge cases
    if result == "" then
        result = "."
    end

    -- Remove trailing slash unless it's root
    if #result > 1 and result:sub(#result) == "/" then
        -- Don't remove trailing slash from root paths or UNC server names
        if not (result == "/" or (is_unc and not result:match("//[^/]+/[^/]+/"))) then
            result = result:sub(1, #result - 1)
        end
    end

    return result
end

-- Helper to truncate the middle of a long string to keep it exactly max_width
local function truncate_middle(str, max_width)
    -- If input is not string or too short, return as is
    if type(str) ~= "string" or max_width <= 0 then
        return ""
    end

    -- If the string fits within max_width, return original string
    if #str <= max_width then
        return str
    end

    -- If max_width is too small to even fit the three dots "..."
    if max_width <= 3 then
        return string.sub(str, 1, max_width)
    end

    -- Calculate no chars to keep from start and end
    local keep = max_width - 3
    local left = math.floor(keep / 2)
    local right = keep - left

    return string.sub(str, 1, left) .. "..." .. string.sub(str, -right)
end

-- Helper function to truncate or wrap long paths, and handle last folder name display
function H.format_path(path, max_width, full_display_mode)
    if type(path) ~= 'string' then
        return {""}
    end

    local display_path = path
    if not full_display_mode then
        local cleaned_path = H.normalize_path(path)
        local last_component = string.match(cleaned_path, "[^/\\]*$")
        display_path = last_component or cleaned_path
    end

    if #display_path <= max_width then
        return {display_path}
    end

    local lines = {}
    local current_line = ""
    local parts = {}

    if full_display_mode then
        for part in string.gmatch(display_path, "[^/\\]+") do
            table.insert(parts, part)
        end
    else
        table.insert(parts, display_path)
    end

    for i, part in ipairs(parts) do
        -- truncate part if it's longer than max_width
        part = truncate_middle(part, max_width)

        local separator = (i == 1) and "" or (string.match(display_path, "\\") and "\\" or "/")
        if not full_display_mode then separator = "" end

        local addition = separator .. part

        if #current_line + #addition <= max_width then
            current_line = current_line .. addition
        else
            if current_line ~= "" then
                table.insert(lines, current_line)
            end
            current_line = addition
        end
    end

    if current_line ~= "" then
        table.insert(lines, current_line)
    end

    return lines
end

-- Helper function to format timestamp
function H.format_timestamp(timestamp)
    local normalized

    if type(timestamp) == "number" then
        normalized = timestamp
    elseif type(timestamp) == "string" then
        -- Try to parse ISO 8601 format: "2022-01-18T06:32:00"
        local year, month, day, hour, min, sec = timestamp:match("(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
        if year then
            normalized = os.time({
                year = tonumber(year),
                month = tonumber(month),
                day = tonumber(day),
                hour = tonumber(hour),
                min = tonumber(min),
                sec = tonumber(sec),
            })
        end
    end

    -- Fallback to current time if normalization fails
    normalized = normalized or os.time()

    return os.date("%Y-%m-%d %H:%M", normalized)
end

-- Helper function to sort the vaults table based on the current sort order
function H.sort_vaults(vaults_table, sort_order)
    if sort_order == 0 then -- Sort by vaultNumber (default: ascending)
        table.sort(vaults_table, function(a, b)
            return a.vaultNumber < b.vaultNumber
        end)
    elseif sort_order == 1 then -- Sort by lastUpdated (descending: most recent first)
        table.sort(vaults_table, function(a, b)
            return a.lastUpdated > b.lastUpdated
        end)
    elseif sort_order == 2 then -- Sort by vaultPath (alphabetical: ascending)
        table.sort(vaults_table, function(a, b)
            return a.vaultPath < b.vaultPath
        end)
    end
end

-- Helper function to sort the files table based on the current sort order
-- 0: fileName (alphabetical), 1: lastUpdated (desc)
function H.sort_files(files_table, sort_order)
    if sort_order == 0 then -- Sort by fileName (alphabetical: ascending)
        table.sort(files_table, function(a, b)
            return a.fileName < b.fileName
        end)
    elseif sort_order == 1 then -- Sort by lastUpdated (descending: most recent first)
        table.sort(files_table, function(a, b)
            return a.lastUpdated > b.lastUpdated
        end)
    end
end

-- Helper to get filename stem (without extension)
function H.get_filename_stem(filename)
    -- Find the position of the last dot
    local last_dot_idx = 0
    for i = #filename, 1, -1 do
        if filename:sub(i, i) == "." then
            last_dot_idx = i
            break
        end
    end

    if last_dot_idx > 0 then
        -- Return substring from start to just before the last dot
        return filename:sub(1, last_dot_idx - 1)
    else
        -- No dot, so the whole filename is the stem
        return filename
    end
end

-- Helper printing function for debugging
function H.printTable(tbl, indent)
    indent = indent or 0
    local prefix = string.rep("  ", indent)

    for key, value in pairs(tbl) do
        if type(value) == "table" then
            print(prefix .. tostring(key) .. " = {")
            H.printTable(value, indent + 1)
            print(prefix .. "}")
        else
            print(prefix .. tostring(key) .. " = " .. tostring(value))
        end
    end
end


return H
