local M = {}

local function display_width(str)
  return vim.fn.strdisplaywidth(str)
end

local function truncate_display(str, max_width)
  if max_width <= 0 then
    return ""
  end

  if display_width(str) <= max_width then
    return str
  end

  local out = {}
  local chars = vim.fn.strchars(str)
  local current = 0

  for i = 0, chars - 1 do
    local ch = vim.fn.strcharpart(str, i, 1)
    local ch_w = display_width(ch)
    if current + ch_w > max_width then
      break
    end
    table.insert(out, ch)
    current = current + ch_w
  end

  return table.concat(out)
end

-- Comprehensive Latin transliteration table.
-- Covers Latin-1 Supplement (U+00C0-U+00FF), Latin Extended-A (U+0100-U+017F),
-- Latin Extended-B (U+0180-U+024F), and Latin Extended Additional (U+1E00-U+1EFF).
-- Multi-char mappings (ae, ss, th, oe, ij, ng) are explicit.
local _translit = {
  -- Latin-1 Supplement
  ["À"]="A",["Á"]="A",["Â"]="A",["Ã"]="A",["Ä"]="A",["Å"]="A",["Æ"]="AE",
  ["Ç"]="C",
  ["È"]="E",["É"]="E",["Ê"]="E",["Ë"]="E",
  ["Ì"]="I",["Í"]="I",["Î"]="I",["Ï"]="I",
  ["Ð"]="D",["Ñ"]="N",
  ["Ò"]="O",["Ó"]="O",["Ô"]="O",["Õ"]="O",["Ö"]="O",["Ø"]="O",
  ["Ù"]="U",["Ú"]="U",["Û"]="U",["Ü"]="U",
  ["Ý"]="Y",["Þ"]="TH",
  ["à"]="a",["á"]="a",["â"]="a",["ã"]="a",["ä"]="a",["å"]="a",["æ"]="ae",
  ["ç"]="c",
  ["è"]="e",["é"]="e",["ê"]="e",["ë"]="e",
  ["ì"]="i",["í"]="i",["î"]="i",["ï"]="i",
  ["ð"]="d",["ñ"]="n",
  ["ò"]="o",["ó"]="o",["ô"]="o",["õ"]="o",["ö"]="o",["ø"]="o",
  ["ù"]="u",["ú"]="u",["û"]="u",["ü"]="u",
  ["ý"]="y",["þ"]="th",["ß"]="ss",["ÿ"]="y",

  -- Latin Extended-A
  ["Ā"]="A",["ā"]="a",["Ă"]="A",["ă"]="a",["Ą"]="A",["ą"]="a",
  ["Ć"]="C",["ć"]="c",["Ĉ"]="C",["ĉ"]="c",["Ċ"]="C",["ċ"]="c",["Č"]="C",["č"]="c",
  ["Ď"]="D",["ď"]="d",["Đ"]="D",["đ"]="d",
  ["Ē"]="E",["ē"]="e",["Ĕ"]="E",["ĕ"]="e",["Ė"]="E",["ė"]="e",
  ["Ę"]="E",["ę"]="e",["Ě"]="E",["ě"]="e",
  ["Ĝ"]="G",["ĝ"]="g",["Ğ"]="G",["ğ"]="g",["Ġ"]="G",["ġ"]="g",["Ģ"]="G",["ģ"]="g",
  ["Ĥ"]="H",["ĥ"]="h",["Ħ"]="H",["ħ"]="h",
  ["Ĩ"]="I",["ĩ"]="i",["Ī"]="I",["ī"]="i",["Ĭ"]="I",["ĭ"]="i",
  ["Į"]="I",["į"]="i",["İ"]="I",["ı"]="i",["Ĳ"]="IJ",["ĳ"]="ij",
  ["Ĵ"]="J",["ĵ"]="j",
  ["Ķ"]="K",["ķ"]="k",["ĸ"]="k",
  ["Ĺ"]="L",["ĺ"]="l",["Ļ"]="L",["ļ"]="l",["Ľ"]="L",["ľ"]="l",["Ŀ"]="L",["ŀ"]="l",["Ł"]="L",["ł"]="l",
  ["Ń"]="N",["ń"]="n",["Ņ"]="N",["ņ"]="n",["Ň"]="N",["ň"]="n",["ŉ"]="n",["Ŋ"]="NG",["ŋ"]="ng",
  ["Ō"]="O",["ō"]="o",["Ŏ"]="O",["ŏ"]="o",["Ő"]="O",["ő"]="o",["Œ"]="OE",["œ"]="oe",
  ["Ŕ"]="R",["ŕ"]="r",["Ŗ"]="R",["ŗ"]="r",["Ř"]="R",["ř"]="r",
  ["Ś"]="S",["ś"]="s",["Ŝ"]="S",["ŝ"]="s",["Ş"]="S",["ş"]="s",["Š"]="S",["š"]="s",
  ["Ţ"]="T",["ţ"]="t",["Ť"]="T",["ť"]="t",["Ŧ"]="T",["ŧ"]="t",
  ["Ũ"]="U",["ũ"]="u",["Ū"]="U",["ū"]="u",["Ŭ"]="U",["ŭ"]="u",["Ů"]="U",["ů"]="u",["Ű"]="U",["ű"]="u",["Ų"]="U",["ų"]="u",
  ["Ŵ"]="W",["ŵ"]="w",
  ["Ŷ"]="Y",["ŷ"]="y",["Ÿ"]="Y",
  ["Ź"]="Z",["ź"]="z",["Ż"]="Z",["ż"]="z",["Ž"]="Z",["ž"]="z",

  -- Latin Extended-B
  ["ƀ"]="b",["Ɓ"]="B",["Ƃ"]="b",["ƃ"]="b",
  ["Ƈ"]="C",["ƈ"]="c",
  ["Ɖ"]="D",["Ɗ"]="D",["Ƌ"]="D",["ƌ"]="d",
  ["Ǆ"]="DZ",["ǆ"]="dz",["ǅ"]="Dz",
  ["Ǉ"]="LJ",["ǉ"]="lj",["ǈ"]="Lj",
  ["Ǌ"]="NJ",["ǌ"]="nj",["ǋ"]="Nj",
  ["Ǎ"]="A",["ǎ"]="a",["Ǐ"]="I",["ǐ"]="i",["Ǒ"]="O",["ǒ"]="o",["Ǔ"]="U",["ǔ"]="u",
  ["Ǖ"]="U",["ǖ"]="u",["Ǘ"]="U",["ǘ"]="u",["Ǚ"]="U",["ǚ"]="u",["Ǜ"]="U",["ǜ"]="u",
  ["Ǟ"]="A",["ǟ"]="a",["Ǡ"]="A",["ǡ"]="a",["Ǣ"]="AE",["ǣ"]="ae",
  ["Ǥ"]="G",["ǥ"]="g",["Ǧ"]="G",["ǧ"]="g",["Ǩ"]="K",["ǩ"]="k",
  ["Ǫ"]="O",["ǫ"]="o",["Ǭ"]="O",["ǭ"]="o",
  ["Ǯ"]="Z",["ǯ"]="z",
  ["Ǳ"]="DZ",["ǲ"]="Dz",["ǳ"]="dz",
  ["Ǵ"]="G",["ǵ"]="g",["Ƕ"]="HV",["Ƿ"]="W",
  ["Ǹ"]="N",["ǹ"]="n",["Ǻ"]="A",["ǻ"]="a",["Ǽ"]="AE",["ǽ"]="ae",["Ǿ"]="O",["ǿ"]="o",
  ["Ȁ"]="A",["ȁ"]="a",["Ȃ"]="A",["ȃ"]="a",
  ["Ȅ"]="E",["ȅ"]="e",["Ȇ"]="E",["ȇ"]="e",
  ["Ȉ"]="I",["ȉ"]="i",["Ȋ"]="I",["ȋ"]="i",
  ["Ȍ"]="O",["ȍ"]="o",["Ȏ"]="O",["ȏ"]="o",
  ["Ȑ"]="R",["ȑ"]="r",["Ȓ"]="R",["ȓ"]="r",
  ["Ȕ"]="U",["ȕ"]="u",["Ȗ"]="U",["ȗ"]="u",
  ["Ș"]="S",["ș"]="s",["Ț"]="T",["ț"]="t",
  ["Ȟ"]="H",["ȟ"]="h",
  ["Ȧ"]="A",["ȧ"]="a",["Ȩ"]="E",["ȩ"]="e",["Ȫ"]="O",["ȫ"]="o",["Ȭ"]="O",["ȭ"]="o",["Ȯ"]="O",["ȯ"]="o",["Ȱ"]="O",["ȱ"]="o",
  ["Ȳ"]="Y",["ȳ"]="y",

  -- Latin Extended Additional
  ["Ạ"]="A",["ạ"]="a",["Ả"]="A",["ả"]="a",["Ấ"]="A",["ấ"]="a",
  ["Ầ"]="A",["ầ"]="a",["Ẩ"]="A",["ẩ"]="a",["Ẫ"]="A",["ẫ"]="a",["Ậ"]="A",["ậ"]="a",
  ["Ắ"]="A",["ắ"]="a",["Ằ"]="A",["ằ"]="a",["Ẳ"]="A",["ẳ"]="a",["Ẵ"]="A",["ẵ"]="a",["Ặ"]="A",["ặ"]="a",
  ["Ḃ"]="B",["ḃ"]="b",["Ḅ"]="B",["ḅ"]="b",["Ḇ"]="B",["ḇ"]="b",
  ["Ḉ"]="C",["ḉ"]="c",
  ["Ḋ"]="D",["ḋ"]="d",["Ḍ"]="D",["ḍ"]="d",["Ḏ"]="D",["ḏ"]="d",["Ḑ"]="D",["ḑ"]="d",["Ḓ"]="D",["ḓ"]="d",
  ["Ẹ"]="E",["ẹ"]="e",["Ẻ"]="E",["ẻ"]="e",["Ẽ"]="E",["ẽ"]="e",
  ["Ế"]="E",["ế"]="e",["Ề"]="E",["ề"]="e",["Ể"]="E",["ể"]="e",["Ễ"]="E",["ễ"]="e",["Ệ"]="E",["ệ"]="e",
  ["Ḟ"]="F",["ḟ"]="f",
  ["Ḡ"]="G",["ḡ"]="g",
  ["Ḣ"]="H",["ḣ"]="h",["Ḥ"]="H",["ḥ"]="h",["Ḧ"]="H",["ḧ"]="h",["Ḩ"]="H",["ḩ"]="h",["Ḫ"]="H",["ḫ"]="h",
  ["Ị"]="I",["ị"]="i",["Ỉ"]="I",["ỉ"]="i",
  ["Ḱ"]="K",["ḱ"]="k",["Ḳ"]="K",["ḳ"]="k",["Ḵ"]="K",["ḵ"]="k",
  ["Ḷ"]="L",["ḷ"]="l",["Ḹ"]="L",["ḹ"]="l",["Ḻ"]="L",["ḻ"]="l",["Ḽ"]="L",["ḽ"]="l",
  ["Ḿ"]="M",["ḿ"]="m",["Ṁ"]="M",["ṁ"]="m",["Ṃ"]="M",["ṃ"]="m",
  ["Ṅ"]="N",["ṅ"]="n",["Ṇ"]="N",["ṇ"]="n",["Ṉ"]="N",["ṉ"]="n",["Ṋ"]="N",["ṋ"]="n",
  ["Ọ"]="O",["ọ"]="o",["Ỏ"]="O",["ỏ"]="o",["Ố"]="O",["ố"]="o",
  ["Ồ"]="O",["ồ"]="o",["Ổ"]="O",["ổ"]="o",["Ỗ"]="O",["ỗ"]="o",["Ộ"]="O",["ộ"]="o",
  ["Ớ"]="O",["ớ"]="o",["Ờ"]="O",["ờ"]="o",["Ở"]="O",["ở"]="o",["Ỡ"]="O",["ỡ"]="o",["Ợ"]="O",["ợ"]="o",
  ["Ṕ"]="P",["ṕ"]="p",["Ṗ"]="P",["ṗ"]="p",
  ["Ṙ"]="R",["ṙ"]="r",["Ṛ"]="R",["ṛ"]="r",["Ṝ"]="R",["ṝ"]="r",["Ṟ"]="R",["ṟ"]="r",
  ["Ṡ"]="S",["ṡ"]="s",["Ṣ"]="S",["ṣ"]="s",["Ṥ"]="S",["ṥ"]="s",["Ṧ"]="S",["ṧ"]="s",["Ṩ"]="S",["ṩ"]="s",
  ["Ṫ"]="T",["ṫ"]="t",["Ṭ"]="T",["ṭ"]="t",["Ṯ"]="T",["ṯ"]="t",["Ṱ"]="T",["ṱ"]="t",
  ["Ụ"]="U",["ụ"]="u",["Ủ"]="U",["ủ"]="u",["Ứ"]="U",["ứ"]="u",
  ["Ừ"]="U",["ừ"]="u",["Ử"]="U",["ử"]="u",["Ữ"]="U",["ữ"]="u",["Ự"]="U",["ự"]="u",
  ["Ṽ"]="V",["ṽ"]="v",["Ṿ"]="V",["ṿ"]="v",
  ["Ẁ"]="W",["ẁ"]="w",["Ẃ"]="W",["ẃ"]="w",["Ẅ"]="W",["ẅ"]="w",["Ẇ"]="W",["ẇ"]="w",["Ẉ"]="W",["ẉ"]="w",
  ["Ẋ"]="X",["ẋ"]="x",["Ẍ"]="X",["ẍ"]="x",
  ["Ẏ"]="Y",["ẏ"]="y",["Ỳ"]="Y",["ỳ"]="y",["Ỵ"]="Y",["ỵ"]="y",["Ỷ"]="Y",["ỷ"]="y",["Ỹ"]="Y",["ỹ"]="y",
  ["Ẑ"]="Z",["ẑ"]="z",["Ẓ"]="Z",["ẓ"]="z",["Ẕ"]="Z",["ẕ"]="z",
}

