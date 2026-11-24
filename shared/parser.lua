Parser = {}
Parser.__index = Parser

local C = ConfigShared

function Parser.strip(s)
    s = tostring(s or '')
    s = s:gsub('%^%d', '')
    return s
end

function Parser.truncate(s, n)
    s = tostring(s or '')
    if #s > n then return s:sub(1, n) end
    return s
end

local function hash(s, seed, mul)
    local h = seed
    for i = 1, #s do
        h = (h * mul + s:byte(i)) & 0xFFFFFFFF
    end
    return h
end

function Parser.id(side, resource, message)
    local norm = tostring(message or ''):lower()
    norm = norm:gsub('0x%x+', '0x#')
    norm = norm:gsub('%d+', '#')
    local key = side .. '|' .. tostring(resource) .. '|' .. norm
    return ('%08x%08x'):format(hash(key, 5381, 33), hash(key, 52711, 131))
end

local function matchAny(list, s)
    for _, p in ipairs(list) do
        if s:find(p) then return true end
    end
    return false
end

local function classify(raw, line, lower)
    if matchAny(C.ignore, lower) then return nil end
    if matchAny(C.errorPatterns, lower) then return 'error' end
    if C.redIsError and raw:find('%^1') then return 'error' end
    if C.captureWarnings and matchAny(C.warnPatterns, lower) then return 'warn' end
    return nil
end

local function isContinuation(line, lower)
    if line:match('^%s') or line:match('^>') or line:match('^%[C%]') then return true end
    if lower:find('^stack traceback') then return true end
    for _, k in ipairs({ 'in function', 'in upvalue', 'in local', 'in method', 'in field', 'tail call' }) do
        if lower:find(k, 1, true) then return true end
    end
    return false
end

local function finalize(g)
    local text = table.concat(g.lines, '\n')
    local resource = text:match('@([%w_%-%.]+)/')
        or text:match('[Ii]n resource ([%w_%-%.]+)')
        or text:match("resource '([%w_%-%.]+)'")
        or (g.channel and tostring(g.channel):match('^script:([%w_%-%.]+)$'))
    local file, ln = text:match('@[%w_%-%.]+/([^%s:%)]+):(%d+)')

    local message = g.lines[1]:gsub('^SCRIPT ERROR:%s*', '')
    local rest = {}
    for i = 2, #g.lines do rest[#rest + 1] = g.lines[i] end

    return {
        level = g.level,
        message = Parser.truncate(message, 300),
        detail = Parser.truncate(table.concat(rest, '\n'), 2000),
        resource = resource,
        location = file and (file .. ':' .. ln) or nil,
        channel = g.channel and tostring(g.channel) or nil,
    }
end

function Parser.new()
    return setmetatable({ cur = nil, done = {} }, Parser)
end

function Parser:flush()
    if self.cur then
        if #self.done < 500 then self.done[#self.done + 1] = finalize(self.cur) end
        self.cur = nil
    end
end

function Parser:push(channel, msg, t)
    for rawLine in tostring(msg or ''):gmatch('[^\r\n]+') do
        local line = Parser.strip(rawLine)
        if not line:match('^%s*$') then
            local lower = line:lower()
            local cur = self.cur
            local within = cur ~= nil and (t - cur.t) <= C.groupWindowMs
            if within and isContinuation(line, lower) then
                if #cur.lines < C.maxLines then cur.lines[#cur.lines + 1] = line end
                cur.t = t
            else
                local level = classify(rawLine, line, lower)
                if level then
                    self:flush()
                    self.cur = { level = level, channel = channel, lines = { line }, t = t }
                elseif within and line:find('%.lua:%d+') then
                    if #cur.lines < C.maxLines then cur.lines[#cur.lines + 1] = line end
                    cur.t = t
                end
            end
        end
    end
end

function Parser:poll(now)
    if self.cur and (now - self.cur.t) > C.groupWindowMs then self:flush() end
    local out = self.done
    self.done = {}
    return out
end
