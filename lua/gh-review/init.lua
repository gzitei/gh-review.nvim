local config = require("gh-review.config")

local M = {}

--- Set up the plugin: merge config, register commands.
---@param opts table|nil User configuration overrides
function M.setup(opts)
  config.setup(opts)

  -- Register user commands
  vim.api.nvim_create_user_command("GhReviewOpen", function()
    require("gh-review.ui").open()
  end, { desc = "Open the PR review list" })

  vim.api.nvim_create_user_command("GhReviewRefresh", function()
    require("gh-review.ui").refresh()
  end, { desc = "Refresh the PR review list" })

  vim.api.nvim_create_user_command("GhReviewClose", function()
    require("gh-review.ui").close()
  end, { desc = "Close the PR review list" })
end

return M
