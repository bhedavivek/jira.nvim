---@class JiraData
---@field jql string
---@field fields string[]
---@field nextPageToken string
---@field maxResults integer

-- api.lua: Jira REST API client using curl
local config = require("jira.common.config")
local util = require("jira.common.util")
local version = require("jira.jira-api.version")
local cache = require("jira.common.cache")

---Execute curl command asynchronously
---@param method string
---@param endpoint string
---@param data? table
---@param callback? fun(T?: table, err?: string)
local function curl_request(method, endpoint, data, callback)
  local jira = config.options.jira
  local url = jira.base .. endpoint

  -- Build curl command
  local auth_header = ""
  if (jira.type or "basic"):lower() == "pat" then
    auth_header = ('-H "Authorization: Bearer %s"'):format(jira.token)
  else
    auth_header = ('-u "%s:%s"'):format(jira.email, jira.token)
  end

  local cmd = ('curl -s -X %s -H "Content-Type: application/json" -H "Accept: application/json" %s '):format(
    method,
    auth_header
  )

  local temp_file = nil
  if data then
    local json_data = vim.json.encode(data)
    temp_file = vim.fn.tempname()
    local f = io.open(temp_file, "w")
    if f then
      f:write(json_data)
      f:close()
      cmd = ("%s-d @%s "):format(cmd, temp_file)
    else
      if callback and vim.is_callable(callback) then
        callback(nil, "Failed to create temp file")
      end
      return
    end
  end

  cmd = ('%s"%s"'):format(cmd, url)

  local stdout = {}
  local stderr = {}

  vim.fn.jobstart(cmd, {
    on_stdout = function(_, d, _)
      for _, chunk in ipairs(d) do
        if chunk ~= "" then
          table.insert(stdout, chunk)
        end
      end
    end,
    on_stderr = function(_, d, _)
      for _, chunk in ipairs(d) do
        if chunk ~= "" then
          table.insert(stderr, chunk)
        end
      end
    end,
    on_exit = function(_, code, _)
      if temp_file then
        os.remove(temp_file)
      end

      if code ~= 0 then
        if callback then
          callback(nil, "Curl failed: " .. table.concat(stderr, "\n"))
        end
        return
      end

      local response = table.concat(stdout, "")
      if not response or response == "" then
        -- Return empty table for success with no content (e.g. 204 No Content)
        if callback and vim.is_callable(callback) then
          callback({}, nil)
        end
        return
      end

      -- Parse JSON
      local ok, result = pcall(vim.json.decode, response)
      if not ok then
        if callback and vim.is_callable(callback) then
          callback(nil, "Failed to parse JSON: " .. tostring(result) .. " | Resp: " .. response)
        end
        return
      end

      if callback and vim.is_callable(callback) then
        callback(result, nil)
      end
    end,
  })
end

---@class Jira.API
local M = {}

-- Search for issues using JQL
---@param jql string
---@param fields? string[]
---@param page_token? string
---@param max_results? integer
---@param callback? fun(T?: table, err?: string)
---@param project_key? string
function M.search_issues(jql, page_token, max_results, fields, callback, project_key)
  local story_point_field = config.get_project_config(project_key).story_point_field
  fields = fields
    or {
      "summary",
      "status",
      "parent",
      "priority",
      "assignee",
      "timespent",
      "timeoriginalestimate",
      "issuetype",
      story_point_field,
    }

  local data = version.transform_search_data(jql, page_token, max_results, fields)
  local endpoint = version.get_search_endpoint()

  curl_request("POST", endpoint, data, function(result, err)
    if err then
      if callback and vim.is_callable(callback) then
        callback(nil, err)
      end
      return
    end

    local transformed_result = version.transform_search_response(result)
    if callback and vim.is_callable(callback) then
      callback(transformed_result, nil)
    end
  end)
end

