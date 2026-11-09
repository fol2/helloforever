-- Small pure-Lua helpers for the mock client: JSON, base64, raw-deflate "stored" blocks.
local M = {}
local function isArray(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
    n = n + 1
  end
  for i = 1, n do if t[i] == nil then return false end end
  return n > 0
end
local function esc(s)
  return (s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' elseif c == "\\" then return "\\\\"
    elseif c == "\n" then return "\\n" else return string.format("\\u%04x", c:byte()) end
  end))
end
function M.json(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "boolean" then return v and "true" or "false" end
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then error("bad number") end
    if v % 1 == 0 and math.abs(v) < 2^53 then return string.format("%d", v) end
    return string.format("%.17g", v)
  end
  if t == "string" then return '"' .. esc(v) .. '"' end
  if t == "table" then
    local out = {}
    if isArray(v) then
      for i = 1, #v do out[i] = M.json(v[i]) end
      return "[" .. table.concat(out, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys+1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do out[#out+1] = '"' .. esc(tostring(k)) .. '":' .. M.json(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
  end
  error("cannot serialize " .. t)
end
local B = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function M.b64enc(s)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1 = math.floor(n / 262144) % 64
    local c2 = math.floor(n / 4096) % 64
    local c3 = math.floor(n / 64) % 64
    local c4 = n % 64
    out[#out+1] = B:sub(c1+1, c1+1) .. B:sub(c2+1, c2+1)
      .. (b and B:sub(c3+1, c3+1) or "=") .. (c and B:sub(c4+1, c4+1) or "=")
  end
  return table.concat(out)
end
local D = {}
for i = 1, 64 do D[B:sub(i, i)] = i - 1 end
function M.b64dec(s)
  s = s:gsub("[^%w%+/=]", "")
  local out = {}
  for i = 1, #s, 4 do
    local q = s:sub(i, i + 3)
    local n, pad = 0, 0
    for j = 1, 4 do
      local ch = q:sub(j, j)
      if ch == "=" then pad = pad + 1; n = n * 64 else n = n * 64 + D[ch] end
    end
    local a = math.floor(n / 65536) % 256
    local b = math.floor(n / 256) % 256
    local c = n % 256
    out[#out+1] = string.char(a) .. (pad < 2 and string.char(b) or "") .. (pad < 1 and string.char(c) or "")
  end
  return table.concat(out)
end
-- raw DEFLATE with stored (uncompressed) blocks: valid input for zlib.decompress(x, -15)
function M.deflateStored(s)
  local out, i, n = {}, 1, #s
  if n == 0 then return string.char(1, 0, 0, 255, 255) end
  while i <= n do
    local len = math.min(65535, n - i + 1)
    local final = (i + len > n) and 1 or 0
    local nlen = 65535 - len
    out[#out+1] = string.char(final, len % 256, math.floor(len / 256), nlen % 256, math.floor(nlen / 256))
    out[#out+1] = s:sub(i, i + len - 1)
    i = i + len
  end
  return table.concat(out)
end
function M.inflateStored(z)
  local out, i = {}, 1
  while i <= #z do
    local hdr = z:byte(i)
    local len = z:byte(i + 1) + z:byte(i + 2) * 256
    out[#out+1] = z:sub(i + 5, i + 4 + len)
    i = i + 5 + len
    if hdr % 2 == 1 then break end
  end
  return table.concat(out)
end
return M
