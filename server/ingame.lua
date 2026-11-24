RegisterNetEvent('piercer_errorwatch:open', function()
    local src = source
    if Auth.isAllowed(src) then
        Collector.viewers[src] = true
        TriggerClientEvent('piercer_errorwatch:open', src)
    else
        Auth.notify(src, 'error', T('notify.no_permission'))
    end
end)

RegisterNetEvent('piercer_errorwatch:closed', function()
    Collector.viewers[source] = nil
end)

RegisterNetEvent('piercer_errorwatch:rpc', function(id, path, method, args)
    local src = source
    if not Auth.isAllowed(src) or type(path) ~= 'string' or type(method) ~= 'string' then
        return TriggerClientEvent('piercer_errorwatch:rpcResult', src, id, { error = 'unauthorized' }, 401)
    end
    if args ~= nil and type(args) ~= 'table' then args = nil end
    local code, body = Api.handle(path, method, Config.IngameLimit, args)
    TriggerClientEvent('piercer_errorwatch:rpcResult', src, id, body, code)
end)

RegisterCommand('errorwatch_status', function(src)
    if src ~= 0 then return end
    local errs, warns = 0, 0
    for _, e in ipairs(Store.list) do
        if e.level == 'error' then errs = errs + 1 else warns = warns + 1 end
    end
    Utils.log(T('log.status', errs, warns))
end, true)
