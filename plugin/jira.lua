vim.api.nvim_create_user_command("Jira", function()
  require("jira").open()
end, {})
