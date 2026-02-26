local config = require("gh-review.config")
local curl = require("plenary.curl")
local filters = require("gh-review.filters")
local cache = require("gh-review.cache")

local M = {}

local API_BASE = "https://api.github.com"

--- Make an authenticated GitHub API GET request (synchronous).
---@param endpoint string API endpoint path (e.g. "/user")
---@return table|nil response Parsed JSON response
---@return string|nil error Error message if request failed
local function api_get(endpoint)
  local token = config.get_token()

  local response = curl.get(API_BASE .. endpoint, {
    headers = {
      ["Authorization"] = "token " .. token,
      ["Accept"] = "application/vnd.github.v3+json",
      ["User-Agent"] = "gh-review.nvim",
    },
    timeout = 30000,
  })

  if not response or response.status ~= 200 then
    local status = response and response.status or "no response"
    return nil, string.format("GitHub API error: %s (endpoint: %s)", tostring(status), endpoint)
  end

  local ok, decoded = pcall(vim.json.decode, response.body)
  if not ok then
    return nil, "Failed to parse GitHub API response"
  end

  return decoded, nil
end

--- Make a paginated GitHub API GET request (follows Link headers).
---@param endpoint string API endpoint path
---@return table results Concatenated array of all pages
---@return string|nil error Error message if any request failed
local function api_get_paginated(endpoint)
  local all_results = {}
  local separator = endpoint:find("?") and "&" or "?"
  local url = endpoint .. separator .. "per_page=100"
  local page = 1

  while url do
    local result, err = api_get(url)
    if err then
      return all_results, err
    end

    if type(result) == "table" then
      -- Search API wraps results in { items: [...] }
      local items = result.items or result
      for _, item in ipairs(items) do
        table.insert(all_results, item)
      end
    end

    -- Check if there are fewer results than per_page (last page)
    local items = result.items or result
    if type(items) ~= "table" or #items < 100 then
      url = nil
    else
      page = page + 1
      -- Rebuild the URL with the next page
      local base = endpoint .. separator .. "per_page=100"
      url = base .. "&page=" .. page
    end
  end

  return all_results, nil
end

--- Get the authenticated user's info.
---@return table|nil user
---@return string|nil error
function M.get_user()
  return api_get("/user")
end

--- Calculate approval status from a list of reviews.
---@param reviews table[] Array of review objects
---@param current_user string The current user's login
---@return table { status: string, approvals: number, changes_requested: number, commenters: number }
local function calculate_approval_status(reviews, current_user)
  local by_user = {}

  for _, review in ipairs(reviews or {}) do
    local login = review.user and review.user.login
    if login and login ~= current_user then
      local existing = by_user[login]
      if not existing or (review.submitted_at or "") > (existing.submitted_at or "") then
        by_user[login] = review
      end
    end
  end

  local approvals = 0
  local changes_requested = 0
  local commenters = 0

  for _, review in pairs(by_user) do
    if review.state == "APPROVED" then
      approvals = approvals + 1
    elseif review.state == "CHANGES_REQUESTED" then
      changes_requested = changes_requested + 1
    elseif review.state == "COMMENTED" then
      commenters = commenters + 1
    end
  end

  local status = "pending"
  if changes_requested > 0 then
    status = "changes_requested"
  elseif approvals > 0 then
    status = "approved"
  elseif commenters > 0 then
    status = "commented"
  end

  return {
    status = status,
    approvals = approvals,
    changes_requested = changes_requested,
    commenters = commenters,
  }
end

--- Calculate CI/pipeline status from check runs.
---@param check_runs table[] Array of check run objects
---@return table { status: string, total: number, completed: number, success: number, failure: number }
local function calculate_pipeline_status(check_runs)
  if not check_runs or #check_runs == 0 then
    return { status = "none", total = 0, completed = 0, success = 0, failure = 0 }
  end

  local total = #check_runs
  local completed = 0
  local success = 0
  local failure = 0

  for _, run in ipairs(check_runs) do
    if run.status == "completed" then
      completed = completed + 1
      if run.conclusion == "success" or run.conclusion == "skipped" or run.conclusion == "neutral" then
        success = success + 1
      elseif run.conclusion == "failure" or run.conclusion == "timed_out" or run.conclusion == "cancelled" or run.conclusion == "action_required" then
        failure = failure + 1
      end
    end
  end

  local status = "pending"
  if failure > 0 then
    status = "failure"
  elseif completed == total and success == total then
    status = "success"
  elseif completed == total then
    status = "success"
  end

  return {
    status = status,
    total = total,
    completed = completed,
    success = success,
    failure = failure,
  }
end

