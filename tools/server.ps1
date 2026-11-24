param(
    [int]$Port = 8788,
    [string]$Bind = 'localhost',
    [string]$DataFile = '',
    [switch]$Open
)
$ErrorActionPreference = 'Stop'

$resource = Split-Path -Parent $PSScriptRoot
$indexFile = [IO.Path]::Combine($resource, 'web', 'index.html')
if (-not $DataFile) { $DataFile = [IO.Path]::Combine($resource, 'data', 'errors.json') }
$DataDir      = Split-Path -Parent $DataFile
$StateFile    = [IO.Path]::Combine($DataDir, 'state.json')
$ResultsFile  = [IO.Path]::Combine($DataDir, 'results.json')
$CommandsFile = [IO.Path]::Combine($DataDir, 'commands.json')

$AllowedActions = @('clear', 'resolve', 'resolve_all', 'mute', 'export', 'test', 'inj_apply', 'inj_revert', 'inj_ignore', 'inj_rescan')

$ActionKey = ''
if ($Bind -ne 'localhost') {
    $ActionKey = -join ((48..57) + (97..122) | Get-Random -Count 20 | ForEach-Object { [char]$_ })
}

$utf8 = New-Object Text.UTF8Encoding($false)  

function Read-Shared([string]$path, [string]$empty = '[]') {
    if (-not [IO.File]::Exists($path)) { return $empty }
    $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try { return (New-Object IO.StreamReader($fs, $utf8)).ReadToEnd() }
    finally { $fs.Dispose() }
}

function Write-Atomic([string]$path, [string]$text) {
    $tmp = "$path.tmp"
    [IO.File]::WriteAllText($tmp, $text, $utf8)
    if ([IO.File]::Exists($path)) { [IO.File]::Replace($tmp, $path, [NullString]::Value) } else { [IO.File]::Move($tmp, $path) }
}

function Send([System.Net.HttpListenerContext]$ctx, [int]$code, [string]$body, [string]$type) {
    $bytes = $utf8.GetBytes($body)
    $ctx.Response.StatusCode = $code
    $ctx.Response.ContentType = $type
    $ctx.Response.Headers.Add('Cache-Control', 'no-store')
    $ctx.Response.Headers.Add('X-Content-Type-Options', 'nosniff')
    $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $ctx.Response.Close()
}
function Send-Json($ctx, [int]$code, $obj) {
    Send $ctx $code (ConvertTo-Json -InputObject $obj -Depth 6 -Compress) 'application/json; charset=utf-8'
}

function Test-ActionRequest($req) {
    if ($req.Headers['X-Errorwatch'] -ne '1') { return 'cabecalho X-Errorwatch ausente' } 
    if ($Bind -eq 'localhost') {
        $h = ($req.Headers['Host'] -split ':')[0]
        if ($h -notin @('localhost', '127.0.0.1')) { return 'host invalido' }
        $origin = $req.Headers['Origin']
        if ($origin -and $origin -notin @("http://localhost:$Port", "http://127.0.0.1:$Port")) { return 'origem invalida' }
    }
    elseif ($req.Headers['X-Errorwatch-Key'] -ne $ActionKey) { return 'chave invalida' }
    return $null
}

function Clean-Args($raw) {
    $a = @{}
    if ($null -eq $raw) { return $a }
    if ($raw.id -is [string] -and $raw.id -match '^[0-9a-f]{1,32}$') { $a.id = $raw.id }
    if ($raw.resource -is [string] -and $raw.resource -match '^[\w\-\.]{1,64}$') { $a.resource = $raw.resource }
    if ($null -ne $raw.names) {
        $list = @($raw.names | Where-Object { $_ -is [string] -and $_ -match '^[\w\-\.]{1,64}$' } | Select-Object -First 300)
        $a.names = [string[]]$list
    }
    if ($raw.restart -is [bool]) { $a.restart = $raw.restart }
    return $a
}

