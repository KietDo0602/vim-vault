local json = require("lib.dkjson")
local CONSTANT = require('constant') -- Assuming this provides CONSTANT.FILE_PATH

local M = {}

-- Module-level state to persist sort order across menu re-opens
-- 0: vaultNumber (default), 1: lastUpdated (desc), 2: vaultPath (alpha)
M.current_sort_order = 0

-- Module-level state to persist path display mode
-- true: full path, false: last folder name only
M.full_path_display_mode = true

-- Module-level variables for the menu window and buffer, allowing external functions to close them
local main_menu_win = nil
local main_menu_buf = nil
local file_menu_win = nil
local file_menu_buf = nil

-- New module-level state to store available (vacated) vault numbers
M.available_vault_numbers = {}

-- New module-level state to store the last selected/opened vault object
M.last_selected_vault = nil

-- Centralized store for all vault data
M.vaults = {}


-- Constants for main menu layout
local MAIN_MENU_WIDTH = 80
local MAIN_MENU_HEADER_LINES_COUNT = 3 -- "", "Number...", "----"
local MAIN_MENU_FOOTER_LINES_COUNT = 9 -- "", "----", "", "Sort: ...", "Path: ...", "Press 'c'...", "Press 'm'...", "Press 'd'...", "Press 'Enter'..."
local MAIN_MENU_SCROLLABLE_AREA_HEIGHT = 10 -- You can adjust this value as needed
local MAIN_MENU_HEIGHT = MAIN_MENU_HEADER_LINES_COUNT + MAIN_MENU_FOOTER_LINES_COUNT + MAIN_MENU_SCROLLABLE_AREA_HEIGHT

-- Constants for file menu layout
local FILE_MENU_WIDTH = 80
local FILE_MENU_HEADER_LINES_COUNT = 3 -- "", "File Name...", "----"
local FILE_MENU_FOOTER_LINES_COUNT = 7 -- "", "----", "", "Sort: ...", "Press 'c'...", "Press 'm'...", "Press 'd'...", "Press 'Enter'..."
local FILE_MENU_SCROLLABLE_AREA_HEIGHT = 10 -- Adjust as needed for file list
local FILE_MENU_HEIGHT = FILE_MENU_HEADER_LINES_COUNT + FILE_MENU_FOOTER_LINES_COUNT + FILE_MENU_SCROLLABLE_AREA_HEIGHT

-- Helper function to format timestamp
local function format_timestamp(timestamp)
    return os.date("%Y-%m-%d %H:%M", timestamp)
end

