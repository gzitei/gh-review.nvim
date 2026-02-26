local M = {}

---@param values string[]|nil
---@return table
local function build_set(values)
  local set = {}
  if type(values) ~= "table" then
    return set
  end

  for _, value in ipairs(values) do
    if type(value) == "string" and value ~= "" then
      set[value:lower()] = true
    end
  end

  return set
end

---@param set table
---@return boolean
local function is_empty_set(set)
  return next(set) == nil
end

---@param iso_str string|nil
---@return number|nil
local function parse_iso8601_utc(iso_str)
  if not iso_str then
    return nil
  end

  local y, mo, d, h, mi, s = iso_str:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then
    return nil
  end

  return os.time({
    year = tonumber(y),
    month = tonumber(mo),
    day = tonumber(d),
    hour = tonumber(h),
    min = tonumber(mi),
    sec = tonumber(s),
  })
end

---@param requested_teams table[]|nil
---@param team_filter_set table
---@return boolean
local function matches_team_filter(requested_teams, team_filter_set)
  if is_empty_set(team_filter_set) then
    return true
  end

  if type(requested_teams) ~= "table" or #requested_teams == 0 then
    return false
  end

  for _, team in ipairs(requested_teams) do
    local slug = team.slug and team.slug:lower() or nil
    local org = team.organization and team.organization.login and team.organization.login:lower() or nil
    if slug and team_filter_set[slug] then
      return true
    end
    if org and slug and team_filter_set[org .. "/" .. slug] then
      return true
    end
  end

  return false
end

---@param options table|nil
---@return table
function M.resolve(options)
  local opts = options or {}
  local configured = opts.filters or {}
  local repositories = configured.repositories
  if type(repositories) ~= "table" or #repositories == 0 then
    repositories = opts.repos or {}
  end

  return {
    repositories = repositories,
    teams = configured.teams or {},
    status = configured.status or {},
    ci_status = configured.ci_status or {},
    max_age_days = configured.max_age_days,
  }
end

---@param pr table
---@param filters table|nil
---@return boolean
function M.matches(pr, filters)
  local configured = filters or {}

  local repo_filter_set = build_set(configured.repositories)
  local team_filter_set = build_set(configured.teams)
  local status_filter_set = build_set(configured.status)
  local ci_filter_set = build_set(configured.ci_status)

  if not is_empty_set(repo_filter_set) then
    local repo = (pr.repo_full_name or ""):lower()
    if not repo_filter_set[repo] then
      return false
    end
  end

  if not matches_team_filter(pr.requested_teams, team_filter_set) then
    return false
  end

  if not is_empty_set(status_filter_set) then
    local review_status = pr.draft and "draft" or (pr.approval_status and pr.approval_status.status or "pending")
    if not status_filter_set[review_status:lower()] then
      return false
    end
  end

  if not is_empty_set(ci_filter_set) then
    local ci_status = pr.pipeline_status and pr.pipeline_status.status or "none"
    if not ci_filter_set[ci_status:lower()] then
      return false
    end
  end

  if configured.max_age_days ~= nil then
    local max_age_days = tonumber(configured.max_age_days)
    if max_age_days and max_age_days >= 0 then
      local created_ts = parse_iso8601_utc(pr.created_at)
      local now_ts = os.time(os.date("!*t"))
      if not created_ts then
        return false
      end
      local age_seconds = now_ts - created_ts
      if age_seconds > (max_age_days * 86400) then
        return false
      end
    end
  end

  return true
end

return M
