if vim.g.loaded_gh_review then
  return
end
vim.g.loaded_gh_review = true

local function ensure_config()
  local config = require("gh-review.config")
  if not config.options or vim.tbl_isempty(config.options) then
    config.setup({})
  end
end

vim.api.nvim_create_user_command("GhReviewOpen", function()
  ensure_config()
  require("gh-review.ui").open()
end, { desc = "Open the PR review list" })

vim.api.nvim_create_user_command("GhReviewRefresh", function()
  ensure_config()
  require("gh-review.ui").refresh()
end, { desc = "Refresh the PR review list" })

vim.api.nvim_create_user_command("GhReviewClose", function()
  require("gh-review.ui").close()
end, { desc = "Close the PR review list" })
