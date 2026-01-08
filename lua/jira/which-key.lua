-- which-key.lua: LazyVim which-key integration
local M = {}

-- Register JIRA keybindings with which-key
function M.setup()
  local ok, wk = pcall(require, "which-key")
  if not ok then
    return
  end

  -- Global JIRA commands
  wk.add({
    { "<leader>j", group = "JIRA" },
    { "<leader>jo", "<cmd>Jira<cr>", desc = "Open JIRA Board" },
    { "<leader>jd", "<cmd>JiraDebug<cr>", desc = "Debug JIRA API" },
    { "<leader>jc", "<cmd>Jira create<cr>", desc = "Create Issue" },
  })
end

-- Register buffer-specific keybindings for JIRA board
function M.setup_board_keys()
  local ok, wk = pcall(require, "which-key")
  if not ok then
    return
  end

  wk.add({
    buffer = vim.api.nvim_get_current_buf(),
    { "?", group = "Help" },
    { "H", desc = "Show Help" },

    -- Navigation
    { "<Tab>", desc = "Toggle Node" },
    { "<CR>", desc = "Enter/Select" },

    -- Views
    { "S", desc = "Sprint View" },
    { "J", desc = "JQL View" },

    -- General
    { "q", desc = "Close Board" },
    { "r", desc = "Refresh View" },

    -- Issue Actions
    { "g", group = "Go/Actions" },
    { "gd", desc = "Read Task" },
    { "ge", desc = "Edit Task" },
    { "gx", desc = "Open in Browser" },
    { "gs", desc = "Update Status" },
    { "ga", desc = "Change Assignee" },
    { "gw", desc = "Add Time" },
    { "gb", desc = "Checkout Branch" },
    { "go", desc = "Show Child Issues" },
    { "gm", desc = "Toggle My Tasks Filter" },

    { "i", desc = "Create Issue" },
    { "K", desc = "Quick Details" },
  })
end

-- Auto-setup when module is loaded
M.setup()

return M
