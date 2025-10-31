local helper = require('helper')

local main_menu = {
  background = helper.validateHexColor(vim.g.vim_vault_main_menu_background) or "#000000",
  text       = helper.validateHexColor(vim.g.vim_vault_main_menu_text) or "#00FF00",
  sort       = helper.validateNumber(vim.g.vim_vault_menu_sort) or 0,
  display    = helper.validateBoolean(vim.g.vim_vault_menu_display) or false,
}
local files_menu = {
  background = helper.validateHexColor(vim.g.vim_vault_files_menu_background) or "#000000",
  text       = helper.validateHexColor(vim.g.vim_vault_files_menu_text) or "#00FF00",
  sort       = helper.validateNumber(vim.g.vim_vault_files_sort) or 0,
  display    = helper.validateBoolean(vim.g.vim_vault_files_display) or false,
}
local notes_menu = {
  background = helper.validateHexColor(vim.g.vim_vault_notes_menu_background) or "#000000",
  text       = helper.validateHexColor(vim.g.vim_vault_notes_menu_text) or "#00FF00",
  sort       = helper.validateNumber(vim.g.vim_vault_notes_menu_sort) or 0,
  display    = helper.validateBoolean(vim.g.vim_vault_notes_menu_display) or false,
}
local notes = {
  background = helper.validateHexColor(vim.g.vim_vault_notes_background) or "#000000",
  text       = helper.validateHexColor(vim.g.vim_vault_notes_text) or "#FFFFFF",
}

return {
  main_menu = main_menu,
  files_menu = files_menu,
  notes_menu = notes_menu,
  notes = notes,
}
