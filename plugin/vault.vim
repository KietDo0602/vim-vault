" Last Change:  2024 Jan 15
" Maintainer:   Kiet Do <kietdo0602@gmail.com>
" License:      GNU General Public License v3.0

if exists('g:loaded_vault') | finish | endif " prevent loading file twice

let s:save_cpo = &cpo
set cpo&vim

" hi VaultCursorLine ctermbg=238 cterm=none

command! Vaults lua require'vault'.ShowVaultMenu()
command! -nargs=1 VaultEnter lua require'vault'.EnterVaultByNumber(<f-args>)
command! -nargs=1 VaultDelete lua require'vault'.DeleteVaultByNumber(<f-args>)
command! VaultCreate lua require'vault'.CreateVaultWithCwd()
command! -nargs=? VaultFiles lua require'vault'.OpenVaultFilesMenu(<f-args>)
command! VaultFileNext lua require'vault'.VaultFileNext()
command! VaultFileAdd lua require'vault'.RemoveCurrentFileFromVault()
command! VaultFileRemove lua require'vault'.RemoveCurrentFileFromVault()
command! -nargs=? VaultNotes lua require'vault'.OpenVaultNotesMenu(<f-args>)
command! VaultNoteOpen lua require'vault'.OpenCurrentFileNotes()
command! VaultNoteDelete lua require'vault'.DeleteCurrentFileNotes()
command! VaultNoteExport lua require'vault'.ExportCurrentFileNotes()

