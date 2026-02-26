local config = require("gh-review.config")
local colors = require("gh-review.colors")
local utils = require("gh-review.utils")
local git = require("gh-review.git")

local M = {}

-- Internal state
local state = {
  buf = nil,
  win = nil,
  ns = vim.api.nvim_create_namespace("gh_review"),
  prs = {},
  card_lines = {}, -- maps line number -> PR index (1-based)
  loading = false,
  detail_win = nil,
  detail_buf = nil,
}

--- Close any open detail popup.
local function close_detail()
  if state.detail_win and vim.api.nvim_win_is_valid(state.detail_win) then
    vim.api.nvim_win_close(state.detail_win, true)
  end
  state.detail_win = nil
  state.detail_buf = nil
end

--- Close the main PR list window.
function M.close()
  close_detail()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.prs = {}
  state.card_lines = {}
end

--- Get the PR index for the current cursor line.
---@return number|nil PR index (1-based)
local function get_pr_at_cursor()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(state.win)
  local line = cursor[1] -- 1-based
  return state.card_lines[line]
end

--- Build the card lines for a single PR.
--- Returns an array of { text: string, highlights: { {group, col_start, col_end} } }
---@param pr table PR data object
---@param card_width number Available width for the card content
---@return table[] lines
local function build_card_lines(pr, card_width)
  local lines = {}
  local inner_width = card_width - 4

  -- Top border
  table.insert(lines, {
    text = "╭" .. string.rep("─", inner_width + 2) .. "╮",
    highlights = { { "GhReviewSeparator", 0, card_width } },
  })

  -- Line 1: Title + PR number
  local number_str = string.format("#%d", pr.number)
  local title_max = inner_width - #number_str - 3 -- space for gap
  local title = utils.truncate(pr.title, title_max)
  local title_padded = utils.pad_right(title, title_max)
  local line1 = "│ " .. title_padded .. "  " .. number_str .. " │"
  line1 = utils.pad_right(line1, card_width)

  local title_hl = pr.draft and "GhReviewCardTitleDraft" or "GhReviewCardTitle"
  table.insert(lines, {
    text = line1,
    highlights = {
      { title_hl, 2, 2 + #title },
      { "GhReviewCardNumber", 2 + title_max + 2, 2 + title_max + 2 + #number_str },
    },
  })

  -- Line 2: repo | author | updated
  local repo_str = pr.repo_name or ""
  local author_str = pr.author or ""
  local time_str = utils.relative_time(pr.updated_at)
  local repo_display = "repo:" .. utils.truncate(repo_str, 18)
  local author_display = "author:" .. utils.truncate(author_str, 13)
  local time_display = "updated:" .. time_str

  local meta_line = repo_display .. "  " .. author_display .. "  " .. time_display
  meta_line = "│ " .. utils.pad_right(meta_line, inner_width) .. " │"
  meta_line = utils.pad_right(meta_line, card_width)

  local col = 2
  table.insert(lines, {
    text = meta_line,
    highlights = {
      { "GhReviewCardRepo", col, col + #repo_display },
      { "GhReviewCardAuthor", col + #repo_display + 2, col + #repo_display + 2 + #author_display },
      { "GhReviewCardTime", col + #repo_display + 2 + #author_display + 2, col + #repo_display + 2 + #author_display + 2 + #time_display },
    },
  })

  -- Line 3: Approval badge | CI badge | Draft badge
  local approval_str = utils.approval_badge(pr.approval_status)
  local ci_str = utils.ci_badge(pr.pipeline_status)
  local draft_str = pr.draft and "  Draft" or ""

  local badges_line = approval_str .. "  " .. ci_str
  if draft_str ~= "" then
    badges_line = badges_line .. "  " .. draft_str
  end
  badges_line = "│ " .. utils.pad_right(badges_line, inner_width) .. " │"
  badges_line = utils.pad_right(badges_line, card_width)

  local badge_col = 2
  local approval_hl = colors.approval_hl(pr.approval_status and pr.approval_status.status or "pending")
  local ci_hl = colors.ci_hl(pr.pipeline_status and pr.pipeline_status.status or "none")

  local badge_highlights = {
    { approval_hl, badge_col, badge_col + #approval_str },
    { ci_hl, badge_col + #approval_str + 2, badge_col + #approval_str + 2 + #ci_str },
  }
  if draft_str ~= "" then
    table.insert(badge_highlights, {
      "GhReviewDraft",
      badge_col + #approval_str + 2 + #ci_str + 2,
      badge_col + #approval_str + 2 + #ci_str + 2 + #draft_str,
    })
  end

  table.insert(lines, {
    text = badges_line,
    highlights = badge_highlights,
  })

  -- Line 4: Stats (additions, deletions, commits, comments)
  local additions_str = string.format("+%d", pr.additions or 0)
  local deletions_str = string.format("-%d", pr.deletions or 0)
  local commits_str = string.format("commits:%d", pr.commits or 0)
  local comments_str = string.format("comments:%d", pr.comments or 0)

  local stats_line = string.format("%s  %s  %s  %s", additions_str, deletions_str, commits_str, comments_str)
  stats_line = "│ " .. utils.pad_right(stats_line, inner_width) .. " │"
  stats_line = utils.pad_right(stats_line, card_width)

  local stats_col = 2
  table.insert(lines, {
    text = stats_line,
    highlights = {
      { "GhReviewAdditions", stats_col, stats_col + #additions_str },
      { "GhReviewDeletions", stats_col + #additions_str + 2, stats_col + #additions_str + 2 + #deletions_str },
      { "GhReviewCardStats", stats_col + #additions_str + 2 + #deletions_str + 2, stats_col + #additions_str + 2 + #deletions_str + 2 + #commits_str },
      { "GhReviewCardStats", stats_col + #additions_str + 2 + #deletions_str + 2 + #commits_str + 2, stats_col + #additions_str + 2 + #deletions_str + 2 + #commits_str + 2 + #comments_str },
    },
  })

  -- Bottom border
  table.insert(lines, {
    text = "╰" .. string.rep("─", inner_width + 2) .. "╯",
    highlights = { { "GhReviewSeparator", 0, card_width } },
  })

  return lines
end

--- Render all PR cards into the buffer.
local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  vim.api.nvim_buf_set_option(state.buf, "modifiable", true)
  vim.api.nvim_buf_clear_namespace(state.buf, state.ns, 0, -1)

  local win_width = vim.api.nvim_win_get_width(state.win)
  local card_width = math.max(30, win_width - 2)

  local all_lines = {}
  local all_highlights = {} -- { line_idx, group, col_start, col_end }
  state.card_lines = {}

  -- Title line
  local title = " GH Review Queue "
  local count_str = string.format("[%d]", #state.prs)
  local title_line = utils.center(title .. count_str, card_width)
  table.insert(all_lines, title_line)
  table.insert(all_highlights, { #all_lines, "GhReviewTitle", 0, #title_line })

  -- Keybindings hint
  local keymaps = config.options.keymaps
  local hint = string.format(
    " %s review  %s refresh  %s browser  %s detail  %s/%s move  %s close ",
    keymaps.open_review,
    keymaps.refresh,
    keymaps.open_in_browser,
    keymaps.toggle_detail,
    keymaps.next_pr,
    keymaps.prev_pr,
    keymaps.close
  )
  local hint_line = utils.center(hint, card_width)
  table.insert(all_lines, hint_line)
  table.insert(all_highlights, { #all_lines, "GhReviewHeader", 0, #hint_line })

  -- Empty line
  table.insert(all_lines, "")

  if state.loading then
    local loading_line = utils.center("Fetching review requests from GitHub...", card_width)
    table.insert(all_lines, loading_line)
    table.insert(all_highlights, { #all_lines, "GhReviewLoading", 0, #loading_line })
  elseif #state.prs == 0 then
    local empty_line = utils.center("No pull requests match your filters", card_width)
    table.insert(all_lines, empty_line)
    table.insert(all_highlights, { #all_lines, "GhReviewEmpty", 0, #empty_line })
  else
    for i, pr in ipairs(state.prs) do
      local card_lines = build_card_lines(pr, card_width)
      for _, cl in ipairs(card_lines) do
        table.insert(all_lines, cl.text)
        local line_idx = #all_lines
        -- Map this line to the PR index
        state.card_lines[line_idx] = i
        for _, hl in ipairs(cl.highlights) do
          table.insert(all_highlights, { line_idx, hl[1], hl[2], hl[3] })
        end
      end
      -- Blank line between cards
      if i < #state.prs then
        table.insert(all_lines, "")
      end
    end
  end

  -- Set buffer lines
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, all_lines)

  -- Apply highlights
  for _, hl in ipairs(all_highlights) do
    local line_idx, group, col_start, col_end = hl[1], hl[2], hl[3], hl[4]
    pcall(vim.api.nvim_buf_add_highlight, state.buf, state.ns, group, line_idx - 1, col_start, col_end)
  end

  vim.api.nvim_buf_set_option(state.buf, "modifiable", false)
end

--- Open event detail popup for the PR under cursor.
local function open_detail_popup()
  local pr_idx = get_pr_at_cursor()
  if not pr_idx then
    return
  end

  -- Toggle: close if already open
  if state.detail_win and vim.api.nvim_win_is_valid(state.detail_win) then
    close_detail()
    return
  end

  local pr = state.prs[pr_idx]
  if not pr then
    return
  end

  -- Build detail content
  local detail_lines = {
    string.format("# %s", pr.title),
    "",
    string.format("**PR:** #%d", pr.number),
    string.format("**Repository:** %s", pr.repo_full_name),
    string.format("**Author:** %s", pr.author),
    string.format("**Branch:** %s -> %s", pr.head_ref or "unknown", pr.base_ref or "unknown"),
    string.format("**Created:** %s", utils.relative_time(pr.created_at)),
    string.format("**Updated:** %s", utils.relative_time(pr.updated_at)),
    "",
    string.format("**Changes:** +%d -%d across %d commits", pr.additions, pr.deletions, pr.commits),
    string.format("**Comments:** %d", pr.comments),
    "",
    string.format("**Approval:** %s", utils.approval_badge(pr.approval_status)),
    string.format("**CI:** %s", utils.ci_badge(pr.pipeline_status)),
  }

  if pr.draft then
    table.insert(detail_lines, "**Status:** Draft")
  end

  if pr.labels and #pr.labels > 0 then
    table.insert(detail_lines, "")
    local label_names = {}
    for _, label in ipairs(pr.labels) do
      table.insert(label_names, label.name)
    end
    table.insert(detail_lines, "**Labels:** " .. table.concat(label_names, ", "))
  end

  table.insert(detail_lines, "")
  table.insert(detail_lines, string.format("**URL:** %s", pr.html_url))

  -- Reviewers
  if pr.reviews and #pr.reviews > 0 then
    table.insert(detail_lines, "")
    table.insert(detail_lines, "**Reviews:**")
    local seen = {}
    for i = #pr.reviews, 1, -1 do
      local review = pr.reviews[i]
      local login = review.user and review.user.login or "unknown"
      if not seen[login] then
        seen[login] = true
        local state_icon = ({
          APPROVED = "",
          CHANGES_REQUESTED = "",
          COMMENTED = "",
          DISMISSED = "",
        })[review.state] or "?"
        table.insert(detail_lines, string.format("  %s %s (%s)", state_icon, login, review.state:lower()))
      end
    end
  end

  -- Create popup buffer
  state.detail_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(state.detail_buf, 0, -1, false, detail_lines)
  vim.api.nvim_buf_set_option(state.detail_buf, "modifiable", false)
  vim.api.nvim_buf_set_option(state.detail_buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(state.detail_buf, "filetype", "markdown")

  -- Calculate popup size
  local max_line = 0
  for _, line in ipairs(detail_lines) do
    max_line = math.max(max_line, #line)
  end
  local popup_width = math.min(max_line + 4, math.floor(vim.o.columns * 0.6))
  local popup_height = math.min(#detail_lines, math.floor(vim.o.lines * 0.6))

  -- Position relative to cursor in the parent window
  state.detail_win = vim.api.nvim_open_win(state.detail_buf, true, {
    relative = "cursor",
    row = 1,
    col = 2,
    width = popup_width,
    height = popup_height,
    style = "minimal",
    border = "rounded",
    title = string.format(" PR #%d ", pr.number),
    title_pos = "center",
  })

  vim.api.nvim_win_set_option(state.detail_win, "conceallevel", 2)
  vim.api.nvim_win_set_option(state.detail_win, "concealcursor", "nvic")
  vim.api.nvim_win_set_option(state.detail_win, "wrap", true)

  -- Keymaps for the popup
  local popup_buf = state.detail_buf
  local close_opts = { buffer = popup_buf, nowait = true, silent = true }
  vim.keymap.set("n", "q", close_detail, close_opts)
  vim.keymap.set("n", "<Esc>", close_detail, close_opts)
  vim.keymap.set("n", "K", close_detail, close_opts)
  vim.keymap.set("n", "<CR>", function()
    if pr.html_url then
      vim.ui.open(pr.html_url)
    end
  end, close_opts)
end

--- Open the PR for review: switch branch and open diffview.
local function open_review()
  local pr_idx = get_pr_at_cursor()
  if not pr_idx then
    vim.notify("gh-review: No PR selected", vim.log.levels.WARN)
    return
  end

  local pr = state.prs[pr_idx]
  if not pr then
    return
  end

  local branch = pr.head_ref
  if not branch then
    vim.notify("gh-review: PR has no branch information", vim.log.levels.ERROR)
    return
  end

  -- Close the PR list window first
  M.close()

  vim.notify(string.format("gh-review: Switching to branch '%s'...", branch), vim.log.levels.INFO)

  -- Switch to the branch (this is blocking, but fast for local operations)
  local ok, err = git.switch_to_branch(branch, pr)
  if not ok then
    vim.notify("gh-review: " .. (err or "Failed to switch branch"), vim.log.levels.ERROR)
    return
  end

  -- Reload all buffers to reflect the new branch
  vim.cmd("checktime")

  -- Open diffview against the base branch
  local base_ref = pr.base_ref or "main"
  local merge_base = git.get_merge_base(branch, base_ref)

  vim.schedule(function()
    if merge_base then
      -- Show only the changes from the PR (from merge-base to HEAD)
      vim.cmd(string.format("DiffviewOpen %s...HEAD", merge_base))
    else
      -- Fallback: diff against the base branch
      vim.cmd(string.format("DiffviewOpen origin/%s...HEAD", base_ref))
    end
    vim.notify(
      string.format("gh-review: Reviewing PR #%d - %s", pr.number, pr.title),
      vim.log.levels.INFO
    )
  end)
end

--- Open the PR URL in the browser.
local function open_in_browser()
  local pr_idx = get_pr_at_cursor()
  if not pr_idx then
    return
  end
  local pr = state.prs[pr_idx]
  if pr and pr.html_url then
    vim.ui.open(pr.html_url)
  end
end

--- Move cursor to the next PR card.
local function move_to_next_pr()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return
  end
  local current = vim.api.nvim_win_get_cursor(state.win)[1]
  local last = vim.api.nvim_buf_line_count(state.buf)
  for line = current + 1, last do
    if state.card_lines[line] then
      vim.api.nvim_win_set_cursor(state.win, { line, 0 })
      return
    end
  end
end

--- Move cursor to the previous PR card.
local function move_to_prev_pr()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return
  end
  local current = vim.api.nvim_win_get_cursor(state.win)[1]
  for line = current - 1, 1, -1 do
    if state.card_lines[line] then
      vim.api.nvim_win_set_cursor(state.win, { line, 0 })
      return
    end
  end
end

--- Set up keymaps for the PR list buffer.
local function setup_keymaps()
  local keymaps = config.options.keymaps
  local opts = { buffer = state.buf, nowait = true, silent = true }

  vim.keymap.set("n", keymaps.close, M.close, opts)
  vim.keymap.set("n", keymaps.open_review, open_review, opts)
  vim.keymap.set("n", keymaps.refresh, M.refresh, opts)
  vim.keymap.set("n", keymaps.open_in_browser, open_in_browser, opts)
  vim.keymap.set("n", keymaps.toggle_detail, open_detail_popup, opts)
  vim.keymap.set("n", keymaps.next_pr, move_to_next_pr, opts)
  vim.keymap.set("n", keymaps.prev_pr, move_to_prev_pr, opts)
end

--- Fetch PRs and re-render.
function M.refresh()
  if state.loading then
    return
  end

  state.loading = true
  render()

  -- Run the API call in a scheduled callback
  vim.schedule(function()
    local api = require("gh-review.api")
    local ok, prs_or_err, api_err = pcall(api.fetch_review_requests)

    vim.schedule(function()
      state.loading = false

      if not ok then
        -- pcall caught a Lua error (e.g., missing token)
        vim.notify("gh-review: " .. tostring(prs_or_err), vim.log.levels.ERROR)
        state.prs = {}
      elseif api_err then
        -- API returned an error string
        vim.notify("gh-review: " .. api_err, vim.log.levels.ERROR)
        state.prs = {}
      else
        state.prs = prs_or_err or {}
      end

      render()

      -- Place cursor on the first PR card if there are any
      if #state.prs > 0 then
        -- Find the first line that maps to a PR
        for line = 1, vim.api.nvim_buf_line_count(state.buf) do
          if state.card_lines[line] then
            pcall(vim.api.nvim_win_set_cursor, state.win, { line, 0 })
            break
          end
        end
      end
    end)
  end)
end

--- Open the PR review list window.
function M.open()
  -- Close any existing window
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
    return
  end

  -- Set up highlight groups
  colors.setup()

  -- Create scratch buffer
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(state.buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(state.buf, "filetype", "gh-review")
  vim.api.nvim_buf_set_option(state.buf, "swapfile", false)

  -- Calculate window dimensions
  local view = config.options.view
  local width = math.floor(vim.o.columns * view.width)
  local height = math.floor(vim.o.lines * view.height)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  -- Open floating window
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = view.border,
    title = " PR Reviews ",
    title_pos = "center",
  })

  vim.api.nvim_win_set_option(state.win, "cursorline", true)
  vim.api.nvim_win_set_option(state.win, "wrap", false)
  vim.api.nvim_win_set_option(state.win, "winhighlight", "Normal:GhReviewNormal,FloatBorder:GhReviewBorder,CursorLine:GhReviewCursorLine")

  -- Set up keymaps
  setup_keymaps()

  -- Auto-close on buffer wipe
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = state.buf,
    once = true,
    callback = function()
      state.win = nil
      state.buf = nil
      state.prs = {}
      state.card_lines = {}
      close_detail()
    end,
  })

  -- Fetch and render
  M.refresh()
end

return M
