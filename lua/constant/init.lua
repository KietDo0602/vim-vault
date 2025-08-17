-- Constants
-- Contains constant strings for path, message, error message.

-- Vim-Vault related
PROJECT_NAME = "Vim-Vault"


-- File Paths
FILE_NAME = "vim-vault.json"
FILE_PATH = "~/" .. FILE_NAME


-- Message
MSG_VAULT_MENU = "Opening Vaults Menu..."
MSG_SET_VAULT_CWD = "Set current working directory as Vault origin."
MSG_VAULT_ADDED = "Experiment at Vault has been started :)"
MSG_VAULT_REMOVED = "Vault Experiment has been destroyed :("
MSG_OPEN_VAULT = "Accessing Vault "

MSG_FILE_MENU = "Show all Files in Vault"
MSG_ADD_FILE = " added to Vault!"
MSG_NO_FILE = "There are no files to remove :("

MSG_NOTE_MENU = "Showing all Notes in Vault"
MSG_NO_NOTE = "There are no notes for this file :("
MSG_ADD_NOTES = "Created notes for file..."
MSG_OPEN_NOTES = "Opening notes for file..."
MSG_EXPORT = "Exported notes as .txt file."


-- Error Messages
ERROR_MSG_FILE_NOT_FOUND = FILE_NAME .. " not found in users home directory (" .. FILE_PATH .. FILE_NAME .. ")"

DEFAULT_SETTING = {
	enableNotes = "true",
	createMissingFile = "true",
	displayFileNameOnly = "true",
	createMissingNote = "true",
}

return {
	PROJECT_NAME=PROJECT_NAME,
	FILE_NAME=FILE_NAME,
	FILE_PATH=FILE_PATH,
	MSG_VAULT_MENU=MSG_VAULT_MENU,
	MSG_SET_VAULT_CWD=MSG_SET_VAULT_CWD,
	MSG_VAULT_ADDED=MSG_VAULT_ADDED,
	MSG_VAULT_REMOVED=MSG_VAULT_REMOVED,
	MSG_OPEN_VAULT=MSG_OPEN_VAULT,
	MSG_FILE_MENU=MSG_FILE_MENU,
	MSG_ADD_FILE=MSG_ADD_FILE,
	MSG_NO_FILE=MSG_NO_FILE,
	MSG_NOTE_MENU=MSG_NOTE_MENU,
	MSG_NO_NOTE=MSG_NO_NOTE,
	MSG_ADD_NOTES=MSG_ADD_NOTES,
	MSG_OPEN_NOTES=MSG_OPEN_NOTES,
	MSG_EXPORT=MSG_EXPORT,
	ERROR_MSG_FILE_NOT_FOUND=ERROR_MSG_FILE_NOT_FOUND,
	ERROR_MSG_SETTING_NOT_FOUND=ERROR_MSG_SETTING_NOT_FOUND,
	DEFAULT_SETTINGS=DEFAULT_SETTING,
}
