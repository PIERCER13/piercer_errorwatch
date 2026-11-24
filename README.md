# piercer_errorwatch

[Português (BR)](README.pt-BR.md)

Collects the errors and warnings your server prints in one place, especially the ones that slip by when
everything loads at once on a restart. It has an **in-game NUI** (`/errorwatch`) and a **web panel**
(`tools/start.bat`), in the same style as `piercer_hitchhunter`. Both are available in **English and
Portuguese (BR)**.

## Installation

```cfg
ensure framezero_bridge
ensure piercer_errorwatch   # as early as possible: it only sees what happens after it starts
```

In-game permission: groups in `config.lua` (via `framezero_bridge`), or ACE:
`add_ace group.admin piercer_errorwatch.use allow`.

## Language

- `Config.Locale = 'pt-br'` or `'en'` (`config.lua`) sets the language of the server console, the admin
  notifications and the default language of the NUI and web panel.
- Each person can switch language with the selector at the top of the NUI/panel; the choice is remembered in that browser.
- All texts live in `locales/pt-br.json` and `locales/en.json`, shared by the server and the UI.
  To add a language: copy `en.json`, translate it, and add the code to `LANGS` in `web/index.html`.

## What it captures

| Source | How | Notes |
|---|---|---|
| **Server** (console) | `RegisterConsoleListener` | Everything the console prints: `SCRIPT ERROR`, resource load/start failures, `attempt to ...`, SQL, red (`^1`) lines and warnings (`warning`, `deprecated`). Stack traces are grouped into the same error. |
| **Client** (F8) | `shim.lua` and `exports.piercer_errorwatch:Report` | FiveM has **no global hook for client errors** and the client console is not readable by scripts. That is why it is opt-in per resource (below). |
| Server scripts | `exports.piercer_errorwatch:Report(msg, detail, resource)` | For your own `pcall`/`try` blocks. |

### Monitoring client errors: the "Injection" tab (NUI and web panel)

The **Injection (client)** tab lists every resource on the server, with search, `[folder]` filter and
status. Tick the ones you want (or "Select visible") and click **Apply**; **Remove** undoes it.

- The shim is added as a marked block right after `fx_version`, so it is always the 1st `client_script`. A `fxmanifest.lua.errorwatch.bak` backup of the original is written once. **Remove** deletes only that block, keeping later manual edits.
- **Ignore** takes a resource out of the injection list (saved in `data/injector.json`).
- Never touched: errorwatch itself, the `protected`/`protectedGroups` from `config.lua`, **escrow** resources (signed; editing breaks them) and resources without a `client_script`.
- After applying, the server runs `refresh`; you must **restart the resource** for it to take effect (and errorwatch must start before it). `Config.Injector.allowRestart = true` enables the "restart afterwards" option.
- From the web panel it only works if `Config.Injector.allowFromWeb = true`. Turn it off if you expose the panel on the network.

Manual equivalent, in the resource's `fxmanifest.lua`, as the **first** client script:

```lua
client_scripts { '@piercer_errorwatch/shim.lua', 'client.lua' }
```

The shim wraps `CreateThread`, `SetTimeout`, `AddEventHandler`, `RegisterNetEvent`, `RegisterCommand` and
`RegisterNUICallback`. The error is reported and **re-thrown**, so F8 stays the same. Limits: it does not catch
errors in loose top-level code or JavaScript errors in a NUI.

## How it works

- Identical errors become **one entry with a counter** (numbers and addresses are normalized). Each entry keeps resource, `file:line`, stack, first/last occurrence and, for the client, the affected players.
- **Session** = since the resource started. The "Since last restart" filter shows only what happened after the restart; "boot" marks errors from the first `Config.BootSeconds`.
- Resolve, mute (no alerts, not counted), search, and filter by server/client/level.
- Online admins get a notification when **new** errors appear (`Config.Notify`). An open NUI updates live.
- Data is stored in `data/errors.json`, written with a delay (debounce) so error bursts do not cause lag.

## Web panel

`tools/start.bat` opens `http://localhost:8788/`. It reads the files in `data/` straight from disk, so it
works even with the server down. Actions (resolve, mute, clear, test, injection) go to the
`data/commands.json` queue and the resource runs them within ~2s. To expose it on the network use `-Bind +`
(requires an administrator PowerShell); actions then require the key shown in the terminal.

## Testing

The **Test capture** button (NUI or web) prints a fake `SCRIPT ERROR` to the console; it should appear in the list within ~1s.
Console: `errorwatch_status`.

## Settings

- `config_shared.lua`: error/warning patterns, ignored lines, grouping window, client sending.
- `config.lua`: language, permissions, entry limit, notifications, client report rate limit, injector.
