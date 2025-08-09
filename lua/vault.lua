local json = require("lib.dkjson")
local CONSTANT = require('constant')

local M = {}

-- Module-level state to persist sort order across menu re-opens
-- 0: vaultNumber (default), 1: lastUpdated (desc), 2: vaultPath (alpha)
M.current_sort_order = 0

-- Module-level state to persist path display mode
-- true: full path, false: last folder name only
M.full_path_display_mode = true

-- Module-level variables for the menu window and buffer, allowing external functions to close them
local menu_win = nil
local menu_buf = nil

-- New module-level state to store available (vacated) vault numbers
M.available_vault_numbers = {}

-- Constants for menu layout
local MENU_WIDTH = 80
-- Define the number of lines for the fixed header and footer
local HEADER_LINES_COUNT = 3 -- "", "Number...", "----"
-- Footer now includes an extra line for sort information and path display mode
local FOOTER_LINES_COUNT = 9 -- "", "----", "", "Sort: ...", "Path: ...", "Press 'c'...", "Press 'm'...", "Press 'd'...", "Press 'Enter'..."

-- Fixed height for the scrollable content area
local SCROLLABLE_AREA_HEIGHT = 10 -- You can adjust this value as needed

-- Calculate the total menu height based on fixed header, footer, and scrollable area
local MENU_HEIGHT = HEADER_LINES_COUNT + FOOTER_LINES_COUNT + SCROLLABLE_AREA_HEIGHT

-- Helper function to format timestamp
local function format_timestamp(timestamp)
    return os.date("%Y-%m-%d %H:%M", timestamp)
end

-- Helper function to truncate or wrap long paths, and handle last folder name display
local function format_path(path, max_width, full_display_mode)
    -- Add a check to ensure 'path' is a string
    if type(path) ~= 'string' then
        return {""} -- Return an empty line if path is not a string
    end

    local display_path = path
    if not full_display_mode then
        -- Remove trailing slashes/backslashes before extracting the last component
        local cleaned_path = path:gsub("[/\\]+$", "")
        
        -- Use string.match to extract the last component after a slash or backslash,
        -- or the entire string if no separators are present.
        local last_component = string.match(cleaned_path, "[^/\\]*$")
        if last_component then
            display_path = last_component
        else
            -- Fallback for cases like '/' or '' after cleaning (e.g., just "/")
            display_path = cleaned_path
        end
    end

    if #display_path <= max_width then
        return {display_path}
    end

    local lines = {}
    local current_line = ""
    local parts = {}

    -- Split by directory separator (handles both / and \) for wrapping the full path
    -- If displaying only the last folder name, we don't need to split by directory separator
    -- for wrapping, as it's already a single segment.
    if full_display_mode then
        for part in string.gmatch(display_path, "[^/\\]+") do
            table.insert(parts, part)
        end
    else
        table.insert(parts, display_path) -- Treat the single name as one part
    end

    -- Reconstruct path with line breaks
    for i, part in ipairs(parts) do
        local separator = (i == 1) and "" or (string.match(display_path, "\\") and "\\" or "/")
        if not full_display_mode then separator = "" end -- No separators if only name is shown

        local addition = separator .. part

        if #current_line + #addition <= max_width then
            current_line = current_line .. addition
        else
            if current_line ~= "" then
                table.insert(lines, current_line)
            end
            current_line = addition -- Start new line, left-aligned
        end
    end

    if current_line ~= "" then
        table.insert(lines, current_line)
    end

    return lines
end

-- Helper function to sort the vaults table based on the current sort order
local function sort_vaults(vaults_table, sort_order)
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

-- Helper to save data to JSON file
local function save_vault_data(vaults_data)
    local json_file_path = vim.fn.expand(CONSTANT.FILE_PATH)
    local updated_data = {
        vaults = vaults_data,
        available_vault_numbers = M.available_vault_numbers -- Include available numbers
    }
    local json_string = json.encode(updated_data, {indent = true})

    if json_string then
        local file = io.open(json_file_path, "w")
        if file then
            file:write(json_string)
            file:close()
            return true
        else
            vim.notify("Error: Could not write to JSON file.", vim.log.levels.ERROR)
            return false
        end
    else
        vim.notify("Error: Could not encode JSON data.", vim.log.levels.ERROR)
        return false
    end
