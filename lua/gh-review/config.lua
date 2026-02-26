---@class GhReviewConfigView
---@field width number Window width ratio
---@field height number Window height ratio
---@field border string|table Window border style

---@class GhReviewConfigKeymaps
---@field close string Close the window
---@field open_review string Open the selected PR
---@field refresh string Refresh PR list
---@field open_in_browser string Open PR in browser
---@field toggle_detail string View PR details
---@field next_pr string Next PR
---@field prev_pr string Previous PR
---@field next_view string Toggle to next list view
---@field prev_view string Toggle to previous list view

---@class GhReviewConfig
---@field github_token? string GitHub personal access token (or set GITHUB_TOKEN env var)
---@field repos? string[] Backward-compatible alias for filters.repositories
---@field teams? string[] Backward-compatible alias for filters.teams
---@field filters? GhReviewConfigFilters PR list filtering options
---@field max_results? number How many PRs to fetch at most
---@field auto_fetch? boolean Auto-fetch remote before switching branches
---@field auto_stash? boolean Auto-stash changes before switching branches
---@field cache_ttl_minutes? number Cache validity in minutes (0 disables caching)
---@field view? GhReviewConfigView View configuration
---@field keymaps? GhReviewConfigKeymaps Keymaps inside the PR list window

---@class GhReviewConfigFilters
---@field repositories? string[] Restrict PR list to these repositories (e.g. {"owner/repo"})
---@field teams? string[] Restrict PR list to PRs requested from these teams (e.g. {"owner/team"})
---@field status? string[] Restrict by review status: pending|commented|approved|changes_requested|draft
---@field ci_status? string[] Restrict by CI status: success|failure|pending|none
---@field max_age_days? number Restrict to PRs created within the last N days

local M = {}

---@type GhReviewConfig
M.defaults = {
  github_token = "",
  repos = {},
  teams = {},
  filters = {
    repositories = {},
    teams = {},
    status = {},
    ci_status = {},
    max_age_days = nil,
  },
  max_results = 50,
  auto_fetch = true,
  auto_stash = true,
  cache_ttl_minutes = 5,
  view = {
    width = 0.7,
    height = 0.8,
    border = "rounded",
  },
  keymaps = {
    close = "q",
    open_review = "<CR>",
    refresh = "r",
    open_in_browser = "o",
    toggle_detail = "K",
    next_pr = "n",
    prev_pr = "N",
    next_view = "<Right>",
    prev_view = "<Left>",
  },
}

---@type GhReviewConfig
M.options = {}

--- Setup the configuration
---@param opts? GhReviewConfig User configuration overrides
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})

  -- Allow env var fallback for token
  if M.options.github_token == "" then
    M.options.github_token = vim.env.GITHUB_TOKEN or ""
  end

  -- Fallback to `gh auth token` if available
  if M.options.github_token == "" and vim.fn.executable("gh") == 1 then
    local token_cmd = vim.fn.system({"gh", "auth", "token"})
    if vim.v.shell_error == 0 and token_cmd and token_cmd ~= "" then
      M.options.github_token = token_cmd:gsub("%s+", "")
    end
  end
end

--- Get the configured GitHub token, raising an error if missing.
---@return string
function M.get_token()
  local token = M.options.github_token
  if not token or token == "" then
    error("gh-review: GitHub token not configured. Set github_token in setup() or GITHUB_TOKEN env var, or install and login with GitHub CLI (gh auth login).")
  end
  return token
end

return M
