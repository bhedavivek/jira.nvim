---@class Jira.Common.Config
local M = {}

local FALLBACKS = {
  story_point_field = "customfield_10035",
  custom_fields = {
    -- { key = "customfield_10016", label = "Acceptance Criteria" }
  },
}

---@class JiraAuthOptions
---@field base string URL of your Jira instance (e.g. https://your-domain.atlassian.net)
---@field email? string Your Jira email (required for basic auth)
---@field token string Your Jira API token or PAT
---@field type? "basic"|"pat" Authentication type (default: "basic")
---@field api_version? "2"|"3" API version to use (default: "3")
---@field limit? number Global limit of tasks when calling API
---@field default_project? string Default project key when none specified

---@class JiraConfig
---@field jira JiraAuthOptions
---@field projects? table<string, table> Project-specific overrides
---@field active_sprint_query? string JQL for active sprint tab
---@field queries? table<string, string> Saved JQL queries
M.defaults = {
  jira = {
    base = "",
    email = "",
    token = "",
    type = "basic",
    api_version = "3",
    limit = 200,
    default_project = nil,
  },
  projects = {},
  active_sprint_query = "project = '%s' AND sprint in openSprints() ORDER BY Rank ASC",
  queries = {
    ["Next sprint"] = "project = '%s' AND sprint in futureSprints() ORDER BY Rank ASC",
    ["Backlog"] = "project = '%s' AND (issuetype IN standardIssueTypes() OR issuetype = Sub-task) AND (sprint IS EMPTY OR sprint NOT IN openSprints()) AND statusCategory != Done ORDER BY Rank ASC",
    ["My Tasks"] = "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC",
  },
}

---@type JiraConfig
M.options = vim.deepcopy(M.defaults)

-- Cache for current user info
M.user = nil

---@param opts JiraConfig
function M.setup(opts)
  -- Start with defaults, then user config
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})

  -- Override with environment variables if they exist
  if os.getenv("JIRA_BASE_URL") then
    M.options.jira.base = os.getenv("JIRA_BASE_URL")
  end
  if os.getenv("JIRA_EMAIL") then
    M.options.jira.email = os.getenv("JIRA_EMAIL")
  end
  if os.getenv("JIRA_TOKEN") then
    M.options.jira.token = os.getenv("JIRA_TOKEN")
  end
  if os.getenv("JIRA_AUTH_TYPE") then
    M.options.jira.type = os.getenv("JIRA_AUTH_TYPE")
  end
  if os.getenv("JIRA_API_VERSION") then
    M.options.jira.api_version = os.getenv("JIRA_API_VERSION")
  end
end

---@param project_key string|nil
---@return table
function M.get_project_config(project_key)
  local projects = M.options.projects or {}
  local p_config = projects[project_key] or {}

  return {
    story_point_field = p_config.story_point_field or FALLBACKS.story_point_field,
    custom_fields = p_config.custom_fields or FALLBACKS.custom_fields,
  }
end

-- Fetch and cache current user info
function M.fetch_user()
  if M.user then
    return M.user -- Return cached user
  end

  local jira_api = require("jira.jira-api.api")
  jira_api.get_myself(function(user, err)
    if not err and user and user.accountId then
      M.user = user
      return user
    end
  end)

  return nil -- No cached user yet
end

-- Validate configuration
---@return boolean valid
function M.validate()
  local jira = M.options.jira
  local is_pat = (jira.type or "basic"):lower() == "pat"

  local missing = {}
  if not jira.base or jira.base == "" then
    table.insert(missing, "base URL")
  end
  if not is_pat and (not jira.email or jira.email == "") then
    table.insert(missing, "email")
  end
  if not jira.token or jira.token == "" then
    table.insert(missing, "token")
  end

  if #missing > 0 then
    local auth_type = is_pat and "PAT" or "basic auth"
    vim.notify(
      string.format(
        "Missing Jira configuration for %s: %s. Set via config or environment variables.",
        auth_type,
        table.concat(missing, ", ")
      ),
      vim.log.levels.ERROR
    )
    M.fetch_user()
    return false
  end
end

return M
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