end

function M.ShowVaultMenu()
    -- Read and parse JSON file
    local json_file_path = vim.fn.expand(CONSTANT.FILE_PATH) -- Expand to absolute path
    local file = io.open(json_file_path, "r")
    local data

    if not file then
        -- Initialize with empty vaults if file doesn't exist
        print("JSON file not found. Creating new vaults file...")
        data = {vaults = {}, available_vault_numbers = {}}
        -- Create the initial JSON file
        if not save_vault_data(data.vaults) then
            print("Error: Could not create initial vaults file at: " .. json_file_path)
            return
        end
    else
        local content = file:read("*all")
        file:close()
        data = json.decode(content)
        if not data or not data.vaults then
            print("Error: Invalid JSON format. Initializing vaults.")
            data = {vaults = {}, available_vault_numbers = {}}
        end
        -- Load available_vault_numbers from file, or initialize if not present
        M.available_vault_numbers = data.available_vault_numbers or {}
    end

    local vaults = data.vaults

    -- Apply sorting based on the current module-level sort order
    sort_vaults(vaults, M.current_sort_order)

    -- Menu state variables (local to this invocation of ShowVaultMenu, captured by closures)
    local current_selected_vault_idx = 1
    local current_scroll_top_line_idx = 0 -- 0-based line index of the first visible vault line in the scrollable area
    local all_vault_lines = {} -- Stores all formatted vault lines (full list)
    local vault_line_map = {} -- Maps vault_idx to {start_line_idx, end_line_idx} within all_vault_lines (0-based)
    local highlight_ns_id = nil -- Namespace for highlights

    -- Function to generate all vault lines and their mappings
    -- This is called whenever the underlying 'vaults' data might have changed.
    local function generate_full_vault_display_info()
        local lines = {}
        local line_map = {}
        local current_line_idx = 0 -- 0-based index for the 'lines' table

        local path_max_width = 40

        for i, vault in ipairs(vaults) do
            -- Pass M.full_path_display_mode to format_path
            local formatted_paths = format_path(vault.vaultPath, path_max_width, M.full_path_display_mode)
            local timestamp = format_timestamp(vault.lastUpdated)

            local start_line_for_vault = current_line_idx

            -- First line with vault number and timestamp
            local first_line = string.format("%-8d %-40s %-20s",
                vault.vaultNumber,
                formatted_paths[1] or "",
                timestamp
            )
            table.insert(lines, first_line)
            current_line_idx = current_line_idx + 1

            -- Additional lines for wrapped paths (if any)
            for j = 2, #formatted_paths do
                local continuation_line = string.format("%-8s %-40s %-20s",
                    "",
                    formatted_paths[j],
                    ""
                )
                table.insert(lines, continuation_line)
                current_line_idx = current_line_idx + 1
            end

            local end_line_for_vault = current_line_idx - 1
            line_map[i] = {start_line_idx = start_line_for_vault, end_line_idx = end_line_for_vault}
        end
        return lines, line_map
    end

    -- Function to update the menu content and highlight in the Neovim buffer
    local function update_menu_display()
        -- Regenerate full vault info (in case data changed, e.g., after add/delete/modify)
        all_vault_lines, vault_line_map = generate_full_vault_display_info()

        local display_lines = {}

        -- Add fixed header lines
        table.insert(display_lines, "")
        table.insert(display_lines, string.format("%-8s %-40s %-20s", "Number", "Path", "Updated"))
        table.insert(display_lines, string.rep("─", MENU_WIDTH - 2))

        -- Add scrollable vault content
        local num_total_vault_lines = #all_vault_lines
        local current_display_end_line_idx = math.min(current_scroll_top_line_idx + SCROLLABLE_AREA_HEIGHT, num_total_vault_lines)

        -- Iterate through the subset of all_vault_lines that should be visible
        for i = current_scroll_top_line_idx, current_display_end_line_idx - 1 do
            table.insert(display_lines, all_vault_lines[i + 1]) -- Lua tables are 1-based
        end

        -- Pad with empty lines if current content is less than SCROLLABLE_AREA_HEIGHT
        -- This ensures the scrollable area always maintains its fixed height
        while #display_lines - HEADER_LINES_COUNT < SCROLLABLE_AREA_HEIGHT do
             table.insert(display_lines, "")
        end

        -- Add fixed footer lines
        table.insert(display_lines, "")
        table.insert(display_lines, string.rep("─", MENU_WIDTH - 2))
        table.insert(display_lines, "")

        -- Display current sort order
        local sort_text = ""
        if M.current_sort_order == 0 then
            sort_text = "Sort: Number (s)"
        elseif M.current_sort_order == 1 then
            sort_text = "Sort: Updated (s)"
        elseif M.current_sort_order == 2 then
            sort_text = "Sort: Path (s)"
        end
        table.insert(display_lines, sort_text)

        -- Display current path display mode
        local path_display_text = ""
        if M.full_path_display_mode then
            path_display_text = "Path: Full (h)"
        else
            path_display_text = "Path: Name Only (h)"
        end
        table.insert(display_lines, path_display_text)


        table.insert(display_lines, "Press 'c' to Create New Vault")
        table.insert(display_lines, "Press 'm' to Modify selected vault path")
        table.insert(display_lines, "Press 'd' to Delete selected vault")
        table.insert(display_lines, "Press 'Enter' to open vault, 'q' to quit")

        -- Set buffer to modifiable before updating content
        vim.api.nvim_buf_set_option(menu_buf, 'modifiable', true)
        -- Set buffer content
        vim.api.nvim_buf_set_lines(menu_buf, 0, -1, false, display_lines)
        -- Set buffer back to non-modifiable
        vim.api.nvim_buf_set_option(menu_buf, 'modifiable', false)


        -- Clear existing highlights before applying new ones
        vim.api.nvim_buf_clear_namespace(menu_buf, highlight_ns_id, 0, -1)

        -- Apply highlight to the currently selected vault
        if #vaults > 0 and vault_line_map[current_selected_vault_idx] then
            local range = vault_line_map[current_selected_vault_idx]
            -- Calculate the start and end buffer line indices for the highlight
            local highlight_start_line_in_buffer = HEADER_LINES_COUNT + (range.start_line_idx - current_scroll_top_line_idx)
            local highlight_end_line_in_buffer = HEADER_LINES_COUNT + (range.end_line_idx - current_scroll_top_line_idx)

            -- Clamp highlight lines to ensure they are within the visible scrollable area
            highlight_start_line_in_buffer = math.max(HEADER_LINES_COUNT, highlight_start_line_in_buffer)
            highlight_end_line_in_buffer = math.min(HEADER_LINES_COUNT + SCROLLABLE_AREA_HEIGHT - 1, highlight_end_line_in_buffer)

            -- Apply highlight for each line of the selected vault that is visible
            for line_num = highlight_start_line_in_buffer, highlight_end_line_in_buffer do
                -- Only add highlight if the line is actually within the scrollable content area of the buffer
                if line_num >= HEADER_LINES_COUNT and line_num < HEADER_LINES_COUNT + SCROLLABLE_AREA_HEIGHT then
                    vim.api.nvim_buf_add_highlight(menu_buf, highlight_ns_id, 'Visual', line_num, 0, -1)
                end
            end
        end

        -- Set cursor position
        if #vaults > 0 and vault_line_map[current_selected_vault_idx] then
            local range = vault_line_map[current_selected_vault_idx]
            -- Calculate the cursor's buffer line index (0-based)
            local cursor_line_in_buffer = HEADER_LINES_COUNT + (range.start_line_idx - current_scroll_top_line_idx)
            -- Set cursor (nvim_win_set_cursor expects 1-based line index)
            vim.api.nvim_win_set_cursor(menu_win, {cursor_line_in_buffer + 1, 0})
        else
            -- If no vaults, set cursor to a neutral position within the scrollable area
            vim.api.nvim_win_set_cursor(menu_win, {HEADER_LINES_COUNT + 1, 0})
        end
    end

    -- Navigation logic for moving the cursor and adjusting scroll
    local function move_cursor(direction)
        if #vaults == 0 then return end -- No vaults to navigate

        local new_selected_vault_idx = current_selected_vault_idx + direction
        -- Clamp the selected vault index to valid range
        new_selected_vault_idx = math.max(1, math.min(#vaults, new_selected_vault_idx))

        if new_selected_vault_idx == current_selected_vault_idx then return end -- No change in selection

        current_selected_vault_idx = new_selected_vault_idx

        -- Get the line range of the newly selected vault within the full list of vault lines
        local selected_vault_line_range = vault_line_map[current_selected_vault_idx]
        local selected_vault_start_line = selected_vault_line_range.start_line_idx
        local selected_vault_end_line = selected_vault_line_range.end_line_idx

        -- Adjust current_scroll_top_line_idx if the selected vault goes out of the visible scroll area

        -- If the selected vault's start line is above the current scroll view (scrolling up)
        if selected_vault_start_line < current_scroll_top_line_idx then
            current_scroll_top_line_idx = selected_vault_start_line
        -- If the selected vault's end line is below the current scroll view (scrolling down)
        elseif selected_vault_end_line >= current_scroll_top_line_idx + SCROLLABLE_AREA_HEIGHT then
            current_scroll_top_line_idx = selected_vault_end_line - SCROLLABLE_AREA_HEIGHT + 1
        end

        -- Clamp current_scroll_top_line_idx to ensure it stays within valid bounds
        -- It should not go negative, and it should not push the last vault line beyond the view
        local max_scroll_top_line_idx = math.max(0, #all_vault_lines - SCROLLABLE_AREA_HEIGHT)
        current_scroll_top_line_idx = math.max(0, math.min(current_scroll_top_line_idx, max_scroll_top_line_idx))

        update_menu_display() -- Redraw the menu with the new scroll and selection
    end

    -- Refresh function (closes current window and re-opens menu to reflect changes)
    local function refresh_menu()
        if menu_win and vim.api.nvim_win_is_valid(menu_win) then
            vim.api.nvim_win_close(menu_win, true)
            menu_win = nil -- Clear reference after closing
            menu_buf = nil -- Clear reference after closing
        end
        M.ShowVaultMenu() -- Re-call to re-initialize all state and redraw
    end

    -- Create new buffer and window for the menu
    menu_buf = vim.api.nvim_create_buf(false, true)
    menu_win = vim.api.nvim_open_win(menu_buf, true, {
        relative = 'editor',
        width = MENU_WIDTH,
        height = MENU_HEIGHT,
        col = (vim.o.columns - MENU_WIDTH) / 2, -- Center horizontally
        row = (vim.o.lines - MENU_HEIGHT) / 2, -- Center vertically
        style = 'minimal',
        border = 'rounded',
        title = ' Vault Manager ',
        title_pos = 'center'
    })

    -- Set buffer options
    vim.api.nvim_buf_set_option(menu_buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(menu_buf, 'modifiable', false)


    -- Initialize highlight namespace
    highlight_ns_id = vim.api.nvim_create_namespace('vault_menu')

    -- Initial display update
    -- Ensure initial selection is valid if there are vaults
    if #vaults > 0 then
        current_selected_vault_idx = 1
        current_scroll_top_line_idx = 0 -- Start at the very top of the vault list
    else
        current_selected_vault_idx = 0 -- No vaults selected
        current_scroll_top_line_idx = 0
    end
    update_menu_display()


    -- Action handlers (modified to use refresh_menu for re-rendering)
    local function create_new_vault()
        -- Determine the new vault number
        local new_vault_number
        if #M.available_vault_numbers > 0 then
            table.sort(M.available_vault_numbers) -- Ensure smallest number is at the front
            new_vault_number = table.remove(M.available_vault_numbers, 1)
        else
            -- Find the current maximum vault number to assign a new sequential one
            local max_vault_num = 0
            for _, vault in ipairs(vaults) do
                if vault.vaultNumber > max_vault_num then
                    max_vault_num = vault.vaultNumber
                end
            end
            new_vault_number = max_vault_num + 1
        end

        -- Always set default_path to current working directory
        local default_path = vim.fn.getcwd()
        
        vim.ui.input({
            prompt = "Enter new vault path: ",
            default = default_path
        }, function(path)
            if path and path ~= "" then
                local expanded_path = vim.fn.expand(path)
                if vim.fn.isdirectory(expanded_path) == 1 then
                    local new_vault = {
                        vaultNumber = new_vault_number,
                        vaultPath = expanded_path,
                        lastUpdated = os.time()
                    }
                    table.insert(vaults, new_vault)

                    if save_vault_data(vaults) then
                        refresh_menu() -- Refresh menu after saving
                    end
                else
                    vim.notify("Error: Invalid directory path", vim.log.levels.ERROR)
                end
            end
        end)
    end

    local function modify_vault_path()
        if #vaults == 0 then vim.notify("No vaults to modify.", vim.log.levels.INFO); return end
        local vault_to_modify = nil
        for _, vault in ipairs(vaults) do
            if vault_line_map[current_selected_vault_idx] and vault.vaultNumber == vaults[current_selected_vault_idx].vaultNumber then
                vault_to_modify = vault
                break
            end
        end

        if not vault_to_modify then return end -- Should not happen if #vaults > 0 and idx is valid

        local current_path = vault_to_modify.vaultPath
        vim.ui.input({
            prompt = "Enter new vault path: ",
            default = current_path
        }, function(path)
            if path and path ~= "" then
                local expanded_path = vim.fn.expand(path)
                if vim.fn.isdirectory(expanded_path) == 1 then
                    vault_to_modify.vaultPath = expanded_path
                    vault_to_modify.lastUpdated = os.time()

                    if save_vault_data(vaults) then
                        refresh_menu() -- Refresh menu after saving
                    end
                else
                    vim.notify("Error: Invalid directory path", vim.log.levels.ERROR)
                end
            end
        end)
    end

    local function delete_vault()
        if #vaults == 0 then vim.notify("No vaults to delete.", vim.log.levels.INFO); return end
        local vault_to_delete_idx_in_table = current_selected_vault_idx -- The actual table index
        local vault_to_delete = vaults[vault_to_delete_idx_in_table]
        if not vault_to_delete then return end -- Should not happen if #vaults > 0 and idx is valid

        local vault_path = vault_to_delete.vaultPath
        local vault_number = vault_to_delete.vaultNumber

        -- Show confirmation dialog
        vim.ui.select({'Yes', 'No'}, {
            prompt = string.format('Delete Vault #%d (%s)?', vault_number, vault_path),
        }, function(choice)
            if choice == 'Yes' then
                table.remove(vaults, vault_to_delete_idx_in_table)
                table.insert(M.available_vault_numbers, vault_number) -- Add the deleted number to available list
                table.sort(M.available_vault_numbers) -- Keep it sorted

                if save_vault_data(vaults) then -- Save updated vaults and available_vault_numbers
                    vim.notify(string.format("Vault #%d (%s) deleted successfully.", vault_number, vault_info.vaultPath), vim.log.levels.INFO)
                    -- Close the menu window if it's currently open, as its data is now stale
                    if menu_win and vim.api.nvim_win_is_valid(menu_win) then
                        vim.api.nvim_win_close(menu_win, true)
                        menu_win = nil
                        menu_buf = nil
                    end
                end
            else
                vim.notify("Vault deletion cancelled.", vim.log.levels.INFO)
            end
        end)
    end

    local function open_vault()
        if #vaults == 0 then vim.notify("No vaults to open.", vim.log.levels.INFO); return end
        local vault_to_open = vaults[current_selected_vault_idx]
        if not vault_to_open then return end -- Should not happen if #vaults > 0 and idx is valid

        local vault_path = vault_to_open.vaultPath
        -- Close the menu window before changing directory
        if menu_win and vim.api.nvim_win_is_valid(menu_win) then
            vim.api.nvim_win_close(menu_win, true)
            menu_win = nil
            menu_buf = nil
        end
        vim.cmd('cd ' .. vim.fn.fnameescape(vault_path)) -- Change Neovim's current directory
        print("Opened vault: " .. vault_path)
    end

    -- Set up key mappings for navigation and actions
    local opts = {buffer = menu_buf, nowait = true, silent = true}

    vim.keymap.set('n', 'j', function() move_cursor(1) end, opts)
    vim.keymap.set('n', 'k', function() move_cursor(-1) end, opts)
    vim.keymap.set('n', '<Down>', function() move_cursor(1) end, opts)
    vim.keymap.set('n', '<Up>', function() move_cursor(-1) end, opts)
    vim.keymap.set('n', 'c', create_new_vault, opts)
    vim.keymap.set('n', 'm', modify_vault_path, opts)
    vim.keymap.set('n', 'd', delete_vault, opts)
    vim.keymap.set('n', '<CR>', open_vault, opts)
    vim.keymap.set('n', 'q', function() if menu_win and vim.api.nvim_win_is_valid(menu_win) then vim.api.nvim_win_close(menu_win, true) end end, opts)
    vim.keymap.set('n', '<Esc>', function() if menu_win and vim.api.nvim_win_is_valid(menu_win) then vim.api.nvim_win_close(menu_win, true) end end, opts)

    -- Key mapping for sorting
    vim.keymap.set('n', 's', function()
        M.current_sort_order = (M.current_sort_order + 1) % 3 -- Cycle through 0, 1, 2
        refresh_menu()
    end, opts)

    -- New key mapping for toggling path display
    vim.keymap.set('n', 'h', function()
        M.full_path_display_mode = not M.full_path_display_mode
        refresh_menu()
    end, opts)

    -- Autocmd to close window when clicking outside or losing focus
    vim.api.nvim_create_autocmd({'BufLeave', 'WinLeave', 'FocusLost'}, {
        buffer = menu_buf,
        once = true, -- Ensure it runs only once to prevent issues if focus shifts rapidly
        callback = function()
            if menu_win and vim.api.nvim_win_is_valid(menu_win) then
                vim.api.nvim_win_close(menu_win, true)
            end
        end
    })

    -- Disable other movements within the menu buffer to prevent unintended actions
    local disabled_keys = {'l', '<Left>', '<Right>', 'w', 'b', 'e', '0', '$', '^', 'G', 'gg'}
    for _, key in ipairs(disabled_keys) do
        vim.keymap.set('n', key, '<Nop>', opts)
    end
end

-- Function to open a vault by its number, callable via a Vim command
function M.EnterVaultByNumber(vault_num_str)
    local vault_number = tonumber(vault_num_str)
    if not vault_number then
        vim.notify("Invalid vault number provided. Please use a number.", vim.log.levels.ERROR)
        return
    end

    -- Read JSON file to get current vaults
    local json_file_path = vim.fn.expand(CONSTANT.FILE_PATH)
    local file = io.open(json_file_path, "r")
    local data = {}
    if file then
        local content = file:read("*all")
        file:close()
        data = json.decode(content) or {}
    end

    local vaults = data.vaults or {}

    local target_vault = nil
    for _, vault in ipairs(vaults) do
        if vault.vaultNumber == vault_number then
            target_vault = vault
            break
        end
    end

    if target_vault then
        -- Close the menu window if it's currently open
        if menu_win and vim.api.nvim_win_is_valid(menu_win) then
            vim.api.nvim_win_close(menu_win, true)
            menu_win = nil
            menu_buf = nil
        end
        vim.cmd('cd ' .. vim.fn.fnameescape(target_vault.vaultPath))
        print("Opened vault: " .. target_vault.vaultPath)
    else
        vim.notify("Vault number " .. vault_number .. " not found.", vim.log.levels.WARN)
    end
end

-- Function to delete a vault by its number, callable via a Vim command
function M.DeleteVaultByNumber(vault_num_str)
    local vault_number = tonumber(vault_num_str)
    if not vault_number then
        vim.notify("Invalid vault number provided. Please use a number.", vim.log.levels.ERROR)
        return
    end

    -- Read JSON file to get current vaults and available numbers
    local json_file_path = vim.fn.expand(CONSTANT.FILE_PATH)
    local file = io.open(json_file_path, "r")
    local data = {}
    if file then
        local content = file:read("*all")
        file:close()
        data = json.decode(content) or {}
    end

    local vaults = data.vaults or {}
    M.available_vault_numbers = data.available_vault_numbers or {}

    if #vaults == 0 then
        vim.notify("No vaults to delete.", vim.log.levels.INFO)
        return
    end

    local vault_to_delete_idx = nil
    local vault_info = nil -- Store info for confirmation message
    for i, vault in ipairs(vaults) do
        if vault.vaultNumber == vault_number then
            vault_to_delete_idx = i
            vault_info = vault
            break
        end
    end

    if vault_to_delete_idx then
        -- Show confirmation dialog
        vim.ui.select({'Yes', 'No'}, {
            prompt = string.format('Are you sure you want to delete Vault #%d (%s)? This action is permanent.', vault_info.vaultNumber, vault_info.vaultPath),
        }, function(choice)
            if choice == 'Yes' then
                table.remove(vaults, vault_to_delete_idx)
                table.insert(M.available_vault_numbers, vault_number) -- Add the deleted number to available list
                table.sort(M.available_vault_numbers) -- Keep it sorted

                if save_vault_data(vaults) then -- Save updated vaults and available_vault_numbers
                    vim.notify(string.format("Vault #%d (%s) deleted successfully.", vault_number, vault_info.vaultPath), vim.log.levels.INFO)
                    -- Close the menu window if it's currently open, as its data is now stale
                    if menu_win and vim.api.nvim_win_is_valid(menu_win) then
                        vim.api.nvim_win_close(menu_win, true)
                        menu_win = nil
                        menu_buf = nil
                    end
                end
            else
                vim.notify("Vault deletion cancelled.", vim.log.levels.INFO)
            end
        end)
    else
        vim.notify("Vault number " .. vault_number .. " not found for deletion.", vim.log.levels.WARN)
    end
end

-- Create a new vault with current working directory as origin
function M.CreateVaultWithCwd()
    -- Read JSON file to get current vaults and available numbers
    local json_file_path = vim.fn.expand(CONSTANT.FILE_PATH)
    local file = io.open(json_file_path, "r")
    local data = {}
    if file then
        local content = file:read("*all")
        file:close()
        data = json.decode(content) or {}
    end

    local vaults = data.vaults or {}
    M.available_vault_numbers = data.available_vault_numbers or {}

    -- Determine the new vault number
    local new_vault_number
    if #M.available_vault_numbers > 0 then
        table.sort(M.available_vault_numbers) -- Ensure smallest number is at the front
        new_vault_number = table.remove(M.available_vault_numbers, 1)
    else
        -- Find the current maximum vault number to assign a new sequential one
        local max_vault_num = 0
        for _, vault in ipairs(vaults) do
            if vault.vaultNumber > max_vault_num then
                max_vault_num = vault.vaultNumber
            end
        end
        new_vault_number = max_vault_num + 1
    end

    local current_cwd = vim.fn.getcwd()
    local expanded_path = vim.fn.expand(current_cwd)

    if vim.fn.isdirectory(expanded_path) == 1 then
        local new_vault = {
            vaultNumber = new_vault_number,
            vaultPath = expanded_path,
            lastUpdated = os.time()
        }
        table.insert(vaults, new_vault)

        if save_vault_data(vaults) then
            vim.notify(string.format("Vault #%d (%s) created successfully.", new_vault_number, expanded_path), vim.log.levels.INFO)
            -- Close the menu window if it's currently open, as its data is now stale
            if menu_win and vim.api.nvim_win_is_valid(menu_win) then
                vim.api.nvim_win_close(menu_win, true)
                menu_win = nil
                menu_buf = nil
            end
        end
    else
        vim.notify("Error: Current working directory is not a valid directory: " .. current_cwd, vim.log.levels.ERROR)
    end
end


return M
