local main_menu = {
  background = vim.g.vim_vault_main_menu_background or "#000000",
  text       = vim.g.vim_vault_main_menu_text or "#00FF00",
  sort    = vim.g.vim_vault_menu_sort or 0,
  display = vim.g.vim_vault_menu_display or 0,
}
local files_menu = {
  background = vim.g.vim_vault_files_menu_background or "#000000",
  text       = vim.g.vim_vault_files_menu_text or "#00FF00",
  sort       = vim.g.vim_vault_files_sort or 0,
  display    = vim.g.vim_vault_files_display or 0,
}
local notes_menu = {
  background = vim.g.vim_vault_notes_menu_background or "#000000",
  text       = vim.g.vim_vault_notes_menu_text or "#00FF00",
  sort       = vim.g.vim_vault_notes_sort or 0,
  display    = vim.g.vim_vault_notes_display or 0,
}
local notes = {
  background = vim.g.vim_vault_notes_menu_background or "#000000",
  text       = vim.g.vim_vault_notes_menu_text or "#FFFFFF",
}

return {
  main_menu = main_menu,
  files_menu = files_menu,
  notes_menu = notes_menu,
  notes = notes,
}
