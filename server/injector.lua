Injector = { cache = {}, cachedAt = 0, ignored = {}, applied = {} }

local RES = GetCurrentResourceName()
local SETTINGS_FILE, OUT_FILE = 'data/injector.json', 'data/resources.json'
local BEGIN_MARK, END_MARK = '-- piercer_errorwatch:begin', '-- piercer_errorwatch:end'
local SHIM_LINE = ("client_script '@%s/shim.lua'"):format(RES)
local SHIM_REF = RES .. '/shim.lua'
local MANIFESTS = { 'fxmanifest.lua', '__resource.lua' }
local MAX_NAMES = 300

local protectedSet, protectedGroups = { [RES] = true }, {}
for _, n in ipairs(Config.Injector.protected or {}) do protectedSet[n] = true end
for _, g in ipairs(Config.Injector.protectedGroups or {}) do protectedGroups[g] = true end

local scanning, rescanQueued = false, false

local function validName(s)
    return type(s) == 'string' and #s > 0 and #s <= 64 and s:match('^[%w_%-%.]+$') ~= nil
end
Injector.validName = validName
Injector.maxNames = MAX_NAMES

local function saveSettings()
    SaveResourceFile(RES, SETTINGS_FILE, json.encode({ ignored = Injector.ignored, applied = Injector.applied }), -1)
end

local function loadSettings()
    local raw = LoadResourceFile(RES, SETTINGS_FILE)
    if not raw or raw == '' then return end
    local ok, d = pcall(json.decode, raw)
    if ok and type(d) == 'table' then
        Injector.ignored = type(d.ignored) == 'table' and d.ignored or {}
        Injector.applied = type(d.applied) == 'table' and d.applied or {}
    end
end

local function manifestOf(name)
    for _, f in ipairs(MANIFESTS) do
        local t = LoadResourceFile(name, f)
        if t and t ~= '' then return f, t end
    end
end