-- Get available transitions for an issue
function M.get_transitions(issue_key, callback)
  local endpoint = version.get_api_path() .. "/issue/" .. issue_key .. "/transitions"
  curl_request("GET", endpoint, nil, function(result, err)
    local is_fun = (callback and vim.is_callable(callback))
    if err then
      if callback and is_fun then
        callback(nil, err)
      end
      return
    end
    if callback and is_fun then
      callback(result.transitions or {}, nil)
    end
  end)
end

---Transition an issue to a new status
---@param issue_key string
---@param callback? fun(cond?: boolean, err?: string)
function M.transition_issue(issue_key, transition_id, callback)
  local data = { transition = { id = transition_id } }
  local endpoint = version.get_api_path() .. "/issue/" .. issue_key .. "/transitions"
  curl_request("POST", endpoint, data, function(_, err)
    if err then
      if callback and vim.is_callable(callback) then
        callback(nil, err)
      end
      return
    end
    if callback and vim.is_callable(callback) then
      callback(true, nil)
    end
  end)
end

-- Add worklog to an issue
---@param comment? string|fun(cond?: boolean, err?: string)
---@param callback? fun(cond?: boolean, err?: string)
function M.add_worklog(issue_key, time_spent, comment, callback)
  -- Support previous signature: (issue_key, time_spent, callback)
  if type(comment) == "function" and vim.is_callable(comment) then
    callback = comment
    comment = nil
  end

  local data = {
    timeSpent = time_spent,
  }

  if comment and comment ~= "" then
    data.comment = version.transform_comment_data(comment).body
  end

  local endpoint = version.get_api_path() .. "/issue/" .. issue_key .. "/worklog"
  curl_request("POST", endpoint, data, function(_, err)
    if err then
      if callback and vim.is_callable(callback) then
        callback(nil, err)
      end
      return
    end
    if callback and vim.is_callable(callback) then
      callback(true, nil)
    end
  end)
end

-- Assign an issue to a user
---@param callback? fun(cond?: boolean, err?: string)
function M.assign_issue(issue_key, account_id, callback)
  local data = {
    accountId = account_id,
  }

  local endpoint = version.get_api_path() .. "/issue/" .. issue_key .. "/assignee"
  curl_request("PUT", endpoint, data, function(_, err)
    if err then
      if callback and vim.is_callable(callback) then
        callback(nil, err)
      end
      return
    end
    if callback and vim.is_callable(callback) then
      callback(true, nil)
    end
  end)
end

-- Get current user details
function M.get_myself(callback)
  local endpoint = version.get_api_path() .. "/myself"
  curl_request("GET", endpoint, nil, callback)
end

-- Get issue details
---@param issue_key string
---@param callback function
function M.get_issue(issue_key, callback)
  local endpoint = version.get_api_path() .. "/issue/" .. issue_key
  curl_request("GET", endpoint, nil, function(result, err)
    if err then
      if callback and vim.is_callable(callback) then
        callback(nil, err)
      end
      return
    end

    -- Ensure the response has the expected structure
    if result and not result.key then
      result.key = issue_key
    end

    if callback and vim.is_callable(callback) then
      callback(result, nil)
    end
  end)
end

-- Get statuses for a project
function M.get_project_statuses(project, callback)
  local endpoint = version.get_api_path() .. "/project/" .. project .. "/statuses"
  curl_request("GET", endpoint, nil, callback)
end

-- Get comments for an issue
function M.get_comments(issue_key, callback)
  local endpoint = version.get_api_path() .. "/issue/" .. issue_key .. "/comment"
  curl_request("GET", endpoint, nil, function(result, err)
    if err then
      if callback then
        callback(nil, err)
      end
      return
    end
    if callback then
      callback(result.comments or {}, nil)
    end
  end)
end

-- Add comment to an issue
function M.add_comment(issue_key, comment, callback)
  local data = version.transform_comment_data(comment)
  local endpoint = version.get_api_path() .. "/issue/" .. issue_key .. "/comment"

  curl_request("POST", endpoint, data, function(_, err)
    if err then
      if callback then
        callback(nil, err)
      end
      return
    end
    if callback then
      callback(true, nil)
    end
  end)
