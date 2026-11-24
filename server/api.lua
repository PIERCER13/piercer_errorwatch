-- Leituras e acoes usadas pela NUI in-game (ingame.lua). O painel web le os arquivos de data/
-- (tools/start.bat) e envia acoes pela fila em commands.json. Ambos montam o resumo no JS.
Api = {}

local function data(limit)
    local out = {}
    for i = #Store.list, 1, -1 do
        out[#out + 1] = Store.list[i]
    end
    table.sort(out, function(a, b) return a.last > b.last end)
    if limit and #out > limit then
        for i = #out, limit + 1, -1 do out[i] = nil end
    end
    return {
        errors = out,
        state = {
            t = os.time(), session = Store.session, startedAt = Store.startedAt,
            players = GetNumPlayerIndices(), total = #Store.list, locale = Config.Locale,
        },
    }
end

-- Retorna (httpCode, tabela). `args` = { action=, args= } para /api/action.
function Api.handle(path, method, limit, args)
    if path == '/api/data' and method == 'GET' then
        return 200, data(limit)
    elseif path == '/api/resources' and method == 'GET' then
        return 200, Injector.get()
    elseif path == '/api/action' and method == 'POST' then
        local ok, msg, parts = Actions.run(type(args) == 'table' and args.action, type(args) == 'table' and args.args, 'ingame')
        return 200, { ok = ok, msg = msg, parts = parts }
    end
    return 404, { error = 'not found' }
end
