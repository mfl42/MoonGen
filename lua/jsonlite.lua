local M = {}

local function is_array(tbl)
  if type(tbl) ~= "table" then
    return false
  end
  local n = 0
  local has_any = false
  for k in pairs(tbl) do
    has_any = true
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
      return false
    end
    if k > n then
      n = k
    end
  end
  if not has_any then
    return false
  end
  for i = 1, n do
    if tbl[i] == nil then
      return false
    end
  end
  return true
end

local function escape_json_string(s)
  s = tostring(s)
  s = s:gsub("\\", "\\\\")
  s = s:gsub("\"", "\\\"")
  s = s:gsub("\b", "\\b")
  s = s:gsub("\f", "\\f")
  s = s:gsub("\n", "\\n")
  s = s:gsub("\r", "\\r")
  s = s:gsub("\t", "\\t")
  return "\"" .. s .. "\""
end

local function encode(v)
  local tv = type(v)
  if tv == "nil" then
    return "null"
  elseif tv == "boolean" then
    return v and "true" or "false"
  elseif tv == "number" then
    return tostring(v)
  elseif tv == "string" then
    return escape_json_string(v)
  elseif tv ~= "table" then
    return escape_json_string(tostring(v))
  end

  if is_array(v) then
    local parts = {}
    for i = 1, #v do
      parts[#parts + 1] = encode(v[i])
    end
    return "[" .. table.concat(parts, ",") .. "]"
  end

  local keys = {}
  for k in pairs(v) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)

  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = escape_json_string(k) .. ":" .. encode(v[k])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

M.encode = encode

function M.dump_file(path, tbl)
  local f, err = io.open(path, "w")
  if not f then
    return nil, err
  end
  f:write(encode(tbl))
  f:write("\n")
  f:close()
  return true
end

local function new_parser(src)
  local p = { s = src or "", i = 1, n = #(src or "") }

  function p:peek()
    if self.i > self.n then
      return nil
    end
    return self.s:sub(self.i, self.i)
  end

  function p:next()
    local ch = self:peek()
    self.i = self.i + 1
    return ch
  end

  function p:skip_ws()
    while true do
      local ch = self:peek()
      if ch == " " or ch == "\n" or ch == "\r" or ch == "\t" then
        self.i = self.i + 1
      else
        return
      end
    end
  end

  function p:error(msg)
    error(string.format("jsonlite decode error at pos %d: %s", self.i, msg))
  end

  function p:expect(str)
    if self.s:sub(self.i, self.i + #str - 1) ~= str then
      self:error("expected '" .. str .. "'")
    end
    self.i = self.i + #str
  end

  function p:parse_string()
    local quote = self:next()
    if quote ~= "\"" then
      self:error("expected string")
    end
    local out = {}
    while true do
      local ch = self:next()
      if ch == nil then
        self:error("unterminated string")
      end
      if ch == "\"" then
        return table.concat(out)
      end
      if ch == "\\" then
        local esc = self:next()
        if esc == nil then
          self:error("unterminated escape")
        end
        if esc == "\"" or esc == "\\" or esc == "/" then
          out[#out + 1] = esc
        elseif esc == "b" then
          out[#out + 1] = "\b"
        elseif esc == "f" then
          out[#out + 1] = "\f"
        elseif esc == "n" then
          out[#out + 1] = "\n"
        elseif esc == "r" then
          out[#out + 1] = "\r"
        elseif esc == "t" then
          out[#out + 1] = "\t"
        elseif esc == "u" then
          local hex = self.s:sub(self.i, self.i + 3)
          if #hex < 4 or not hex:match("^[0-9a-fA-F]+$") then
            self:error("invalid unicode escape")
          end
          self.i = self.i + 4
          local code = tonumber(hex, 16) or 0
          if code < 128 then
            out[#out + 1] = string.char(code)
          else
            out[#out + 1] = "?"
          end
        else
          self:error("unknown escape '\\" .. esc .. "'")
        end
      else
        out[#out + 1] = ch
      end
    end
  end

  function p:parse_number()
    local start = self.i
    local ch = self:peek()
    if ch == "-" then
      self.i = self.i + 1
    end
    local has_digit = false
    while true do
      ch = self:peek()
      if ch and ch:match("%d") then
        has_digit = true
        self.i = self.i + 1
      else
        break
      end
    end
    ch = self:peek()
    if ch == "." then
      self.i = self.i + 1
      local frac_digit = false
      while true do
        ch = self:peek()
        if ch and ch:match("%d") then
          frac_digit = true
          self.i = self.i + 1
        else
          break
        end
      end
      if not frac_digit then
        self:error("invalid number fraction")
      end
    end
    ch = self:peek()
    if ch == "e" or ch == "E" then
      self.i = self.i + 1
      ch = self:peek()
      if ch == "+" or ch == "-" then
        self.i = self.i + 1
      end
      local exp_digit = false
      while true do
        ch = self:peek()
        if ch and ch:match("%d") then
          exp_digit = true
          self.i = self.i + 1
        else
          break
        end
      end
      if not exp_digit then
        self:error("invalid number exponent")
      end
    end
    if not has_digit then
      self:error("invalid number")
    end
    local raw = self.s:sub(start, self.i - 1)
    local n = tonumber(raw)
    if not n then
      self:error("invalid numeric value")
    end
    return n
  end

  function p:parse_array()
    local open = self:next()
    if open ~= "[" then
      self:error("expected '['")
    end
    self:skip_ws()
    local out = {}
    if self:peek() == "]" then
      self.i = self.i + 1
      return out
    end
    while true do
      out[#out + 1] = self:parse_value()
      self:skip_ws()
      local ch = self:next()
      if ch == "]" then
        return out
      elseif ch ~= "," then
        self:error("expected ',' or ']' in array")
      end
      self:skip_ws()
    end
  end

  function p:parse_object()
    local open = self:next()
    if open ~= "{" then
      self:error("expected '{'")
    end
    self:skip_ws()
    local out = {}
    if self:peek() == "}" then
      self.i = self.i + 1
      return out
    end
    while true do
      self:skip_ws()
      local key = self:parse_string()
      self:skip_ws()
      if self:next() ~= ":" then
        self:error("expected ':' after object key")
      end
      self:skip_ws()
      out[key] = self:parse_value()
      self:skip_ws()
      local ch = self:next()
      if ch == "}" then
        return out
      elseif ch ~= "," then
        self:error("expected ',' or '}' in object")
      end
      self:skip_ws()
    end
  end

  function p:parse_value()
    self:skip_ws()
    local ch = self:peek()
    if ch == nil then
      self:error("unexpected end of input")
    end
    if ch == "{" then
      return self:parse_object()
    elseif ch == "[" then
      return self:parse_array()
    elseif ch == "\"" then
      return self:parse_string()
    elseif ch == "-" or ch:match("%d") then
      return self:parse_number()
    elseif ch == "t" then
      self:expect("true")
      return true
    elseif ch == "f" then
      self:expect("false")
      return false
    elseif ch == "n" then
      self:expect("null")
      return nil
    end
    self:error("unexpected token '" .. tostring(ch) .. "'")
  end

  return p
end

function M.decode(src)
  local p = new_parser(src)
  local ok, result = pcall(function()
    local value = p:parse_value()
    p:skip_ws()
    if p.i <= p.n then
      p:error("trailing data")
    end
    return value
  end)
  if not ok then
    return nil, result
  end
  return result, nil
end

function M.load_file(path)
  local f, err = io.open(path, "r")
  if not f then
    return nil, err
  end
  local s = f:read("*a")
  f:close()
  return M.decode(s)
end

return M
