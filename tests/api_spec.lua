local function assert_true(value, message)
  if not value then
    error(message or "expected true", 2)
  end
end

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(message or string.format("expected %s, got %s", tostring(expected), tostring(actual)), 2)
  end
end

local function assert_match(str, pattern, message)
  if type(str) ~= "string" or not str:match(pattern) then
    error(message or string.format("expected '%s' to match '%s'", tostring(str), pattern), 2)
  end
end

local function deep_extend(_, dst, src)
  local out = {}
  for k, v in pairs(dst or {}) do
    out[k] = v
  end
  for k, v in pairs(src or {}) do
    if type(v) == "table" and type(out[k]) == "table" then
      out[k] = deep_extend("force", out[k], v)
    else
      out[k] = v
    end
  end
  return out
end

local function run()
  _G.vim = {
    uri_encode = function(s)
      return (s:gsub(" ", "%%20"))
    end,
    tbl_deep_extend = deep_extend,
    json = {
      decode = function(body)
        return body
      end,
    },
  }

  local function setup_mocks(opts)
    local filter_calls = {}
    opts = opts or {}

    package.loaded["gh-review.api"] = nil
    package.loaded["gh-review.config"] = {
      options = {
        max_results = 50,
        cache_ttl_minutes = 0,
        filters = {
          teams = opts.configured_teams or { "acme/backend" },
        },
      },
      get_token = function()
        return "token"
      end,
    }
    package.loaded["gh-review.cache"] = {
      get = function()
        return nil
      end,
      set = function() end,
      invalidate = function() end,
    }
    package.loaded["gh-review.filters"] = {
      resolve = function(options)
        return {
          repositories = options.filters.repositories or {},
          teams = options.filters.teams or {},
          status = {},
          ci_status = {},
          max_age_days = nil,
        }
      end,
      matches = function(_, configured)
        table.insert(filter_calls, configured)
        return true
      end,
    }
    package.loaded["plenary.curl"] = {
      get = function(url)
        if url:find("/user$") or url:find("/user%?") then
          return { status = 200, body = { login = "alice" } }
        end
        if url:find("/user/teams%?") then
          if opts.team_api_error then
            return { status = 403, body = {} }
          end
          return {
            status = 200,
            body = {
              {
                slug = "backend",
                organization = { login = "acme" },
              },
            },
          }
        end
        if url:find("/search/issues%?") then
          return {
            status = 200,
            body = {
              items = {
                {
                  number = 7,
                  title = "Fix auth",
                  html_url = "https://github.com/acme/repo/pull/7",
                  created_at = "2026-02-20T00:00:00Z",
                  updated_at = "2026-02-21T00:00:00Z",
                  repository_url = "https://api.github.com/repos/acme/repo",
                  user = { login = "alice" },
                  comments = 2,
                  labels = {},
                },
              },
            },
          }
        end
        if url:find("/repos/acme/repo/pulls/7$") then
          return {
            status = 200,
            body = {
              head = {
                sha = "abc123",
                ref = "feature",
                repo = { full_name = "acme/repo" },
              },
              base = { ref = "main" },
              additions = 10,
              deletions = 3,
              commits = 1,
              review_comments = 1,
              requested_teams = {},
              draft = false,
            },
          }
        end
        if url:find("/repos/acme/repo/pulls/7/reviews$") then
          return {
            status = 200,
            body = {
              {
                user = { login = "bob" },
                state = "COMMENTED",
                submitted_at = "2026-02-21T00:00:00Z",
              },
            },
          }
        end
        if url:find("/repos/acme/repo/commits/abc123/check%-runs$") then
          return {
            status = 200,
            body = {
              check_runs = {
                { status = "completed", conclusion = "success" },
              },
            },
          }
        end

        return { status = 404, body = {} }
      end,
    }

    return filter_calls
  end

  local filter_calls = setup_mocks()
  local api = require("gh-review.api")

  local review_prs, review_err, review_diag = api.fetch_review_requests({ force = true })
  assert_eq(review_err, nil, "review fetch should not error")
  assert_true(type(review_prs) == "table", "review fetch should return a table")
  assert_eq(review_diag.mode, "review", "review diagnostics should identify mode")
  assert_true(#review_diag.query_results >= 1, "review diagnostics should include query results")

  local saw_team_query = false
  for _, query_result in ipairs(review_diag.query_results) do
    if type(query_result.query) == "string" and query_result.query:find("team%-review%-requested:") then
      saw_team_query = true
      break
    end
  end
  assert_true(saw_team_query, "review diagnostics should include a team query")

  local authored_prs, authored_err, authored_diag = api.fetch_authored_prs({ force = true })
  assert_eq(authored_err, nil, "authored fetch should not error")
  assert_true(type(authored_prs) == "table", "authored fetch should return a table")
  assert_eq(authored_diag.mode, "authored", "authored diagnostics should identify mode")
  assert_eq(#authored_diag.query_results, 1, "authored diagnostics should include exactly one query")
  assert_match(authored_diag.query_results[1].query, "author:alice", "authored query should target current user")

  assert_true(#filter_calls > 0, "filters should be invoked")

  -- Re-load API with team discovery failure to validate warning propagation.
  setup_mocks({ team_api_error = true, configured_teams = {} })
  api = require("gh-review.api")
  local _, warn_err, warn_diag = api.fetch_review_requests({ force = true })
  assert_eq(warn_err, nil, "review fetch should continue when team discovery fails")
  assert_true(type(warn_diag.warnings) == "table", "warnings should be present in diagnostics")
  assert_true(#warn_diag.warnings > 0, "team discovery failure should emit at least one warning")

  local warning_found = false
  for _, warning in ipairs(warn_diag.warnings) do
    if warning:find("/user/teams") then
      warning_found = true
      break
    end
  end
  assert_true(warning_found, "warning should mention /user/teams failure")

  -- Configured teams should be used as-is (normalized when possible) without /user/teams discovery.
  setup_mocks({ configured_teams = { "acme/acme/backend" } })
  api = require("gh-review.api")
  local _, normalized_err, normalized_diag = api.fetch_review_requests({ force = true })
  assert_eq(normalized_err, nil, "review fetch should not error with normalizable team filter")
  assert_eq(normalized_diag.team_discovery.skipped, true, "team discovery should be skipped when teams are configured")

  local normalized_query_found = false
  local invalid_query_found = false
  for _, result in ipairs(normalized_diag.query_results or {}) do
    if type(result.query) == "string" and result.query:find("team%-review%-requested:acme/backend") then
      normalized_query_found = true
    end
    if type(result.query) == "string" and result.query:find("team%-review%-requested:acme/acme/backend") then
      invalid_query_found = true
    end
  end
  assert_true(normalized_query_found, "normalized team query should be used")
  assert_true(not invalid_query_found, "invalid duplicated-org query should not be used")

  package.loaded["gh-review.api"] = nil
  package.loaded["gh-review.config"] = nil
  package.loaded["gh-review.cache"] = nil
  package.loaded["gh-review.filters"] = nil
  package.loaded["plenary.curl"] = nil
end

return {
  run = run,
}
