local M = {}

--- Set up all highlight groups for the plugin.
function M.setup()
  local set_hl = vim.api.nvim_set_hl

  -- Window chrome
  set_hl(0, "GhReviewTitle", { fg = "#c9d1d9", bg = "#161b22", bold = true })
  set_hl(0, "GhReviewBorder", { fg = "#30363d", bg = "#0d1117" })
  set_hl(0, "GhReviewNormal", { fg = "#c9d1d9", bg = "#0d1117" })
  set_hl(0, "GhReviewHeader", { fg = "#8b949e", bg = "#0d1117", bold = true })
  set_hl(0, "GhReviewSeparator", { fg = "#21262d", bg = "#0d1117" })

  -- Card components
  set_hl(0, "GhReviewCardTitle", { fg = "#58a6ff", bold = true })
  set_hl(0, "GhReviewCardTitleDraft", { fg = "#d29922", bold = true, italic = true })
  set_hl(0, "GhReviewCardNumber", { fg = "#8b949e" })
  set_hl(0, "GhReviewCardRepo", { fg = "#bc8cff" })
  set_hl(0, "GhReviewCardAuthor", { fg = "#c9d1d9" })
  set_hl(0, "GhReviewCardTime", { fg = "#484f58" })
  set_hl(0, "GhReviewCardStats", { fg = "#8b949e" })

  -- Approval status badges
  set_hl(0, "GhReviewApproved", { fg = "#3fb950", bold = true })
  set_hl(0, "GhReviewChangesRequested", { fg = "#f85149", bold = true })
  set_hl(0, "GhReviewCommented", { fg = "#58a6ff" })
  set_hl(0, "GhReviewPending", { fg = "#d29922" })

  -- CI status badges
  set_hl(0, "GhReviewCISuccess", { fg = "#3fb950" })
  set_hl(0, "GhReviewCIFailure", { fg = "#f85149" })
  set_hl(0, "GhReviewCIPending", { fg = "#d29922" })
  set_hl(0, "GhReviewCINone", { fg = "#484f58" })

  -- Stats
  set_hl(0, "GhReviewAdditions", { fg = "#3fb950" })
  set_hl(0, "GhReviewDeletions", { fg = "#f85149" })

  -- Selected card
  set_hl(0, "GhReviewSelected", { bg = "#161b22" })
  set_hl(0, "GhReviewCursorLine", { bg = "#1c2128" })

  -- Draft indicator
  set_hl(0, "GhReviewDraft", { fg = "#d29922", italic = true })

  -- Labels
  set_hl(0, "GhReviewLabel", { fg = "#c9d1d9", bg = "#21262d" })

  -- Loading / empty states
  set_hl(0, "GhReviewLoading", { fg = "#d29922", italic = true })
  set_hl(0, "GhReviewEmpty", { fg = "#484f58", italic = true })
  set_hl(0, "GhReviewError", { fg = "#f85149", bold = true })
end

--- Get the highlight group for an approval status.
---@param status string "approved"|"changes_requested"|"commented"|"pending"
---@return string highlight group name
function M.approval_hl(status)
  local map = {
    approved = "GhReviewApproved",
    changes_requested = "GhReviewChangesRequested",
    commented = "GhReviewCommented",
    pending = "GhReviewPending",
  }
  return map[status] or "GhReviewPending"
end

--- Get the highlight group for a CI status.
---@param status string "success"|"failure"|"pending"|"none"
---@return string highlight group name
function M.ci_hl(status)
  local map = {
    success = "GhReviewCISuccess",
    failure = "GhReviewCIFailure",
    pending = "GhReviewCIPending",
    none = "GhReviewCINone",
  }
  return map[status] or "GhReviewCINone"
end

return M