--- Convert UTF-8 text to stable printable ASCII for terminal layout.
---@param str any
---@return string
function M.ascii_safe(str)
  if not str then
    return ""
  end
  str = tostring(str)
  local result = {}
  local i = 1
  local bytes = { str:byte(1, #str) }

  while i <= #bytes do
    local b = bytes[i]
    local char_len
    if b < 0x80 then
      char_len = 1
    elseif b < 0xE0 then
      char_len = 2
    elseif b < 0xF0 then
      char_len = 3
    else
      char_len = 4
    end

    local char = str:sub(i, i + char_len - 1)
    local replacement = _translit[char]

    if replacement then
      table.insert(result, replacement)
    elseif b >= 0x20 and b < 0x7F then
      table.insert(result, char)
    end

    i = i + char_len
  end

  return table.concat(result)
end

--- Format a relative time string from an ISO8601 timestamp.
---@param iso_str string ISO8601 timestamp (e.g. "2025-02-15T10:30:00Z")
---@return string
function M.relative_time(iso_str)
  if not iso_str then
    return "unknown"
  end

  -- Parse ISO8601
  local y, mo, d, h, mi, s = iso_str:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then
    return "unknown"
  end

  local ts = os.time({
    year = tonumber(y),
    month = tonumber(mo),
    day = tonumber(d),
    hour = tonumber(h),
    min = tonumber(mi),
    sec = tonumber(s),
  })

  local now = os.time(os.date("!*t"))
  local diff = now - ts

  if diff < 0 then
    return "just now"
  elseif diff < 60 then
    return diff .. "s ago"
  elseif diff < 3600 then
    local mins = math.floor(diff / 60)
    return mins .. "m ago"
  elseif diff < 86400 then
    local hours = math.floor(diff / 3600)
    return hours .. "h ago"
  else
    local days = math.floor(diff / 86400)
    if days == 1 then
      return "1 day ago"
    else
      return days .. " days ago"
    end
  end
end

--- Truncate a string to max_len, appending "..." if truncated.
---@param str string
---@param max_len number
---@return string
function M.truncate(str, max_len)
  if not str then
    return ""
  end
  str = M.ascii_safe(str)
  if #str <= max_len then
    return str
  end
  if max_len <= 2 then
    return str:sub(1, max_len)
  end
  return str:sub(1, max_len - 3) .. "..."
end

--- Pad a string to exactly `width` characters (right-padded with spaces).
---@param str string
---@param width number
---@return string
function M.pad_right(str, width)
  if str == nil then
    str = ""
  else
    str = tostring(str)
  end
  str = truncate_display(str, width)
  local w = display_width(str)
  if w >= width then
    return str
  end
  return str .. string.rep(" ", width - w)
end

--- Center a string within `width` characters.
---@param str string
---@param width number
---@return string
function M.center(str, width)
  if str == nil then
    str = ""
  else
    str = tostring(str)
  end
  str = truncate_display(str, width)
  local w = display_width(str)
  if w >= width then
    return str
  end
  local pad = width - w
  local left = math.floor(pad / 2)
  local right = pad - left
  return string.rep(" ", left) .. str .. string.rep(" ", right)
end

--- Map approval status to a display string.
---@param status table { status: string, approvals: number, changes_requested: number }
---@return string
function M.approval_badge(status)
  if not status then
    return "Review: Pending"
  end
  if status.status == "approved" then
    return string.format("Review: Approved (%d)", status.approvals)
  elseif status.status == "changes_requested" then
    return "Review: Changes Requested"
  elseif status.status == "commented" then
    return "Review: Commented"
  else
    return "Review: Pending"
  end
end

--- Map CI status to a display string.
---@param status table { status: string, success: number, total: number }
---@return string
function M.ci_badge(status)
  if not status then
    return "CI: None"
  end
  if status.status == "success" then
    return string.format("CI: Passing (%d/%d)", status.success, status.total)
  elseif status.status == "failure" then
    return string.format("CI: Failing (%d/%d)", status.success, status.total)
  elseif status.status == "pending" then
    return string.format("CI: Running (%d/%d)", status.completed, status.total)
  else
    return "CI: None"
  end
end

return M
