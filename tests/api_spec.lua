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
  local filter_calls = {}

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

  package.loaded["gh-review.api"] = nil
  package.loaded["gh-review.config"] = {
    options = {
      max_results = 50,
      cache_ttl_minutes = 0,
      filters = {
        teams = { "acme/backend" },
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

  local api = require("gh-review.api")

  local review_prs, review_err = api.fetch_review_requests({ force = true })
  assert_eq(review_err, nil, "review fetch should not error")
  assert_true(type(review_prs) == "table", "review fetch should return a table")

  local authored_prs, authored_err = api.fetch_authored_prs({ force = true })
  assert_eq(authored_err, nil, "authored fetch should not error")
  assert_true(type(authored_prs) == "table", "authored fetch should return a table")

  assert_true(#filter_calls > 0, "filters should be invoked")

  package.loaded["gh-review.api"] = nil
  package.loaded["gh-review.config"] = nil
  package.loaded["gh-review.cache"] = nil
  package.loaded["gh-review.filters"] = nil
  package.loaded["plenary.curl"] = nil
end

return {
  run = run,
}
