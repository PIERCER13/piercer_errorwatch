if IsDuplicityVersion() then return end

local resName = GetCurrentResourceName()
if resName == 'piercer_errorwatch' then return end

local function report(err, tb)
    local text = tostring(err)
    local ok = pcall(TriggerEvent, 'piercer_errorwatch:clientReport', {
        message = text,
        detail = tb,
        resource = resName,
        location = text:match('([%w_%-%.]+%.lua:%d+)'),
    })
    return ok
end

local function onError(err)
    return { err = err, tb = debug.traceback('', 2) }
end

local function guard(fn)
    if type(fn) ~= 'function' then return fn end
    return function(...)
        local r = table.pack(xpcall(fn, onError, ...))
        if r[1] then return table.unpack(r, 2, r.n) end
        report(r[2].err, r[2].tb)
        error(r[2].err, 0)
    end
end

local function wrap(name, argIndex, tbl)
    tbl = tbl or _G
    local orig = tbl[name]
    if type(orig) ~= 'function' then return end
    tbl[name] = function(...)
        local args = table.pack(...)
        if type(args[argIndex]) == 'function' then args[argIndex] = guard(args[argIndex]) end
        return orig(table.unpack(args, 1, args.n))
    end
end

wrap('CreateThread', 1)
wrap('SetTimeout', 2)
wrap('AddEventHandler', 2)
wrap('RegisterNetEvent', 2)
wrap('RegisterCommand', 2)
wrap('RegisterNUICallback', 2)
if type(Citizen) == 'table' then
    wrap('CreateThread', 1, Citizen)
    wrap('SetTimeout', 2, Citizen)
end
