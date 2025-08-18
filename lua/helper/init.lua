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

return H
