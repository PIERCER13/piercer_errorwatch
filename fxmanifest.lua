fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'piercer_errorwatch'
author 'piercer'

dependency 'framezero_bridge'

ui_page 'web/index.html'

shared_scripts {
    'config_shared.lua',
    'shared/parser.lua',
}

client_script 'client/main.lua'

server_scripts {
    '@framezero_bridge/import.lua',
    'config.lua',
    'server/i18n.lua',
    'server/utils.lua',
    'server/auth.lua',
    'server/store.lua',
    'server/collector.lua',
    'server/injector.lua',
    'server/actions.lua',
    'server/api.lua',
    'server/ingame.lua',
}

files {
    'web/index.html',
    'locales/*.json',
    -- opcional: client_script '@piercer_errorwatch/shim.lua' nos resources que voce quer monitorar
    'shim.lua',
}
