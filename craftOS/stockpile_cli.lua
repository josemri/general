-- Stockpile CLI v1.2
local logFile = "stockpile_cli.log"
local fh = fs.open(logFile, "w")
local function log(...)
  local parts = {...}
  local msg = os.date("%H:%M:%S") .. " " .. table.concat(parts, " ")
  if fh then fh.writeLine(msg) fh.flush() end
end
log("=== Inicio CLI ===")

for _, s in ipairs(peripheral.getNames()) do
  if peripheral.hasType(s, "modem") then rednet.open(s) log("modem: " .. s) break end
end

local server = nil

local function findServer()
  local id = rednet.lookup("stockpile")
  if id and id ~= 0 then server = id return true end
  local uuid = math.random(1, 2 ^ 32)
  rednet.send(0, { "usage()", uuid }, "stockpile")
  for _ = 1, 8 do
    local rid, msg = rednet.receive("stockpile", 2)
    if rid and type(msg) == "table" and msg[2] == uuid then
      server = rid
      return true
    end
  end
  return false
end

local function cmd(cmdStr)
  if not server then return nil end
  local uuid = math.random(1, 2 ^ 32)
  rednet.send(server, { cmdStr, uuid }, "stockpile")
  for _ = 1, 5 do
    local id, msg = rednet.receive("stockpile", 2)
    if id and type(msg) == "table" and msg[2] == uuid then
      if server ~= id then server = id end
      return msg[1]
    end
  end
  return nil
end

local dumpItems = {}
local function refreshDumpItems()
  dumpItems = {}
  local utbl = cmd("unit.get()")
  if type(utbl) ~= "table" or type(utbl.dump) ~= "table" or #utbl.dump == 0 then return end
  local ct = cmd("get_content()")
  if type(ct) ~= "table" or type(ct.inv_index) ~= "table" then return end
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

if not findServer() then
  print("ERROR: No se encuentra servidor Stockpile")
  if fh then fh.close() end
  return
end
print("Servidor #" .. server)

while true do
  term.setCursorBlink(false)
  write("\n> ")
  local line = read()
  if line == "q" or line == "quit" then break end
  if line == "" then line = "search(.)" end

  if line == "scan" then
    local utbl = cmd("unit.get()")
    if type(utbl) == "table" then
      for _, u in ipairs({"storage", "dump", "undefined"}) do
        if type(utbl[u]) == "table" and #utbl[u] > 0 then
          print("Escaneando " .. u .. " (" .. #utbl[u] .. " inventarios)...")
          local r = cmd('scan(units.' .. u .. ')')
          print("  " .. tostring(r))
        end
      end
    end
    refreshDumpItems()
  elseif line == "status" then
    local utbl = cmd("unit.get()")
    if type(utbl) == "table" then
      for u, chests in pairs(utbl) do
        if type(chests) == "table" then
          print("  " .. u .. ": " .. (#chests > 0 and table.concat(chests, ", ") or "(vacio)"))
        end
      end
    end
  elseif line:match("^status (.+)$") then
    local name = line:match("^status (.+)$")
    local utbl = cmd("unit.get()")
    if type(utbl) == "table" then
      for u, chests in pairs(utbl) do
        if type(chests) == "table" then
          for _, c in ipairs(chests) do
            if c:find(name, 1, true) then print("  " .. u .. ": " .. c) end
          end
        end
      end
    end
  elseif line:match("^search(.*)") then
    local q = line:match("^search%((.*)%)$") or ""
    if q == "" then q = "." end
    local r = cmd('search("' .. q:gsub('"', '\\"') .. '")')
    if type(r) == "table" then
      local n = 0
      for k, v in pairs(r) do
        if not dumpItems[k] then
          print("  " .. k:gsub("^minecraft:", "") .. " x" .. v)
          n = n + 1
        end
      end
      print(n .. " items encontrados (dump oculto)")
    else
      print("Error/Timeout: " .. tostring(r))
    end
  elseif line == "searchall" then
    local r = cmd('search(".")')
    if type(r) == "table" then
      local n = 0
      for k, v in pairs(r) do
        print("  " .. k:gsub("^minecraft:", "") .. " x" .. v)
        n = n + 1
      end
      print(n .. " items totales (incluye dump)")
    else
      print("Error/Timeout: " .. tostring(r))
    end
  elseif line:match("^add ") then
    local chest = line:match("^add (.+)$")
    if chest then
      cmd('unit.add("storage",{"' .. chest:gsub('"', '\\"') .. '"})')
      local r = cmd("scan(units.storage)")
      print("Anadido " .. chest .. " a storage: " .. tostring(r))
    end
  elseif line:match("^adddump ") then
    local chest = line:match("^adddump (.+)$")
    if chest then
      cmd('unit.add("dump",{"' .. chest:gsub('"', '\\"') .. '"})')
      cmd("scan(units.dump)")
      refreshDumpItems()
      print("Anadido " .. chest .. " a dump")
    end
  elseif line:match("^remove ") then
    local args = line:match("^remove (.+)$")
    if args then
      local unitType, chest = args:match("^(%S+) (.+)$")
      if unitType and chest then
        cmd('unit.remove("' .. unitType:gsub('"', '\\"') .. '",{"' .. chest:gsub('"', '\\"') .. '"})')
        print("Eliminado " .. chest .. " de " .. unitType)
        if unitType == "dump" then refreshDumpItems() end
      else print("Uso: remove <storage|dump> <nombre_cofre>") end
    end
  elseif line == "dump" then
    cmd("scan(units.dump)")
    local r = cmd("move_item(units.dump, units.storage)")
    print("Dump -> Storage: " .. tostring(r))
    cmd("scan(units.storage)")
    refreshDumpItems()
  elseif line:match("^get ") then
    local item = line:match("^get (.+)$")
    if item then
      local utbl = cmd("unit.get()")
      if type(utbl) ~= "table" or type(utbl.dump) ~= "table" or #utbl.dump == 0 then
        print("ERROR: units.dump no tiene chests. Usa 'adddump <cofre>' primero.")
      else
        cmd("scan(units.storage)")
        local r = cmd('move_item(units.storage, units.dump, "' .. item:gsub(' ', '_'):gsub('"', '\\"') .. '")')
        print("Storage -> Dump: " .. tostring(r))
        refreshDumpItems()
      end
    end
  elseif line == "setup" then
    local r1 = cmd('unit.is_io("dump", false)')
    print("unit.is_io(dump, false): " .. tostring(r1))
    print("REINICIA el servidor para limpiar cache de busqueda.")
  elseif line:match("%(") then
    local r = cmd(line)
    if type(r) == "table" then
      print(textutils.serialize(r))
    else
      print(tostring(r))
    end
  else
    print("Comandos:")
    print("  scan            - escanea storage+dump+undefined")
    print("  status          - muestra configuracion de units")
    print("  search          - lista items (oculta dump)")
    print("  searchall       - lista todos los items (incluye dump)")
    print("  add <cofre>     - anyade cofre a storage y escanea")
    print("  adddump <cofre> - anyade cofre a dump y escanea")
    print("  dump            - mueve items de dump a storage")
    print("  get <item>      - mueve items de storage a dump")
    print("  remove <t> <c>  - elimina cofre de unit")
    print("  setup           - oculta dump de busquedas (1 vez)")
    print("  q               - salir")
  end
end

if fh then fh.close() end
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("CLI cerrado. Log: " .. logFile)
