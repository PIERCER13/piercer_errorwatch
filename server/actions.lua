-- Acoes remotas. Duas entradas, mesma whitelist:
--   1) NUI in-game  -> Actions.run (apos checar permissao em Auth)
--   2) Painel web   -> fila data/commands.json (o painel escreve, este resource le a cada ~2s)
-- Nada aqui executa texto livre: so as acoes de `handlers`, com argumentos validados.
-- Cada handler devolve (ok, trecho) onde trecho = P('chave', params...) (ver server/i18n.lua).
Actions = {}

local RES = GetCurrentResourceName()
local handlers = {}

local function findEntry(id)
    if type(id) ~= 'string' or not id:match('^%x+$') then return nil end
    return Store.index[id]
end

handlers.clear = function()
    Store.clear()
    Store.save()
    return true, P('act.cleared')
end

handlers.resolve = function(args)
    local e = findEntry(args.id)
    if not e then return false, P('act.not_found') end
    e.resolved = (not e.resolved) or nil
    Store.dirty = true
    return true, P(e.resolved and 'act.resolved' or 'act.reopened')
end

handlers.resolve_all = function()
    local n = 0
    for _, e in ipairs(Store.list) do
        if not e.resolved then e.resolved = true; n = n + 1 end
    end
    Store.dirty = true
    return true, P('act.resolved_n', n)
end

handlers.mute = function(args)
    local e = findEntry(args.id)
    if not e then return false, P('act.not_found') end
    e.muted = (not e.muted) or nil
    Store.dirty = true
    return true, P(e.muted and 'act.muted' or 'act.unmuted')
end

handlers.export = function()
    local file = ('data/report-%s.json'):format(os.date('%Y%m%d-%H%M%S'))
    local ok = SaveResourceFile(RES, file, json.encode(Store.list, { indent = true }), -1)
    if not ok then return false, P('act.export_fail') end
    return true, P('act.exported', ('%s/%s'):format(RES, file))
end

-- Gera um erro de teste no console para validar a captura de ponta a ponta.
handlers.test = function()
    print('^1SCRIPT ERROR: @piercer_errorwatch/teste.lua:1: ' .. T('test.message'))
    print('> test_function (@piercer_errorwatch/teste.lua:1)')
    return true, P('act.test_sent')
end

---------------------------------------------------------------------
-- Injecao do shim (ver server/injector.lua)
---------------------------------------------------------------------
local function injectorGuard(origin)
    if not Config.Injector.enabled then return false, P('inj.disabled') end
    if origin == 'web' and not Config.Injector.allowFromWeb then
        return false, P('inj.web_disabled')
    end
    return true
end

local function namesFrom(args)
    local out = {}
    if type(args.names) == 'table' then
        for i = 1, math.min(#args.names, Injector.maxNames) do out[#out + 1] = args.names[i] end
    elseif type(args.resource) == 'string' then
        out[1] = args.resource
    end
    return out
end

handlers.inj_apply = function(args, origin)
    local ok, msg = injectorGuard(origin)
    if not ok then return false, msg end
    return Injector.applyMany(namesFrom(args), args.restart == true)
end

handlers.inj_revert = function(args, origin)
    local ok, msg = injectorGuard(origin)
    if not ok then return false, msg end
    return Injector.revertMany(namesFrom(args), args.restart == true)
end

handlers.inj_ignore = function(args, origin)
    local ok, msg = injectorGuard(origin)
    if not ok then return false, msg end
    return Injector.toggleIgnore(args.resource)
end

handlers.inj_rescan = function()
    Injector.scan()
    return true, P('inj.rescanned')
end

-- Retorna (ok, msg no idioma do servidor, parts para a NUI traduzir). `origin` = 'ingame' | 'web'
function Actions.run(action, args, origin)
    local fn = type(action) == 'string' and handlers[action]
    if not fn then
        local p = P('act.unknown')
        return false, I18n.text(p), { p }
    end
    if type(args) ~= 'table' then args = {} end
    local ok, a, b = pcall(fn, args, origin or 'ingame')
    if not ok then
        local p = P('act.error', tostring(a))
        return false, I18n.text(p), { p }
    end
    local parts = b
    if type(parts) == 'table' and parts.key then parts = { parts } end
    return a == true, parts and I18n.text(parts) or nil, parts
end

---------------------------------------------------------------------
-- Fila de comandos do painel web (arquivos)
---------------------------------------------------------------------
local CMD_FILE, RES_FILE = 'data/commands.json', 'data/results.json'
local COMMAND_TTL = 60
local seen, results, order = {}, {}, {}

local function readCommands()
    local raw = LoadResourceFile(RES, CMD_FILE)
    if not raw or raw == '' then return {} end
    local ok, list = pcall(json.decode, raw)
    return (ok and type(list) == 'table') and list or {}
end

local function record(id, ok, msg, parts)
    results[id] = { ok = ok, msg = msg, parts = parts, t = os.time() }
    order[#order + 1] = id
    while #order > 50 do results[table.remove(order, 1)] = nil end
    SaveResourceFile(RES, RES_FILE, json.encode(results), -1)
end

CreateThread(function()
    Wait(3000)
    for _, c in ipairs(readCommands()) do   -- o que ja estava na fila antes de subir nao roda
        if type(c) == 'table' and type(c.id) == 'string' then seen[c.id] = true end
    end
    while true do
        for _, c in ipairs(readCommands()) do
            if type(c) == 'table' and type(c.id) == 'string' and not seen[c.id] then
                seen[c.id] = true
                local age = os.time() - (tonumber(c.at) or 0)
                if age > COMMAND_TTL or age < -30 then
                    local p = P('act.expired')
                    record(c.id, false, I18n.text(p), { p })
                else
                    local ok, msg, parts = Actions.run(c.action, c.args, 'web')
                    record(c.id, ok, msg, parts)
                end
            end
        end
        Wait(2000)
    end
end)
