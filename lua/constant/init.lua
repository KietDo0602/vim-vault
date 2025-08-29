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
ERROR_WRITE_OPERATION = "Error during file write operation: "
ERROR_JSON_WRITING = "Error: Could not open JSON file for writing: "
ERROR_NIL_JSON = "Error: Could not encode JSON data. JSON string is nil."
UNKNOWN_ERROR = "UNKNOWN ERROR"


return {
	FILE_NAME=FILE_NAME,
	FILE_PATH=FILE_PATH,
  ERROR_WRITE_OPERATION=ERROR_WRITE_OPERATION,
  ERROR_JSON_WRITING=ERROR_JSON_WRITING,
  ERROR_NIL_JSON=ERROR_NIL_JSON,
  UNKNOWN_ERROR=UNKNOWN_ERROR,
}
