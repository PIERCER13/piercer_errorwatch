Collector = { buffer = {}, viewers = {}, newPending = {} }

local startMs = GetGameTimer()
local parser = Parser.new()
local changed = false

function Collector.ingest(side, g, who, times)
    local boot = side == 'server' and (GetGameTimer() - startMs) <= Config.BootSeconds * 1000
    local e, isNew = Store.upsert(side, g, who, times, boot)
    changed = true
    if isNew and not e.muted then
        Collector.newPending[#Collector.newPending + 1] = e
    end
end

RegisterConsoleListener(function(channel, message)
    local b = Collector.buffer
    if #b < 3000 then b[#b + 1] = { channel, message, GetGameTimer() } end
end)

CreateThread(function()
    while true do
        Wait(200)
        local b = Collector.buffer
        if #b > 0 then
            Collector.buffer = {}
            for _, x in ipairs(b) do
                local ok, err = pcall(parser.push, parser, x[1], x[2], x[3])
                if not ok then Utils.log(T('log.parser_err', tostring(err))) end
            end
        end
        for _, g in ipairs(parser:poll(GetGameTimer())) do
            local ok, err = pcall(Collector.ingest, 'server', g)
            if not ok then Utils.log(T('log.ingest_err', tostring(err))) end
        end
    end
end)

local rate = {}

local function cleanName(s, max)
    if type(s) ~= 'string' then return nil end
    s = s:sub(1, max)
    return s
end

RegisterNetEvent('piercer_errorwatch:clientReport', function(batch)
    local src = source
    if not ConfigShared.client.enabled or type(batch) ~= 'table' then return end

    local now = GetGameTimer()
    local r = rate[src]
    if not r or now - r.t > 10000 then r = { t = now, n = 0 }; rate[src] = r end

    local who = GetPlayerName(src) or ('id ' .. tostring(src))
    local limit = math.min(#batch, ConfigShared.client.maxPerBatch)
    for i = 1, limit do
        local it = batch[i]
        if r.n >= Config.Client.maxPer10s then break end
        if type(it) == 'table' and type(it.message) == 'string' and it.message ~= '' then
            r.n = r.n + 1
            local res = cleanName(it.resource, 64)
            if not (res and res:match('^[%w_%-%.]+$')) then res = '(unknown)' end
            local times = math.max(1, math.min(50, math.floor(tonumber(it.count) or 1)))
            pcall(Collector.ingest, 'client', {
                level = it.level == 'warn' and 'warn' or 'error',
                message = Parser.truncate(it.message, 300),
                detail = Parser.truncate(type(it.detail) == 'string' and it.detail or '', 2000),
                resource = res,
                location = cleanName(it.location, 120),
                channel = 'client',
            }, who, times)
        end
    end
end)

AddEventHandler('playerDropped', function()
    rate[source] = nil
    Collector.viewers[source] = nil
end)

exports('Report', function(message, detail, resource)
    if type(message) ~= 'string' or message == '' then return false end
    local res = type(resource) == 'string' and resource:match('^[%w_%-%.]+$') and resource
        or GetInvokingResource() or '(unknown)'
    Collector.ingest('server', {
        level = 'error',
        message = Parser.truncate(message, 300),
        detail = Parser.truncate(type(detail) == 'string' and detail or '', 2000),
        resource = res,
        channel = 'export',
    })
    return true
end)

CreateThread(function()
    while true do
        Wait(1000)
        if changed then
            changed = false
            for src in pairs(Collector.viewers) do
                TriggerClientEvent('piercer_errorwatch:changed', src)
            end
        end
    end
end)

CreateThread(function()
    local n = Config.Notify
    while n.enabled do
        Wait(n.cooldown * 1000)
        local list = Collector.newPending
        if #list > 0 then
            Collector.newPending = {}
            local errs, top = 0, nil
            for _, e in ipairs(list) do
                if e.level == 'error' or n.includeWarnings then
                    errs = errs + 1
                    top = top or e
                end
            end
            if errs > 0 then
                local text = errs == 1
                    and T('notify.new_error', top.resource, Parser.truncate(top.message, 80))
                    or T('notify.new_errors', errs, top.resource)
                for _, id in ipairs(GetPlayers()) do
                    local src = tonumber(id)
                    if src and Auth.isAllowed(src) then Auth.notify(src, 'error', text) end
                end
            end
        end
    end
end)
