Utils = {}

function Utils.log(msg)
    print(('^5[errorwatch]^7 %s'):format(msg))
end

function Utils.iso(ts)
    return os.date('!%Y-%m-%dT%H:%M:%SZ', ts or os.time())
end