--- Fetch all PRs that the current user needs to review directly from GitHub.
--- This is a blocking call -- use vim.schedule or wrap in async for UI.
---@return table[] prs Array of enriched PR objects
---@return string|nil error
local function fetch_review_requests_live()
  -- Get current user
  local user, user_err = M.get_user()
  if user_err then
    return {}, user_err
  end
  local current_user = user.login

  local configured_filters = filters.resolve(config.options)

  -- Search for PRs where review is requested for user or configured teams
  local search_results = {}
  local seen_prs = {}
  local max = config.options.max_results or 50

  local queries = {}
  table.insert(queries, string.format("type:pr state:open archived:false review-requested:%s", current_user))

  if config.options.teams and type(config.options.teams) == "table" then
    for _, team in ipairs(config.options.teams) do
      table.insert(queries, string.format("type:pr state:open archived:false team-review-requested:%s", team))
    end
  end

  for _, query in ipairs(queries) do
    if #search_results >= max then
      break
    end

    local search_endpoint = string.format("/search/issues?q=%s&sort=updated&order=desc", vim.uri_encode(query))
    local results, search_err = api_get_paginated(search_endpoint)
    
    if results and not search_err then
      for _, item in ipairs(results) do
        if not seen_prs[item.number] then
          seen_prs[item.number] = true
          table.insert(search_results, item)
          if #search_results >= max then
            break
          end
        end
      end
    end
  end

  -- Enrich each PR with details, reviews, and check runs
  local prs = {}

  for _, item in ipairs(search_results) do
    -- Extract owner/repo from the repository_url
    local owner, repo = item.repository_url:match("/repos/([^/]+)/([^/]+)$")
    if owner and repo then
      local full_name = owner .. "/" .. repo

      local pr_number = item.number

      -- Fetch PR details
      local pr_detail = api_get(string.format("/repos/%s/%s/pulls/%d", owner, repo, pr_number))

      -- Fetch reviews
      local reviews = api_get(string.format("/repos/%s/%s/pulls/%d/reviews", owner, repo, pr_number))

      -- Check if user already approved
      local user_approved = false
      if reviews then
        for i = #reviews, 1, -1 do
          local r = reviews[i]
          if r.user and r.user.login == current_user then
            if r.state == "APPROVED" then
              user_approved = true
            end
            break
          end
        end
      end

      if not user_approved then
        -- Fetch check runs for head commit
        local check_runs_data = nil
        if pr_detail and pr_detail.head and pr_detail.head.sha then
          local cr = api_get(string.format("/repos/%s/%s/commits/%s/check-runs", owner, repo, pr_detail.head.sha))
          if cr then
            check_runs_data = cr.check_runs
          end
        end

        local pr = {
          number = pr_number,
          title = item.title or "Untitled",
          html_url = item.html_url,
          created_at = item.created_at,
          updated_at = item.updated_at,
          draft = pr_detail and pr_detail.draft or false,
          author = item.user and item.user.login or "unknown",
          repo_name = repo,
          repo_full_name = full_name,
          head_ref = pr_detail and pr_detail.head and pr_detail.head.ref or nil,
          head_sha = pr_detail and pr_detail.head and pr_detail.head.sha or nil,
          head_repo_full_name = pr_detail and pr_detail.head and pr_detail.head.repo and pr_detail.head.repo.full_name or nil,
          base_ref = pr_detail and pr_detail.base and pr_detail.base.ref or nil,
          additions = pr_detail and pr_detail.additions or 0,
          deletions = pr_detail and pr_detail.deletions or 0,
          commits = pr_detail and pr_detail.commits or 0,
          comments = (item.comments or 0) + (pr_detail and pr_detail.review_comments or 0),
          labels = item.labels or {},
          requested_teams = pr_detail and pr_detail.requested_teams or {},
          approval_status = calculate_approval_status(reviews, current_user),
          pipeline_status = calculate_pipeline_status(check_runs_data),
          reviews = reviews or {},
        }

        if filters.matches(pr, configured_filters) then
          table.insert(prs, pr)
        end
      end
    end
  end

  return prs, nil
end

--- Fetch review requests using cache with configurable invalidation.
---@param opts? { force?: boolean }
---@return table[] prs Array of enriched PR objects
---@return string|nil error
function M.fetch_review_requests(opts)
  opts = opts or {}

  local key = "review_requests"
  local ttl_minutes = tonumber(config.options.cache_ttl_minutes) or 0
  local ttl_seconds = ttl_minutes > 0 and (ttl_minutes * 60) or nil
  local stale_cached = cache.get(key)

  if (not opts.force) and ttl_seconds then
    local cached = cache.get(key, ttl_seconds)
    if cached then
      return cached, nil
    end
  end

  local prs, err = fetch_review_requests_live()
  if err then
    if stale_cached then
      return stale_cached, nil
    end
    return {}, err
  end

  if ttl_seconds then
    cache.set(key, prs)
  else
    cache.invalidate(key)
  end

  return prs, nil
end

return M
