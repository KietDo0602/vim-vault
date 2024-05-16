" Last Change:  2024 Jan 15
" Maintainer:   Kiet Do <kietdo0602@gmail.com>
" License:      GNU General Public License v3.0

if exists('g:loaded_vault') | finish | endif " prevent loading file twice

let s:save_cpo = &cpo
set cpo&vim

hi VaultCursorLine ctermbg=238 cterm=none

command! HanoiFiles lua require'vault'.hanoi_toggle_file()

