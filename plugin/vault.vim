" Last Change:  2024 Jan 15
" Maintainer:   Kiet Do <kietdo0602@gmail.com>
" License:      GNU General Public License v3.0

if exists('g:loaded_vault') | finish | endif " prevent loading file twice

let s:save_cpo = &cpo
set cpo&vim

" hi VaultCursorLine ctermbg=238 cterm=none

command! Vaults lua require'vault'.ShowVaultMenu()
command! VaultEnter lua require'vault'.create_vault_window()
" command! VaultCreate lua require'vault'.ShowVaultMenu()
" command! VaultDelete lua require'vault'.ShowVaultMenu()
" command! VaultFiles lua require'vault'.ShowVaultMenu()
" command! VaultFileNext lua require'vault'.ShowVaultMenu()
" command! VaultFileAdd lua require'vault'.ShowVaultMenu()
" command! VaultFileRemove lua require'vault'.ShowVaultMenu()
" command! VaultNotes lua require'vault'.ShowVaultMenu()
" command! VaultNoteOpen lua require'vault'.ShowVaultMenu()
" command! VaultNoteDelete lua require'vault'.ShowVaultMenu()
" command! VaultNoteExport lua require'vault'.ShowVaultMenu()

