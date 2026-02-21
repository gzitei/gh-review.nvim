local config = require("gh-review.config")

local M = {}

--- Stash changes if there are any.
---@return boolean stashed Whether changes were stashed
---@return string|nil error
function M.stash_if_needed()
  if not config.options.auto_stash then
    return false, nil
  end

  -- Check if there are uncommitted changes
  local result = vim.fn.systemlist("git status --porcelain")
  if vim.v.shell_error ~= 0 then
    return false, "Failed to check git status"
  end

  if #result == 0 then
    return false, nil
  end

  vim.fn.system("git stash push -m 'gh-review: auto-stash before branch switch'")
  if vim.v.shell_error ~= 0 then
    return false, "Failed to stash changes"
  end

  return true, nil
end

--- Pop the most recent stash (if it was auto-created by us).
function M.stash_pop()
  local stash_list = vim.fn.systemlist("git stash list -1")
  if #stash_list > 0 and stash_list[1]:find("gh%-review: auto%-stash") then
    vim.fn.system("git stash pop")
  end
end

--- Fetch the remote for a given branch.
---@param remote string Remote name (default "origin")
---@param branch string Branch name to fetch
---@return boolean success
---@return string|nil error
function M.fetch_branch(remote, branch)
  if not config.options.auto_fetch then
    return true, nil
  end

  remote = remote or "origin"
  vim.fn.system(string.format("git fetch %s %s", remote, branch))
  if vim.v.shell_error ~= 0 then
    return false, string.format("Failed to fetch %s/%s", remote, branch)
  end

  return true, nil
end

--- Get the current branch name.
---@return string|nil branch
function M.current_branch()
  local result = vim.fn.systemlist("git rev-parse --abbrev-ref HEAD")
  if vim.v.shell_error ~= 0 or #result == 0 then
    return nil
  end
  return vim.trim(result[1])
end

--- Check if a branch exists locally.
---@param branch string
---@return boolean
function M.branch_exists(branch)
  vim.fn.system(string.format("git rev-parse --verify %s", branch))
  return vim.v.shell_error == 0
end

--- Switch to a branch. Creates it from the remote tracking branch if it doesn't exist locally.
---@param branch string Branch name
---@param pr table PR data object (for remote info)
---@return boolean success
---@return string|nil error
function M.switch_to_branch(branch, pr)
  if not branch then
    return false, "No branch name provided"
  end

  -- Fetch the branch first
  local fetch_ok, fetch_err = M.fetch_branch("origin", branch)
  if not fetch_ok then
    -- Non-fatal: we might still have the branch locally
    vim.notify("gh-review: " .. (fetch_err or "fetch failed, trying local"), vim.log.levels.WARN)
  end

  -- Stash changes if needed
  local stashed, stash_err = M.stash_if_needed()
  if stash_err then
    return false, stash_err
  end

  -- Switch to the branch
  if M.branch_exists(branch) then
    vim.fn.system(string.format("git checkout %s", branch))
  else
    -- Create local branch tracking the remote
    vim.fn.system(string.format("git checkout -b %s origin/%s", branch, branch))
  end

  if vim.v.shell_error ~= 0 then
    -- Restore stash if we stashed
    if stashed then
      M.stash_pop()
    end
    return false, string.format("Failed to checkout branch: %s", branch)
  end

  -- Pull latest
  vim.fn.system("git pull --ff-only 2>/dev/null")

  return true, nil
end

--- Get the merge base between the PR branch and its base.
---@param head_ref string PR head branch
---@param base_ref string PR base branch (e.g. "main")
---@return string|nil merge_base_sha
function M.get_merge_base(head_ref, base_ref)
  local result = vim.fn.systemlist(string.format("git merge-base %s origin/%s", head_ref, base_ref))
  if vim.v.shell_error ~= 0 or #result == 0 then
    return nil
  end
  return vim.trim(result[1])
end

return M
