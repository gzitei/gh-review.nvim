local config = require("gh-review.config")

local M = {}

--- Set up the plugin: merge config, register commands.
---@param opts table|nil User configuration overrides
function M.setup(opts)
  config.setup(opts)
end

return M