local function groupOf(path)
    local rel = tostring(path or ''):gsub('\\', '/'):match('.*/resources/(.+)$')
    if not rel then return nil end
    local segs = {}
    for s in rel:gmatch('[^/]+') do segs[#segs + 1] = s end
    for i = #segs - 1, 1, -1 do
        local g = segs[i]:match('^%[(.+)%]$')
        if g then return g end
    end
    return nil
end

local function hasClientScript(text)
    local s = text:gsub('%-%-%[%[.-%]%]', ''):gsub('%-%-[^\n]*', '')
    return s:find('client_scripts?%f[^%w_]') ~= nil
end

local function analyze(name)
    local row = { name = name, state = GetResourceState(name), ignored = Injector.ignored[name] or nil }
    local group = groupOf(GetResourcePath(name))
    row.group = group
    local isProtected = protectedSet[name] or (group and protectedGroups[group]) or false

    local file, text = manifestOf(name)
    if not file then row.status = 'nomanifest'; return row end
    row.file = file

    if LoadResourceFile(name, '.fxap') then row.status = 'escrow'; return row end 

    if text:find(BEGIN_MARK, 1, true) then row.status = 'applied'
    elseif text:find(SHIM_REF, 1, true) then row.status = 'manual'
    elseif isProtected then row.status = 'protected'
    elseif not hasClientScript(text) then row.status = 'noclient'
    else row.status = 'ready' end
    return row
end

function Injector.payload()
    return {
        t = Injector.cachedAt, resources = Injector.cache,
        enabled = Config.Injector.enabled, allowRestart = Config.Injector.allowRestart,
        allowFromWeb = Config.Injector.allowFromWeb,
    }
end

function Injector.scan()
    if scanning then rescanQueued = true; return end  
    scanning = true
    local ok, err = pcall(function()
        local rows = {}
        for i = 0, GetNumResources() - 1 do
            local name = GetResourceByFindIndex(i)
            if name then
                local okA, row = pcall(analyze, name)
                if okA then rows[#rows + 1] = row end
            end
            if i % 40 == 39 then Wait(0) end
        end
        table.sort(rows, function(a, b) return a.name:lower() < b.name:lower() end)
        Injector.cache, Injector.cachedAt = rows, os.time()
        SaveResourceFile(RES, OUT_FILE, json.encode(Injector.payload()), -1)
    end)
    scanning = false
    if not ok then Utils.log(T('log.scan_err', tostring(err))) end
    if rescanQueued then
        rescanQueued = false
        Injector.scan()
    end
end

function Injector.get()
    if os.time() - Injector.cachedAt > 30 then Injector.scan() end
    return Injector.payload()
end

local function insertBlock(file, text, eol, block)
    if file == 'fxmanifest.lua' then
        local pos = 1
        while pos <= #text do
            local nl = text:find('\n', pos, true)
            local line = text:sub(pos, nl or #text)
            if line:match('^%s*fx_version') then
                if nl then return text:sub(1, nl) .. block .. text:sub(nl + 1) end
                return text .. eol .. block
            end
            if not nl then break end
            pos = nl + 1
        end
    end
    return block .. text
end

local function applyOne(name)
    if GetResourceState(name) == 'missing' then return false, 'inj.r_missing' end
    local row = analyze(name)
    if row.ignored then return false, 'inj.r_ignored' end
    if row.status ~= 'ready' then return false, 'inj.r_' .. row.status end

    local file, text = manifestOf(name)
    if not file then return false, 'inj.r_nomanifest' end
    local eol = text:find('\r\n', 1, true) and '\r\n' or '\n'

    local bak = file .. '.errorwatch.bak'
    if not LoadResourceFile(name, bak) and not SaveResourceFile(name, bak, text, -1) then
        return false, 'inj.r_backup'
    end

    local block = BEGIN_MARK .. eol .. SHIM_LINE .. eol .. END_MARK .. eol
    if not SaveResourceFile(name, file, insertBlock(file, text, eol, block), -1) then
        return false, 'inj.r_write'
    end
    local check = LoadResourceFile(name, file)
    if not check or not check:find(BEGIN_MARK, 1, true) then
        SaveResourceFile(name, file, text, -1)   -- desfaz
        return false, 'inj.r_verify'
    end
    Injector.applied[name] = { at = os.time() }
    return true
end

local function revertOne(name)
    if GetResourceState(name) == 'missing' then return false, 'inj.r_missing' end
    local file, text = manifestOf(name)
    if not file then return false, 'inj.r_nomanifest' end
    if not text:find(BEGIN_MARK, 1, true) then return false, 'inj.r_nomarker' end
    local new = text:gsub('[ \t]*%-%- piercer_errorwatch:begin.-%-%- piercer_errorwatch:end[ \t]*\r?\n?', '')
    if not SaveResourceFile(name, file, new, -1) then return false, 'inj.r_write' end
    local check = LoadResourceFile(name, file)
    if not check or check:find(BEGIN_MARK, 1, true) then
        SaveResourceFile(name, file, text, -1)
        return false, 'inj.r_verify'
    end
    Injector.applied[name] = nil
    return true
end

local function batch(names, fn, restart, doneKey)
    local done, failed, okNames, seen = 0, {}, {}, {}
    for _, n in ipairs(names) do
        if validName(n) and not seen[n] then
            seen[n] = true
            local okc, ok, why = pcall(fn, n)
            if okc and ok then
                done = done + 1
                okNames[#okNames + 1] = n
            else
                local reason = (okc and type(why) == 'string') and why or 'inj.r_internal'
                failed[#failed + 1] = P('inj.fail_item', n, '~' .. reason)
            end
        end
    end

    local restarted = false
    if done > 0 then
        saveSettings()
        ExecuteCommand('refresh')
        if restart and Config.Injector.allowRestart then
            restarted = true
            Wait(800)
            for _, n in ipairs(okNames) do
                if GetResourceState(n) == 'started' then
                    ExecuteCommand('restart ' .. n)
                    Wait(400)
                end
            end
        end
    end
    Injector.scan()

    if done == 0 and #failed == 0 then return false, { P('inj.none') } end
    local parts = { P(doneKey, done) }
    if #failed > 0 then
        local show = {}
        for i = 1, math.min(4, #failed) do show[i] = failed[i] end
        parts[#parts + 1] = P('inj.failures', #failed, { join = show, sep = ', ', more = #failed > 4 })
    end
    if done > 0 and not restarted then parts[#parts + 1] = P('inj.restart_hint') end
    return #failed == 0, parts
end

function Injector.applyMany(names, restart) return batch(names, applyOne, restart, 'inj.applied_n') end
function Injector.revertMany(names, restart) return batch(names, revertOne, restart, 'inj.removed_n') end

function Injector.toggleIgnore(name)
    if not validName(name) or GetResourceState(name) == 'missing' then return false, P('inj.invalid') end
    Injector.ignored[name] = (not Injector.ignored[name]) or nil
    saveSettings()
    Injector.scan()
    return true, P(Injector.ignored[name] and 'inj.ignored' or 'inj.unignored', name)
end

CreateThread(function()
    loadSettings()
    Wait(2000)   
    Injector.scan()
    while true do
        Wait(120000)
        Injector.scan()
    end
end)
