-- Configuracao compartilhada (server + client). Nada sensivel aqui.
ConfigShared = {}

-- Captura tambem avisos (warning/deprecated), marcados como "warn".
ConfigShared.captureWarnings = true

-- Linhas impressas em vermelho (^1) contam como erro, mesmo sem palavra-chave.
ConfigShared.redIsError = true

-- Linhas do mesmo erro (stack trace etc.) que chegam dentro dessa janela viram UMA entrada.
ConfigShared.groupWindowMs = 250
ConfigShared.maxLines = 40

-- Padroes Lua (case-insensitive: comparados contra a linha em minusculas).
ConfigShared.errorPatterns = {
    'script error', 'error running', 'error loading', 'error parsing',
    'failed to', "couldn't", 'could not', 'attempt to', 'unhandled',
    'exception', 'sql error', 'syntax error',
    '%f[%a]error%f[%A]',
}
ConfigShared.warnPatterns = {
    '%f[%a]warning%f[%A]', '%f[%a]warn%f[%A]', 'deprecated',
}

-- Linhas que casam com algum destes padroes sao ignoradas (ruido conhecido).
ConfigShared.ignore = {
    'thread hitch warning',     -- e assunto do piercer_hitchhunter
    '%[errorwatch%]',           -- logs deste proprio resource
    'no errors', '0 errors', 'errors: 0',
}

-- Erros de client chegam por report (shim.lua / export Report), nao pelo console.
ConfigShared.client = {
    enabled = true,
    flushMs = 2000,       -- agrupa e envia ao servidor a cada N ms
    maxPerBatch = 10,     -- maximo de erros distintos por envio
}
