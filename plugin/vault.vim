" Last Change:  2024 Jan 15
" Maintainer:   Kiet Do <kietdo0602@gmail.com>
" License:      GNU General Public License v3.0

if exists('g:loaded_vault') | finish | endif " prevent loading file twice

let s:save_cpo = &cpo
set cpo&vim

hi VaultCursorLine ctermbg=238 cterm=none

command! Vaults lua require'vault'.open_vault_menu()
command! VaultEnter lua require'vault'.create_vault_window()
" command! VaultCreate lua require'vault'.open_vault_menu()
" command! VaultDelete lua require'vault'.open_vault_menu()
" command! VaultFiles lua require'vault'.open_vault_menu()
" command! VaultFileNext lua require'vault'.open_vault_menu()
" command! VaultFileAdd lua require'vault'.open_vault_menu()
" command! VaultFileRemove lua require'vault'.open_vault_menu()
" command! VaultNotes lua require'vault'.open_vault_menu()
" command! VaultNoteOpen lua require'vault'.open_vault_menu()
" command! VaultNoteDelete lua require'vault'.open_vault_menu()
" command! VaultNoteExport lua require'vault'.open_vault_menu()

