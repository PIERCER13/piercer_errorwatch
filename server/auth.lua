-- Permissao e notificacao via framezero_bridge (vRP, QBCore, Qbox, ESX, OxCore, TNet, Standalone...).
Auth = {}

local function lower(s) return tostring(s):lower() end

local function listHas(list, fn)
    if type(list) ~= 'table' then return false end
    for _, v in ipairs(list) do
        local ok, res = pcall(fn, tostring(v))
        if ok and res then return true end
    end
    return false
end

function Auth.isAllowed(src)
    src = tonumber(src)
    if not src then return false end
    if src == 0 then return true end -- console

    local p = Config.Permissions

    if listHas(p.bridge, function(perm) return framezero.HasPermission(src, perm) end) then
        return true
    end

    if listHas(p.ace, function(ace) return IsPlayerAceAllowed(src, ace) end) then
        return true
    end

    if type(p.identifiers) == 'table' and #p.identifiers > 0 then
        for _, id in ipairs(GetPlayerIdentifiers(src)) do
            for _, allowed in ipairs(p.identifiers) do
                if lower(id) == lower(allowed) then return true end
            end
        end
    end

    return false
end

function Auth.notify(src, kind, message)
    local ok = pcall(framezero.Notify, src, kind, message, 6000)
    if not ok then
        TriggerClientEvent('chat:addMessage', src, { args = { 'errorwatch', message } })
    end
end

CreateThread(function()
    if framezero.WaitReady(15000) then
        local info = (framezero.Info and framezero.Info()) or {}
        Utils.log(T('log.bridge_ready', '^3' .. tostring(info.framework or '?') .. '^7'))
    else
        Utils.log('^3' .. T('log.bridge_timeout') .. '^7')
    end
end)
