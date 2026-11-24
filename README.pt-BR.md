# piercer_errorwatch

[English](README.md)

Junta em um lugar só os erros e avisos que o servidor mostra, principalmente os que passam
despercebidos quando tudo carrega junto no restart. Tem **NUI in-game** (`/errorwatch`) e **painel web**
(`tools/start.bat`), no mesmo estilo do `piercer_hitchhunter`.

## Instalação

```cfg
ensure framezero_bridge
ensure piercer_errorwatch   # o mais cedo possível: só enxerga o que acontece depois que ele sobe
```

Permissão in-game: grupos em `config.lua` (via `framezero_bridge`), ou ACE:
`add_ace group.admin piercer_errorwatch.use allow`.

## Idioma

- `Config.Locale = 'pt-br'` ou `'en'` (`config.lua`) define o idioma do console do servidor, das notificações aos admins e o idioma padrão da NUI e do painel web.
- Cada pessoa pode trocar o idioma no seletor no topo da NUI/painel; a escolha fica salva naquele navegador.
- Todos os textos ficam em `locales/pt-br.json` e `locales/en.json`, compartilhados pelo servidor e pela interface. Para adicionar um idioma: copie o `en.json`, traduza e inclua o código em `LANGS` no `web/index.html`.

## O que captura

| Origem | Como | Observação |
|---|---|---|
| **Server** (console) | `RegisterConsoleListener` | Tudo que o console imprime: `SCRIPT ERROR`, falha ao carregar/iniciar resource, `attempt to ...`, SQL, linhas em vermelho (`^1`) e avisos (`warning`, `deprecated`). Stack traces entram agrupados no mesmo erro. |
| **Client** (F8) | `shim.lua` e `exports.piercer_errorwatch:Report` | O FiveM **não tem gancho global para erros de client**; o console do client não é acessível por script. Por isso é opt-in por resource (abaixo). |
| Scripts de server | `exports.piercer_errorwatch:Report(msg, detalhe, resource)` | Para `pcall`/`try` próprios. |

### Monitorar erros de client: aba "Injeção" (NUI e painel web)

A aba **Injeção (client)** lista todos os resources do servidor, com busca, filtro por pasta `[grupo]` e
status. Você marca os que quer (ou "Selecionar visíveis") e clica em **Aplicar**; **Remover** desfaz.

- O shim entra como bloco marcado logo após `fx_version`, então é sempre o 1º `client_script`. Um backup `fxmanifest.lua.errorwatch.bak` do original é gravado uma vez. **Remover** apaga só o bloco, preservando edições manuais.
- **Ignorar** tira o resource da lista de aplicação (fica salvo em `data/injector.json`).
- Nunca recebem o shim: o próprio errorwatch, os `protected`/`protectedGroups` do `config.lua`, resources **escrow** (assinados, editar quebra) e os que não têm `client_script`.
- Depois de aplicar o servidor roda `refresh`; é preciso **reiniciar o resource** para valer (e o errorwatch deve subir antes dele). `Config.Injector.allowRestart = true` libera a opção "reiniciar depois".
- Pelo painel web só funciona se `Config.Injector.allowFromWeb = true`. Desligue se expuser o painel na rede.

Manualmente, o equivalente é, no `fxmanifest.lua` do resource, como **primeiro** client script:

```lua
client_scripts { '@piercer_errorwatch/shim.lua', 'client.lua' }
```

O shim envolve `CreateThread`, `SetTimeout`, `AddEventHandler`, `RegisterNetEvent`, `RegisterCommand` e
`RegisterNUICallback`. O erro é reportado e **relançado**, então o F8 continua igual. Limites: não pega erro de
código solto no topo do arquivo, nem erros de JavaScript da NUI.

## Como funciona

- Erros iguais viram **uma entrada com contador** (números e endereços são normalizados). Cada entrada guarda resource, `arquivo:linha`, stack, 1ª/última ocorrência e, no client, os jogadores afetados.
- **Sessão** = desde que o resource subiu. O filtro "Desde o último restart" mostra só o que aconteceu depois do restart; "boot" marca erros dos primeiros `Config.BootSeconds`.
- Resolver, silenciar (não avisa nem conta), buscar e filtrar por server/client/nível.
- Admins online recebem uma notificação quando surgem erros **novos** (`Config.Notify`). A NUI aberta atualiza ao vivo.
- Dados em `data/errors.json`, gravados com atraso (debounce) para não pesar em rajadas.

## Painel web

`tools/start.bat` abre `http://localhost:8788/`. Lê os arquivos de `data/` direto do disco, então funciona
mesmo com o servidor fora do ar. Ações (resolver, silenciar, limpar, testar) vão para a fila
`data/commands.json`, e o resource as executa em ~2s. Para expor na rede use `-Bind +` (exige PowerShell
como administrador); as ações passam a exigir a chave mostrada no terminal.

## Testar

Botão **Testar captura** (NUI ou web) imprime um `SCRIPT ERROR` falso no console; ele deve aparecer na lista em ~1s.
Console: `errorwatch_status`.

## Ajustes

- `config_shared.lua`: padrões de erro/aviso, ignorados, janela de agrupamento, envio do client.
- `config.lua`: idioma, permissões, limite de entradas, notificações, rate limit de reports de client, injetor.
