-- Stockpile Search v1.2 (Spotlight-style)
local logFile = "stockpile_search.log"
local fh = fs.open(logFile, "w")
local function log(...)
  local msg = os.date("%H:%M:%S") .. " " .. table.concat({...}, " ")
  if fh then fh.writeLine(msg) fh.flush() end
end
log("inicio")

local modemSide = ""
for _, s in ipairs(peripheral.getNames()) do
  if peripheral.hasType(s, "modem") then rednet.open(s); modemSide = s; break end
end
if modemSide == "" then
  for _, s in ipairs({"right","left","top","bottom","front","back"}) do
    local ok, e = pcall(rednet.open, s)
    if ok then modemSide = s; break end
  end
end
if modemSide == "" then print("No modem"); fh.close(); return end

local server = nil
local function findServer()
  local id = rednet.lookup("stockpile")
  if id and id ~= 0 then server = id; return true end
  local uuid = math.random(1, 2^32)
  rednet.send(0, {"usage()", uuid}, "stockpile")
  for _ = 1, 8 do
    local rid, msg = rednet.receive("stockpile", 2)
    if rid and type(msg) == "table" and msg[2] == uuid then server = rid; return true end
  end
  return false
end

local function cmd(s)
  if not server then return nil end
  local uuid = math.random(1, 2^32)
  rednet.send(server, {s, uuid}, "stockpile")
  for _ = 1, 5 do
    local id, msg = rednet.receive("stockpile", 2)
    if id and type(msg) == "table" and msg[2] == uuid then
      if server ~= id then server = id end; return msg[1]
    end
  end
  log("timeout " .. s)
  return nil
end

local items, keys, scroll, sel = {}, {}, 0, nil
local query, searching = "", false
local w, h = 0, 0
local function wh() w, h = term.getSize() end

local function doSearch(q)
  searching = true
  local filter = (q and q ~= "") and q or "."
  local r = cmd('search("' .. filter:gsub('"', '\\"') .. '")')
  if type(r) == "table" then
    items = r; keys = {}; for k, _ in pairs(r) do table.insert(keys, k) end
    table.sort(keys); scroll = 0; sel = nil
  end
  searching = false
end

local function render()
  wh()

  term.setBackgroundColor(colors.black)
  for y = 1, h do term.setCursorPos(1, y); term.clearLine() end

  local boxW = math.min(48, w - 4)
  local boxX = math.floor((w - boxW) / 2)
  local boxY = math.max(2, math.floor(h / 4))

  -- Box background
  local rows = math.min(#keys, 12)
  if rows < 1 then rows = 1 end
  local totalH = 2 + rows + 1
  if boxY + totalH > h then rows = h - boxY - 3 end
  if rows < 1 then rows = 1 end
  for y = 0, rows + 1 do
    local yy = boxY + y
    if yy >= 1 and yy <= h then
      term.setBackgroundColor(colors.gray)
      term.setCursorPos(boxX, yy); term.write(string.rep(" ", boxW))
    end
  end

  -- Input line
  term.setBackgroundColor(colors.gray)
  term.setTextColor(colors.lightGray)
  term.setCursorPos(boxX + 1, boxY); term.write(">")
  term.setTextColor(colors.white)
  local txt = query
  if #txt > boxW - 4 then txt = string.sub(txt, #txt - boxW + 5) end
  term.write(txt)
  local pad = boxW - 3 - #txt
  if pad > 0 then term.write(string.rep(" ", pad)) end
  term.setCursorBlink(true)
  term.setCursorPos(boxX + 2 + #txt, boxY)

  -- Separator
  term.setBackgroundColor(colors.blue)
  term.setCursorPos(boxX, boxY + 1); term.write(string.rep(" ", boxW))

  -- Results
  local rY = boxY + 2
  if #keys > 0 then
    local vis = math.min(rows, #keys)
    if scroll > #keys - vis then scroll = math.max(0, #keys - vis) end
    for i = 0, vis - 1 do
      local idx = scroll + i + 1
      local y = rY + i
      term.setBackgroundColor(sel == idx and colors.blue or colors.gray)
      term.setCursorPos(boxX, y); term.clearLine()
      if idx <= #keys then
        local name = keys[idx]:match(":(.+)$") or keys[idx]
        name = (name:match("^([^%-]+)") or name):gsub("_", " ")
        local amt = tostring(items[keys[idx]])
        term.setTextColor(colors.white)
        term.setCursorPos(boxX + 2, y); term.write(name)
        term.setTextColor(colors.green)
        term.setCursorPos(boxX + boxW - #amt - 2, y); term.write(amt)
      end
    end
  elseif query ~= "" and not searching then
    term.setBackgroundColor(colors.gray); term.setTextColor(colors.gray)
    term.setCursorPos(boxX + 2, rY); term.write("No results")
  elseif searching then
    term.setBackgroundColor(colors.gray); term.setTextColor(colors.gray)
    term.setCursorPos(boxX + 2, rY); term.write("Searching...")
  end

  term.setBackgroundColor(colors.black); term.setTextColor(colors.gray)
  term.setCursorPos(2, h); term.write("ESC=quit ENTER=search")
end

if not findServer() then print("Servidor no encontrado"); fh.close(); return end
log("server " .. server)
query = ""; render()

local ok, err = pcall(function()
  while true do
    local ev = {os.pullEventRaw()}
    local t = ev[1]

    if t == "key" then
      local code = ev[2]
      if searching then
        if code == 16 or code == 1 then error("quit") end
      elseif code == 1 or code == 16 then
        error("quit")
      elseif code == 14 or code == 211 then
        if #query > 0 then query = string.sub(query, 1, -2) end
      elseif code == 28 then
        if #keys > 0 and sel and keys[sel] then
          term.setCursorBlink(false)
          term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
          term.clear(); term.setCursorPos(1,1)
          print(keys[sel])
          fh.close(); return
        else
          doSearch(query)
        end
      elseif code == 200 then
        if #keys > 0 then sel = sel and math.max(1,sel-1) or 1
          if sel <= scroll then scroll = math.max(0,scroll-1) end end
      elseif code == 208 then
        if #keys > 0 then sel = sel and math.min(#keys,sel+1) or 1
          if sel > scroll + 12 then scroll = sel - 12 end end
      end

    elseif t == "char" then
      local ch = ev[2]
      if not searching then
        local b = string.byte(ch)
        if b and b >= 32 and b <= 126 then query = query .. ch end
      end

    elseif t == "mouse_click" and not searching then
      local x, y = ev[3], ev[4]
      local boxW = math.min(48, w - 4)
      local boxX = math.floor((w - boxW) / 2)
      local boxY = math.max(2, math.floor(h / 4))
      if y >= boxY + 2 and y <= boxY + 2 + math.min(#keys, 12) - 1 then
        local idx = scroll + (y - boxY - 2) + 1
        if idx <= #keys then sel = (sel == idx) and nil or idx end
      end
    end

    render()
  end
end)

fh.close()
term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
term.setCursorBlink(false); term.clear(); term.setCursorPos(1,1)
if err and err ~= "quit" then print("Error: " .. tostring(err) .. "  log:" .. logFile) end
