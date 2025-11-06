local helper = require('helper')

local main_menu = {
  guide      = helper.validateBoolean(vim.g.vim_vault_main_menu_guide, true),
  width      = helper.validateMax(vim.g.vim_vault_main_menu_width, 70) or 70,
  background = helper.validateHexColor(vim.g.vim_vault_main_menu_background) or "#000000",
  text       = helper.validateHexColor(vim.g.vim_vault_main_menu_text) or "#00FFFF",
  sort       = helper.validateNumber(vim.g.vim_vault_main_menu_sort) or 0,
  display    = helper.validateNumber(vim.g.vim_vault_main_menu_display) or 0,
}
local files_menu = {
  guide      = helper.validateBoolean(vim.g.vim_vault_files_menu_guide, true),
  width      = helper.validateMax(vim.g.vim_vault_files_menu_width, 70) or 70,
  background = helper.validateHexColor(vim.g.vim_vault_files_menu_background) or "#000000",
  text       = helper.validateHexColor(vim.g.vim_vault_files_menu_text) or "#00FF00",
  sort       = helper.validateNumber(vim.g.vim_vault_files_menu_sort) or 0,
  display    = helper.validateNumber(vim.g.vim_vault_files_menu_display) or 0,
}
local notes = {
  background = helper.validateHexColor(vim.g.vim_vault_notes_background) or "#000000",
  text       = helper.validateHexColor(vim.g.vim_vault_notes_text) or "#FFFFFF",
}

return {
  main_menu = main_menu,
  files_menu = files_menu,
  notes = notes,
}
