Config = {}

Config.Locale = 'pt-br'

-- Comando in-game: /errorwatch. Quem pode usar (qualquer regra libera):
Config.Permissions = {
    -- Grupos/permissoes/jobs da sua base, resolvidos pelo framezero_bridge
    bridge = { 'admin', 'Admin', 'admin.acess', 'superadmin', 'owner' },
    -- ACE nativo. No server.cfg: add_ace group.admin piercer_errorwatch.use allow
    ace = { 'piercer_errorwatch.use' },
    -- Identificadores fixos, ex.: 'license:abc123', 'discord:123'
    identifiers = {},
}

-- Maximo de entradas (erros distintos) guardadas em data/errors.json.
Config.MaxEntries = 500

-- Quantas entradas a NUI in-game recebe por consulta.
Config.IngameLimit = 150

-- Erros do servidor nos primeiros N segundos depois do resource subir sao marcados como "boot".
Config.BootSeconds = 120

-- Um erro ja marcado como resolvido volta a aparecer como aberto se ocorrer de novo.
Config.ReopenResolved = true

-- Aviso aos admins online quando surgem erros NOVOS (nao repetidos).
Config.Notify = {
    enabled = true,
    cooldown = 20,         -- segundos entre avisos (agrupa varios erros em um)
    includeWarnings = false,
}

-- Protecao contra client malicioso/barulhento enviando reports falsos.
Config.Client = {
    maxPer10s = 30,        -- reports aceitos por jogador a cada 10s
}

-- Injecao do shim.lua nos manifests de outros resources (aba "Injecao" da NUI e do painel web).
Config.Injector = {
    enabled = true,
    -- Permite aplicar/remover pelo painel web (fila em arquivo, sem checagem de permissao do jogo).
    -- Desligue se o painel for exposto na rede.
    allowFromWeb = true,
    -- Mostra a opcao "reiniciar depois de aplicar". DESLIGADO por padrao: reinicia o resource de verdade.
    allowRestart = false,
    -- Nunca recebem o shim (o proprio errorwatch ja e protegido).
    protected = { 'framezero_bridge', 'oxmysql', 'monitor', 'sessionmanager', 'mapmanager', 'spawnmanager', 'chat', 'hardcap' },
    -- Pastas [grupo] inteiras protegidas.
    protectedGroups = { 'system', 'cfx-default' },
}

-- Intervalo de gravacao em disco (so grava se houve mudanca) e do sinal de vida.
Config.SaveIntervalMs = 2000
