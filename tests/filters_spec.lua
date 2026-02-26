local filters = require("gh-review.filters")

local function iso_utc_from_epoch(epoch)
  return os.date("!%Y-%m-%dT%H:%M:%SZ", epoch)
end

local function now_iso_minus_days(days)
  local now = os.time(os.date("!*t"))
  return iso_utc_from_epoch(now - (days * 86400))
end

local function assert_true(value, message)
  if not value then
    error(message or "expected true", 2)
  end
end

local function assert_false(value, message)
  if value then
    error(message or "expected false", 2)
  end
end

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(message or string.format("expected %s, got %s", tostring(expected), tostring(actual)), 2)
  end
end

local function run()
  do
    local resolved = filters.resolve({ repos = { "owner/repo-a" } })
    assert_eq(#resolved.repositories, 1, "resolve should fallback to top-level repos")
    assert_eq(resolved.repositories[1], "owner/repo-a")
  end

  do
    local resolved = filters.resolve({
      repos = { "owner/repo-a" },
      filters = { repositories = { "owner/repo-b" } },
    })
    assert_eq(#resolved.repositories, 1, "explicit filters.repositories should win")
    assert_eq(resolved.repositories[1], "owner/repo-b")
  end

  local pr = {
    repo_full_name = "acme/platform",
    requested_teams = {
      { slug = "backend", organization = { login = "acme" } },
    },
    draft = false,
    approval_status = { status = "pending" },
    pipeline_status = { status = "success" },
    created_at = now_iso_minus_days(2),
  }

  assert_true(filters.matches(pr, { repositories = { "acme/platform" } }), "repo filter should match")
  assert_false(filters.matches(pr, { repositories = { "acme/other" } }), "repo filter should reject")

  assert_true(filters.matches(pr, { teams = { "backend" } }), "team slug should match")
  assert_true(filters.matches(pr, { teams = { "acme/backend" } }), "org/slug should match")
  assert_false(filters.matches(pr, { teams = { "frontend" } }), "non-matching team should reject")

  assert_true(filters.matches(pr, { status = { "pending" } }), "status should match")
  assert_false(filters.matches(pr, { status = { "approved" } }), "status should reject")

  assert_true(filters.matches(pr, { ci_status = { "success" } }), "ci status should match")
  assert_false(filters.matches(pr, { ci_status = { "failure" } }), "ci status should reject")

  assert_true(filters.matches(pr, { max_age_days = 3 }), "age filter should include fresh PR")
  assert_false(filters.matches(pr, { max_age_days = 1 }), "age filter should exclude old PR")

  local draft_pr = {
    repo_full_name = pr.repo_full_name,
    requested_teams = pr.requested_teams,
    draft = true,
    approval_status = { status = "approved" },
    pipeline_status = pr.pipeline_status,
    created_at = pr.created_at,
  }
  assert_true(filters.matches(draft_pr, { status = { "draft" } }), "draft status should be filterable")
  assert_false(filters.matches(draft_pr, { status = { "approved" } }), "draft should not match approved")
end

return {
  run = run,
}