end

-- Edit a comment
function M.edit_comment(issue_key, comment_id, comment, callback)
  local data = version.transform_comment_data(comment)
  local endpoint = version.get_api_path() .. "/issue/" .. issue_key .. "/comment/" .. comment_id

  curl_request("PUT", endpoint, data, function(_, err)
    if err then
      if callback then
        callback(nil, err)
      end
      return
    end
    if callback then
      callback(true, nil)
    end
  end)
end

-- Update issue
---@param issue_key string
---@param fields table
---@param callback? fun(result?: table, err?: string)
function M.update_issue(issue_key, fields, callback)
  local data = {
    fields = fields,
  }

  local endpoint = version.get_api_path() .. "/issue/" .. issue_key
  curl_request("PUT", endpoint, data, function(result, err)
    if err then
      if callback and vim.is_callable(callback) then
        callback(nil, err)
      end
      return
    end
    if callback and vim.is_callable(callback) then
      callback(result, nil)
    end
  end)
end

-- Create issue
---@param fields table
---@param callback? fun(result?: table, err?: string)
function M.create_issue(fields, callback)
  local data = {
    fields = fields,
  }

  local endpoint = version.get_api_path() .. "/issue"
  curl_request("POST", endpoint, data, function(result, err)
    if err then
      if callback and vim.is_callable(callback) then
        callback(nil, err)
      end
      return
    end

    if result and (result.errorMessages or result.errors) then
      local errors = {}
      if result.errorMessages then
        for _, msg in ipairs(result.errorMessages) do
          table.insert(errors, msg)
        end
      end
      if result.errors then
        for k, v in pairs(result.errors) do
          table.insert(errors, k .. ": " .. v)
        end
      end

      if #errors > 0 then
        if callback and vim.is_callable(callback) then
          callback(nil, table.concat(errors, "\n"))
        end
        return
      end
    end

    -- Ensure result has key field for both v2 and v3
    if result and not result.key and result.id then
      -- For some responses, we might need to fetch the issue to get the key
      M.get_issue(result.id, callback)
      return
    end

    if callback and vim.is_callable(callback) then
      callback(result, nil)
    end
  end)
end

-- Get create metadata (issue types) for a project
function M.get_create_meta(project_key, callback)
  local endpoint = version.get_api_path() .. "/issue/createmeta?projectKeys=" .. project_key
  curl_request("GET", endpoint, nil, function(result, err)
    if err then
      if callback and vim.is_callable(callback) then
        callback(nil, err)
      end
      return
    end
    if callback and vim.is_callable(callback) then
      -- Result structure: { projects: [ { key: "PROJ", issuetypes: [ ... ] } ] }
      local project_data = result.projects and result.projects[1]
      if project_data then
        callback(project_data.issuetypes, nil)
      else
        callback({}, nil)
      end
    end
  end)
end

-- Get all issue types
function M.get_issue_types(callback)
  local cached = cache.get("issue_types")
  if cached then
    callback(cached, nil)
    return
  end

  local endpoint = version.get_api_path() .. "/issuetype"
  curl_request("GET", endpoint, nil, function(result, err)
    if not err and result then
      cache.set("issue_types", result)
    end
    callback(result, err)
  end)
end

-- Get all priorities
function M.get_priorities(callback)
  local cached = cache.get("priorities")
  if cached then
    callback(cached, nil)
    return
  end

  local endpoint = version.get_api_path() .. "/priority"
  curl_request("GET", endpoint, nil, function(result, err)
    if not err and result then
      cache.set("priorities", result)
    end
    callback(result, err)
  end)
end