function Queue-Command($req) {
    $sr = New-Object IO.StreamReader($req.InputStream, $utf8)
    $buf = New-Object char[] 16385
    $n = $sr.Read($buf, 0, 16385)
    if ($n -gt 16384) { return @{ code = 413; body = @{ error = 'corpo grande demais' } } }
    $payload = (New-Object string($buf, 0, $n)) | ConvertFrom-Json
    $action = [string]$payload.action
    if ($action -notin $AllowedActions) { return @{ code = 400; body = @{ error = 'acao desconhecida' } } }

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $id = [guid]::NewGuid().ToString('N')
    $existing = @()
    try {
        $parsed = ConvertFrom-Json (Read-Shared $CommandsFile '[]')
        if ($parsed -is [array]) { $existing = $parsed } elseif ($null -ne $parsed) { $existing = ,$parsed }
    } catch { }
    $items = New-Object System.Collections.Generic.List[string]
    foreach ($c in $existing) {
        if ($c.id -is [string] -and $c.at -and ($now - [long]$c.at) -le 120) {   # descarta comandos antigos
            $items.Add((ConvertTo-Json -InputObject ([ordered]@{ id = $c.id; action = [string]$c.action; args = (Clean-Args $c.args); at = [long]$c.at }) -Depth 4 -Compress))
        }
    }
    $items.Add((ConvertTo-Json -InputObject ([ordered]@{ id = $id; action = $action; args = (Clean-Args $payload.args); at = $now }) -Depth 4 -Compress))
    Write-Atomic $CommandsFile ('[' + ($items -join ',') + ']')
    return @{ code = 200; body = @{ id = $id } }
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://${Bind}:$Port/")
try { $listener.Start() }
catch {
    Write-Host "Nao foi possivel abrir a porta $Port ($($_.Exception.Message))." -ForegroundColor Red
    Write-Host "Tente outra porta:  start.bat -Port 8789" -ForegroundColor Yellow
    exit 1
}

$url = "http://localhost:$Port/"
Write-Host ""
Write-Host "  piercer_errorwatch - painel web" -ForegroundColor Magenta
Write-Host "  Abra: $url"
Write-Host "  Dados: $DataDir"
if ($ActionKey) { Write-Host "  Chave das acoes (rede): $ActionKey" -ForegroundColor Yellow }
Write-Host "  Acoes ficam na fila data\commands.json e o resource as executa em ~2s."
Write-Host "  Ctrl+C para encerrar."
Write-Host ""
if ($Open) { Start-Process $url }

try {
    while ($listener.IsListening) {
        $task = $listener.GetContextAsync()
        while (-not $task.AsyncWaitHandle.WaitOne(500)) { }   # mantem o Ctrl+C responsivo
        $ctx = $task.GetAwaiter().GetResult()
        try {
            $method = $ctx.Request.HttpMethod
            $path = $ctx.Request.Url.AbsolutePath
            if ($method -eq 'GET') {
                switch ($path) {
                    '/'             { Send $ctx 200 ([IO.File]::ReadAllText($indexFile)) 'text/html; charset=utf-8' }
                    '/index.html'   { Send $ctx 200 ([IO.File]::ReadAllText($indexFile)) 'text/html; charset=utf-8' }
                    '/errors.json'  { Send $ctx 200 (Read-Shared $DataFile) 'application/json; charset=utf-8' }
                    '/state.json'   { Send $ctx 200 (Read-Shared $StateFile '{}') 'application/json; charset=utf-8' }
                    '/resources.json' { Send $ctx 200 (Read-Shared ([IO.Path]::Combine($DataDir, 'resources.json')) '{}') 'application/json; charset=utf-8' }
                    '/locales/pt-br.json' { Send $ctx 200 ([IO.File]::ReadAllText([IO.Path]::Combine($resource, 'locales', 'pt-br.json'), $utf8)) 'application/json; charset=utf-8' }
                    '/locales/en.json'    { Send $ctx 200 ([IO.File]::ReadAllText([IO.Path]::Combine($resource, 'locales', 'en.json'), $utf8)) 'application/json; charset=utf-8' }
                    '/results.json' { Send $ctx 200 (Read-Shared $ResultsFile '{}') 'application/json; charset=utf-8' }
                    default         { Send $ctx 404 'not found' 'text/plain' }
                }
            }
            elseif ($method -eq 'POST' -and $path -eq '/action') {
                $why = Test-ActionRequest $ctx.Request
                if ($why) { Send-Json $ctx 403 @{ error = $why } }
                else { $r = Queue-Command $ctx.Request; Send-Json $ctx $r.code $r.body }
            }
            else { Send $ctx 405 'method not allowed' 'text/plain' }
        }
        catch {
            try { Send $ctx 500 'erro interno' 'text/plain' } catch { }
        }
    }
}
finally { $listener.Stop() }
