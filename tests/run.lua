package.path = table.concat({
  "./?.lua",
  "./?/init.lua",
  "./lua/?.lua",
  "./lua/?/init.lua",
  package.path,
}, ";")

local suites = {
  dofile("tests/filters_spec.lua"),
  dofile("tests/api_spec.lua"),
}

local passed = 0
for _, suite in ipairs(suites) do
  suite.run()
  passed = passed + 1
end

print(string.format("ok - %d test suite(s)", passed))
