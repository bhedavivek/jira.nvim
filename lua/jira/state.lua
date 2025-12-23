local state = {
  buf = nil,
  win = nil,
  dim_win = nil,
  ns = vim.api.nvim_create_namespace("Jira"),
  status_hls = {},
  tree = {},
  line_map = {},
  project_key = nil,
  current_view = nil,
  current_query = nil,
  custom_jql = nil,
  cache = {},
  query_map = {},
  jql_line = nil,
}

return state
