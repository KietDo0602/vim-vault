local json = require("lib.dkjson")
local CONSTANT = require('constant')
local helper = require('helper')

local M = {}

-- Function to read vault data from JSON file (populates M.vaults directly)
local function read_vault_data_into_M()
    local json_file_path = vim.fn.expand(CONSTANT.FILE_PATH)
    local file, err = io.open(json_file_path, "r")
    local data = {vaults = {}, available_vault_numbers = {}} -- Default empty structure

    if file then
        local content = file:read("*all")
        file:close()
        local success, decoded_data = pcall(json.decode, content)
        if success and decoded_data then
            data = decoded_data
        else
            vim.notify("Error decoding JSON from file: " .. (decoded_data or "unknown error") .. ". Initializing with empty data.", vim.log.levels.ERROR)
        end
    else
        vim.notify("JSON file not found or could not be read: " .. (err or "unknown error") .. ". Creating new vaults file on first save.", vim.log.levels.INFO)
        -- save_vault_data will create it with defaults on first write if it doesn't exist.
    end

    M.vaults = data.vaults or {}
    M.available_vault_numbers = data.available_vault_numbers or {}

    -- Ensure each vault has 'files' and each file has 'notes' and 'lastUpdated', 'line', 'col'
    -- Also ensure each vault has a 'lastSelectedFile'
    for _, vault in ipairs(M.vaults) do
        vault.files = vault.files or {}
        vault.lastSelectedFile = vault.lastSelectedFile or nil -- Initialize if not present
        for _, file_entry in ipairs(vault.files) do
            file_entry.notes = file_entry.notes or ""
            file_entry.lastUpdated = file_entry.lastUpdated or os.time()
            file_entry.line = file_entry.line or 1 -- Default to line 1
            file_entry.col = file_entry.col or 0 -- Default to column 0 (which is 1st character of line)
        end
    end
    return true
end


-- Module-level state to persist sort order across menu re-opens
-- 0: vaultNumber (default), 1: lastUpdated (desc), 2: vaultPath (alpha)
M.current_sort_order = 0

-- Module-level state to persist path display mode for the main vault menu
-- true: full path, false: last folder name only
M.full_path_display_mode = true

-- New: Module-level state to persist path display mode for the file menu
-- true: full path (default), false: last folder name only
M.file_menu_full_path_display_mode = true

-- New: Module-level state for notes menu sorting
-- 0: fileName (alphabetical), 1: lastUpdated (desc)
M.current_notes_sort_order = 0

-- New: Module-level state for notes menu path display
-- true: full path (default), false: last folder name only
M.notes_menu_full_path_display_mode = true

-- Module-level variables for the menu window and buffer, allowing external functions to close them
local main_menu_win = nil
local main_menu_buf = nil
local file_menu_win = nil
local file_menu_buf = nil
local notes_menu_win = nil -- New: Notes menu window
local notes_menu_buf = nil -- New: Notes menu buffer
local notes_editor_win = nil -- New: Notes editor window
local notes_editor_buf = nil -- New: Notes editor buffer

-- New module-level state to store available (vacated) vault numbers
M.available_vault_numbers = {}

-- New module-level state to store the last selected/opened vault object
M.last_selected_vault = nil

-- Centralized store for all vault data
M.vaults = {}

-- Load vault data immediately when the module is required
-- This populates M.vaults and M.last_selected_vault at startup
read_vault_data_into_M()


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

-- Constants for notes menu layout (similar to file menu)
local NOTES_MENU_WIDTH = 80
local NOTES_MENU_HEADER_LINES_COUNT = 3 -- "", "File Name...", "----"
local NOTES_MENU_FOOTER_LINES_COUNT = 7 -- "", "----", "", "Sort: ...", "Path: ...", "Press 'Enter'..."
local NOTES_MENU_SCROLLABLE_AREA_HEIGHT = 10 -- Adjust as needed
local NOTES_MENU_HEIGHT = NOTES_MENU_HEADER_LINES_COUNT + NOTES_MENU_FOOTER_LINES_COUNT + NOTES_MENU_SCROLLABLE_AREA_HEIGHT


-- Helper to get filename and parent directory from a full path using standard Lua string functions
local function get_file_and_dir_from_path(full_path)
    local normalized_path = helper.normalize_path(full_path)

    local last_slash_idx = 0
    -- Iterate backward to find the last slash
    for i = #normalized_path, 1, -1 do
        if normalized_path:sub(i, i) == "/" then
            last_slash_idx = i
            break
        end
    end

    local dir_path
    local file_name
    if last_slash_idx > 0 then
        dir_path = normalized_path:sub(1, last_slash_idx - 1)
        file_name = normalized_path:sub(last_slash_idx + 1)
    else
        -- No slashes, so the whole path is the filename, and directory is assumed to be current working directory
        dir_path = "." -- Use "." to explicitly denote current directory
        file_name = normalized_path
    end

    return dir_path, file_name
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
        local cleaned_path = helper.normalize_path(path)

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


-- Helper to save data to JSON file
local function save_vault_data()
    local json_file_path = vim.fn.expand(CONSTANT.FILE_PATH)
    local updated_data = {
        vaults = M.vaults, -- Use the centralized M.vaults
        available_vault_numbers = M.available_vault_numbers or {} -- Ensure it's always included
    }
    local json_string = json.encode(updated_data, {indent = true})

    if json_string then
        local file, err = io.open(json_file_path, "w")
        if file then
            local success, write_err = pcall(file.write, file, json_string)
            file:close()
            if success then
                return true
            else
                vim.notify("Error during file write operation: " .. (write_err or "unknown error"), vim.log.levels.ERROR)
                return false
            end
        else
            vim.notify("Error: Could not open JSON file for writing: " .. (err or "unknown error"), vim.log.levels.ERROR)
            return false
        end
    else
        vim.notify("Error: Could not encode JSON data. JSON string is nil.", vim.log.levels.ERROR)
        return false
    end
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
    if notes_menu_win and vim.api.nvim_win_is_valid(notes_menu_win) then -- Close notes menu
        vim.api.nvim_win_close(notes_menu_win, true)
        notes_menu_win = nil
        notes_menu_buf = nil
    end
    if notes_editor_win and vim.api.nvim_win_is_valid(notes_editor_win) then -- Close notes editor
        vim.api.nvim_win_close(notes_editor_win, true)
        notes_editor_win = nil
        notes_editor_buf = nil
    end
end


--------------------------------------------------------------------------------
-- Main Vault Menu Functions
--------------------------------------------------------------------------------

