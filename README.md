# ☢️🚀💥 THE VAULT — Vault-Tec's Official NeoVim Plugin

Welcome to **THE VAULT**, the file navigation, project management and note taking plugin for NeoVim - inspired by the legendary Vault-Tec systems of the Fallout universe! 

Whether you're hacking terminals in the Wasteland or organizing your code in Vault 11, The Vault keeps your workflow secure, efficient, and irradiated with productivity. 💾☢️

---

## 🛠️☣️ Features (Vault-Tec Certified)

- 📂 Navigate files quickly
- 🗂️ Bookmark and switch between projects faster than a Nuka-Cola delivery  
- 🧠 Smart caching to keep your vault memory sharp  
- 🛠️ Minimal setup — just plug in to survive the nuclear winter ❄️

---

## 💥 Installation (No Power Armor Required)

Use your favorite plugin manager:

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'kietdo0602/vault'
```

### [Vundle](https://github.com/VundleVim/Vundle.vim)

```vim
Plugin 'kietdo0602/vault'
```

### [Pathogen](https://github.com/tpope/vim-pathogen)

```bash
cd ~/.vim/bundle
git clone https://github.com/kietdo0602/vault.git
```

---

## 📟 Configuration (Customize Your Terminal)

Add this to your `init.lua` file to get started:

```lua
--Customize the styling of the main menu (default: black background, green text)
vim.g.vim_vault_main_menu_guide = true   -- Show the keymaps guide footer
vim.g.vim_vault_main_menu_width = 80     -- Default: 70
vim.g.vim_vault_main_menu_background = '#000000'
vim.g.vim_vault_main_menu_text = '#FFFFFF'

--Change the styling of the files menu
vim.g.vim_vault_files_menu_guide = true  -- Show the keymaps guide footer
vim.g.vim_vault_files_menu_width = 80    -- Default: 70
vim.g.vim_vault_files_menu_background = '#000000'
vim.g.vim_vault_files_menu_text = '#FFFFFF'

--Change the styling of the notes
vim.g.vim_vault_notes_width = 80    -- Default: 70
vim.g.vim_vault_notes_height = 40    -- Default: 30
vim.g.vim_vault_notes_background = '#000000'
vim.g.vim_vault_notes_text = '#FFFFFF'

--Set the default sorting / display type
vim.g.vim_vault_main_menu_sort = 0            -- Sort By: 0: Vault Number, 1: Last Updated, 2: Folder Path
vim.g.vim_vault_main_menu_display = 0         -- Display: 0: Smart Display (Difference between) 1: Display Folder Name Only, 2: Show Full Path

vim.g.vim_vault_files_menu_sort = 1           -- Sort By: 0: File Name, 1: Last Updated
vim.g.vim_vault_files_menu_display = 0        -- Display: 0: Smart Display, 1: Display File Name Only, 2: Show Full File Path

```

---

## 🧭 Usage (Survival Guide)

- `:Vaults` — Open the Vaults menu  

- `:Vault [number]` — Select Vault with number
- `:VaultCreate` — Create a new Vault with current working directory (cwd) as origin
- `:VaultDelete [number]` — Delete Vault with id number

- `:VaultFiles` — Open Files Menu inside the selected Vault
- `:VaultFileAdd` — Add current file to selected Vault
- `:VaultFileDelete` — Delete current file from the selected Vault (if exists)

- `:VaultNoteOpen` — Open Note of the current File.
- `:VaultNoteDelete` — Delete note content of the current file
- `:VaultNoteExport` — Export note of the current file


## 🗺️ Basic Mappings

```lua
-- Mappings for Vim Vault
vim.api.nvim_set_keymap('n', '<SPACE>vv', '<cmd>Vaults<cr>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<SPACE>vc', '<cmd>VaultCreate<cr>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<SPACE>ff', '<cmd>VaultFiles<cr>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<SPACE>fa', '<cmd>VaultFileAdd<cr>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<SPACE>nn', '<cmd>VaultNoteOpen<cr>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<SPACE>ne', '<cmd>VaultNoteExport<cr>', { noremap = true, silent = true })
```
---

## 📦 Requirements

- Vim 8.0+ or Neovim  
- Optional: A Vault Boy bobblehead for good luck 🤖

---

## 🙌 Contributing (Join the Resistance)

Pull requests, bug reports, and feature suggestions are welcome! Whether you're a lone wanderer or part of a modding faction, your help keeps The Vault thriving in the post-apocalyptic coding landscape. 💡🧑‍🔧

---

## 📄 License

MIT License © kietdo0602
No Rad-X required.

---

## 💬 Feedback

If The Vault makes your Vim experience feel like a Pip-Boy upgrade, let me know! If it feels more like a Deathclaw encounter… tell me anyway so I can patch it up. 😄🦎

> “War never changes. But your Vim setup can.” — Vault-Tec

---

## 🖼️ Beware, very strong enemy ahead!

```
       .-"      "-.
      /            \
     |              |
     |,  .-.  .-.  ,|
     | )(_o/  \o_)( |
     |/     /\     \|
     (_     ^^     _)
      \__|IIIIII|__/
       | \IIIIII/ |
       \          /
        `--------`
```

Stay safe out there, Overseer. Your terminal is your vault. 🧑‍💻🔒
