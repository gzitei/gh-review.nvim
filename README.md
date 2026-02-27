# gh-review.nvim

A Neovim plugin that displays GitHub pull requests awaiting your review as visual cards in a floating window. Select a PR to automatically switch to its branch and open [diffview.nvim](https://github.com/sindrets/diffview.nvim) for a full code review.

## Requirements

- Neovim >= 0.9
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (for HTTP requests)
- [diffview.nvim](https://github.com/sindrets/diffview.nvim) (for the diff review UI)
- A GitHub token with repository access and org/team read access
  - Classic PAT: `repo` + `read:org`
  - Fine-grained PAT: repository read + organization members/teams read
- `git` CLI available on PATH

## Installation

### lazy.nvim

```lua
{
  "gzitei/gh-review.nvim",
  cmd = { "GhReviewOpen", "GhReviewRefresh", "GhReviewClose", "GhReviewDebug" },
  dependencies = {
    "nvim-lua/plenary.nvim",
    "sindrets/diffview.nvim",
  },
  config = function()
    require("gh-review").setup()
  end,
  keys = {
    { "<leader>pr", "<cmd>GhReviewOpen<cr>", desc = "Open PR Review List" },
  },
}
```

`GhReviewOpen`, `GhReviewRefresh`, `GhReviewClose`, and `GhReviewDebug` are defined automatically when the plugin loads.
Calling `setup()` is still recommended so you can configure token, filters, and keymaps.

## Configuration

```lua
require("gh-review").setup({
  -- GitHub personal access token
  -- Falls back to GITHUB_TOKEN env var, or `gh auth token` if GitHub CLI is installed
  github_token = "",

  -- Filter to specific repos (empty = all repos where review is requested)
  -- Backward-compatible alias for filters.repositories
  repos = {},

  -- Backward-compatible alias for filters.teams
  teams = {},

  -- Optional PR list filters
  filters = {
    -- Restrict to these repositories (full name: owner/repo)
    repositories = {},

    -- Restrict to PRs requested from these teams (slug or owner/slug)
    teams = {},

    -- Restrict by review status:
    -- pending | commented | approved | changes_requested | draft
    status = {},

    -- Restrict by CI status:
    -- success | failure | pending | none
    ci_status = {},

    -- Restrict to PRs created within the last N days (nil disables)
    max_age_days = nil,
  },

  -- Maximum number of PRs to fetch
  max_results = 50,

  -- Auto-fetch remote before switching branches
  auto_fetch = true,

  -- Auto-stash uncommitted changes before switching branches
  auto_stash = true,

  -- Cache PR list for this many minutes (0 disables cache)
  cache_ttl_minutes = 5,

  -- Debug options
  debug = {
    -- Show query/result diagnostics in :messages
    show_queries = false,
  },

  -- Floating window appearance
  view = {
    width = 0.7,    -- fraction of editor width
    height = 0.8,   -- fraction of editor height
    border = "rounded",
  },

  -- Keymaps inside the PR list window
  keymaps = {
    close = "q",
    open_review = "<CR>",    -- switch branch + open diffview
    refresh = "r",
    open_in_browser = "o",
    toggle_detail = "K",
    next_pr = "n",
    prev_pr = "N",
    next_view = "<Right>",   -- toggle between review queue and authored PRs
    prev_view = "<Left>",
  },
})
```

## Commands

| Command | Description |
|---|---|
| `:GhReviewOpen` | Open/toggle the PR review list |
| `:GhReviewRefresh` | Refresh the PR list (bypasses cache) |
| `:GhReviewClose` | Close the PR review list |
| `:GhReviewDebug` | Force fetch and print query/result diagnostics |

## Usage

1. Set your GitHub token via `GITHUB_TOKEN` env var or in the `setup()` call
2. Run `:GhReviewOpen` (or your keymap) to see all PRs awaiting your review
3. Navigate with `n`/`N`, press `K` to see PR details
4. Press `<Left>` or `<Right>` to switch between review requests and your authored open PRs
5. Press `<CR>` on a PR to:
   - Auto-stash any uncommitted changes
   - Fetch and switch to the PR branch
   - Open `diffview.nvim` showing only the PR's changes (merge-base diff)
6. Press `o` to open the PR in your browser
7. Press `q` to close the list

`r` and `:GhReviewRefresh` always bypass cache and fetch fresh data.

When `debug.show_queries = true`, each refresh also prints query diagnostics in `:messages`.

## PR Card Layout

Each PR is displayed as a card showing:

```
╭────────────────────────────────────────╮
│ Fix authentication timeout issue  #142 │
│ repo:my-repo  author:johndoe  updated:2h ago │
│ Review: Approved (2)  CI: Passing (8/8) │
│ changes:+45 -12  commits:3  comments:5 │
╰────────────────────────────────────────╯
```

- **Title** and PR number
- Repository name, author, and last update time
- Approval status and CI status badges
- Lines added/removed, commit count, comment count

Cards are color-coded by approval and CI status:
- Green: approved / CI passing
- Red: changes requested / CI failing
- Yellow: pending review / CI running / draft
- Blue: commented

## How It Works

1. Uses the GitHub Search API to find open PRs where `review-requested:YOUR_USERNAME`, `team-review-requested:ORG/TEAM`, or `author:YOUR_USERNAME` (authored view)
2. Enriches each PR with details, reviews, and check run data
3. Filters out PRs you've already approved
4. Applies configured filters (repository, team, review status, age, CI status)
5. When you select a PR for review:
   - Stashes uncommitted changes (configurable)
   - Fetches the remote branch
   - Checks out the PR branch locally
   - Computes the merge-base with the target branch
   - Opens `diffview.nvim` with a `merge-base...HEAD` diff

## Troubleshooting

### Team review requests do not show up

If PRs requested to your team are missing, check:

1. Your token scopes include org/team read access (`read:org` for classic PAT)
2. `:GhReviewRefresh` to bypass cache
3. You are in review queue view (`<Left>` / `<Right>`)
4. Active filters are not excluding the PR

Run `:GhReviewDebug` to see the exact queries and result counts used by the plugin.

## License

MIT

## Testing

Run the filter test suite with:

```sh
lua tests/run.lua
```
