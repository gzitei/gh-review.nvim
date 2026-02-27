local M = {}

--- Set up all highlight groups for the plugin.
function M.setup()
  local set_hl = vim.api.nvim_set_hl

  -- Theme-aware defaults for better integration with active colorscheme.
  set_hl(0, "GhReviewTitle", { link = "Title", default = true })
  set_hl(0, "GhReviewBorder", { link = "FloatBorder", default = true })
  set_hl(0, "GhReviewNormal", { link = "NormalFloat", default = true })
  set_hl(0, "GhReviewHeader", { link = "Comment", default = true })
  set_hl(0, "GhReviewSeparator", { link = "WinSeparator", default = true })

  set_hl(0, "GhReviewCardTitle", { link = "Function", default = true })
  set_hl(0, "GhReviewCardTitleDraft", { link = "WarningMsg", default = true })
  set_hl(0, "GhReviewCardNumber", { link = "Comment", default = true })
  set_hl(0, "GhReviewCardRepo", { link = "Identifier", default = true })
  set_hl(0, "GhReviewCardAuthor", { link = "Normal", default = true })
  set_hl(0, "GhReviewCardTime", { link = "Comment", default = true })
  set_hl(0, "GhReviewCardStats", { link = "NonText", default = true })

  set_hl(0, "GhReviewApproved", { link = "DiffAdd", default = true })
  set_hl(0, "GhReviewChangesRequested", { link = "DiffDelete", bg='none', default = true })
  set_hl(0, "GhReviewCommented", { link = "Special", default = true })
  set_hl(0, "GhReviewPending", { link = "WarningMsg", bg = 'none', default = true })

  set_hl(0, "GhReviewCISuccess", { link = "DiffAdd", default = true })
  set_hl(0, "GhReviewCIFailure", { link = "DiffDelete", default = true })
  set_hl(0, "GhReviewCIPending", { link = "WarningMsg", default = true })
  set_hl(0, "GhReviewCINone", { link = "Comment", default = true })

  set_hl(0, "GhReviewAdditions", { link = "DiffAdd", default = true })
  set_hl(0, "GhReviewDeletions", { link = "DiffDelete", default = true })
  set_hl(0, "GhReviewSelected", { link = "Visual", default = true })
  set_hl(0, "GhReviewSelectedText", { fg = "#ffffff", ctermfg = 15, bold = true, default = true })
  set_hl(0, "GhReviewSelectedBorder", { fg = "#ffffff", ctermfg = 15, bold = true, default = true })
  set_hl(0, "GhReviewSelectedNumber", { fg = "#ffffff", ctermfg = 15, bold = true, default = true })
  set_hl(0, "GhReviewSelectedApproved", { fg = "#4fa368", bg = 'none', ctermfg = 71, bold = true, default = true })
  set_hl(0, "GhReviewSelectedChangesRequested", { fg = "#c26161", bg = 'none', ctermfg = 131, bold = true, default = true })
  set_hl(0, "GhReviewSelectedCISuccess", { fg = "#0b3016", bg = "#6ea37b", ctermfg = 22, ctermbg = 71, bold = true, default = true })
  set_hl(0, "GhReviewSelectedCIFailure", { fg = "#4a0f0f", bg = "#b67f7f", ctermfg = 52, ctermbg = 131, bold = true, default = true })
  set_hl(0, "GhReviewSelectedCIPending", { fg = "#4a3b00", bg = "#b39f67", ctermfg = 94, ctermbg = 143, bold = true, default = true })
  set_hl(0, "GhReviewSelectedAdditions", { fg = "#0b3016", bg = "#6ea37b", ctermfg = 22, ctermbg = 71, bold = true, default = true })
  set_hl(0, "GhReviewSelectedDeletions", { fg = "#4a0f0f", bg = "#b67f7f", ctermfg = 52, ctermbg = 131, bold = true, default = true })
  set_hl(0, "GhReviewCursorLine", { link = "CursorLine", default = true })
  set_hl(0, "GhReviewDraft", { link = "WarningMsg", default = true })
  set_hl(0, "GhReviewLabel", { link = "PmenuSel", default = true })
  set_hl(0, "GhReviewLoading", { link = "WarningMsg", default = true })
  set_hl(0, "GhReviewEmpty", { link = "Comment", default = true })
  set_hl(0, "GhReviewError", { link = "ErrorMsg", default = true })
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

---@param status string
---@return string
function M.selected_approval_hl(status)
  local map = {
    approved = "GhReviewSelectedApproved",
    changes_requested = "GhReviewSelectedChangesRequested",
    commented = "GhReviewCommented",
    pending = "GhReviewSelectedCIPending",
  }
  return map[status] or "GhReviewCommented"
end

---@param status string
---@return string
function M.selected_ci_hl(status)
  local map = {
    success = "GhReviewSelectedCISuccess",
    failure = "GhReviewSelectedCIFailure",
    pending = "GhReviewSelectedCIPending",
    none = "GhReviewSelectedText",
  }
  return map[status] or "GhReviewSelectedText"
end

return M
