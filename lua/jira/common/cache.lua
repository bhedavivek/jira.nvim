-- cache.lua: Generic cache implementation with optional persistence
local M = {}

local cache = {}
local data_dir = vim.fn.stdpath("data") .. "/jira.nvim"
local persist_file = data_dir .. "/prefs.json"
local persist_data = nil

local function load_persist()
  if persist_data then return persist_data end
  local f = io.open(persist_file, "r")
  if f then
    local content = f:read("*a")
    f:close()
    local ok, data = pcall(vim.json.decode, content)
    persist_data = ok and data or {}
  else
    persist_data = {}
  end
  return persist_data
end

local function save_persist()
  vim.fn.mkdir(data_dir, "p")
  local content = vim.json.encode(persist_data or {})
  vim.uv.fs_open(persist_file, "w", 438, function(err, fd)
    if err or not fd then return end
    vim.uv.fs_write(fd, content, -1, function()
      vim.uv.fs_close(fd)
    end)
  end)
end

local function make_key(key)
  if type(key) == "table" then
    return table.concat(key, ".")
  end
  return key
end

---@param key string|string[]
---@param persist? boolean
function M.get(key, persist)
  local k = make_key(key)
  if persist then
    return load_persist()[k]
  end
  return cache[k]
end

---@param key string|string[]
---@param value any
---@param persist? boolean
function M.set(key, value, persist)
  local k = make_key(key)
  if persist then
    local data = load_persist()
    data[k] = value
    save_persist()
  else
    cache[k] = value
  end
end

---@param key? string|string[]
---@param persist? boolean
function M.clear(key, persist)
  if persist then
    local data = load_persist()
    if key then
      data[make_key(key)] = nil
    else
      persist_data = {}
    end
    save_persist()
  else
    if key then
      cache[make_key(key)] = nil
    else
      cache = {}
    end
  end
end

return M
