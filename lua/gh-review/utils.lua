local M = {}

--- Format a relative time string from an ISO8601 timestamp.
---@param iso_str string ISO8601 timestamp (e.g. "2025-02-15T10:30:00Z")
---@return string
function M.relative_time(iso_str)
  if not iso_str then
    return "unknown"
  end

  -- Parse ISO8601
  local y, mo, d, h, mi, s = iso_str:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then
    return "unknown"
  end

  local ts = os.time({
    year = tonumber(y),
    month = tonumber(mo),
    day = tonumber(d),
    hour = tonumber(h),
    min = tonumber(mi),
    sec = tonumber(s),
  })

  local now = os.time(os.date("!*t"))
  local diff = now - ts

  if diff < 0 then
    return "just now"
  elseif diff < 60 then
    return diff .. "s ago"
  elseif diff < 3600 then
    local mins = math.floor(diff / 60)
    return mins .. "m ago"
  elseif diff < 86400 then
    local hours = math.floor(diff / 3600)
    return hours .. "h ago"
  else
    local days = math.floor(diff / 86400)
    if days == 1 then
      return "1 day ago"
    else
      return days .. " days ago"
    end
  end
end

--- Truncate a string to max_len, appending ".." if truncated.
---@param str string
---@param max_len number
---@return string
function M.truncate(str, max_len)
  if not str then
    return ""
  end
  if #str <= max_len then
    return str
  end
  return str:sub(1, max_len - 2) .. ".."
end

--- Pad a string to exactly `width` characters (right-padded with spaces).
---@param str string
---@param width number
---@return string
function M.pad_right(str, width)
  if #str >= width then
    return str:sub(1, width)
  end
  return str .. string.rep(" ", width - #str)
end

--- Center a string within `width` characters.
---@param str string
---@param width number
---@return string
function M.center(str, width)
  if #str >= width then
    return str:sub(1, width)
  end
  local pad = width - #str
  local left = math.floor(pad / 2)
  local right = pad - left
  return string.rep(" ", left) .. str .. string.rep(" ", right)
end

--- Map approval status to a display string.
---@param status table { status: string, approvals: number, changes_requested: number }
---@return string
function M.approval_badge(status)
  if not status then
    return "  Pending"
  end
  if status.status == "approved" then
    return string.format("  Approved (%d)", status.approvals)
  elseif status.status == "changes_requested" then
    return "  Changes Requested"
  elseif status.status == "commented" then
    return "  Commented"
  else
    return "  Pending"
  end
end

--- Map CI status to a display string.
---@param status table { status: string, success: number, total: number }
---@return string
function M.ci_badge(status)
  if not status then
    return "  No CI"
  end
  if status.status == "success" then
    return string.format("  CI Passing (%d/%d)", status.success, status.total)
  elseif status.status == "failure" then
    return string.format("  CI Failing (%d/%d)", status.success, status.total)
  elseif status.status == "pending" then
    return string.format("  CI Running (%d/%d)", status.completed, status.total)
  else
    return "  No CI"
  end
end

return M
