local RES = GetCurrentResourceName()
local C = ConfigShared.client

---------------------------------------------------------------------
-- Reports de erro do client -> servidor (em lotes, deduplicados)
-- Fontes: shim.lua (evento local), export Report.
---------------------------------------------------------------------
local queue, byKey = {}, {}

local function enqueue(e)
    if not C.enabled or type(e) ~= 'table' or type(e.message) ~= 'string' or e.message == '' then return end
    local resource = type(e.resource) == 'string' and e.resource or 'unknown'
    local message = Parser.truncate(e.message, 300)
    local key = resource .. '|' .. message
    local hit = byKey[key]
    if hit then
        hit.count = hit.count + 1
        return
    end
    if #queue >= C.maxPerBatch then return end
    local item = {
        level = e.level == 'warn' and 'warn' or 'error',
        message = message,
        detail = Parser.truncate(type(e.detail) == 'string' and e.detail or '', 2000),
        resource = resource,
        location = type(e.location) == 'string' and Parser.truncate(e.location, 120) or nil,
        count = 1,
    }
    queue[#queue + 1] = item
    byKey[key] = item
end

AddEventHandler('piercer_errorwatch:clientReport', enqueue)

exports('Report', function(message, detail, resource)
    enqueue({
        message = tostring(message), detail = detail,
        resource = resource or GetInvokingResource() or 'unknown',
    })
end)

CreateThread(function()
    while true do
        Wait(C.flushMs)
        if #queue > 0 then
            local batch = queue
            queue, byKey = {}, {}
            TriggerServerEvent('piercer_errorwatch:clientReport', batch)
        end
    end
end)

---------------------------------------------------------------------
-- NUI
---------------------------------------------------------------------
local isOpen = false
local pending, counter = {}, 0

local function setOpen(state)
    isOpen = state
    SetNuiFocus(state, state)
    SendNUIMessage({ action = state and 'open' or 'close' })
    if not state then TriggerServerEvent('piercer_errorwatch:closed') end
end

RegisterCommand('errorwatch', function()
    if isOpen then return setOpen(false) end
    TriggerServerEvent('piercer_errorwatch:open')
end, false)

RegisterNetEvent('piercer_errorwatch:open', function()
    setOpen(true)
end)

RegisterNetEvent('piercer_errorwatch:changed', function()
    if isOpen then SendNUIMessage({ action = 'changed' }) end
end)

RegisterNUICallback('close', function(_, cb)
    setOpen(false)
    cb({})
end)

-- A NUI pede dados; repassamos ao servidor e devolvemos a resposta.
RegisterNUICallback('rpc', function(data, cb)
    counter = counter + 1
    local id = counter
    pending[id] = cb
    TriggerServerEvent('piercer_errorwatch:rpc', id, data.path, data.method, data.args)
    SetTimeout(15000, function()
        if pending[id] == cb then
            pending[id] = nil
            cb({ __status = 504, error = 'timeout' })
        end
    end)
end)

RegisterNetEvent('piercer_errorwatch:rpcResult', function(id, body, code)
    local cb = pending[id]
    if not cb then return end
    pending[id] = nil
    cb({ __status = code, data = body })
end)

AddEventHandler('onResourceStop', function(name)
    if name == RES and isOpen then
        SetNuiFocus(false, false)
    end
end)
