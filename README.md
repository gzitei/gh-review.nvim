# gh-review.nvim

A Neovim plugin that displays GitHub pull requests awaiting your review as visual cards in a floating window. Select a PR to automatically switch to its branch and open [diffview.nvim](https://github.com/sindrets/diffview.nvim) for a full code review.

## Requirements

- Neovim >= 0.9
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (for HTTP requests)
- [diffview.nvim](https://github.com/sindrets/diffview.nvim) (for the diff review UI)
- A GitHub Personal Access Token with `repo` scope
- `git` CLI available on PATH

## Installation

### lazy.nvim

```lua
{
  "gzitei/gh-review.nvim",
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

## Configuration

```lua
require("gh-review").setup({
  -- GitHub personal access token
  -- Falls back to GITHUB_TOKEN env var, or `gh auth token` if GitHub CLI is installed
  github_token = "",

  -- Filter to specific repos (empty = all repos where review is requested)
  repos = {},

  -- Monitor review requests for specific teams (e.g., { "my-org/backend-team" })
  teams = {},

  -- Maximum number of PRs to fetch
  max_results = 50,

  -- Auto-fetch remote before switching branches
  auto_fetch = true,

  -- Auto-stash uncommitted changes before switching branches
  auto_stash = true,

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
    next_pr = "j",
    prev_pr = "k",
  },
})
```

## Commands

| Command | Description |
|---|---|
| `:GhReviewOpen` | Open/toggle the PR review list |
| `:GhReviewRefresh` | Refresh the PR list |
| `:GhReviewClose` | Close the PR review list |

## Usage

1. Set your GitHub token via `GITHUB_TOKEN` env var or in the `setup()` call
2. Run `:GhReviewOpen` (or your keymap) to see all PRs awaiting your review
3. Navigate with `j`/`k`, press `K` to see PR details
4. Press `<CR>` on a PR to:
   - Auto-stash any uncommitted changes
   - Fetch and switch to the PR branch
   - Open `diffview.nvim` showing only the PR's changes (merge-base diff)
5. Press `o` to open the PR in your browser
6. Press `q` to close the list

## PR Card Layout

Each PR is displayed as a card showing:

```
──────────────────────────────────────────
  Fix authentication timeout issue  #142
   my-repo   johndoe   2h ago
   Approved (2)   CI Passing (8/8)
  +45  -12   3   5
──────────────────────────────────────────
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

1. Uses the GitHub Search API to find open PRs where `review-requested:YOUR_USERNAME`
2. Enriches each PR with details, reviews, and check run data
3. Filters out PRs you've already approved
4. When you select a PR for review:
   - Stashes uncommitted changes (configurable)
   - Fetches the remote branch
   - Checks out the PR branch locally
   - Computes the merge-base with the target branch
   - Opens `diffview.nvim` with a `merge-base...HEAD` diff

## License

MIT
