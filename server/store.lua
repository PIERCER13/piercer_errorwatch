Store = { list = {}, index = {}, dirty = false }

local RES = GetCurrentResourceName()
local ERRORS_FILE, STATE_FILE = 'data/errors.json', 'data/state.json'

Store.session = os.time() 
Store.startedAt = os.time()

local function rebuildIndex()
    Store.index = {}
    for _, e in ipairs(Store.list) do Store.index[e.id] = e end
end

function Store.load()
    local raw = LoadResourceFile(RES, ERRORS_FILE)
    if raw and raw ~= '' then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == 'table' then
            Store.list = data
            rebuildIndex()
            return
        end
    end
    Store.list, Store.index = {}, {}
end

function Store.writeState(clean)
    local st = {
        t = os.time(), clean = clean == true,
        session = Store.session, startedAt = Store.startedAt,
        players = GetNumPlayerIndices(), locale = Config.Locale,
    }
    SaveResourceFile(RES, STATE_FILE, json.encode(st), -1)
end

function Store.save()
    SaveResourceFile(RES, ERRORS_FILE, json.encode(Store.list), -1)
    Store.dirty = false
end

local function trim()
    while #Store.list > Config.MaxEntries do
        local pick, pickScore
        for i, e in ipairs(Store.list) do
            local score = e.last - ((e.resolved or e.muted) and 1e10 or 0)
            if not pickScore or score < pickScore then pick, pickScore = i, score end
        end
        local gone = table.remove(Store.list, pick)
        Store.index[gone.id] = nil
    end
end

function Store.upsert(side, g, who, times, boot)
    local now = os.time()
    local resource = g.resource or '(unknown)'
    local id = Parser.id(side, resource, g.message)
    times = times or 1

    local e = Store.index[id]
    if e then
        if e.session ~= Store.session then e.runCount = 0 end
        e.session = Store.session
        e.count = e.count + times
        e.runCount = (e.runCount or 0) + times
        e.last = now
        e.level = g.level == 'error' and 'error' or e.level
        if g.detail and g.detail ~= '' then e.detail = g.detail end
        if g.location then e.location = g.location end
        if e.resolved and Config.ReopenResolved then e.resolved = nil end
        if boot and not e.boot then e.boot = true end
    else
        e = {
            id = id, side = side, level = g.level, resource = resource,
            message = g.message, detail = g.detail or '', location = g.location,
            channel = g.channel, count = times, runCount = times,
            first = now, last = now, session = Store.session, boot = boot or nil,
        }
        Store.list[#Store.list + 1] = e
        Store.index[id] = e
        trim()
    end

    if who then
        e.who = e.who or {}
        local known = false
        for _, n in ipairs(e.who) do if n == who then known = true break end end
        if not known and #e.who < 10 then e.who[#e.who + 1] = who end
    end

    Store.dirty = true
    return e, e.count == times
end

function Store.clear()
    Store.list, Store.index = {}, {}
    Store.dirty = true
end

CreateThread(function()
    Store.load()
    Store.writeState(false)
    while true do
        Wait(Config.SaveIntervalMs)
        if Store.dirty then pcall(Store.save) end
        pcall(Store.writeState, false)
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == RES then
        pcall(Store.save)
        pcall(Store.writeState, true)
    end
end)
AddEventHandler('txAdmin:events:serverShuttingDown', function()
    pcall(Store.save)
    pcall(Store.writeState, true)
end)