-- Helper for path normalization
local function normalize_path(path)
    -- Replace backslashes with forward slashes
    local normalized = path:gsub("\\", "/")
    -- Remove trailing slash unless it's the root directory "/"
    if #normalized > 1 and normalized:sub(#normalized) == "/" then
        normalized = normalized:sub(1, #normalized - 1)
    end
    return normalized
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

-- Helper function to sort the files table based on the current sort order
-- 0: fileName (alphabetical), 1: lastUpdated (desc)
local function sort_files(files_table, sort_order)
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


-- Helper to save data to JSON file
local function save_vault_data()
    local json_file_path = vim.fn.expand(CONSTANT.FILE_PATH)
    local updated_data = {
        vaults = M.vaults, -- Use the centralized M.vaults
        available_vault_numbers = M.available_vault_numbers or {} -- Ensure it's always included
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

-- Function to read vault data from JSON file (now populates M.vaults directly)
local function read_vault_data_into_M()
    local json_file_path = vim.fn.expand(CONSTANT.FILE_PATH)
    local file = io.open(json_file_path, "r")
    local data = {vaults = {}, available_vault_numbers = {}} -- Default empty structure

    if file then
        local content = file:read("*all")
        file:close()
        data = json.decode(content) or data
    else
        vim.notify("JSON file not found. Creating new vaults file...", vim.log.levels.INFO)
        -- save_vault_data will create it with defaults on first write if it doesn't exist.
    end

    M.vaults = data.vaults or {}
    M.available_vault_numbers = data.available_vault_numbers or {}

    -- Ensure each vault has 'files' and each file has 'notes' and 'lastUpdated'
    for _, vault in ipairs(M.vaults) do
        vault.files = vault.files or {}
        for _, file_entry in ipairs(vault.files) do
            file_entry.notes = file_entry.notes or ""
            file_entry.lastUpdated = file_entry.lastUpdated or os.time()
        end
    end
    return true
end

-- Utility to close any open menu windows
local function close_all_menus()
    if main_menu_win and vim.api.nvim_win_is_valid(main_menu_win) then
        vim.api.nvim_win_close(main_menu_win, true)
        main_menu_win = nil
        main_menu_buf = nil
    end
    if file_menu_win and vim.api.nvim_win_is_valid(file_menu_win) then
        vim.api.nvim_win_close(file_menu_win, true)
        file_menu_win = nil
        file_menu_buf = nil
    end
end


--------------------------------------------------------------------------------
-- Main Vault Menu Functions
--------------------------------------------------------------------------------

function M.ShowVaultMenu()
    close_all_menus() -- Close any existing menus

    read_vault_data_into_M() -- Populate M.vaults

    -- Apply sorting based on the current module-level sort order
    sort_vaults(M.vaults, M.current_sort_order)

    -- Menu state variables (local to this invocation of ShowVaultMenu, captured by closures)
    local current_selected_vault_idx = 1
    local current_scroll_top_line_idx = 0 -- 0-based line index of the first visible vault line in the scrollable area
    local all_vault_lines = {} -- Stores all formatted vault lines (full list)
    local vault_line_map = {} -- Maps vault_idx (in the sorted table) to {start_line_idx, end_line_idx} within all_vault_lines (0-based)
    local highlight_ns_id = vim.api.nvim_create_namespace('vault_menu_highlight')

    -- Function to generate all vault lines and their mappings
    local function generate_full_vault_display_info()
        local lines = {}
        local line_map = {}
        local current_line_idx = 0 -- 0-based index for the 'lines' table

        local path_max_width = 40

        for i, vault in ipairs(M.vaults) do
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
    local function update_main_menu_display()
        -- Regenerate full vault info (in case data changed, e.g., after add/delete/modify)
        all_vault_lines, vault_line_map = generate_full_vault_display_info()

        local display_lines = {}

        -- Add fixed header lines
        table.insert(display_lines, "")
        table.insert(display_lines, string.format("%-8s %-40s %-20s", "Number", "Path", "Updated"))
        table.insert(display_lines, string.rep("─", MAIN_MENU_WIDTH - 2))

        -- Add scrollable vault content
        local num_total_vault_lines = #all_vault_lines
        local current_display_end_line_idx = math.min(current_scroll_top_line_idx + MAIN_MENU_SCROLLABLE_AREA_HEIGHT, num_total_vault_lines)

        -- Iterate through the subset of all_vault_lines that should be visible
        for i = current_scroll_top_line_idx, current_display_end_line_idx - 1 do
            table.insert(display_lines, all_vault_lines[i + 1]) -- Lua tables are 1-based
        end

        -- Pad with empty lines if current content is less than MAIN_MENU_SCROLLABLE_AREA_HEIGHT
        -- This ensures the scrollable area always maintains its fixed height
        while #display_lines - MAIN_MENU_HEADER_LINES_COUNT < MAIN_MENU_SCROLLABLE_AREA_HEIGHT do
             table.insert(display_lines, "")
        end

        -- Add fixed footer lines
        table.insert(display_lines, "")
        table.insert(display_lines, string.rep("─", MAIN_MENU_WIDTH - 2))
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
        vim.api.nvim_buf_set_option(main_menu_buf, 'modifiable', true)
        -- Set buffer content
        vim.api.nvim_buf_set_lines(main_menu_buf, 0, -1, false, display_lines)
        -- Set buffer back to non-modifiable
        vim.api.nvim_buf_set_option(main_menu_buf, 'modifiable', false)


        -- Clear existing highlights before applying new ones
        vim.api.nvim_buf_clear_namespace(main_menu_buf, highlight_ns_id, 0, -1)

        -- Apply highlight to the currently selected vault
        if #M.vaults > 0 and vault_line_map[current_selected_vault_idx] then
            local range = vault_line_map[current_selected_vault_idx]
            -- Calculate the start and end buffer line indices for the highlight
            local highlight_start_line_in_buffer = MAIN_MENU_HEADER_LINES_COUNT + (range.start_line_idx - current_scroll_top_line_idx)
            local highlight_end_line_in_buffer = MAIN_MENU_HEADER_LINES_COUNT + (range.end_line_idx - current_scroll_top_line_idx)

            -- Clamp highlight lines to ensure they are within the visible scrollable area
            highlight_start_line_in_buffer = math.max(MAIN_MENU_HEADER_LINES_COUNT, highlight_start_line_in_buffer)
            highlight_end_line_in_buffer = math.min(MAIN_MENU_HEADER_LINES_COUNT + MAIN_MENU_SCROLLABLE_AREA_HEIGHT - 1, highlight_end_line_in_buffer)

            for line_num = highlight_start_line_in_buffer, highlight_end_line_in_buffer do
                if line_num >= MAIN_MENU_HEADER_LINES_COUNT and line_num < MAIN_MENU_HEADER_LINES_COUNT + MAIN_MENU_SCROLLABLE_AREA_HEIGHT then
                    vim.api.nvim_buf_add_highlight(main_menu_buf, highlight_ns_id, 'Visual', line_num, 0, -1)
                end
            end
        end

        -- Set cursor position
        if #M.vaults > 0 and vault_line_map[current_selected_vault_idx] then
            local range = vault_line_map[current_selected_vault_idx]
            -- Calculate the cursor's buffer line index (0-based)
            local cursor_line_in_buffer = MAIN_MENU_HEADER_LINES_COUNT + (range.start_line_idx - current_scroll_top_line_idx)
            -- Set cursor (nvim_win_set_cursor expects 1-based line index)
            vim.api.nvim_win_set_cursor(main_menu_win, {cursor_line_in_buffer + 1, 0})
        else
            -- If no vaults, set cursor to a neutral position within the scrollable area
            vim.api.nvim_win_set_cursor(main_menu_win, {MAIN_MENU_HEADER_LINES_COUNT + 1, 0})
        end
    end

    -- Navigation logic for moving the cursor and adjusting scroll
    local function move_main_menu_cursor(direction)
        if #M.vaults == 0 then return end -- No vaults to navigate

        local new_selected_vault_idx = current_selected_vault_idx + direction
        -- Clamp the selected vault index to valid range
        new_selected_vault_idx = math.max(1, math.min(#M.vaults, new_selected_vault_idx))

        if new_selected_vault_idx == current_selected_vault_idx then return end -- No change in selection

        current_selected_vault_idx = new_selected_vault_idx
        M.last_selected_vault = M.vaults[current_selected_vault_idx] -- Update last selected vault

        -- Get the line range of the newly selected vault within the full list of vault lines
        local selected_vault_line_range = vault_line_map[current_selected_vault_idx]
        local selected_vault_start_line = selected_vault_line_range.start_line_idx
        local selected_vault_end_line = selected_vault_line_range.end_line_idx

        -- Adjust current_scroll_top_line_idx if the selected vault goes out of the visible scroll area

        -- If the selected vault's start line is above the current scroll view (scrolling up)
        if selected_vault_start_line < current_scroll_top_line_idx then
            current_scroll_top_line_idx = selected_vault_start_line
        -- If the selected vault's end line is below the current scroll view (scrolling down)
        elseif selected_vault_end_line >= current_scroll_top_line_idx + MAIN_MENU_SCROLLABLE_AREA_HEIGHT then
            current_scroll_top_line_idx = selected_vault_end_line - MAIN_MENU_SCROLLABLE_AREA_HEIGHT + 1
        end

        -- Clamp current_scroll_top_line_idx to ensure it stays within valid bounds
        -- It should not go negative, and it should not push the last vault line beyond the view
        local max_scroll_top_line_idx = math.max(0, #all_vault_lines - MAIN_MENU_SCROLLABLE_AREA_HEIGHT)
        current_scroll_top_line_idx = math.max(0, math.min(current_scroll_top_line_idx, max_scroll_top_line_idx))

        update_main_menu_display() -- Redraw the menu with the new scroll and selection
    end

    -- Refresh function (closes current window and re-opens menu to reflect changes)
    local function refresh_main_menu()
        close_all_menus() -- Ensure all menus are closed before refreshing
        M.ShowVaultMenu() -- Re-call to re-initialize all state and redraw
    end

    -- Create new buffer and window for the menu
    main_menu_buf = vim.api.nvim_create_buf(false, true)
    main_menu_win = vim.api.nvim_open_win(main_menu_buf, true, {
        relative = 'editor',
        width = MAIN_MENU_WIDTH,
        height = MAIN_MENU_HEIGHT,
        col = (vim.o.columns - MAIN_MENU_WIDTH) / 2, -- Center horizontally
        row = (vim.o.lines - MAIN_MENU_HEIGHT) / 2, -- Center vertically
        style = 'minimal',
        border = 'rounded',
        title = ' Vault Manager ',
        title_pos = 'center'
    })

    -- Set buffer options
    vim.api.nvim_buf_set_option(main_menu_buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(main_menu_buf, 'modifiable', false)


    -- Initial display update
    -- Ensure initial selection is valid if there are vaults
    if #M.vaults > 0 then
        current_selected_vault_idx = 1
        current_scroll_top_line_idx = 0 -- Start at the very top of the vault list
        M.last_selected_vault = M.vaults[current_selected_vault_idx] -- Set initial last selected
    else
        current_selected_vault_idx = 0 -- No vaults selected
        current_scroll_top_line_idx = 0
        M.last_selected_vault = nil
    end
    update_main_menu_display()


    -- Action handlers (modified to use refresh_main_menu for re-rendering)
    local function create_new_vault_interactive()
        -- Determine the new vault number
        local new_vault_number
        if #M.available_vault_numbers > 0 then
            table.sort(M.available_vault_numbers) -- Ensure smallest number is at the front
            new_vault_number = table.remove(M.available_vault_numbers, 1)
        else
            -- Find the current maximum vault number to assign a new sequential one
            local max_vault_num = 0
            for _, vault in ipairs(M.vaults) do
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
                        lastUpdated = os.time(),
                        files = {} -- Initialize with empty files array
                    }
                    table.insert(M.vaults, new_vault)

                    if save_vault_data() then
                        M.last_selected_vault = new_vault -- Update last selected vault
                        refresh_main_menu() -- Refresh menu after saving
                    end
                else
                    vim.notify("Error: Invalid directory path", vim.log.levels.ERROR)
                end
            end
        end)
    end

    local function modify_vault_path_interactive()
        if #M.vaults == 0 then vim.notify("No vaults to modify.", vim.log.levels.INFO); return end
        local vault_to_modify = nil
        for _, vault in ipairs(M.vaults) do
            -- Find the currently selected vault by its *actual* vault number, not its table index
            -- This is important because sorting changes table indices but not vaultNumbers
            if current_selected_vault_idx > 0 and current_selected_vault_idx <= #M.vaults and vault.vaultNumber == M.vaults[current_selected_vault_idx].vaultNumber then
                vault_to_modify = vault
                break
            end
        end

        if not vault_to_modify then return end -- Should not happen if #M.vaults > 0 and idx is valid

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

                    if save_vault_data() then
                        M.last_selected_vault = vault_to_modify -- Update last selected vault
                        refresh_main_menu() -- Refresh menu after saving
                    end
                else
                    vim.notify("Error: Invalid directory path", vim.log.levels.ERROR)
                end
            end
        end)
    end

    local function delete_vault_interactive()
        if #M.vaults == 0 then vim.notify("No vaults to delete.", vim.log.levels.INFO); return end
        local vault_to_delete_idx_in_table = current_selected_vault_idx -- The actual table index
        local vault_to_delete = M.vaults[vault_to_delete_idx_in_table]
        if not vault_to_delete then return end -- Should not happen if #M.vaults > 0 and idx is valid

        local vault_path = vault_to_delete.vaultPath
        local vault_number = vault_to_delete.vaultNumber

        -- Show confirmation dialog
        vim.ui.select({'Yes', 'No'}, {
            prompt = string.format('Are you sure you want to delete Vault #%d (%s)? This action is permanent.', vault_number, vault_path),
        }, function(choice)
            if choice == 'Yes' then
                table.remove(M.vaults, vault_to_delete_idx_in_table)
                table.insert(M.available_vault_numbers, vault_number) -- Add the deleted number to available list
                table.sort(M.available_vault_numbers) -- Keep it sorted

                if save_vault_data() then -- Save updated vaults and available_vault_numbers
                    vim.notify(string.format("Vault #%d (%s) deleted successfully.", vault_number, vault_path), vim.log.levels.INFO)
                    -- If the deleted vault was the last selected, clear the reference
                    if M.last_selected_vault and M.last_selected_vault.vaultNumber == vault_number then
                        M.last_selected_vault = nil
                    end
                    close_all_menus() -- Close all menus if data changed
                end
            else
                vim.notify("Vault deletion cancelled.", vim.log.levels.INFO)
            end
        end)
    end

    local function open_vault_from_menu()
        if #M.vaults == 0 then vim.notify("No vaults to open.", vim.log.levels.INFO); return end
        local vault_to_open = M.vaults[current_selected_vault_idx]
        if not vault_to_open then return end -- Should not happen if #M.vaults > 0 and idx is valid

        local vault_path = vault_to_open.vaultPath
        M.last_selected_vault = vault_to_open -- Update last selected vault before changing directory
        close_all_menus() -- Close the menu window before changing directory
        vim.cmd('cd ' .. vim.fn.fnameescape(vault_path)) -- Change Neovim's current directory
        print("Opened vault: " .. vault_path)
    end

    -- Set up key mappings for navigation and actions
    local opts = {buffer = main_menu_buf, nowait = true, silent = true}

    vim.keymap.set('n', 'j', function() move_main_menu_cursor(1) end, opts)
    vim.keymap.set('n', 'k', function() move_main_menu_cursor(-1) end, opts)
    vim.keymap.set('n', '<Down>', function() move_main_menu_cursor(1) end, opts)
    vim.keymap.set('n', '<Up>', function() move_main_menu_cursor(-1) end, opts)
    vim.keymap.set('n', 'c', create_new_vault_interactive, opts)
    vim.keymap.set('n', 'm', modify_vault_path_interactive, opts)
    vim.keymap.set('n', 'd', delete_vault_interactive, opts)
    vim.keymap.set('n', '<CR>', open_vault_from_menu, opts)
    vim.keymap.set('n', 'q', function() close_all_menus() end, opts)
    vim.keymap.set('n', '<Esc>', function() close_all_menus() end, opts)

    -- Key mapping for sorting
    vim.keymap.set('n', 's', function()
        M.current_sort_order = (M.current_sort_order + 1) % 3 -- Cycle through 0, 1, 2
        refresh_main_menu()
    end, opts)

    -- New key mapping for toggling path display
    vim.keymap.set('n', 'h', function()
        M.full_path_display_mode = not M.full_path_display_mode
        refresh_main_menu()
    end, opts)

    -- Autocmd to close window when clicking outside or losing focus
    vim.api.nvim_create_autocmd({'BufLeave', 'WinLeave', 'FocusLost'}, {
        buffer = main_menu_buf,
        once = true, -- Ensure it runs only once to prevent issues if focus shifts rapidly
        callback = function()
            if main_menu_win and vim.api.nvim_win_is_valid(main_menu_win) then
                vim.api.nvim_win_close(main_menu_win, true)
                main_menu_win = nil
                main_menu_buf = nil
            end
        end
    })

    -- Disable other movements within the menu buffer to prevent unintended actions
    local disabled_keys = {'l', '<Left>', '<Right>', 'w', 'b', 'e', '0', '$', '^', 'G', 'gg'}
    for _, key in ipairs(disabled_keys) do
        vim.keymap.set('n', key, '<Nop>', opts)
    end
end

--------------------------------------------------------------------------------
-- File Menu Functions
--------------------------------------------------------------------------------

-- Current sort order for the file menu
-- 0: fileName (default), 1: lastUpdated (desc)
local current_file_sort_order = 0

function M.ShowFileMenu(vault_object)
    close_all_menus() -- Close any existing menus

    if not vault_object or not vault_object.vaultPath or not vault_object.files then
        vim.notify("Invalid vault selected for File Menu.", vim.log.levels.ERROR)
        return
    end

    -- Deep copy the files table to avoid modifying the original during sorting within the menu
    local files_in_vault = vim.deepcopy(vault_object.files)
    sort_files(files_in_vault, current_file_sort_order)

    local current_selected_file_idx = 1
    local current_file_scroll_top_line_idx = 0 -- 0-based line index of first visible file line
    local all_file_display_lines = {} -- Full list of formatted file lines
    local file_line_map = {} -- Maps file_idx (in sorted table) to {start_line_idx, end_line_idx}

    local highlight_ns_id = vim.api.nvim_create_namespace('file_menu_highlight')

    -- Function to generate all file display lines
    local function generate_full_file_display_info()
        local lines = {}
        local line_map = {}
        local current_line_idx = 0 -- 0-based index

        local filename_max_width = 50 -- Adjust as needed for filename column

        for i, file_entry in ipairs(files_in_vault) do
            -- File names are relative to vault path, so we use it directly
            local formatted_filename = format_path(file_entry.fileName, filename_max_width, true) -- Always full path for internal files
            local timestamp = format_timestamp(file_entry.lastUpdated)

            local start_line_for_file = current_line_idx

            local first_line = string.format("%-50s %-20s",
                formatted_filename[1] or "",
                timestamp
            )
            table.insert(lines, first_line)
            current_line_idx = current_line_idx + 1

            -- Additional lines for wrapped filenames
            for j = 2, #formatted_filename do
                local continuation_line = string.format("%-50s %-20s",
                    formatted_filename[j],
                    ""
                )
                table.insert(lines, continuation_line)
                current_line_idx = current_line_idx + 1
            end
            local end_line_for_file = current_line_idx - 1
            line_map[i] = {start_line_idx = start_line_for_file, end_line_idx = end_line_for_file}
        end
        return lines, line_map
    end

    -- Function to update the file menu content
    local function update_file_menu_display()
        all_file_display_lines, file_line_map = generate_full_file_display_info()

        local display_lines = {}

        -- Header
        table.insert(display_lines, "")
        table.insert(display_lines, string.format("%-50s %-20s", "File Name", "Updated"))
        table.insert(display_lines, string.rep("─", FILE_MENU_WIDTH - 2))

        -- Scrollable content
        local num_total_file_lines = #all_file_display_lines
        local current_display_end_line_idx = math.min(current_file_scroll_top_line_idx + FILE_MENU_SCROLLABLE_AREA_HEIGHT, num_total_file_lines)

        for i = current_file_scroll_top_line_idx, current_display_end_line_idx - 1 do
            table.insert(display_lines, all_file_display_lines[i + 1])
        end

        -- Pad with empty lines
        while #display_lines - FILE_MENU_HEADER_LINES_COUNT < FILE_MENU_SCROLLABLE_AREA_HEIGHT do
            table.insert(display_lines, "")
        end

        -- Footer
        table.insert(display_lines, "")
        table.insert(display_lines, string.rep("─", FILE_MENU_WIDTH - 2))
        table.insert(display_lines, "")

        local sort_text = ""
        if current_file_sort_order == 0 then
            sort_text = "Sort: Name (s)"
        elseif current_file_sort_order == 1 then
            sort_text = "Sort: Updated (s)"
        end
        table.insert(display_lines, sort_text)
        
        table.insert(display_lines, "Press 'c' to Create New File")
        table.insert(display_lines, "Press 'm' to Modify File Name")
        table.insert(display_lines, "Press 'd' to Delete File")
        table.insert(display_lines, "Press 'Enter' to open file, 'q' to quit")

        vim.api.nvim_buf_set_option(file_menu_buf, 'modifiable', true)
        vim.api.nvim_buf_set_lines(file_menu_buf, 0, -1, false, display_lines)
        vim.api.nvim_buf_set_option(file_menu_buf, 'modifiable', false)

        -- Clear existing highlights
        vim.api.nvim_buf_clear_namespace(file_menu_buf, highlight_ns_id, 0, -1)

        -- Apply highlight to the currently selected file
        if #files_in_vault > 0 and file_line_map[current_selected_file_idx] then
            local range = file_line_map[current_selected_file_idx]
            local highlight_start_line_in_buffer = FILE_MENU_HEADER_LINES_COUNT + (range.start_line_idx - current_file_scroll_top_line_idx)
            local highlight_end_line_in_buffer = FILE_MENU_HEADER_LINES_COUNT + (range.end_line_idx - current_file_scroll_top_line_idx)

            highlight_start_line_in_buffer = math.max(FILE_MENU_HEADER_LINES_COUNT, highlight_start_line_in_buffer)
            highlight_end_line_in_buffer = math.min(FILE_MENU_HEADER_LINES_COUNT + FILE_MENU_SCROLLABLE_AREA_HEIGHT - 1, highlight_end_line_in_buffer)

            for line_num = highlight_start_line_in_buffer, highlight_end_line_in_buffer do
                if line_num >= FILE_MENU_HEADER_LINES_COUNT and line_num < FILE_MENU_HEADER_LINES_COUNT + FILE_MENU_SCROLLABLE_AREA_HEIGHT then
                    vim.api.nvim_buf_add_highlight(file_menu_buf, highlight_ns_id, 'Visual', line_num, 0, -1)
                end
            end
        end

        -- Set cursor position
        if #files_in_vault > 0 and file_line_map[current_selected_file_idx] then
            local range = file_line_map[current_selected_file_idx]
            local cursor_line_in_buffer = FILE_MENU_HEADER_LINES_COUNT + (range.start_line_idx - current_file_scroll_top_line_idx)
            vim.api.nvim_win_set_cursor(file_menu_win, {cursor_line_in_buffer + 1, 0})
        else
            vim.api.nvim_win_set_cursor(file_menu_win, {FILE_MENU_HEADER_LINES_COUNT + 1, 0})
        end
    end

    -- Navigation logic for file menu
    local function move_file_cursor(direction)
        if #files_in_vault == 0 then return end

        local new_selected_file_idx = current_selected_file_idx + direction
        new_selected_file_idx = math.max(1, math.min(#files_in_vault, new_selected_file_idx))

        if new_selected_file_idx == current_selected_file_idx then return end

        current_selected_file_idx = new_selected_file_idx

        local selected_file_line_range = file_line_map[current_selected_file_idx]
        local selected_file_start_line = selected_file_line_range.start_line_idx
        local selected_file_end_line = selected_file_line_range.end_line_idx

        if selected_file_start_line < current_file_scroll_top_line_idx then
            current_file_scroll_top_line_idx = selected_file_start_line
        elseif selected_file_end_line >= current_file_scroll_top_line_idx + FILE_MENU_SCROLLABLE_AREA_HEIGHT then
            current_file_scroll_top_line_idx = selected_file_end_line - FILE_MENU_SCROLLABLE_AREA_HEIGHT + 1
        end

        local max_scroll_top_line_idx = math.max(0, #all_file_display_lines - FILE_MENU_SCROLLABLE_AREA_HEIGHT)
        current_file_scroll_top_line_idx = math.max(0, math.min(current_file_scroll_top_line_idx, max_scroll_top_line_idx))

        update_file_menu_display()
    end

    local function refresh_file_menu()
        -- Re-read data to get latest files for the current vault
        read_vault_data_into_M()
        local found_vault = nil
        for _, v in ipairs(M.vaults) do
            if v.vaultNumber == vault_object.vaultNumber then
                found_vault = v
                break
            end
        end

        close_all_menus() -- Close current file menu before recreating
        if found_vault then
            M.ShowFileMenu(found_vault) -- Re-open file menu with updated data
        else
            vim.notify("Parent vault no longer exists.", vim.log.levels.ERROR)
        end
    end

    local function create_file_entry()
        vim.ui.input({
            prompt = "Enter new file path (relative to vault): ",
            default = ""
        }, function(relative_path)
            if relative_path and relative_path ~= "" then
                local full_file_path = vim.fn.fnamemodify(vault_object.vaultPath .. "/" .. relative_path, ":p")
                
                -- Check if directory exists, create if not
                local parent_dir = vim.fn.fnamemodify(full_file_path, ":h")
                if vim.fn.isdirectory(parent_dir) == 0 then
                    local confirm_create_dir = vim.fn.confirm("Parent directory '" .. parent_dir .. "' does not exist. Create it?", "&Yes\n&No")
                    if confirm_create_dir == 1 then -- Yes
                        vim.fn.mkdir(parent_dir, "p")
                    else
                        vim.notify("File creation cancelled (directory not created).", vim.log.levels.INFO)
                        return
                    end
                end

                -- Create empty file if it doesn't exist
                local f = io.open(full_file_path, "a")
                if f then
                    io.close(f)
                else
                    vim.notify("Error: Could not create file on disk: " .. full_file_path, vim.log.levels.ERROR)
                    return
                end


                local new_file = {
                    fileName = relative_path,
                    lastUpdated = os.time(),
                    notes = ""
                }
                table.insert(vault_object.files, new_file)

                -- Update parent vault's lastUpdated
                vault_object.lastUpdated = os.time()

                if save_vault_data() then -- Save the centralized M.vaults
                    vim.cmd("edit " .. vim.fn.fnameescape(full_file_path)) -- Open file in Vim
                    refresh_file_menu() -- Refresh file menu
                else
                    vim.notify("Error saving vault data after file creation.", vim.log.levels.ERROR)
                end
            end
        end)
    end

    local function modify_file_entry()
        if #files_in_vault == 0 then vim.notify("No files to modify.", vim.log.levels.INFO); return end
        local file_to_modify = files_in_vault[current_selected_file_idx]
        if not file_to_modify then return end

        local old_relative_path = file_to_modify.fileName
        local old_full_path = vim.fn.fnamemodify(vault_object.vaultPath .. "/" .. old_relative_path, ":p")

        vim.ui.input({
            prompt = "Enter new file path (relative to vault): ",
            default = old_relative_path
        }, function(new_relative_path)
            if new_relative_path and new_relative_path ~= "" then
                local new_full_path = vim.fn.fnamemodify(vault_object.vaultPath .. "/" .. new_relative_path, ":p")

                if old_full_path == new_full_path then
                    vim.notify("New path is the same as old path. No changes made.", vim.log.levels.INFO)
                    return
                end

                -- Optional: Check if new file already exists on disk
                if vim.fn.filereadable(new_full_path) == 1 or vim.fn.isdirectory(new_full_path) == 1 then
                    vim.notify("Error: Target file/directory already exists: " .. new_full_path, vim.log.levels.ERROR)
                    return
                end
                
                -- Check if parent directory exists for the new path, create if not
                local new_parent_dir = vim.fn.fnamemodify(new_full_path, ":h")
                if vim.fn.isdirectory(new_parent_dir) == 0 then
                     local confirm_create_dir = vim.fn.confirm("Parent directory '" .. new_parent_dir .. "' does not exist. Create it?", "&Yes\n&No")
                    if confirm_create_dir == 1 then -- Yes
                        vim.fn.mkdir(new_parent_dir, "p")
                    else
                        vim.notify("File rename/move cancelled (directory not created).", vim.log.levels.INFO)
                        return
                    end
                end

                -- Rename/move file on disk
                local success, err = pcall(vim.cmd, 'silent !mv ' .. vim.fn.fnameescape(old_full_path) .. ' ' .. vim.fn.fnameescape(new_full_path))
                if not success then
                    vim.notify("Error renaming file on disk: " .. err, vim.log.levels.ERROR)
                    return
                end

                -- Update data in JSON
                file_to_modify.fileName = new_relative_path
                file_to_modify.lastUpdated = os.time()
                vault_object.lastUpdated = os.time() -- Update parent vault

                if save_vault_data() then -- Save the centralized M.vaults
                    refresh_file_menu()
                else
                    vim.notify("Error saving vault data after file modification.", vim.log.levels.ERROR)
                end
            end
        end)
    end

    local function delete_file_entry()
        if #files_in_vault == 0 then vim.notify("No files to delete.", vim.log.levels.INFO); return end
        local file_to_delete_idx = current_selected_file_idx
        local file_to_delete = files_in_vault[file_to_delete_idx]
        if not file_to_delete then return end

        local full_file_path = vim.fn.fnamemodify(vault_object.vaultPath .. "/" .. file_to_delete.fileName, ":p")

        vim.ui.select({'Yes', 'No'}, {
            prompt = string.format('Delete file "%s" from vault data? (File on disk will NOT be deleted)', file_to_delete.fileName),
        }, function(choice)
            if choice == 'Yes' then
                -- Remove from the actual vault_object.files which is passed by reference from main data
                -- We need to find the original index in the actual vault_object.files array
                local original_idx = nil
                for i, f in ipairs(vault_object.files) do
                    if f.fileName == file_to_delete.fileName then
                        original_idx = i
                        break
                    end
                end

                if original_idx then
                    table.remove(vault_object.files, original_idx)
                    vault_object.lastUpdated = os.time() -- Update parent vault

                    if save_vault_data() then -- Save the centralized M.vaults
                        vim.notify(string.format("File '%s' deleted from vault #%d data.", file_to_delete.fileName, vault_object.vaultNumber), vim.log.levels.INFO)
                        refresh_file_menu()
                    else
                        vim.notify("Error saving vault data after file deletion.", vim.log.levels.ERROR)
                    end
                else
                    vim.notify("Error: Could not find file in original vault data.", vim.log.levels.ERROR)
                end
            end
        end)
    end

    local function open_file_entry()
        if #files_in_vault == 0 then vim.notify("No files to open.", vim.log.levels.INFO); return end
        local file_to_open = files_in_vault[current_selected_file_idx]
        if not file_to_open then return end

        local full_file_path = vim.fn.fnamemodify(vault_object.vaultPath .. "/" .. file_to_open.fileName, ":p")
        close_all_menus() -- Close file menu
        vim.cmd("edit " .. vim.fn.fnameescape(full_file_path))
    end

    -- Get the last component of the vault path for the title
    local last_folder_name = format_path(vault_object.vaultPath, FILE_MENU_WIDTH, false)[1]

    -- Create new buffer and window for the file menu
    file_menu_buf = vim.api.nvim_create_buf(false, true)
    file_menu_win = vim.api.nvim_open_win(file_menu_buf, true, {
        relative = 'editor',
        width = FILE_MENU_WIDTH,
        height = FILE_MENU_HEIGHT,
        col = (vim.o.columns - FILE_MENU_WIDTH) / 2,
        row = (vim.o.lines - FILE_MENU_HEIGHT) / 2,
        style = 'minimal',
        border = 'rounded',
        title = ' Files in Vault: ' .. (last_folder_name or "N/A"),
        title_pos = 'center'
    })

    vim.api.nvim_buf_set_option(file_menu_buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(file_menu_buf, 'modifiable', false)

    -- Initial display
    if #files_in_vault > 0 then
        current_selected_file_idx = 1
        current_file_scroll_top_line_idx = 0
    else
        current_selected_file_idx = 0
        current_file_scroll_top_line_idx = 0
    end
    update_file_menu_display()

    -- Set up key mappings for file menu
    local opts = {buffer = file_menu_buf, nowait = true, silent = true}
    vim.keymap.set('n', 'j', function() move_file_cursor(1) end, opts)
    vim.keymap.set('n', 'k', function() move_file_cursor(-1) end, opts)
    vim.keymap.set('n', '<Down>', function() move_file_cursor(1) end, opts)
    vim.keymap.set('n', '<Up>', function() move_file_cursor(-1) end, opts)
    vim.keymap.set('n', 'c', create_file_entry, opts)
    vim.keymap.set('n', 'm', modify_file_entry, opts)
    vim.keymap.set('n', 'd', delete_file_entry, opts)
    vim.keymap.set('n', '<CR>', open_file_entry, opts)
    vim.keymap.set('n', 'q', function() close_all_menus() end, opts)
    vim.keymap.set('n', '<Esc>', function() close_all_menus() end, opts)

    -- Key mapping for sorting files
    vim.keymap.set('n', 's', function()
        current_file_sort_order = (current_file_sort_order + 1) % 2 -- Cycle through 0, 1
        sort_files(files_in_vault, current_file_sort_order) -- Re-sort the local copy
        update_file_menu_display()
    end, opts)

    -- Disable other movements for file menu
    local disabled_keys_file_menu = {'h', 'l', '<Left>', '<Right>', 'w', 'b', 'e', '0', '$', '^', 'G', 'gg'}
    for _, key in ipairs(disabled_keys_file_menu) do
        vim.keymap.set('n', key, '<Nop>', opts)
    end

    -- Autocmd to close window when clicking outside or losing focus
    vim.api.nvim_create_autocmd({'BufLeave', 'WinLeave', 'FocusLost'}, {
        buffer = file_menu_buf,
        once = true,
        callback = function()
            if file_menu_win and vim.api.nvim_win_is_valid(file_menu_win) then
                vim.api.nvim_win_close(file_menu_win, true)
                file_menu_win = nil
                file_menu_buf = nil
            end
        end
    })
end

--------------------------------------------------------------------------------
-- Vim Commands
--------------------------------------------------------------------------------

-- Function to open a vault by its number, callable via a Vim command
function M.EnterVaultByNumber(vault_num_str)
    local vault_number = tonumber(vault_num_str)
    if not vault_number then
        vim.notify("Invalid vault number provided. Please use a number.", vim.log.levels.ERROR)
        return
    end

    read_vault_data_into_M() -- Ensure M.vaults is up-to-date

    local target_vault = nil
    for _, vault in ipairs(M.vaults) do
        if vault.vaultNumber == vault_number then
            target_vault = vault
            break
        end
    end

    if target_vault then
        M.last_selected_vault = target_vault -- Update last selected vault
        close_all_menus()
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

    read_vault_data_into_M() -- Ensure M.vaults is up-to-date

    if #M.vaults == 0 then
        vim.notify("No vaults to delete.", vim.log.levels.INFO)
        return
    end

    local vault_to_delete_idx = nil
    local vault_info = nil
    for i, vault in ipairs(M.vaults) do
        if vault.vaultNumber == vault_number then
            vault_to_delete_idx = i
            vault_info = vault
            break
        end
    end

    if vault_to_delete_idx then
        vim.ui.select({'Yes', 'No'}, {
            prompt = string.format('Are you sure you want to delete Vault #%d (%s)? This action is permanent.', vault_info.vaultNumber, vault_info.vaultPath),
        }, function(choice)
            if choice == 'Yes' then
                table.remove(M.vaults, vault_to_delete_idx)
                table.insert(M.available_vault_numbers, vault_number)
                table.sort(M.available_vault_numbers)

                if save_vault_data() then
                    vim.notify(string.format("Vault #%d (%s) deleted successfully.", vault_number, vault_info.vault.Path), vim.log.levels.INFO)
                    -- If the deleted vault was the last selected, clear the reference
                    if M.last_selected_vault and M.last_selected_vault.vaultNumber == vault_number then
                        M.last_selected_vault = nil
                    end
                    close_all_menus() -- Close all menus if data changed
                end
            else
                vim.notify("Vault deletion cancelled.", vim.log.levels.INFO)
            end
        end)
    else
        vim.notify("Vault number " .. vault_number .. " not found for deletion.", vim.log.levels.WARN)
    end
end

-- New function to create a new vault with current working directory as origin
function M.CreateVaultWithCwd()
    read_vault_data_into_M() -- Ensure M.vaults is up-to-date

    local new_vault_number
    if #M.available_vault_numbers > 0 then
        table.sort(M.available_vault_numbers)
        new_vault_number = table.remove(M.available_vault_numbers, 1)
    else
        local max_vault_num = 0
        for _, vault in ipairs(M.vaults) do
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
            lastUpdated = os.time(),
            files = {} -- Initialize with empty files array
        }
        table.insert(M.vaults, new_vault)

        if save_vault_data() then
            M.last_selected_vault = new_vault -- Update last selected vault
            vim.notify(string.format("Vault #%d (%s) created successfully.", new_vault_number, expanded_path), vim.log.levels.INFO)
            close_all_menus() -- Close menus
        end
    else
        vim.notify("Error: Current working directory is not a valid directory: " .. current_cwd, vim.log.levels.ERROR)
    end
end

-- New function to open the File Menu for a specified vault number or the last selected one
function M.OpenVaultFilesMenu(vault_num_str)
    read_vault_data_into_M() -- Ensure M.vaults is up-to-date
    
    local target_vault = nil
    
    if vault_num_str and vault_num_str ~= "" then -- An argument was provided
        local vault_number = tonumber(vault_num_str)
        if not vault_number then
            vim.notify("Invalid vault number provided. Please use a number.", vim.log.levels.ERROR)
            return
        end

        for _, vault in ipairs(M.vaults) do
            if vault.vaultNumber == vault_number then
                target_vault = vault
                break
            end
        end
        if not target_vault then
            vim.notify("Vault number " .. vault_number .. " not found.", vim.log.levels.WARN)
            return
        end
    else -- No argument was provided, use the last selected vault
        if M.last_selected_vault then
            -- Find the last selected vault in the refreshed M.vaults (important for correct reference)
            local found_match = false
            for _, vault in ipairs(M.vaults) do
                if vault.vaultNumber == M.last_selected_vault.vaultNumber then
                    target_vault = vault
                    found_match = true
                    break
                end
            end
            if not found_match then
                vim.notify("Last selected vault no longer exists. Please select a vault first or provide a number.", vim.log.levels.WARN)
                M.last_selected_vault = nil -- Clear invalid reference
                return
            end
        else
            vim.notify("No vault selected. Please select a vault first in the main menu or use :VaultFiles [Number].", vim.log.levels.INFO)
            return
        end
    end

    -- If a target_vault is found (either by argument or last selected)
    M.last_selected_vault = target_vault -- Always update last selected vault with the one we're opening
    M.ShowFileMenu(target_vault) -- Open the file menu for this vault
end

-- New function to add the current file to the selected vault
function M.AddCurrentFileToVault()
    read_vault_data_into_M() -- Ensure M.vaults is up-to-date

    -- Re-find M.last_selected_vault to ensure it's a live reference to an object in M.vaults
    if M.last_selected_vault then
        local found_live_vault = nil
        for _, vault_in_M_vaults in ipairs(M.vaults) do
            if vault_in_M_vaults.vaultNumber == M.last_selected_vault.vaultNumber then
                found_live_vault = vault_in_M_vaults
                break
            end
        end
        M.last_selected_vault = found_live_vault -- Update to the live reference
    end

    local current_file_path = vim.api.nvim_buf_get_name(0)
    
    if current_file_path == "" then
        vim.notify("Not currently in a file buffer or buffer has no name. Cannot add.", vim.log.levels.WARN)
        return
    end

    if not M.last_selected_vault then
        vim.notify("No vault selected. Please select a vault first in the main menu or using :VaultEnter.", vim.log.levels.WARN)
        return
    end

    local normalized_vault_path = normalize_path(M.last_selected_vault.vaultPath)
    local normalized_file_path = normalize_path(current_file_path)

    -- Ensure vault path also ends with a slash for proper `find` and `sub` behavior, unless it's the root itself.
    if normalized_vault_path ~= "/" and normalized_vault_path:sub(-1) ~= "/" then
        normalized_vault_path = normalized_vault_path .. "/"
    end
    
    -- Check if file path starts with vault path (ensuring it's a sub-path)
    if not (normalized_file_path:sub(1, #normalized_vault_path) == normalized_vault_path) then
        vim.notify("Error: Current file ('" .. current_file_path .. "') is not located within the selected vault's directory structure ('" .. M.last_selected_vault.vaultPath .. "').", vim.log.levels.ERROR)
        return
    end

    -- Calculate relative path
    local relative_path = normalized_file_path:sub(#normalized_vault_path + 1)
    
    -- Ensure no leading slash on relative path, if the vaultPath already includes it in its normalization
    if relative_path:sub(1,1) == "/" then
        relative_path = relative_path:sub(2)
    end
    
    -- Handle case where the file is exactly the vault directory itself
    if relative_path == "" then
        vim.notify("Cannot add the vault directory itself as a file entry (relative path is empty).", vim.log.levels.ERROR)
        return
    end

    -- Check for duplicate file entry in the vault's files array
    local is_duplicate = false
    for _, file_entry in ipairs(M.last_selected_vault.files) do
        if normalize_path(file_entry.fileName) == normalize_path(relative_path) then
            is_duplicate = true
            break
        end
    end

    if is_duplicate then
        vim.notify(string.format("File '%s' is already registered in vault #%d.", relative_path, M.last_selected_vault.vaultNumber), vim.log.levels.INFO)
        return
    end

    -- Add new file entry
    local new_file = {
        fileName = relative_path,
        lastUpdated = os.time(),
        notes = ""
    }
    
    vim.notify("DEBUG: Files array BEFORE insert (count): " .. tostring(#M.last_selected_vault.files), vim.log.levels.INFO)
    table.insert(M.last_selected_vault.files, new_file)
    vim.notify("DEBUG: Files array AFTER insert (count): " .. tostring(#M.last_selected_vault.files), vim.log.levels.INFO)


    M.last_selected_vault.lastUpdated = os.time() -- Update vault's timestamp
    
    vim.notify("DEBUG: Calling save_vault_data...", vim.log.levels.INFO)
    if save_vault_data() then
        vim.notify(string.format("File '%s' added to vault #%d successfully and data saved.", relative_path, M.last_selected_vault.vaultNumber), vim.log.levels.INFO)
        -- Refresh file menu if it's currently open for this vault
        if file_menu_win and vim.api.nvim_win_is_valid(file_menu_win) then
            M.ShowFileMenu(M.last_selected_vault) -- Re-open the file menu for the selected vault to refresh
        end
    else
        vim.notify("Error saving vault data after adding file (save_vault_data failed).", vim.log.levels.ERROR)
    end
end


-- Define the new Vim user commands
vim.api.nvim_create_user_command('VaultEnter', function(opts)
    M.EnterVaultByNumber(opts.args)
end, {
    nargs = 1, -- Expects exactly one argument (the vault number)
    desc = 'Open a vault by its number'
})

vim.api.nvim_create_user_command('VaultDelete', function(opts)
    M.DeleteVaultByNumber(opts.args)
end, {
    nargs = 1, -- Expects exactly one argument (the vault number)
    desc = 'Delete a vault by its number'
})

vim.api.nvim_create_user_command('VaultCreate', function()
    M.CreateVaultWithCwd()
end, {
    nargs = 0, -- Expects no arguments
    desc = 'Create a new vault with the current working directory'
})

vim.api.nvim_create_user_command('VaultFiles', function(opts)
    M.OpenVaultFilesMenu(opts.fargs[1]) -- opts.fargs[1] handles optional argument correctly for nargs='?'
end, {
    nargs = "?", -- Now accepts 0 or 1 argument
    desc = 'Open the File Menu for a specified vault or the last selected one'
})

vim.api.nvim_create_user_command('VaultFileAdd', function()
    M.AddCurrentFileToVault()
end, {
    nargs = 0, -- Expects no arguments
    desc = 'Add the current file to the selected vault'
})

return M

