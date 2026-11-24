I18n = {}

local RES = GetCurrentResourceName()

local function loadFile(code)
    code = tostring(code or ''):lower()
    if not code:match('^[%a%-]+$') then return {} end
    local raw = LoadResourceFile(RES, ('locales/%s.json'):format(code))
    if raw and raw ~= '' then
        local ok, d = pcall(json.decode, raw)
        if ok and type(d) == 'table' then return d end
    end
    return {}
end

local dict, fallback = loadFile(Config.Locale), loadFile('en')

local render

function I18n.t(key, ...)
    local tpl = dict[key] or fallback[key] or key
    local args = { ... }
    return (tpl:gsub('{(%d+)}', function(i) return render(args[tonumber(i)]) end))
end

render = function(v)
    if v == nil then return '' end
    local tv = type(v)
    if tv == 'string' then
        if v:sub(1, 1) == '~' then return I18n.t(v:sub(2)) end
        return v
    elseif tv == 'table' then
        if v.join then
            local out = {}
            for _, p in ipairs(v.join) do out[#out + 1] = render(p) end
            return table.concat(out, v.sep or ', ') .. (v.more and '...' or '')
        elseif v.key then
            return I18n.t(v.key, table.unpack(v.params or {}))
        end
    end
    return tostring(v)
end

function I18n.part(key, ...)
    return { key = key, params = { ... } }
end

function I18n.text(parts)
    if type(parts) ~= 'table' then return tostring(parts or '') end
    if parts.key then parts = { parts } end
    local out = {}
    for _, p in ipairs(parts) do out[#out + 1] = render(p) end
    return table.concat(out)
end

T = I18n.t
P = I18n.part