-- Get assignable users
-- Get assignable users with dynamic prefix expansion
function M.get_assignable_users(project_key, issue_key, callback)
  local cache_key = "assignable_users_" .. (project_key or "")
  local cached = cache.get(cache_key)
  if cached then
    callback(cached, nil)
    return
  end

  local all_users = {}
  local user_ids = {}
  local chars = {"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"}
  local prefixes_to_process = {}
  local processed_prefixes = {}
  local max_depth = 3
  
  -- Start with single character prefixes only
  for _, char in ipairs(chars) do
    table.insert(prefixes_to_process, char)
  end

  local function fetch_with_prefix(prefix)
    -- Skip if already processed
    if processed_prefixes[prefix] then
      -- Process next prefix
      if #prefixes_to_process > 0 then
        local next_prefix = table.remove(prefixes_to_process, 1)
        vim.defer_fn(function() fetch_with_prefix(next_prefix) end, 50)
      else
        vim.notify("Final assignable user count: " .. #all_users, vim.log.levels.INFO)
        if project_key then
          cache.set(cache_key, all_users)
        end
        callback(all_users, nil)
      end
      return
    end
    
    processed_prefixes[prefix] = true
    local params = { "maxResults=100" }
    if prefix ~= "" then
      table.insert(params, "username=" .. prefix .. "*")
    end
    if project_key then
      table.insert(params, "project=" .. project_key)
    end
    if issue_key then
      table.insert(params, "issueKey=" .. issue_key)
    end

    local query_string = "?" .. table.concat(params, "&")
    local endpoint = version.get_api_path() .. "/user/assignable/search" .. query_string

    curl_request("GET", endpoint, nil, function(result, err)
      if err then
        callback(nil, err)
        return
      end

      local new_users = 0
      if result and #result > 0 then
        for _, user in ipairs(result) do
          local user_id = user.accountId or user.name
          if not user_ids[user_id] then
            table.insert(all_users, user)
            user_ids[user_id] = true
            new_users = new_users + 1
          end
        end

        -- If we got exactly 100 results and haven't reached max depth, expand this prefix further
        if #result == 100 and #prefix < max_depth then
          for _, char in ipairs(chars) do
            table.insert(prefixes_to_process, prefix .. char)
          end
          vim.notify("Prefix '" .. (prefix == "" and "empty" or prefix) .. "': 100 users (expanding), " .. new_users .. " new, total: " .. #all_users, vim.log.levels.INFO)
        else
          vim.notify("Prefix '" .. (prefix == "" and "empty" or prefix) .. "': " .. #result .. " users, " .. new_users .. " new, total: " .. #all_users, vim.log.levels.INFO)
        end
      else
        vim.notify("Prefix '" .. (prefix == "" and "empty" or prefix) .. "': 0 users", vim.log.levels.INFO)
      end

      -- Process next prefix
      if #prefixes_to_process > 0 then
        local next_prefix = table.remove(prefixes_to_process, 1)
        vim.defer_fn(function() fetch_with_prefix(next_prefix) end, 50)
      else
        vim.notify("Final assignable user count: " .. #all_users, vim.log.levels.INFO)
        if project_key then
          cache.set(cache_key, all_users)
        end
        callback(all_users, nil)
      end
    end)
  end

  fetch_with_prefix("")
end

-- Get board for project
---@param project_key string
---@param callback fun(board?: table, err?: string)
function M.get_board_for_project(project_key, callback)
  local endpoint = "/rest/agile/1.0/board?projectKeyOrId=" .. project_key
  curl_request("GET", endpoint, nil, function(result, err)
    if err then
      callback(nil, err)
      return
    end
    local boards = result and result.values or {}
    callback(boards[1], nil)
  end)
end

-- Get board configuration (columns)
---@param board_id number
---@param callback fun(config?: table, err?: string)
function M.get_board_config(board_id, callback)
  local endpoint = "/rest/agile/1.0/board/" .. board_id .. "/configuration"
  curl_request("GET", endpoint, nil, callback)
end

return M
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
