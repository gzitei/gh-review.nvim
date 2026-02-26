local M = {}

local VALID_KEYS = {
  review_requests = true,
  authored_prs = true,
}
local mem = {}

local function cache_dir()
  local dir = vim.fn.stdpath("cache") .. "/gh-review"
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
  return dir
end

local function file_path(key)
  return cache_dir() .. "/" .. key .. ".json"
end

local function read_disk(key)
  local path = file_path(key)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  local lines = vim.fn.readfile(path)
  if not lines or #lines == 0 then
    return nil
  end
  local ok, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if ok and data then
    return data
  end
  return nil
end

local function write_disk(key, entry)
  local ok, encoded = pcall(vim.json.encode, entry)
  if not ok then
    return
  end
  vim.fn.writefile({ encoded }, file_path(key))
end

---Returns cached value for key if younger than max_age_seconds.
---@param key string
---@param max_age_seconds? number
---@return any|nil
function M.get(key, max_age_seconds)
  if not VALID_KEYS[key] then
    return nil
  end

  local now = os.time()

  local m = mem[key]
  if m and (not max_age_seconds or (now - m.saved_at) < max_age_seconds) then
    return m.value
  end

  local d = read_disk(key)
  if d and d.saved_at and (not max_age_seconds or (now - d.saved_at) < max_age_seconds) then
    mem[key] = d
    return d.value
  end

  return nil
end

---@param key string
---@param value any
function M.set(key, value)
  if not VALID_KEYS[key] then
    return
  end

  local entry = {
    value = value,
    saved_at = os.time(),
  }
  mem[key] = entry
  write_disk(key, entry)
end

---@param key string
function M.invalidate(key)
  if not VALID_KEYS[key] then
    return
  end

  mem[key] = nil
  local path = file_path(key)
  if vim.fn.filereadable(path) == 1 then
    vim.fn.delete(path)
  end
end

return M
