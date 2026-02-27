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
  ns_selected = vim.api.nvim_create_namespace("gh_review_selected"),
  prs = {},
  view_mode = "review", -- "review" | "authored"
  card_lines = {}, -- maps line number -> PR index (1-based)
  card_title_lines = {}, -- maps PR index -> title line number
  card_ranges = {}, -- maps PR index -> { start_line, end_line }
  card_width = 0,
  loading = false,
  detail_win = nil,
  detail_buf = nil,
}

---@return boolean
local function show_query_debug()
  return config.options
    and config.options.debug
    and config.options.debug.show_queries == true
end

---@param diagnostics table|nil
---@param title string
---@return string[]
local function diagnostics_lines(diagnostics, title)
  if type(diagnostics) ~= "table" then
    return {}
  end

  local lines = {
    string.format("gh-review debug [%s]", title),
  }

  if diagnostics.from_cache then
    table.insert(lines, "source: cache")
  else
    table.insert(lines, "source: live")
  end

  local counts = diagnostics.counts or {}
  table.insert(
    lines,
    string.format(
      "counts: candidates=%d skipped_approved=%d returned=%d",
      counts.search_candidates or 0,
      counts.skipped_user_approved or 0,
      counts.returned or 0
    )
  )

  local query_results = diagnostics.query_results or {}
  if #query_results == 0 then
    table.insert(lines, "queries: none")
  else
    table.insert(lines, "queries:")
    for _, result in ipairs(query_results) do
      local status = result.status or "ok"
      local suffix = ""
      if result.error and result.error ~= "" then
        suffix = string.format(" err=%s", result.error)
      end
      table.insert(
        lines,
        string.format(
          "- [%s] returned=%d unique=%d | %s%s",
          status,
          result.returned or 0,
          result.unique_added or 0,
          result.query or "",
          suffix
        )
      )
    end
  end

  local team_discovery = diagnostics.team_discovery
  if type(team_discovery) == "table" then
    table.insert(
      lines,
      string.format(
        "teams: configured=%d discovered=%d",
        team_discovery.configured_count or 0,
        team_discovery.discovered_count or 0
      )
    )
    if team_discovery.error and team_discovery.error ~= "" then
      table.insert(lines, "teams_error: " .. team_discovery.error)
    end
  end

  return lines
end

---@param diagnostics table|nil
---@param title string
---@param force_debug boolean
local function notify_diagnostics(diagnostics, title, force_debug)
  if type(diagnostics) ~= "table" then
    return
  end

  for _, warning in ipairs(diagnostics.warnings or {}) do
    vim.notify("gh-review: " .. warning, vim.log.levels.WARN)
  end

  if force_debug or show_query_debug() then
    vim.notify(table.concat(diagnostics_lines(diagnostics, title), "\n"), vim.log.levels.INFO)
  end
end

local function card_border_chars()
  local border = config.options.view and config.options.view.border or "rounded"
  if border == "rounded" then
    return {
      top_left = "╭",
      top_right = "╮",
      bottom_left = "╰",
      bottom_right = "╯",
      horizontal = "─",
      vertical = "│",
    }
  end

  return {
    top_left = "+",
    top_right = "+",
    bottom_left = "+",
    bottom_right = "+",
    horizontal = "-",
    vertical = "|",
  }
end

---@return string
local function view_mode_label()
  if state.view_mode == "authored" then
    return "My Open PRs"
  end
  return "Review Queue"
