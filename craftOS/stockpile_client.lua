-- Stockpile GUI v4.2
local logFile = "stockpile.log"
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
log("modem " .. modemSide)

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
local status, mode = "Conectando...", ""
local w, h = 0, 0

local function wh() w, h = term.getSize() end

local function render()
  wh()
  term.setBackgroundColor(colors.black); term.clear()

  -- Header line
  term.setBackgroundColor(colors.blue)
  term.setCursorPos(1,1); term.clearLine()

  local hbtns = {"[?]","[\30]","[\31]"," x"}
  local bx = w + 1
  for i = #hbtns, 1, -1 do
    local lbl = hbtns[i]
    local bw = (i == #hbtns) and #lbl or #lbl + 2
    bx = bx - bw
    if i == #hbtns then
      term.setBackgroundColor(colors.red); term.setTextColor(colors.white)
    else
      term.setBackgroundColor(colors.cyan); term.setTextColor(colors.black)
    end
    term.setCursorPos(bx, 1)
    if i == #hbtns then term.write(lbl) else term.write(" " .. lbl .. " ") end
  end

  -- Status at top-left
  term.setBackgroundColor(colors.blue)
  term.setCursorPos(2, 1)
  if mode == "wait" then
    term.setTextColor(colors.yellow); term.write(status)
  else
    term.setTextColor(colors.white); term.write(status)
    if #keys > 0 then
      term.setTextColor(colors.lightGray); term.write("  " .. #keys .. " items")
    end
  end

  -- Items (line 2 to h)
  local vis = h - 1
  if #keys == 0 then
    for i = 2, h do
      term.setBackgroundColor(colors.black); term.setCursorPos(1, i); term.clearLine()
    end
    term.setCursorPos(3, 2 + math.floor((vis-1)/2)); term.setTextColor(colors.gray)
    term.write(status)
  else
    if scroll > #keys - vis then scroll = math.max(0, #keys - vis) end
    for i = 0, vis - 1 do
      local y = 2 + i; local idx = scroll + i + 1
      term.setBackgroundColor(sel == idx and colors.blue or colors.black)
      term.setCursorPos(1, y); term.clearLine()
      if idx <= #keys then
        local name = keys[idx]:match(":(.+)$") or keys[idx]
        name = (name:match("^([^%-]+)") or name):gsub("_", " ")
        local amt = tostring(items[keys[idx]])
        term.setTextColor(colors.white); term.setCursorPos(2, y); term.write(name)
        term.setTextColor(colors.green); term.setCursorPos(w - #amt - 1, y); term.write(amt)
      end
    end
  end
end

local dumpItems, dumpInit = {}, false
local function autoScan()
  local utbl = cmd("unit.get()")
  if type(utbl) == "table" then
    for _, u in ipairs({"storage","dump","undefined"}) do
      if type(utbl[u]) == "table" and #utbl[u] > 0 then cmd('scan(units.' .. u .. ')') end
    end
    -- Build dump items set (hides dump chest items from search)
    dumpItems = {}
    if type(utbl.dump) == "table" and #utbl.dump > 0 then
      local ct = cmd("get_content()")
      if type(ct) == "table" and type(ct.inv_index) == "table" then
        for _, inv in ipairs(utbl.dump) do
          if type(ct.inv_index[inv]) == "table" then
            for _, s in pairs(ct.inv_index[inv]) do
              if type(s) == "table" then for k, q in pairs(s) do
                if type(k) == "string" and q > 0 then dumpItems[k] = true end
              end end
            end
          end
        end
      end
    end
  end
  return utbl
end

local function actSearch(q)
  if mode == "wait" then return end
  mode = "wait"
  -- Build dump cache on first use
  if not dumpInit then
    dumpInit = true
    local ut = cmd("unit.get()")
    if type(ut) == "table" and type(ut.dump) == "table" and #ut.dump > 0 then
      local ct = cmd("get_content()")
      if type(ct) == "table" and type(ct.inv_index) == "table" then
        for _, inv in ipairs(ut.dump) do
          if type(ct.inv_index[inv]) == "table" then
            for _, s in pairs(ct.inv_index[inv]) do
              if type(s) == "table" then for k, q in pairs(s) do
                if type(k) == "string" and q > 0 then dumpItems[k] = true end
              end end
            end
          end
        end
      end
    end
  end
  local filter = (q and q ~= "") and q or "."
  local r = cmd('search("' .. filter:gsub('"', '\\"') .. '")')
  if type(r) == "table" then
    items = r; keys = {}; for k, _ in pairs(r) do table.insert(keys, k) end
    table.sort(keys); scroll = 0; sel = nil
    if #keys == 0 and filter ~= "." then
      local r2 = cmd('search(".")')
      if type(r2) == "table" then
        items = r2; keys = {}; for k, _ in pairs(r2) do table.insert(keys, k) end
        table.sort(keys)
        status = 'Sin resultados para "' .. q .. '"'
      else status = r2 and tostring(r2) or "timeout" end
    else status = "OK" end
    -- Hide items in the front chest, and items in dump chests
    if #keys > 0 then
      local chest = peripheral.find("inventory")
      local localItems = {}
      if chest then
        for _, slot in pairs(chest.list()) do
          if slot and slot.name then localItems[slot.name] = true end
        end
      end
      local filtered = {}
      for _, k in ipairs(keys) do
        if not dumpItems[k] and not localItems[k] then table.insert(filtered, k) end
      end
      keys = filtered
    end
  else status = r and tostring(r) or "timeout" end
  mode = ""
end

local function actDump()
  if mode == "wait" then return end
  mode = "wait"; status = "Dump..."; render(); log("dump")
  local utbl = autoScan()
  if type(utbl) ~= "table" or type(utbl.dump) ~= "table" or #utbl.dump == 0 then
    status = "Dump vacio"; mode = ""; return
  end
  local r = cmd("move_item(units.dump, units.storage)")
  status = r and tostring(r) or "timeout"; mode = ""; actSearch("")
end

local function actGet()
  if mode == "wait" then return end
  if not sel or not keys[sel] then status = "Selecciona item"; return end
  mode = "wait"; status = "Get..."; render(); log("get " .. keys[sel])
  local utbl = autoScan()
  if type(utbl) ~= "table" or type(utbl.dump) ~= "table" or #utbl.dump == 0 then
    status = "Dump vacio"; mode = ""; return
  end
  local r = cmd('move_item(units.storage, units.dump, "' .. keys[sel]:gsub('"', '\\"') .. '")')
  status = r and tostring(r) or "timeout"; mode = ""; actSearch("")
end

local function actSearchPrompt()
  if mode == "wait" then return end
  mode = "wait"
  wh(); render()
  term.setCursorPos(2, 1); term.setBackgroundColor(colors.black)
  term.clearLine(); term.setTextColor(colors.white)
  term.write("Buscar: ")
  term.setCursorBlink(true)
  local q = read()
  term.setCursorBlink(false)
  if q and q ~= "" then
    status = "Buscando..."
    mode = ""; actSearch(q)
  else
    status = "OK"
    mode = ""; render()
  end
end

if not findServer() then print("Servidor no encontrado"); fh.close(); return end
log("server " .. server)
status = "OK  S=buscar D=dumpIn G=get R=refresh Q=quit"
actSearch(""); render()

local ok, err = pcall(function()
  while true do
    local ev = {os.pullEventRaw()}
    local t = ev[1]
    if t == "key" then
      local code = ev[2]
      if mode == "wait" then
        if code == 16 or (keys.q and code == keys.q) then error("quit") end
      elseif code == 31 or (keys.s and code == keys.s) then actSearchPrompt()
      elseif code == 32 or (keys.d and code == keys.d) then actDump()
      elseif code == 34 or (keys.g and code == keys.g) then actGet()
      elseif code == 19 or (keys.r and code == keys.r) then actSearch("")
      elseif code == 16 or (keys.q and code == keys.q) then error("quit")
      elseif (code == 200) or (keys.up and code == keys.up) then
        if #keys > 0 then sel = sel and math.max(1,sel-1) or 1
          if sel <= scroll then scroll = math.max(0,scroll-1) end end
      elseif (code == 208) or (keys.down and code == keys.down) then
        if #keys > 0 then sel = sel and math.min(#keys,sel+1) or 1
          if sel > scroll + h - 1 then scroll = sel - (h - 1) end end
      end
    elseif t == "mouse_click" then
      local x, y = ev[3], ev[4]
      if mode ~= "wait" and y == 1 then
        local hbtns = {"[?]","[\30]","[\31]"," x"}
        local bx = w + 1
        for i = #hbtns, 1, -1 do
          local lbl = hbtns[i]
          local bw = (i == #hbtns) and #lbl or #lbl + 2
          bx = bx - bw
          if x >= bx and x < bx + bw then
            if i == 1 then actSearchPrompt()
            elseif i == 2 then actDump()
            elseif i == 3 then actGet()
            elseif i == 4 then error("quit") end
            break
          end
        end
      elseif mode ~= "wait" and y >= 2 then
        local idx = scroll + (y - 2) + 1
        if idx <= #keys then sel = (sel == idx) and nil or idx end
      end
    elseif t == "mouse_scroll" then
      if mode ~= "wait" then scroll = math.max(0, scroll + (ev[2] > 0 and 1 or -1)) end
    end
    render()
  end
end)

fh.close()
term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
term.clear(); term.setCursorPos(1,1)
if err and err ~= "quit" then print("Error: " .. tostring(err) .. "  log:" .. logFile) end
