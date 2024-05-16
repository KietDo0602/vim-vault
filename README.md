# Vim Vault (vim-vault)

**File Navigation and Project Management Library (not inspired by Fallout and Harpoon)**


## Explanation

There are multiple Vaults (Project).

Each Vaults contains multiple Files.

You can add Files to each Vault. You can jump between Files within a Vault.

Each File is mapped to a Note (empty by default). 

You can add Notes to each File.


## Installation
Use vim-plug or other alternatives to install vim-vault.

```text
Plug 'kietdo0602/vim-vault'
```


## Commands 

':Vaults' - Toggle menu that shows available Vaults.

':VaultSelect [number]' - Select Vault with number.

':VaultNext' - Go to the next Vault.

':VaultCreate' - Create new Vault Project with current folder as origin.

':VaultDelete' - Delete current Vault.

':VaultFiles' - Toggle menu that shows Files within selected Vault.

':VaultFileNext' - Go to the next File within selected Vault.

':VaultFileAdd' - Add current File to selected Vault.

':VaultFileRemove' - Remove current File from the Vault.

':VaultNotes' - Toggle menu that shows all Notes within that Vault.

':VaultNoteOpen' - Open Notes of current File.

':VaultNoteDelete' - Delete Note of current File.

':VaultNoteExport' - Export note to current Folder.



## Cusomization
To customize settings, change content of the settings key of json inside '~/vim-vault.json'



## Implementation
All settings are stored within vim-vault-settings.json file
All files the user utilized are stored within vim-vault.json file

1. Allow storing files paths and jumping around
2. Each file has a note - txt or json - txt now only