end

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
  state.card_title_lines = {}
  state.card_ranges = {}
  state.card_width = 0
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
  local safe = utils.ascii_safe
  local border = card_border_chars()

  local line_prefix = border.vertical .. " "
  local line_suffix = " " .. border.vertical

  -- Top border
  table.insert(lines, {
    text = border.top_left .. string.rep(border.horizontal, inner_width + 2) .. border.top_right,
    highlights = { { "GhReviewSeparator", 0, -1 } },
  })

  -- Line 1: Title + PR number
  local number_str = string.format("#%d", pr.number)
  local title_max = inner_width - #number_str - 2
  local title = utils.truncate(safe(pr.title), title_max)
  local title_padded = utils.pad_right(title, title_max)
  local line1 = line_prefix .. title_padded .. "  " .. number_str .. line_suffix
  line1 = utils.pad_right(line1, card_width)

  local title_start = #line_prefix
  local number_start = #line_prefix + #title_padded + 2

  local title_hl = pr.draft and "GhReviewCardTitleDraft" or "GhReviewCardTitle"
  table.insert(lines, {
    text = line1,
    highlights = {
      { "GhReviewSeparator", 0, -1 },
      { title_hl, title_start, title_start + #title },
      { "GhReviewCardNumber", number_start, number_start + #number_str },
    },
  })

  -- Line 2: repo | author | updated
  local repo_str = safe(pr.repo_name or pr.repo_full_name or "")
  local author_str = safe(pr.author or "")
  local time_str = utils.relative_time(pr.updated_at)
  local repo_display = "repo:" .. utils.truncate(repo_str, 20)
  local author_display = "author:" .. utils.truncate(author_str, 14)
  local time_display = "updated:" .. time_str

  local meta_line = repo_display .. "  " .. author_display .. "  " .. time_display
  meta_line = line_prefix .. utils.pad_right(meta_line, inner_width) .. line_suffix
  meta_line = utils.pad_right(meta_line, card_width)

  local col = #line_prefix
  table.insert(lines, {
    text = meta_line,
    highlights = {
      { "GhReviewSeparator", 0, -1 },
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
  badges_line = line_prefix .. utils.pad_right(badges_line, inner_width) .. line_suffix
  badges_line = utils.pad_right(badges_line, card_width)

  local badge_col = #line_prefix
  local approval_hl = colors.approval_hl(pr.approval_status and pr.approval_status.status or "pending")
  local ci_hl = colors.ci_hl(pr.pipeline_status and pr.pipeline_status.status or "none")

  local badge_highlights = {
    { "GhReviewSeparator", 0, -1 },
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

  local stats_line = string.format("changes:%s %s  %s  %s", additions_str, deletions_str, commits_str, comments_str)
  stats_line = line_prefix .. utils.pad_right(stats_line, inner_width) .. line_suffix
  stats_line = utils.pad_right(stats_line, card_width)

  local stats_col = #line_prefix
  local changes_prefix = "changes:"
  local additions_start = stats_col + #changes_prefix
  local deletions_start = additions_start + #additions_str + 1
  local commits_start = deletions_start + #deletions_str + 2
  local comments_start = commits_start + #commits_str + 2
  table.insert(lines, {
    text = stats_line,
    highlights = {
      { "GhReviewSeparator", 0, -1 },
      { "GhReviewAdditions", additions_start, additions_start + #additions_str },
      { "GhReviewDeletions", deletions_start, deletions_start + #deletions_str },
      { "GhReviewCardStats", commits_start, commits_start + #commits_str },
      { "GhReviewCardStats", comments_start, comments_start + #comments_str },
    },
  })

  -- Bottom border
  table.insert(lines, {
    text = border.bottom_left .. string.rep(border.horizontal, inner_width + 2) .. border.bottom_right,
    highlights = { { "GhReviewSeparator", 0, -1 } },
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
  state.card_width = card_width

  local all_lines = {}
  local all_highlights = {} -- { line_idx, group, col_start, col_end }
  state.card_lines = {}
  state.card_title_lines = {}
  state.card_ranges = {}

  -- Title line
  local title = "GH " .. view_mode_label()
  local count_str = string.format("[%d]", #state.prs)
  local title_line = utils.pad_right(string.format(" %s %s", title, count_str), card_width)
  table.insert(all_lines, title_line)
  table.insert(all_highlights, { #all_lines, "GhReviewTitle", 0, #title_line })

  -- Keybindings hint
  local keymaps = config.options.keymaps
  local hint = string.format(
    " keys: %s review | %s refresh | %s browser | %s detail | %s/%s move | %s close",
    keymaps.open_review,
    keymaps.refresh,
    keymaps.open_in_browser,
    keymaps.toggle_detail,
    keymaps.next_pr,
    keymaps.prev_pr,
    keymaps.close
  )
  local view_hint = string.format(" view: %s/%s switch", keymaps.prev_view, keymaps.next_view)
  hint = hint .. view_hint
  local hint_line = utils.pad_right(hint, card_width)
  table.insert(all_lines, hint_line)
  table.insert(all_highlights, { #all_lines, "GhReviewHeader", 0, #hint_line })

  -- Empty line
  table.insert(all_lines, "")

  if state.loading then
    local loading_line = utils.center("Fetching review requests from GitHub...", card_width)
    table.insert(all_lines, loading_line)
    table.insert(all_highlights, { #all_lines, "GhReviewLoading", 0, #loading_line })
  elseif #state.prs == 0 then
    local empty_msg = state.view_mode == "authored"
        and "No authored pull requests match your filters"
      or "No pull requests match your filters"
    local empty_line = utils.center(empty_msg, card_width)
    table.insert(all_lines, empty_line)
    table.insert(all_highlights, { #all_lines, "GhReviewEmpty", 0, #empty_line })
  else
    for i, pr in ipairs(state.prs) do
      local card_lines = build_card_lines(pr, card_width)
      local card_start = #all_lines + 1
      for _, cl in ipairs(card_lines) do
        table.insert(all_lines, cl.text)
        local line_idx = #all_lines
        -- Map this line to the PR index
        state.card_lines[line_idx] = i
        for _, hl in ipairs(cl.highlights) do
          table.insert(all_highlights, { line_idx, hl[1], hl[2], hl[3] })
        end
      end
      state.card_ranges[i] = { start_line = card_start, end_line = #all_lines }
      state.card_title_lines[i] = card_start + 1
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

local highlight_selected_card_border

local function move_to_pr_index(pr_idx)
  local title_line = state.card_title_lines[pr_idx]
  if not title_line then
    return
  end
  pcall(vim.api.nvim_win_set_cursor, state.win, { title_line, 4 })
  highlight_selected_card_border()
end

--- Highlight the selected card border using the warn color.
highlight_selected_card_border = function()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  vim.api.nvim_buf_clear_namespace(state.buf, state.ns_selected, 0, -1)

  local pr_idx = get_pr_at_cursor()
  if not pr_idx then
    return
  end

  local pr = state.prs[pr_idx]
  if not pr then
    return
  end

  local card_range = state.card_ranges[pr_idx]
  if not card_range then
    return
  end

  local width = state.card_width
  if width <= 0 then
    return
  end

  local border = card_border_chars()

  local function find_last(haystack, needle)
    local last = nil
    local start = 1
    while true do
      local idx = haystack:find(needle, start, true)
      if not idx then
        return last
      end
      last = idx
      start = idx + 1
    end
  end

  local function add_selected_highlight(line0, group, col_start, col_end)
    if col_start < col_end then
      pcall(vim.api.nvim_buf_add_highlight, state.buf, state.ns_selected, group, line0, col_start, col_end)
    end
  end

  local function find_span(haystack, needle)
    local start_idx = haystack:find(needle, 1, true)
    if not start_idx then
      return nil, nil
    end
    local start_col = start_idx - 1
    return start_col, start_col + #needle
  end

  for line = card_range.start_line, card_range.end_line do
    local line0 = line - 1
    local line_text = vim.api.nvim_buf_get_lines(state.buf, line0, line0 + 1, false)[1] or ""
    local is_edge = (line == card_range.start_line) or (line == card_range.end_line)
    local line_offset = line - card_range.start_line
    if is_edge then
      pcall(vim.api.nvim_buf_add_highlight, state.buf, state.ns_selected, "GhReviewSelectedBorder", line0, 0, -1)
    else
      local first = line_text:find(border.vertical, 1, true)
      local last = find_last(line_text, border.vertical)
      if first then
        local first_col = first - 1
        local content_start = first_col + #border.vertical
        local content_end = #line_text
        if last then
          content_end = last - 1
        end

        if content_end > content_start then
          add_selected_highlight(line0, "GhReviewSelectedText", content_start, content_end)

          if line_offset == 3 then
            local approval_str = utils.approval_badge(pr.approval_status)
            local ci_str = utils.ci_badge(pr.pipeline_status)
            local approval_status = pr.approval_status and pr.approval_status.status or "pending"
            local ci_status = pr.pipeline_status and pr.pipeline_status.status or "none"

            local approval_start, approval_end = find_span(line_text, approval_str)
            if approval_start and approval_end then
              add_selected_highlight(line0, colors.selected_approval_hl(approval_status), approval_start, approval_end)
            end

            local ci_start, ci_end = find_span(line_text, ci_str)
            if ci_start and ci_end then
              add_selected_highlight(line0, colors.selected_ci_hl(ci_status), ci_start, ci_end)
            end
          elseif line_offset == 4 then
            local additions_str = string.format("+%d", pr.additions or 0)
            local deletions_str = string.format("-%d", pr.deletions or 0)

            local add_start, add_end = find_span(line_text, additions_str)
            if add_start and add_end then
              add_selected_highlight(line0, "GhReviewSelectedAdditions", add_start, add_end)
            end

            local del_start, del_end = find_span(line_text, deletions_str)
            if del_start and del_end then
              add_selected_highlight(line0, "GhReviewSelectedDeletions", del_start, del_end)
            end
          end
        end

        pcall(
          vim.api.nvim_buf_add_highlight,
          state.buf,
          state.ns_selected,
          "GhReviewSelectedBorder",
          line0,
          first_col,
          first_col + #border.vertical
        )
      end
      if last and last ~= first then
        pcall(
          vim.api.nvim_buf_add_highlight,
          state.buf,
          state.ns_selected,
          "GhReviewSelectedBorder",
          line0,
          last - 1,
          last - 1 + #border.vertical
        )
      end
    end

    if line == (state.card_title_lines[pr_idx] or -1) then
      local num_start, num_end = line_text:find("#%d+")
      if num_start and num_end then
        pcall(
          vim.api.nvim_buf_add_highlight,
          state.buf,
          state.ns_selected,
          "GhReviewSelectedNumber",
          line0,
          num_start - 1,
          num_end
        )
      end
    end
  end
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

  local safe = utils.ascii_safe

  -- Build detail content
  local detail_lines = {
    string.format("# %s", safe(pr.title)),
    "",
    string.format("**PR:** #%d", pr.number),
    string.format("**Repository:** %s", safe(pr.repo_full_name)),
    string.format("**Author:** %s", safe(pr.author)),
    string.format("**Branch:** %s -> %s", safe(pr.head_ref or "unknown"), safe(pr.base_ref or "unknown")),
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
      table.insert(label_names, safe(label.name))
    end
    table.insert(detail_lines, "**Labels:** " .. table.concat(label_names, ", "))
  end

  table.insert(detail_lines, "")
  table.insert(detail_lines, string.format("**URL:** %s", safe(pr.html_url)))

  -- Reviewers
  if pr.reviews and #pr.reviews > 0 then
    table.insert(detail_lines, "")
    table.insert(detail_lines, "**Reviews:**")
    local seen = {}
    for i = #pr.reviews, 1, -1 do
      local review = pr.reviews[i]
      local login = safe(review.user and review.user.login or "unknown")
      if not seen[login] then
        seen[login] = true
        local state_icon = ({
          APPROVED = " ",
          CHANGES_REQUESTED = " ",
          COMMENTED = " ",
          DISMISSED = "",
        })[review.state] or "?"
        local review_state = safe((review.state or "unknown"):lower())
        table.insert(detail_lines, string.format("  %s %s (%s)", state_icon, login, review_state))
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
  local current_idx = get_pr_at_cursor() or 0
  local next_idx = current_idx + 1
  if next_idx <= #state.prs then
    move_to_pr_index(next_idx)
  end
end

--- Move cursor to the previous PR card.
local function move_to_prev_pr()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return
  end
  local current_idx = get_pr_at_cursor() or 1
  local prev_idx = current_idx - 1
  if prev_idx >= 1 then
    move_to_pr_index(prev_idx)
  end
end

--- Toggle list mode between review requests and authored PRs.
---@param step number Positive for next view, negative for previous view
local function toggle_view(step)
  local modes = { "review", "authored" }
  local idx = 1
  for i, mode in ipairs(modes) do
    if mode == state.view_mode then
      idx = i
      break
    end
  end

  local new_idx = ((idx - 1 + step) % #modes) + 1
  local next_mode = modes[new_idx]
  if next_mode ~= state.view_mode then
    state.view_mode = next_mode
    close_detail()
    M.refresh(false)
  end
end

local function toggle_next_view()
  toggle_view(1)
end

local function toggle_prev_view()
  toggle_view(-1)
end

--- Set up keymaps for the PR list buffer.
local function setup_keymaps()
  local keymaps = config.options.keymaps
  local opts = { buffer = state.buf, nowait = true, silent = true }

  vim.keymap.set("n", keymaps.close, M.close, opts)
  vim.keymap.set("n", keymaps.open_review, open_review, opts)
  vim.keymap.set("n", keymaps.refresh, function()
    M.refresh(true)
  end, opts)
  vim.keymap.set("n", keymaps.open_in_browser, open_in_browser, opts)
  vim.keymap.set("n", keymaps.toggle_detail, open_detail_popup, opts)
  vim.keymap.set("n", keymaps.next_pr, move_to_next_pr, opts)
  vim.keymap.set("n", keymaps.prev_pr, move_to_prev_pr, opts)
  vim.keymap.set("n", keymaps.next_view, toggle_next_view, opts)
  vim.keymap.set("n", keymaps.prev_view, toggle_prev_view, opts)
  if keymaps.next_pr ~= "n" then
    vim.keymap.set("n", "n", move_to_next_pr, opts)
  end
  if keymaps.prev_pr ~= "N" then
    vim.keymap.set("n", "N", move_to_prev_pr, opts)
  end
  if keymaps.next_view ~= "<Right>" and keymaps.prev_view ~= "<Right>" then
    vim.keymap.set("n", "<Right>", toggle_next_view, opts)
  end
  if keymaps.prev_view ~= "<Left>" and keymaps.next_view ~= "<Left>" then
    vim.keymap.set("n", "<Left>", toggle_prev_view, opts)
  end
end

--- Fetch PRs and re-render.
---@param force? boolean Bypass cache when true
function M.refresh(force)
  if state.loading then
    return
  end

  state.loading = true
  render()

  -- Run the API call in a scheduled callback
  vim.schedule(function()
    local api = require("gh-review.api")
    local fetcher = state.view_mode == "authored" and api.fetch_authored_prs or api.fetch_review_requests
    local ok, prs_or_err, api_err, diagnostics = pcall(fetcher, { force = force == true })

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

      notify_diagnostics(diagnostics, state.view_mode, false)

      render()
      highlight_selected_card_border()

      -- Place cursor on the first PR card if there are any
      if #state.prs > 0 then
        -- Find the first line that maps to a PR
        for line = 1, vim.api.nvim_buf_line_count(state.buf) do
          if state.card_lines[line] then
            move_to_pr_index(state.card_lines[line])
            break
          end
        end
      end
    end)
  end)
end

--- Fetch and print query diagnostics for both views.
function M.debug_queries()
  local api = require("gh-review.api")

  local ok_review, review_result_or_error, review_err, review_diag = pcall(api.fetch_review_requests, { force = true })
  if not ok_review then
    vim.notify("gh-review: " .. tostring(review_result_or_error), vim.log.levels.ERROR)
  elseif review_err then
    vim.notify("gh-review: " .. review_err, vim.log.levels.ERROR)
  end
  notify_diagnostics(review_diag, "review", true)

  local ok_authored, authored_result_or_error, authored_err, authored_diag = pcall(api.fetch_authored_prs, { force = true })
  if not ok_authored then
    vim.notify("gh-review: " .. tostring(authored_result_or_error), vim.log.levels.ERROR)
  elseif authored_err then
    vim.notify("gh-review: " .. authored_err, vim.log.levels.ERROR)
  end
  notify_diagnostics(authored_diag, "authored", true)
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
  state.view_mode = "review"

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
      state.card_title_lines = {}
      state.card_ranges = {}
      state.card_width = 0
      close_detail()
    end,
  })

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = state.buf,
    callback = highlight_selected_card_border,
  })

  -- Fetch and render
  M.refresh()
end

return M