function M.ShowVaultMenu()
    close_all_menus() -- Close any existing menus

    -- Data is already loaded globally via read_vault_data_into_M() at module start.
    -- Re-read here to ensure freshest data if changes were made outside the current session.
    read_vault_data_into_M()

    -- Apply sorting based on the current module-level sort order
    helper.sort_vaults(M.vaults, M.current_sort_order)

    -- Menu state variables (local to this invocation of ShowVaultMenu, captured by closures)
    local current_selected_vault_idx = 0 -- Default to no selection initially
    local current_scroll_top_line_idx = 0
    local all_vault_lines = {}
    local vault_line_map = {}
    local highlight_ns_id = vim.api.nvim_create_namespace('vault_menu_highlight')

    -- Determine default selection: vault matching current CWD
    local current_cwd = helper.normalize_path(vim.fn.getcwd())
    for i, vault in ipairs(M.vaults) do
        if helper.normalize_path(vault.vaultPath) == current_cwd then
            current_selected_vault_idx = i
            break
        end
    end

    -- If no vault matches CWD and there are vaults, select the first one.
    -- If there are no vaults at all, current_selected_vault_idx remains 0.
    if current_selected_vault_idx == 0 and #M.vaults > 0 then
        current_selected_vault_idx = 1
    end

    -- Set last_selected_vault based on the final current_selected_vault_idx
    M.last_selected_vault = (current_selected_vault_idx > 0) and M.vaults[current_selected_vault_idx] or nil

    -- Function to generate all vault lines and their mappings
    local function generate_full_vault_display_info()
        local lines = {}
        local line_map = {} -- This is the table that becomes vault_line_map
        local current_line_idx = 0 -- 0-based index for the 'lines' table

        local path_max_width = 40

        for i, vault in ipairs(M.vaults) do -- It iterates M.vaults
            local formatted_paths = format_path(vault.vaultPath, path_max_width, M.full_path_display_mode)
            local timestamp = helper.format_timestamp(vault.lastUpdated)

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

    -- Generate full display info for initial calculation
    all_vault_lines, vault_line_map = generate_full_vault_display_info()

    -- Function to update the menu content and highlight in the Neovim buffer
    local function update_main_menu_display()
        -- Regenerate full vault info (in case data changed, e.g., after add/delete/modify)
        -- This call is intentionally placed here to re-generate the map for display updates
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
        if current_selected_vault_idx > 0 then
            local range = vault_line_map[current_selected_vault_idx]
            if range then
                local highlight_start_line_in_buffer = MAIN_MENU_HEADER_LINES_COUNT + (range.start_line_idx - current_scroll_top_line_idx)
                local highlight_end_line_in_buffer = MAIN_MENU_HEADER_LINES_COUNT + (range.end_line_idx - current_scroll_top_line_idx)

                highlight_start_line_in_buffer = math.max(MAIN_MENU_HEADER_LINES_COUNT, highlight_start_line_in_buffer)
                highlight_end_line_in_buffer = math.min(MAIN_MENU_HEADER_LINES_COUNT + MAIN_MENU_SCROLLABLE_AREA_HEIGHT - 1, highlight_end_line_in_buffer)

                for line_num = highlight_start_line_in_buffer, highlight_end_line_in_buffer do
                    if line_num >= MAIN_MENU_HEADER_LINES_COUNT and line_num < MAIN_MENU_HEADER_LINES_COUNT + MAIN_MENU_SCROLLABLE_AREA_HEIGHT then
                        vim.api.nvim_buf_add_highlight(main_menu_buf, highlight_ns_id, 'Visual', line_num, 0, -1)
                    end
                end
            else
                current_selected_vault_idx = 0
                current_scroll_top_line_idx = 0
                M.last_selected_vault = nil
            end
        end

        -- Set cursor position
        if current_selected_vault_idx > 0 then
            local range = vault_line_map[current_selected_vault_idx]
            if range then
                local cursor_line_in_buffer = MAIN_MENU_HEADER_LINES_COUNT + (range.start_line_idx - current_scroll_top_line_idx)
                vim.api.nvim_win_set_cursor(main_menu_win, {cursor_line_in_buffer + 1, 0})
            end
        else
            vim.api.nvim_win_set_cursor(main_menu_win, {MAIN_MENU_HEADER_LINES_COUNT + 1, 0})
        end
    end

    -- Navigation logic for moving the cursor and adjusting scroll
    local function move_main_menu_cursor(direction)
        if #M.vaults == 0 then return end

        local new_selected_vault_idx = current_selected_vault_idx + direction
        if current_selected_vault_idx == 0 and direction == 1 then
            new_selected_vault_idx = 1
        end

        new_selected_vault_idx = math.max(1, math.min(#M.vaults, new_selected_vault_idx))

        if new_selected_vault_idx == current_selected_vault_idx then return end

        current_selected_vault_idx = new_selected_vault_idx
        M.last_selected_vault = M.vaults[current_selected_vault_idx]

        local selected_vault_line_range = nil
        if current_selected_vault_idx > 0 then
            selected_vault_line_range = vault_line_map[current_selected_vault_idx]
        end

        if not selected_vault_line_range then
            current_selected_vault_idx = 0
            current_scroll_top_line_idx = 0
            M.last_selected_vault = nil
            update_main_menu_display()
            return
        end

        local selected_vault_start_line = selected_vault_line_range.start_line_idx
        local selected_vault_end_line = selected_vault_line_range.end_line_idx

        if selected_vault_start_line < current_scroll_top_line_idx then
            current_scroll_top_line_idx = selected_vault_start_line
        elseif selected_vault_end_line >= current_scroll_top_line_idx + MAIN_MENU_SCROLLABLE_AREA_HEIGHT then
            current_scroll_top_line_idx = selected_vault_end_line - MAIN_MENU_SCROLLABLE_AREA_HEIGHT + 1
        end

        local max_scroll_top_line_idx = math.max(0, #all_vault_lines - MAIN_MENU_SCROLLABLE_AREA_HEIGHT)
        current_scroll_top_line_idx = math.max(0, math.min(current_scroll_top_line_idx, max_scroll_top_line_idx))

        update_main_menu_display()
    end

    -- Refresh function (closes current window and re-opens menu to reflect changes)
    local function refresh_main_menu()
        close_all_menus()
        M.ShowVaultMenu()
    end

    -- Create new buffer and window for the menu
    main_menu_buf = vim.api.nvim_create_buf(false, true)
    main_menu_win = vim.api.nvim_open_win(main_menu_buf, true, {
        relative = 'editor',
        width = MAIN_MENU_WIDTH,
        height = MAIN_MENU_HEIGHT,
        col = (vim.o.columns - MAIN_MENU_WIDTH) / 2,
        row = (vim.o.lines - MAIN_MENU_HEIGHT) / 2,
        style = 'minimal',
        border = 'rounded',
        title = ' Vault ',
        title_pos = 'center'
    })

    -- Set buffer options
    vim.api.nvim_buf_set_option(main_menu_buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(main_menu_buf, 'modifiable', false)


    -- Initial display update - This section calculates initial scroll based on selection
    local selected_vault_line_range = nil
    if current_selected_vault_idx > 0 then
        selected_vault_line_range = vault_line_map[current_selected_vault_idx]
    end

    if selected_vault_line_range then
        local selected_vault_start_line = selected_vault_line_range.start_line_idx
        local selected_vault_end_line = selected_vault_line_range.end_line_idx

        if selected_vault_start_line < current_scroll_top_line_idx then
            current_scroll_top_line_idx = selected_vault_start_line
        elseif selected_vault_end_line >= current_scroll_top_line_idx + MAIN_MENU_SCROLLABLE_AREA_HEIGHT then
            current_scroll_top_line_idx = selected_vault_end_line - MAIN_MENU_SCROLLABLE_AREA_HEIGHT + 1
        end
        local max_scroll_top_line_idx = math.max(0, #all_vault_lines - MAIN_MENU_SCROLLABLE_AREA_HEIGHT)
        current_scroll_top_line_idx = math.max(0, math.min(current_scroll_top_line_idx, max_scroll_top_line_idx))
    else
        current_selected_vault_idx = 0
        current_scroll_top_line_idx = 0
        M.last_selected_vault = nil
    end
    update_main_menu_display()


    -- Action handlers (modified to use refresh_main_menu for re-rendering)
    local function create_new_vault_interactive()
        -- Determine the new vault number
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
                        files = {}
                    }
                    table.insert(M.vaults, new_vault)

                    if save_vault_data() then
                        M.last_selected_vault = new_vault
                        refresh_main_menu()
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
            if current_selected_vault_idx > 0 and current_selected_vault_idx <= #M.vaults and vault.vaultNumber == M.vaults[current_selected_vault_idx].vaultNumber then
                vault_to_modify = vault
                break
            end
        end

        if not vault_to_modify then return end

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
                        M.last_selected_vault = vault_to_modify
                        refresh_main_menu()
                    end
                else
                    vim.notify("Error: Invalid directory path", vim.log.levels.ERROR)
                end
            end
        end)
    end

    local function delete_vault_interactive()
        if #M.vaults == 0 then vim.notify("No vaults to delete.", vim.log.levels.INFO); return end
        local vault_to_delete_idx_in_table = current_selected_vault_idx
        local vault_to_delete = M.vaults[vault_to_delete_idx_in_table]
        if not vault_to_delete then return end

        local vault_path = vault_to_delete.vaultPath
        local vault_number = vault_to_delete.vaultNumber

        vim.ui.select({'Yes', 'No'}, {
            prompt = string.format('Are you sure you want to delete Vault #%d (%s)? This action is permanent.', vault_number, vault_path),
        }, function(choice)
            if choice == 'Yes' then
                table.remove(M.vaults, vault_to_delete_idx_in_table)
                table.insert(M.available_vault_numbers, vault_number)
                table.sort(M.available_vault_numbers)

                if save_vault_data() then
                    vim.api.nvim_out_write("\n")
                    vim.notify(string.format("Vault #%d (%s) deleted successfully.", vault_number, vault_path), vim.log.levels.INFO)
                    if M.last_selected_vault and M.last_selected_vault.vaultNumber == vault_number then
                        M.last_selected_vault = nil
                    end
                    close_all_menus()
                end
            else
                vim.notify("Vault deletion cancelled.", vim.log.levels.INFO)
            end
        end)
    end

    local function open_vault_from_menu()
        if #M.vaults == 0 then vim.notify("No vaults to open.", vim.log.levels.INFO); return end
        local vault_to_open = M.vaults[current_selected_vault_idx]
        if not vault_to_open then return end

        local vault_path = vault_to_open.vaultPath
        M.last_selected_vault = vault_to_open
        close_all_menus()
        vim.cmd('cd ' .. vim.fn.fnameescape(vault_path))
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
        M.current_sort_order = (M.current_sort_order + 1) % 3
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
        once = true,
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

-- Autocommand group for vault file buffer events
local vault_file_autocmd_grp = vim.api.nvim_create_augroup('VaultFileAutoCommands', { clear = true })

-- Function to save current buffer position to JSON for a given file path
local function save_file_position_to_json(file_path_to_save)
    if not file_path_to_save or file_path_to_save == "" then return end

    local current_buf = vim.api.nvim_get_current_buf()
    local current_buf_file_path = vim.api.nvim_buf_get_name(current_buf)

    -- Only save if the buffer's file path matches the one we intended to save
    if current_buf_file_path ~= file_path_to_save then
        return
    end

    local current_line = vim.api.nvim_win_get_cursor(0)[1]
    local current_col = vim.api.nvim_win_get_cursor(0)[2]

    for _, vault in ipairs(M.vaults) do
        local normalized_vault_path = helper.normalize_path(vault.vaultPath)
        if normalized_vault_path ~= "/" and normalized_vault_path:sub(-1) ~= "/" then
            normalized_vault_path = normalized_vault_path .. "/"
        end

        local normalized_file_path = helper.normalize_path(file_path_to_save)
        
        if normalized_file_path:sub(1, #normalized_vault_path) == normalized_vault_path then
            local relative_path = normalized_file_path:sub(#normalized_vault_path + 1)
            if relative_path:sub(1,1) == "/" then
                relative_path = relative_path:sub(2)
            end

            for _, file_entry in ipairs(vault.files) do
                if helper.normalize_path(file_entry.fileName) == helper.normalize_path(relative_path) then
                    file_entry.line = current_line
                    file_entry.col = current_col
                    file_entry.lastUpdated = os.time()
                    save_vault_data()
                    return
                end
            end
        end
    end
end

-- Moved open_file_entry to M module so it can be called from VaultFileNext
function M.open_file_entry(vault_object, target_file_entry, current_selected_file_idx, files_in_vault)
    if #files_in_vault == 0 then vim.notify("No files to open.", vim.log.levels.INFO); return end
    local file_to_open = target_file_entry or files_in_vault[current_selected_file_idx] -- Use argument or current selection
    if not file_to_open then return end

    -- Use vim.fn.resolve for robust path resolution
    local full_file_path = vim.fn.resolve(vault_object.vaultPath .. "/" .. file_to_open.fileName)
    close_all_menus() -- Close file menu
    vim.cmd("edit " .. vim.fn.fnameescape(full_file_path))

    -- Get the current buffer for the opened file
    local current_buf = vim.api.nvim_get_current_buf()

    -- Clear any existing BufLeave autocommands for this buffer to prevent duplicates
    vim.api.nvim_exec_autocmds('BufLeave', { buffer = current_buf, group = vault_file_autocmd_grp })

    -- Set an autocommand to save position when this specific buffer is left
    vim.api.nvim_create_autocmd('BufLeave', {
        group = vault_file_autocmd_grp,
        buffer = current_buf,
        callback = function()
            save_file_position_to_json(full_file_path)
        end,
        desc = "Save vault file position on BufLeave"
    })

    local target_line = 1
    local target_col = 0

    -- Try to get the position of the last edit (the "." mark) in this buffer
    local last_edit_pos = vim.api.nvim_buf_get_mark(current_buf, ".")

    -- Check if the '.' mark is valid (i.e., not [0,0] for an empty buffer or non-existent mark)
    -- The '.' mark is typically valid if the buffer has been modified in the current session.
    -- If the buffer content is empty, get_mark might return [0,0]. Also check if line > 0.
    if last_edit_pos and last_edit_pos[1] > 0 then
        -- If a valid '.' mark exists, use its line and column (session-specific last edit)
        target_line = last_edit_pos[1]
        target_col = last_edit_pos[2]
    else
        -- Otherwise, use the stored line and column from the vault data
        target_line = file_to_open.line or 1
        target_col = file_to_open.col or 0
    end

    -- Validate cursor position before setting it
    local total_lines = vim.api.nvim_buf_line_count(current_buf)
    if target_line < 1 then
        target_line = 1
    elseif target_line > total_lines then
        target_line = total_lines
    end

    -- Get the length of the target line to validate column position
    local line_content = ""
    if total_lines > 0 then
        local lines = vim.api.nvim_buf_get_lines(current_buf, target_line - 1, target_line, false)
        if #lines > 0 then
            line_content = lines[1]
        end
    end

    -- Validate column position
    if target_col < 0 then
        target_col = 0
    elseif target_col > #line_content then
        target_col = #line_content
    end

    -- Safely set cursor position with error handling
    local success, err = pcall(vim.api.nvim_win_set_cursor, 0, {target_line, target_col})
    if not success then
        -- Fallback to safe position if there's still an error
        vim.notify("Warning: Could not set cursor to stored position. Using line 1, column 0.", vim.log.levels.WARN)
        vim.api.nvim_win_set_cursor(0, {1, 0})
    end

    vim.cmd("normal! zz")

    -- Update last selected file in the vault object and save data
    vault_object.lastSelectedFile = file_to_open.fileName
    vault_object.lastUpdated = os.time()
    save_vault_data()
end

function M.ShowFileMenu(vault_object)
    close_all_menus()

    if not vault_object or not vault_object.vaultPath or not vault_object.files then
        vim.notify("Invalid vault selected for File Menu.", vim.log.levels.ERROR)
        return
    end

    local files_in_vault = vim.deepcopy(vault_object.files)
    helper.sort_files(files_in_vault, current_file_sort_order)

    local current_selected_file_idx = 1
    local current_file_scroll_top_line_idx = 0
    local all_file_display_lines = {}
    local file_line_map = {}

    local highlight_ns_id = vim.api.nvim_create_namespace('file_menu_highlight')

    -- Determine initial selection based on lastSelectedFile
    if vault_object.lastSelectedFile then
        local found_idx = nil
        for i, file_entry in ipairs(files_in_vault) do
            if file_entry.fileName == vault_object.lastSelectedFile then
                found_idx = i
                break
            end
        end
        if found_idx then
            current_selected_file_idx = found_idx
        end
    end


    -- Function to generate all file display lines
    local function generate_full_file_display_info()
        local lines = {}
        local line_map = {}
        local current_line_idx = 0

        local filename_max_width = 50

        for i, file_entry in ipairs(files_in_vault) do
            local formatted_filename = format_path(file_entry.fileName, filename_max_width, M.file_menu_full_path_display_mode)
            local timestamp = helper.format_timestamp(file_entry.lastUpdated)

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

        -- Display current file path display mode
        local file_path_display_text = ""
        if M.file_menu_full_path_display_mode then
            file_path_display_text = "Path: Full (h)"
        else
            file_path_display_text = "Path: Name Only (h)"
        end
        table.insert(display_lines, file_path_display_text)

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
        read_vault_data_into_M()
        local found_vault = nil
        for _, v in ipairs(M.vaults) do
            if v.vaultNumber == vault_object.vaultNumber then
                found_vault = v
                break
            end
        end

        close_all_menus()
        if found_vault then
            M.ShowFileMenu(found_vault)
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
                local full_file_path = vim.fn.resolve(vault_object.vaultPath .. "/" .. relative_path)

                local parent_dir, _ = get_file_and_dir_from_path(full_file_path)
                if vim.fn.isdirectory(parent_dir) == 0 then
                    local confirm_create_dir = vim.fn.confirm("Parent directory '" .. parent_dir .. "' does not exist. Create it?", "&Yes\n&No")
                    if confirm_create_dir == 1 then
                        vim.fn.mkdir(parent_dir, "p")
                    else
                        vim.notify("File creation cancelled (directory not created).", vim.log.levels.INFO)
                        return
                    end
                end

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
                    notes = "",
                    line = 1,
                    col = 0
                }
                table.insert(vault_object.files, new_file)

                vault_object.lastUpdated = os.time()
                vault_object.lastSelectedFile = new_file.fileName

                if save_vault_data() then
                    vim.cmd("edit " .. vim.fn.fnameescape(full_file_path))
                    refresh_file_menu()
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
        local old_full_path = vim.fn.resolve(vault_object.vaultPath .. "/" .. old_relative_path)

        vim.ui.input({
            prompt = "Enter new file path (relative to vault): ",
            default = old_relative_path
        }, function(new_relative_path)
            if new_relative_path and new_relative_path ~= "" then
                local new_full_path = vim.fn.resolve(vault_object.vaultPath .. "/" .. new_relative_path)

                if old_full_path == new_full_path then
                    vim.notify("New path is the same as old path. No changes made.", vim.log.levels.INFO)
                    return
                end

                if vim.fn.filereadable(new_full_path) == 1 or vim.fn.isdirectory(new_full_path) == 1 then
                    vim.notify("Error: Target file/directory already exists: " .. new_full_path, vim.log.levels.ERROR)
                    return
                end

                local new_parent_dir, _ = get_file_and_dir_from_path(new_full_path)
                if vim.fn.isdirectory(new_parent_dir) == 0 then
                     local confirm_create_dir = vim.fn.confirm("Parent directory '" .. new_parent_dir .. "' does not exist. Create it?", "&Yes\n&No")
                    if confirm_create_dir == 1 then
                        vim.fn.mkdir(new_parent_dir, "p")
                    else
                        vim.notify("File rename/move cancelled (directory not created).", vim.log.levels.INFO)
                        return
                    end
                end

                local success, err = pcall(vim.cmd, 'silent !mv ' .. vim.fn.fnameescape(old_full_path) .. ' ' .. vim.fn.fnameescape(new_full_path))
                if not success then
                    vim.notify("Error renaming file on disk: " .. err, vim.log.levels.ERROR)
                    return
                end

                file_to_modify.fileName = new_relative_path
                file_to_modify.lastUpdated = os.time()
                file_to_modify.line = file_to_modify.line or 1
                file_to_modify.col = file_to_modify.col or 0
                vault_object.lastUpdated = os.time()
                vault_object.lastSelectedFile = file_to_modify.fileName

                if save_vault_data() then
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

        local full_file_path = vim.fn.resolve(vault_object.vaultPath .. "/" .. file_to_delete.fileName)

        vim.ui.select({'Yes', 'No'}, {
            prompt = string.format('Delete file "%s" from vault data? (File on disk will NOT be deleted)', file_to_delete.fileName),
        }, function(choice)
            if choice == 'Yes' then
                local original_idx = nil
                for i, f in ipairs(vault_object.files) do
                    if f.fileName == file_to_delete.fileName then
                        original_idx = i
                        break
                    end
                end

                if original_idx then
                    table.remove(vault_object.files, original_idx)
                    vault_object.lastUpdated = os.time()
                    if vault_object.lastSelectedFile == file_to_delete.fileName then
                        vault_object.lastSelectedFile = nil
                    end

                    vim.api.nvim_out_write("\n")
                    if save_vault_data() then
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
        title = ' Files in vault: ' .. (last_folder_name or "N/A"),
        title_pos = 'center'
    })

    vim.api.nvim_buf_set_option(file_menu_buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(file_menu_buf, 'modifiable', false)

    -- Initial display
    if #files_in_vault > 0 then
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
    vim.keymap.set('n', '<CR>', function() M.open_file_entry(vault_object, nil, current_selected_file_idx, files_in_vault) end, opts)
    vim.keymap.set('n', 'q', function() close_all_menus() end, opts)
    vim.keymap.set('n', '<Esc>', function() close_all_menus() end, opts)

    -- Key mapping for sorting files
    vim.keymap.set('n', 's', function()
        current_file_sort_order = (current_file_sort_order + 1) % 2
        helper.sort_files(files_in_vault, current_file_sort_order)
        update_file_menu_display()
    end, opts)

    -- New key mapping for toggling file path display in file menu
    vim.keymap.set('n', 'h', function()
        M.file_menu_full_path_display_mode = not M.file_menu_full_path_display_mode
        update_file_menu_display()
    end, opts)


    -- Disable other movements for file menu
    local disabled_keys_file_menu = {'l', '<Left>', '<Right>', 'w', 'b', 'e', '0', '$', '^', 'G', 'gg'}
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
-- Notes Menu Functions
--------------------------------------------------------------------------------

-- Autocommand group for notes editor buffer events
local notes_editor_autocmd_grp = vim.api.nvim_create_augroup('VaultNotesEditorAutoCommands', { clear = true })


function M.EditFileNotes(vault_object, file_entry)
    close_all_menus()

    if not vault_object or not file_entry then
        vim.notify("Invalid vault or file entry for notes editing.", vim.log.levels.ERROR)
        return
    end

    notes_editor_buf = vim.api.nvim_create_buf(false, true)

    notes_editor_win = vim.api.nvim_open_win(notes_editor_buf, true, {
        relative = 'editor',
        width = math.floor(vim.o.columns * 0.8),
        height = math.floor(vim.o.lines * 0.6),
        col = (vim.o.columns - math.floor(vim.o.columns * 0.8)) / 2,
        row = (vim.o.lines - math.floor(vim.o.lines * 0.6)) / 2,
        style = 'minimal',
        border = 'rounded',
        title = ' Notes for: ' .. file_entry.fileName,
        title_pos = 'center'
    })

    vim.api.nvim_buf_set_option(notes_editor_buf, 'modifiable', true)
    vim.api.nvim_buf_set_option(notes_editor_buf, 'bufhidden', 'wipe')

    -- Store identifiers (not direct references) to retrieve the correct entry later
    vim.api.nvim_buf_set_var(notes_editor_buf, 'vault_number_id', vault_object.vaultNumber)
    vim.api.nvim_buf_set_var(notes_editor_buf, 'file_name_id', file_entry.fileName)


    local note_lines = {}
    -- Load notes, ensuring empty lines are preserved.
    -- vim.split is preferred over string.gmatch for this purpose.
    if file_entry.notes and #file_entry.notes > 0 then
        note_lines = vim.split(file_entry.notes, "\n", {plain=true})
    end
    vim.api.nvim_buf_set_lines(notes_editor_buf, 0, -1, false, note_lines)

    vim.api.nvim_buf_set_option(notes_editor_buf, 'modified', false)

    vim.api.nvim_win_set_cursor(notes_editor_win, {1,0})
    -- Removed vim.cmd("startinsert") to default to normal mode

    local function save_and_close_notes_editor()
        vim.notify("Attempting to save notes and close editor.", vim.log.levels.INFO)
        if notes_editor_buf and vim.api.nvim_buf_is_valid(notes_editor_buf) then
            local current_notes_content = table.concat(vim.api.nvim_buf_get_lines(notes_editor_buf, 0, -1, false), "\n")

            -- Retrieve identifiers
            local vault_num_id = vim.api.nvim_buf_get_var(notes_editor_buf, 'vault_number_id')
            local file_name_id = vim.api.nvim_buf_get_var(notes_editor_buf, 'file_name_id')

            vim.notify("Retrieved IDs: Vault=" .. tostring(vault_num_id) .. ", File='" .. tostring(file_name_id) .. "'", vim.log.levels.INFO)

            local target_vault = nil
            local target_file_entry = nil

            -- Re-locate the actual file entry in M.vaults
            for _, vault in ipairs(M.vaults) do
                if vault.vaultNumber == vault_num_id then
                    target_vault = vault
                    for _, file_e in ipairs(target_vault.files) do
                        if file_e.fileName == file_name_id then
                            target_file_entry = file_e
                            break
                        end
                    end
                    break
                end
            end

            if target_file_entry then
                vim.notify("Target file entry re-located. Current notes in buffer len: " .. #current_notes_content .. ", Stored notes len: " .. #target_file_entry.notes, vim.log.levels.INFO)
                if current_notes_content ~= target_file_entry.notes then -- Only save if notes have actually changed
                    target_file_entry.notes = current_notes_content
                    target_file_entry.lastUpdated = os.time()
                    if save_vault_data() then
                        vim.notify("Notes for '" .. target_file_entry.fileName .. "' saved successfully.", vim.log.levels.INFO)
                        -- Set modified to false only after a successful save
                        vim.api.nvim_buf_set_option(notes_editor_buf, 'modified', false)
                    else
                        vim.notify("Error saving notes for '" .. target_file_entry.fileName .. "'.", vim.log.levels.ERROR)
                    end
                else
                    vim.notify("No changes detected for notes of '" .. target_file_entry.fileName .. "'. Not saving.", vim.log.levels.INFO)
                end
            else
                vim.notify("Could not find the target file entry in vault data (after re-location). Notes not saved.", vim.log.levels.ERROR)
            end
        else
            vim.notify("Notes editor buffer is invalid. Skipping save.", vim.log.levels.WARN)
        end

        -- Always close the window/buffer regardless of whether changes were saved
        if notes_editor_win and vim.api.nvim_win_is_valid(notes_editor_win) then
            vim.api.nvim_win_close(notes_editor_win, true)
            vim.notify("Notes editor window closed.", vim.log.levels.INFO)
        else
            vim.notify("Notes editor window not valid or already closed.", vim.log.levels.WARN)
        end
        -- Clear module-level references
        notes_editor_win = nil
        notes_editor_buf = nil

        -- Ensure any autocmds specific to this buffer are cleared now that the buffer is gone
        vim.api.nvim_del_augroup_by_name('VaultNotesEditorAutoCommands')
        vim.api.nvim_create_augroup('VaultNotesEditorAutoCommands', { clear = true })
        vim.notify("Notes editor autocommand group cleared.", vim.log.levels.INFO)
    end

    -- Clear any existing autocmds for this specific group before creating new ones
    vim.api.nvim_del_augroup_by_name('VaultNotesEditorAutoCommands')
    vim.api.nvim_create_augroup('VaultNotesEditorAutoCommands', { clear = true })

    -- Autocommand to save notes when the buffer is left or wiped out.
    -- This acts as a fallback if custom mappings aren't used or if Neovim's quit logic takes over.
    vim.api.nvim_create_autocmd({'BufLeave', 'BufWipeout'}, {
        group = 'VaultNotesEditorAutoCommands',
        buffer = notes_editor_buf,
        callback = function()
            -- Only run save_and_close if the buffer is still valid and not already handled
            if notes_editor_buf and vim.api.nvim_buf_is_valid(notes_editor_buf) then
                save_and_close_notes_editor()
            end
        end,
        desc = "Fallback save notes on BufLeave/BufWipeout"
    })

    -- Set up key mappings for notes editor
    local opts_normal = {buffer = notes_editor_buf, nowait = true, silent = true}
    local opts_insert = {buffer = notes_editor_buf, nowait = true, silent = true} 

    -- Normal mode mappings: 'q' and '<Esc>' in normal mode will now save and close.
    vim.keymap.set('n', 'q', save_and_close_notes_editor, opts_normal)
    vim.keymap.set('n', '<Esc>', save_and_close_notes_editor, opts_normal)

    -- Insert mode mappings: 'jk' and '<Esc>' will ONLY exit insert mode, allowing normal mode editing.
    vim.keymap.set('i', 'jk', function() vim.cmd("stopinsert") end, opts_insert)
    vim.keymap.set('i', '<Esc>', function() vim.cmd("stopinsert") end, opts_insert)

    -- Disabled keys for notes editor. No keys related to basic editing or navigation should be disabled.
    -- These are very specific commands that might conflict with the floating window's management.
    local disabled_keys_notes_editor = {
        -- Only disable commands that affect window/buffer management in a way that conflicts
        -- with the floating window's intended lifecycle or the vault data structure directly.
        -- For a normal editing experience, almost nothing should be explicitly disabled here.
    }
    for _, key in ipairs(disabled_keys_notes_editor) do
        vim.keymap.set('n', key, '<Nop>', opts_normal)
    end
end

function M.ShowNotesMenu(vault_object)
    close_all_menus()

    if not vault_object or not vault_object.vaultPath or not vault_object.files then
        vim.notify("Invalid vault selected for Notes Menu.", vim.log.levels.ERROR)
        return
    end

    local files_in_vault = vim.deepcopy(vault_object.files)
    helper.sort_files(files_in_vault, M.current_notes_sort_order)

    local current_selected_file_idx = 1
    local current_notes_scroll_top_line_idx = 0
    local all_notes_display_lines = {}
    local notes_line_map = {}

    local highlight_ns_id = vim.api.nvim_create_namespace('notes_menu_highlight')

    -- Determine initial selection based on lastSelectedFile
    if vault_object.lastSelectedFile then
        local found_idx = nil
        for i, file_entry in ipairs(files_in_vault) do
            if file_entry.fileName == vault_object.lastSelectedFile then
                found_idx = i
                break
            end
        end
        if found_idx then
            current_selected_file_idx = found_idx
        end
    end

    -- Function to generate all file display lines for notes menu
    local function generate_full_notes_display_info()
        local lines = {}
        local line_map = {}
        local current_line_idx = 0

        local filename_max_width = 50

        for i, file_entry in ipairs(files_in_vault) do
            local formatted_filename = format_path(file_entry.fileName, filename_max_width, M.notes_menu_full_path_display_mode)
            local timestamp = helper.format_timestamp(file_entry.lastUpdated)

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

    -- Function to update the notes menu content
    local function update_notes_menu_display()
        all_notes_display_lines, notes_line_map = generate_full_notes_display_info()

        local display_lines = {}

        -- Header
        table.insert(display_lines, "")
        table.insert(display_lines, string.format("%-50s %-20s", "File Name", "Updated"))
        table.insert(display_lines, string.rep("─", NOTES_MENU_WIDTH - 2))

        -- Scrollable content
        local num_total_file_lines = #all_notes_display_lines
        local current_display_end_line_idx = math.min(current_notes_scroll_top_line_idx + NOTES_MENU_SCROLLABLE_AREA_HEIGHT, num_total_file_lines)

        for i = current_notes_scroll_top_line_idx, current_display_end_line_idx - 1 do
            table.insert(display_lines, all_notes_display_lines[i + 1])
        end

        -- Pad with empty lines
        while #display_lines - NOTES_MENU_HEADER_LINES_COUNT < NOTES_MENU_SCROLLABLE_AREA_HEIGHT do
            table.insert(display_lines, "")
        end

        -- Footer
        table.insert(display_lines, "")
        table.insert(display_lines, string.rep("─", NOTES_MENU_WIDTH - 2))
        table.insert(display_lines, "")

        local sort_text = ""
        if M.current_notes_sort_order == 0 then
            sort_text = "Sort: Name (s)"
        elseif M.current_notes_sort_order == 1 then
            sort_text = "Sort: Updated (s)"
        end
        table.insert(display_lines, sort_text)

        -- Display current file path display mode
        local notes_path_display_text = ""
        if M.notes_menu_full_path_display_mode then
            notes_path_display_text = "Path: Full (h)"
        else
            notes_path_display_text = "Path: Name Only (h)"
        end
        table.insert(display_lines, notes_path_display_text)


        table.insert(display_lines, "Press 'Enter' to edit notes, 'q' to quit")

        vim.api.nvim_buf_set_option(notes_menu_buf, 'modifiable', true)
        vim.api.nvim_buf_set_lines(notes_menu_buf, 0, -1, false, display_lines)
        vim.api.nvim_buf_set_option(notes_menu_buf, 'modifiable', false)

        -- Clear existing highlights
        vim.api.nvim_buf_clear_namespace(notes_menu_buf, highlight_ns_id, 0, -1)

        -- Apply highlight to the currently selected file
        if #files_in_vault > 0 and notes_line_map[current_selected_file_idx] then
            local range = notes_line_map[current_selected_file_idx]
            local highlight_start_line_in_buffer = NOTES_MENU_HEADER_LINES_COUNT + (range.start_line_idx - current_notes_scroll_top_line_idx)
            local highlight_end_line_in_buffer = NOTES_MENU_HEADER_LINES_COUNT + (range.end_line_idx - current_notes_scroll_top_line_idx)

            highlight_start_line_in_buffer = math.max(NOTES_MENU_HEADER_LINES_COUNT, highlight_start_line_in_buffer)
            highlight_end_line_in_buffer = math.min(NOTES_MENU_HEADER_LINES_COUNT + NOTES_MENU_SCROLLABLE_AREA_HEIGHT - 1, highlight_end_line_in_buffer)

            for line_num = highlight_start_line_in_buffer, highlight_end_line_in_buffer do
                if line_num >= NOTES_MENU_HEADER_LINES_COUNT and line_num < NOTES_MENU_HEADER_LINES_COUNT + NOTES_MENU_SCROLLABLE_AREA_HEIGHT then
                    vim.api.nvim_buf_add_highlight(notes_menu_buf, highlight_ns_id, 'Visual', line_num, 0, -1)
                end
            end
        end

        -- Set cursor position
        if #files_in_vault > 0 and notes_line_map[current_selected_file_idx] then
            local range = notes_line_map[current_selected_file_idx]
            local cursor_line_in_buffer = NOTES_MENU_HEADER_LINES_COUNT + (range.start_line_idx - current_notes_scroll_top_line_idx)
            vim.api.nvim_win_set_cursor(notes_menu_win, {cursor_line_in_buffer + 1, 0})
        else
            vim.api.nvim_win_set_cursor(notes_menu_win, {NOTES_MENU_HEADER_LINES_COUNT + 1, 0})
        end
    end

    -- Navigation logic for notes menu
    local function move_notes_cursor(direction)
        if #files_in_vault == 0 then return end

        local new_selected_file_idx = current_selected_file_idx + direction
        new_selected_file_idx = math.max(1, math.min(#files_in_vault, new_selected_file_idx))

        if new_selected_file_idx == current_selected_file_idx then return end

        current_selected_file_idx = new_selected_file_idx

        local selected_file_line_range = notes_line_map[current_selected_file_idx]
        local selected_file_start_line = selected_file_line_range.start_line_idx
        local selected_file_end_line = selected_file_line_range.end_line_idx

        if selected_file_start_line < current_notes_scroll_top_line_idx then
            current_notes_scroll_top_line_idx = selected_file_start_line
        elseif selected_file_end_line >= current_notes_scroll_top_line_idx + NOTES_MENU_SCROLLABLE_AREA_HEIGHT then
            current_notes_scroll_top_line_idx = selected_file_end_line - NOTES_MENU_SCROLLABLE_AREA_HEIGHT + 1
        end

        local max_scroll_top_line_idx = math.max(0, #all_notes_display_lines - NOTES_MENU_SCROLLABLE_AREA_HEIGHT)
        current_notes_scroll_top_line_idx = math.max(0, math.min(current_notes_scroll_top_line_idx, max_scroll_top_line_idx))

        update_notes_menu_display()
    end

    local function refresh_notes_menu()
        read_vault_data_into_M()
        local found_vault = nil
        for _, v in ipairs(M.vaults) do
            if v.vaultNumber == vault_object.vaultNumber then
                found_vault = v
                break
            end
        end

        close_all_menus()
        if found_vault then
            M.ShowNotesMenu(found_vault)
        else
            vim.notify("Parent vault no longer exists.", vim.log.levels.ERROR)
        end
    end

    local function open_notes_editor()
        if #files_in_vault == 0 then vim.notify("No files to edit notes for.", vim.log.levels.INFO); return end
        local selected_file_from_display = files_in_vault[current_selected_file_idx]

        if not selected_file_from_display then return end

        local original_file_entry = nil
        for _, f_orig in ipairs(vault_object.files) do 
            if f_orig.fileName == selected_file_from_display.fileName then
                original_file_entry = f_orig
                break
            end
        end

        if original_file_entry then
            M.EditFileNotes(vault_object, original_file_entry)
        else
            vim.notify("Error: Original file entry not found for notes editing.", vim.log.levels.ERROR)
        end
    end


    local last_folder_name = format_path(vault_object.vaultPath, NOTES_MENU_WIDTH, false)[1]

    notes_menu_buf = vim.api.nvim_create_buf(false, true)
    notes_menu_win = vim.api.nvim_open_win(notes_menu_buf, true, {
        relative = 'editor',
        width = NOTES_MENU_WIDTH,
        height = NOTES_MENU_HEIGHT,
        col = (vim.o.columns - NOTES_MENU_WIDTH) / 2,
        row = (vim.o.lines - NOTES_MENU_HEIGHT) / 2,
        style = 'minimal',
        border = 'rounded',
        title = ' Notes in vault: ' .. (last_folder_name or "N/A"),
        title_pos = 'center'
    })

    vim.api.nvim_buf_set_option(notes_menu_buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(notes_menu_buf, 'modifiable', false)

    if #files_in_vault > 0 then
    else
        current_selected_file_idx = 0
        current_notes_scroll_top_line_idx = 0
    end
    update_notes_menu_display()

    local opts = {buffer = notes_menu_buf, nowait = true, silent = true}
    vim.keymap.set('n', 'j', function() move_notes_cursor(1) end, opts)
    vim.keymap.set('n', 'k', function() move_notes_cursor(-1) end, opts)
    vim.keymap.set('n', '<Down>', function() move_notes_cursor(1) end, opts)
    vim.keymap.set('n', '<Up>', function() move_notes_cursor(-1) end, opts)
    vim.keymap.set('n', '<CR>', open_notes_editor, opts)
    vim.keymap.set('n', 'q', function() close_all_menus() end, opts)
    vim.keymap.set('n', '<Esc>', function() close_all_menus() end, opts)

    vim.keymap.set('n', 's', function()
        M.current_notes_sort_order = (M.current_notes_sort_order + 1) % 2
        refresh_notes_menu()
    end, opts)

    vim.keymap.set('n', 'h', function()
        M.notes_menu_full_path_display_mode = not M.notes_menu_full_path_display_mode
        update_notes_menu_display()
    end, opts)

    local disabled_keys_notes_menu = {'l', '<Left>', '<Right>', 'w', 'b', 'e', '0', '$', '^', 'G', 'gg', 'c', 'm', 'd'}
    for _, key in ipairs(disabled_keys_notes_menu) do
        vim.keymap.set('n', key, '<Nop>', opts)
    end

    vim.api.nvim_create_autocmd({'BufLeave', 'WinLeave', 'FocusLost'}, {
        buffer = notes_menu_buf,
        once = true,
        callback = function()
            if notes_menu_win and vim.api.nvim_win_is_valid(notes_menu_win) then
                vim.api.nvim_win_close(notes_menu_win, true)
                notes_menu_win = nil
                notes_menu_buf = nil
            end
        end
    })
end

-- Open the Notes Menu for a specified vault number or the last selected one
function M.OpenVaultNotesMenu(vault_num_str)
    local target_vault = nil

    if vault_num_str and vault_num_str ~= "" then
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
    else
        if M.last_selected_vault then
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
                M.last_selected_vault = nil
                M.ShowVaultMenu() 
                return
            end
        else
            vim.notify("No vault selected. Opening main Vaults menu...", vim.log.levels.INFO)
            M.ShowVaultMenu()
            return
        end
    end

    M.last_selected_vault = target_vault
    M.ShowNotesMenu(target_vault)
end

-- Open the Files Menu for a specified vault number or the last selected one
function M.OpenVaultFilesMenu(vault_num_str)
    read_vault_data_into_M()
    local target_vault = nil

    if vault_num_str and vault_num_str ~= "" then
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
    else
        if M.last_selected_vault then
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
                M.last_selected_vault = nil
                M.ShowVaultMenu()
                return
            end
        else
            vim.notify("No vault selected. Opening main Vaults menu...", vim.log.levels.INFO)
            M.ShowVaultMenu()
            return
        end
    end

    M.last_selected_vault = target_vault
    M.ShowFileMenu(target_vault)
end

-- Open a vault by its number
function M.EnterVaultByNumber(vault_num_str)
    read_vault_data_into_M()
    local vault_number = tonumber(vault_num_str)
    if not vault_number then
        vim.notify("Invalid vault number provided. Please use a number.", vim.log.levels.ERROR)
        return
    end

    local target_vault = nil
    for _, vault in ipairs(M.vaults) do
        if vault.vaultNumber == vault_number then
            target_vault = vault
            break
        end
    end

    if target_vault then
        M.last_selected_vault = target_vault
        close_all_menus()
        vim.cmd('cd ' .. vim.fn.fnameescape(target_vault.vaultPath))
        vim.notify("Entered vault: " .. target_vault.vaultPath, vim.log.levels.INFO)
    else
        vim.notify("Vault number " .. vault_number .. " not found.", vim.log.levels.WARN)
    end
end

-- Delete a vault by its number
function M.DeleteVaultByNumber(vault_num_str)
    read_vault_data_into_M()
    local vault_number = tonumber(vault_num_str)
    if not vault_number then
        vim.notify("Invalid vault number provided. Please use a number.", vim.log.levels.ERROR)
        return
    end

    local found_idx = nil
    local vault_to_delete = nil
    for i, vault in ipairs(M.vaults) do
        if vault.vaultNumber == vault_number then
            found_idx = i
            vault_to_delete = vault
            break
        end
    end

    if found_idx then
        vim.ui.select({'Yes', 'No'}, {
            prompt = string.format('Are you sure you want to delete Vault #%d (%s)? This action is permanent.', vault_number, vault_to_delete.vaultPath),
        }, function(choice)
            if choice == 'Yes' then
                table.remove(M.vaults, found_idx)
                table.insert(M.available_vault_numbers, vault_number)
                table.sort(M.available_vault_numbers)

                vim.api.nvim_out_write("\n")
                if save_vault_data() then
                    vim.notify(string.format("Vault #%d (%s) deleted successfully.", vault_number, vault_path), vim.log.levels.INFO)
                    if M.last_selected_vault and M.last_selected_vault.vaultNumber == vault_number then
                        M.last_selected_vault = nil
                    end
                    close_all_menus()
                end
            else
                vim.notify("Vault deletion cancelled.", vim.log.levels.INFO)
            end
        end)
    else
        vim.notify("Vault number " .. vault_number .. " not found.", vim.log.levels.WARN)
    end
end

-- Create a new vault with the current working directory
function M.CreateVaultWithCwd()
    read_vault_data_into_M()

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
    local new_vault = {
        vaultNumber = new_vault_number,
        vaultPath = current_cwd,
        lastUpdated = os.time(),
        files = {}
    }

    -- Check if a vault with this path already exists
    for _, vault in ipairs(M.vaults) do
        if helper.normalize_path(vault.vaultPath) == helper.normalize_path(current_cwd) then
            vim.notify("A vault for the current directory already exists.", vim.log.levels.WARN)
            return
        end
    end

    table.insert(M.vaults, new_vault)

    if save_vault_data() then
        M.last_selected_vault = new_vault
        vim.notify("Vault created for current working directory: " .. current_cwd, vim.log.levels.INFO)
    else
        vim.notify("Error creating vault for current working directory.", vim.log.levels.ERROR)
    end
end

-- Add the current file to the selected vault
function M.AddCurrentFileToVault()
    read_vault_data_into_M()

    if not M.last_selected_vault then
        vim.notify("No vault is currently selected. Please select a vault first.", vim.log.levels.WARN)
        return
    end

    -- Re-point M.last_selected_vault to the current object in M.vaults after read_vault_data_into_M()
    -- This is crucial because read_vault_data_into_M() re-assigns M.vaults with new tables.
    local current_vault_in_M_vaults = nil
    if M.last_selected_vault then
        for _, vault in ipairs(M.vaults) do
            if vault.vaultNumber == M.last_selected_vault.vaultNumber then
                current_vault_in_M_vaults = vault
                break
            end
        end
    end

    if not current_vault_in_M_vaults then
        vim.notify("Error: No valid vault selected or vault disappeared. Please select a vault first.", vim.log.levels.ERROR)
        M.last_selected_vault = nil -- Clear stale reference
        return
    end
    M.last_selected_vault = current_vault_in_M_vaults -- Re-point to the freshest object

    local current_file_path = vim.api.nvim_buf_get_name(0)
    if current_file_path == "" then
        vim.notify("No file is currently open or buffer has no name. Cannot add to vault.", vim.log.levels.WARN)
        return
    end

    local normalized_vault_path = helper.normalize_path(M.last_selected_vault.vaultPath)
    -- Resolve current_file_path to its canonical absolute path for robust comparison
    local resolved_current_file_path = vim.fn.resolve(current_file_path)
    local normalized_current_file_path = helper.normalize_path(resolved_current_file_path)

    if normalized_vault_path ~= "/" and normalized_vault_path:sub(-1) ~= "/" then
        normalized_vault_path = normalized_vault_path .. "/"
    end

    if not (normalized_current_file_path:sub(1, #normalized_vault_path) == normalized_vault_path) then
        vim.notify(string.format("Current file '%s' is not within the selected vault's path ('%s').", current_file_path, M.last_selected_vault.vaultPath), vim.log.levels.WARN)
        return
    end

    local relative_path = normalized_current_file_path:sub(#normalized_vault_path + 1)
    if relative_path:sub(1,1) == "/" then
        relative_path = relative_path:sub(2)
    end

    for _, file_entry in ipairs(M.last_selected_vault.files) do
        if helper.normalize_path(file_entry.fileName) == helper.normalize_path(relative_path) then
            vim.notify(string.format("File '%s' is already in the selected vault.", relative_path), vim.log.levels.INFO)
            return
        end
    end

    local new_file_entry = {
        fileName = relative_path,
        lastUpdated = os.time(),
        notes = "",
        line = vim.api.nvim_win_get_cursor(0)[1],
        col = vim.api.nvim_win_get_cursor(0)[2]
    }
    table.insert(M.last_selected_vault.files, new_file_entry)
    M.last_selected_vault.lastUpdated = os.time()
    M.last_selected_vault.lastSelectedFile = new_file_entry.fileName

    if save_vault_data() then
        vim.notify(string.format("File '%s' added to vault '%s'.", relative_path, M.last_selected_vault.vaultPath), vim.log.levels.INFO)
    else
        vim.notify("Error adding file to vault.", vim.log.levels.ERROR)
    end
end

-- Go to the next file in the selected vault
function M.VaultFileNext()
    read_vault_data_into_M()

    if not M.last_selected_vault then
        vim.notify("No vault is currently selected. Please select a vault first.", vim.log.levels.WARN)
        return
    end

    -- Re-point M.last_selected_vault to the current object in M.vaults after read_vault_data_into_M()
    local current_vault_in_M_vaults = nil
    if M.last_selected_vault then
        for _, vault in ipairs(M.vaults) do
            if vault.vaultNumber == M.last_selected_vault.vaultNumber then
                current_vault_in_M_vaults = vault
                break
            end
        end
    end

    if not current_vault_in_M_vaults then
        vim.notify("Error: No valid vault selected or vault disappeared. Please select a vault first.", vim.log.levels.ERROR)
        M.last_selected_vault = nil -- Clear stale reference
        return
    end
    M.last_selected_vault = current_vault_in_M_vaults -- Re-point to the freshest object

    local files_in_vault = M.last_selected_vault.files
    if #files_in_vault == 0 then
        vim.notify("No files in the current vault.", vim.log.levels.INFO)
        return
    end

    helper.sort_files(files_in_vault, current_file_sort_order) -- Ensure sorted order for 'next' logic

    local current_file_path = vim.api.nvim_buf_get_name(0)
    local current_relative_path = nil

    local normalized_vault_path = helper.normalize_path(M.last_selected_vault.vaultPath)
    if normalized_vault_path ~= "/" and normalized_vault_path:sub(-1) ~= "/" then
        normalized_vault_path = normalized_vault_path .. "/"
    end

    -- Resolve current_file_path to its canonical absolute path for robust comparison
    local resolved_current_file_path = vim.fn.resolve(current_file_path)

    if resolved_current_file_path ~= "" and (helper.normalize_path(resolved_current_file_path):sub(1, #normalized_vault_path) == normalized_vault_path) then
        current_relative_path = helper.normalize_path(resolved_current_file_path):sub(#normalized_vault_path + 1)
        if current_relative_path:sub(1,1) == "/" then
            current_relative_path = current_relative_path:sub(2)
        end
    end

    local current_idx_in_list = -1
    if current_relative_path then
        for i, file_entry in ipairs(files_in_vault) do
            if helper.normalize_path(file_entry.fileName) == helper.normalize_path(current_relative_path) then
                current_idx_in_list = i
                break
            end
        end
    end

    local next_idx = (current_idx_in_list == -1 or current_idx_in_list == #files_in_vault) and 1 or current_idx_in_list + 1
    local next_file_entry = files_in_vault[next_idx]

    if next_file_entry then
        -- Fix: Pass all 4 required parameters to open_file_entry
        M.open_file_entry(M.last_selected_vault, next_file_entry, next_idx, files_in_vault)
    else
        vim.notify("Could not find next file. Perhaps the vault file list is empty.", vim.log.levels.ERROR)
    end
end

-- Remove the current file from the selected vault
function M.RemoveCurrentFileFromVault()
    read_vault_data_into_M()

    if not M.last_selected_vault then
        vim.notify("No vault is currently selected. Please select a vault first.", vim.log.levels.WARN)
        return
    end

    -- Re-point M.last_selected_vault to the current object in M.vaults after read_vault_data_into_M()
    local current_vault_in_M_vaults = nil
    if M.last_selected_vault then
        for _, vault in ipairs(M.vaults) do
            if vault.vaultNumber == M.last_selected_vault.vaultNumber then
                current_vault_in_M_vaults = vault
                break
            end
        end
    end

    if not current_vault_in_M_vaults then
        vim.notify("Error: No valid vault selected or vault disappeared. Please select a vault first.", vim.log.levels.ERROR)
        M.last_selected_vault = nil -- Clear stale reference
        return
    end
    M.last_selected_vault = current_vault_in_M_vaults -- Re-point to the freshest object

    local current_file_path = vim.api.nvim_buf_get_name(0)
    if current_file_path == "" then
        vim.notify("No file is currently open or buffer has no name. Cannot remove from vault.", vim.log.levels.WARN)
        return
    end

    local normalized_vault_path = helper.normalize_path(M.last_selected_vault.vaultPath)
    -- Resolve current_file_path to its canonical absolute path for robust comparison
    local resolved_current_file_path = vim.fn.resolve(current_file_path)
    local normalized_current_file_path = helper.normalize_path(resolved_current_file_path)

    if normalized_vault_path ~= "/" and normalized_vault_path:sub(-1) ~= "/" then
        normalized_vault_path = normalized_vault_path .. "/"
    end

    if not (normalized_current_file_path:sub(1, #normalized_vault_path) == normalized_vault_path) then
        vim.notify(string.format("Current file '%s' is not within the selected vault's path ('%s'). Cannot remove.", current_file_path, M.last_selected_vault.vaultPath), vim.log.levels.WARN)
        return
    end

    local relative_path = normalized_current_file_path:sub(#normalized_vault_path + 1)
    if relative_path:sub(1,1) == "/" then
        relative_path = relative_path:sub(2)
    end

    local found_idx = nil
    for i, file_entry in ipairs(M.last_selected_vault.files) do
        if helper.normalize_path(file_entry.fileName) == helper.normalize_path(relative_path) then
            found_idx = i
            break
        end
    end

    if found_idx then
        vim.ui.select({'Yes', 'No'}, {
            prompt = string.format('Are you sure you want to remove file "%s" from the selected vault? (File on disk will NOT be deleted)', relative_path),
        }, function(choice)
            if choice == 'Yes' then
                table.remove(M.last_selected_vault.files, found_idx)
                M.last_selected_vault.lastUpdated = os.time()
                if M.last_selected_vault.lastSelectedFile == relative_path then
                    M.last_selected_vault.lastSelectedFile = nil
                end
                vim.api.nvim_out_write("\n")
                if save_vault_data() then
                    vim.notify(string.format("File '%s' removed from vault '%s'.", relative_path, M.last_selected_vault.vaultPath), vim.log.levels.INFO)
                else
                    vim.notify("Error removing file from vault.", vim.log.levels.ERROR)
                end
            end
        end)
    else
        vim.notify(string.format("File '%s' is not found in the selected vault.", relative_path), vim.log.levels.INFO)
    end
end

-- Open the notes editor for the current file, if it's in the selected vault
function M.OpenCurrentFileNotes()
    -- Ensure vault data is up-to-date
    read_vault_data_into_M()

    -- Ensure M.last_selected_vault points to the most current object in M.vaults
    if M.last_selected_vault then
        local found_current_vault = nil
        for _, v in ipairs(M.vaults) do
            if v.vaultNumber == M.last_selected_vault.vaultNumber then
                found_current_vault = v
                break
            end
        end
        if found_current_vault then
            M.last_selected_vault = found_current_vault -- Explicitly re-point
        else
            -- Last selected vault no longer exists in current data, clear it
            M.last_selected_vault = nil
            vim.notify("Last selected vault no longer exists. Please select a vault first using :Vaults or :VaultEnter.", vim.log.levels.WARN)
            return
        end
    else
        vim.notify("No vault is currently selected. Please select a vault first using :Vaults or :VaultEnter.", vim.log.levels.WARN)
        return
    end

    local current_file_path = vim.api.nvim_buf_get_name(0)
    if current_file_path == "" then
        vim.notify("No file is currently open or buffer has no name. Cannot open notes.", vim.log.levels.WARN)
        return
    end

    local normalized_vault_path = helper.normalize_path(M.last_selected_vault.vaultPath)
    -- Resolve current_file_path to its canonical absolute path for robust comparison
    local resolved_current_file_path = vim.fn.resolve(current_file_path)
    local normalized_current_file_path = helper.normalize_path(resolved_current_file_path)

    if normalized_vault_path ~= "/" and normalized_vault_path:sub(-1) ~= "/" then
        normalized_vault_path = normalized_vault_path .. "/"
    end

    if not (normalized_current_file_path:sub(1, #normalized_vault_path) == normalized_vault_path) then
        vim.notify(string.format("Current file '%s' is not within the selected vault's path ('%s').", current_file_path, M.last_selected_vault.vaultPath), vim.log.levels.WARN)
        return
    end

    local relative_path = normalized_current_file_path:sub(#normalized_vault_path + 1)
    if relative_path:sub(1,1) == "/" then
        relative_path = relative_path:sub(2)
    end

    if relative_path == "" then
        vim.notify("You are currently in the vault's root directory. Please open a specific file within the vault to edit its notes.", vim.log.levels.INFO)
        return
    end

    local found_file_entry = nil
    for _, file_entry in ipairs(M.last_selected_vault.files) do
        if helper.normalize_path(file_entry.fileName) == helper.normalize_path(relative_path) then
            found_file_entry = file_entry
            break
        end
    end

    if found_file_entry then
        M.EditFileNotes(M.last_selected_vault, found_file_entry)
    else
        vim.notify(string.format("File '%s' is not registered in the selected vault. Add it first using :VaultFileAdd.", relative_path), vim.log.levels.WARN)
    end
end

--- Delete all note content for the current file.
function M.DeleteCurrentFileNotes()
    read_vault_data_into_M()

    -- Ensure M.last_selected_vault points to the most current object in M.vaults
    if M.last_selected_vault then
        local found_current_vault = nil
        for _, v in ipairs(M.vaults) do
            if v.vaultNumber == M.last_selected_vault.vaultNumber then
                found_current_vault = v
                break
            end
        end
        if found_current_vault then
            M.last_selected_vault = found_current_vault -- Explicitly re-point
        else
            -- Last selected vault no longer exists in current data, clear it
            M.last_selected_vault = nil
            vim.notify("No vault is currently selected. Please select a vault first.", vim.log.levels.WARN)
            return
        end
    else
        vim.notify("No vault is currently selected. Please select a vault first.", vim.log.levels.WARN)
        return
    end

    local current_file_path = vim.api.nvim_buf_get_name(0)
    if current_file_path == "" then
        vim.notify("No file is currently open or buffer has no name. Cannot delete notes.", vim.log.levels.WARN)
        return
    end

    local normalized_vault_path = helper.normalize_path(M.last_selected_vault.vaultPath)
    local resolved_current_file_path = vim.fn.resolve(current_file_path)
    local normalized_current_file_path = helper.normalize_path(resolved_current_file_path)

    if normalized_vault_path ~= "/" and normalized_vault_path:sub(-1) ~= "/" then
        normalized_vault_path = normalized_vault_path .. "/"
    end

    if not (normalized_current_file_path:sub(1, #normalized_vault_path) == normalized_vault_path) then
        vim.notify(string.format("Current file '%s' is not within the selected vault's path ('%s'). Cannot delete notes.", current_file_path, M.last_selected_vault.vaultPath), vim.log.levels.WARN)
        return
    end

    local relative_path = normalized_current_file_path:sub(#normalized_vault_path + 1)
    if relative_path:sub(1,1) == "/" then
        relative_path = relative_path:sub(2)
    end

    if relative_path == "" then
        vim.notify("You are currently in the vault's root directory. Please open a specific file within the vault to delete its notes.", vim.log.levels.INFO)
        return
    end

    local found_file_entry = nil
    for _, file_entry in ipairs(M.last_selected_vault.files) do
        if helper.normalize_path(file_entry.fileName) == helper.normalize_path(relative_path) then
            found_file_entry = file_entry
            break
        end
    end

    if not found_file_entry then
        vim.notify(string.format("File '%s' is not registered in the selected vault. Add it first using :VaultFileAdd.", relative_path), vim.log.levels.WARN)
        return
    end

    if found_file_entry.notes == "" then
        vim.notify("Notes for '" .. found_file_entry.fileName .. "' are already empty.", vim.log.levels.INFO)
        return
    end

    vim.ui.select({'Yes', 'No'}, {
        prompt = string.format('Are you sure you want to delete ALL notes for "%s"? This action cannot be undone.', found_file_entry.fileName),
    }, function(choice)
        if choice == 'Yes' then
            found_file_entry.notes = ""
            found_file_entry.lastUpdated = os.time()
            if save_vault_data() then
                vim.api.nvim_out_write("\n")
                vim.notify("Notes for '" .. found_file_entry.fileName .. "' deleted successfully.", vim.log.levels.INFO)

                -- Refresh the notes editor if it's currently open and displaying these notes
                if notes_editor_win and vim.api.nvim_win_is_valid(notes_editor_win) then
                    local current_editor_buf = vim.api.nvim_win_get_buf(notes_editor_win)
                    -- Use the stored identifiers to verify it's the correct buffer
                    local editor_vault_num = vim.api.nvim_buf_get_var(current_editor_buf, 'vault_number_id')
                    local editor_file_name = vim.api.nvim_buf_get_var(current_editor_buf, 'file_name_id')

                    if editor_vault_num == M.last_selected_vault.vaultNumber and editor_file_name == found_file_entry.fileName then
                        vim.api.nvim_buf_set_option(current_editor_buf, 'modifiable', true)
                        vim.api.nvim_buf_set_lines(current_editor_buf, 0, -1, false, {}) -- Set to empty table
                        vim.api.nvim_buf_set_option(current_editor_buf, 'modifiable', false)
                        vim.notify("Notes editor content refreshed.", vim.log.levels.INFO)
                    end
                end
            else
                vim.notify("Error deleting notes for '" .. found_file_entry.fileName .. "'.", vim.log.levels.ERROR)
            end
        else
            vim.notify("Notes deletion cancelled.", vim.log.levels.INFO)
        end
    end)
end

-- Export the note of the current file as a file.
function M.ExportCurrentFileNotes()
    read_vault_data_into_M()

    if not M.last_selected_vault then
        vim.notify("No vault is currently selected. Please select a vault first using :Vaults or :VaultEnter.", vim.log.levels.WARN)
        return
    end

    -- Ensure M.last_selected_vault points to the most current object in M.vaults
    local found_current_vault = nil
    for _, v in ipairs(M.vaults) do
        if v.vaultNumber == M.last_selected_vault.vaultNumber then
            found_current_vault = v
            break
        end
    end
    if found_current_vault then
        M.last_selected_vault = found_current_vault -- Explicitly re-point
    else
        M.last_selected_vault = nil
        vim.notify("Last selected vault no longer exists. Please select a vault first.", vim.log.levels.WARN)
        return
    end

    local current_file_path = vim.api.nvim_buf_get_name(0)
    if current_file_path == "" then
        vim.notify("No file is currently open or buffer has no name. Cannot export notes.", vim.log.levels.WARN)
        return
    end

    local normalized_vault_path = helper.normalize_path(M.last_selected_vault.vaultPath)
    local resolved_current_file_path = vim.fn.resolve(current_file_path)
    local normalized_current_file_path = helper.normalize_path(resolved_current_file_path)

    if normalized_vault_path ~= "/" and normalized_vault_path:sub(-1) ~= "/" then
        normalized_vault_path = normalized_vault_path .. "/"
    end

    if not (normalized_current_file_path:sub(1, #normalized_vault_path) == normalized_vault_path) then
        vim.notify(string.format("Current file '%s' is not within the selected vault's path ('%s'). Cannot export notes.", current_file_path, M.last_selected_vault.vaultPath), vim.log.levels.WARN)
        return
    end

    local relative_path = normalized_current_file_path:sub(#normalized_vault_path + 1)
    if relative_path:sub(1,1) == "/" then
        relative_path = relative_path:sub(2)
    end

    if relative_path == "" then
        vim.notify("You are currently in the vault's root directory. Please open a specific file within the vault to export its notes.", vim.log.levels.INFO)
        return
    end

    local found_file_entry = nil
    for _, file_entry in ipairs(M.last_selected_vault.files) do
        if helper.normalize_path(file_entry.fileName) == helper.normalize_path(relative_path) then
            found_file_entry = file_entry
            break
        end
    end

    if not found_file_entry then
        vim.notify(string.format("File '%s' is not registered in the selected vault. Add it first using :VaultFileAdd.", relative_path), vim.log.levels.WARN)
        return
    end

    if found_file_entry.notes == "" then
        vim.notify("No notes found for '" .. found_file_entry.fileName .. "'. Nothing to export.", vim.log.levels.WARN)
        return
    end

    -- Construct default export path using Lua string manipulation
    local _, current_filename = get_file_and_dir_from_path(current_file_path)
    local current_file_stem = helper.get_filename_stem(current_filename)
    local default_export_filename = current_file_stem .. "_notes.txt"

    local path_separator = string.sub(package.config, 1, 1)
    local default_export_path = vim.fn.expand(vim.fn.getcwd() .. path_separator .. default_export_filename)

    vim.ui.input({
        prompt = "Export notes to (full path): ",
        default = default_export_path
    }, function(export_path)
        if export_path and export_path ~= "" then
            local expanded_export_path = vim.fn.expand(export_path)
            local parent_dir, _ = get_file_and_dir_from_path(expanded_export_path)

            if vim.fn.isdirectory(parent_dir) == 0 then
                local success_mkdir, err_mkdir = pcall(vim.fn.mkdir, parent_dir, "p")
                if not success_mkdir then
                    vim.notify("Error creating directory '" .. parent_dir .. "': " .. (err_mkdir or "unknown error"), vim.log.levels.ERROR)
                    return
                end
            end

            local file, err = io.open(expanded_export_path, "w")
            if file then
                local success, write_err = pcall(file.write, file, found_file_entry.notes)
                file:close()
                if success then
                    vim.notify("Notes for '" .. found_file_entry.fileName .. "' exported to '" .. expanded_export_path .. "'.", vim.log.levels.INFO)
                else
                    vim.notify("Error writing notes to file '" .. expanded_export_path .. "': " .. (write_err or "unknown error"), vim.log.levels.ERROR)
                end
            else
                vim.notify("Error opening file for writing '" .. expanded_export_path .. "': " .. (err or "unknown error"), vim.log.levels.ERROR)
            end
        else
            vim.notify("Notes export cancelled.", vim.log.levels.INFO)
        end
    end)
end


return M
