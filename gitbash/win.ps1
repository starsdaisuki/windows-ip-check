# Git Bash edition bootstrap:  irm https://raw.githubusercontent.com/starsdaisuki/windows-ip-check/v3/gitbash/win.ps1 | iex
# Needs Git for Windows only (winget install --id Git.Git -e). ~1 MB download, no Cygwin.
$ErrorActionPreference = 'Stop'
$ref  = 'v3'
$raw  = "https://raw.githubusercontent.com/starsdaisuki/windows-ip-check/$ref/gitbash"
$jq   = 'https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-windows-amd64.exe'
$dest = Join-Path $env:LOCALAPPDATA 'WindowsIPCheck\gitbash'
$core = $null; try { $core = (& git --exec-path 2>$null) } catch {}
if (-not $core) { Write-Host "Git for Windows not found. Install, reopen PowerShell, run again:`n    winget install --id Git.Git -e" -ForegroundColor Yellow; return }
$bash = [IO.Path]::GetFullPath((Join-Path $core '..\..\..\usr\bin\bash.exe'))
if (-not (Test-Path $bash)) { $bash = Join-Path $env:ProgramFiles 'Git\usr\bin\bash.exe' }
if (-not (Test-Path $bash)) { Write-Host "bash.exe not found next to git (exec-path: $core)" -ForegroundColor Red; return }
New-Item -ItemType Directory -Force -Path (Join-Path $dest 'shim'), (Join-Path $dest 'bin') | Out-Null
foreach ($f in 'run.sh','run.cmd','shim/bc','shim/nc','shim/dig','shim/nslookup','shim/ss','shim/date') {
  Invoke-WebRequest -UseBasicParsing "$raw/$f" -OutFile (Join-Path $dest $f)
}
$jqExe = Join-Path $dest 'bin\jq.exe'
if (-not (Test-Path $jqExe)) { Invoke-WebRequest -UseBasicParsing $jq -OutFile $jqExe }
$runsh = (Join-Path $dest 'run.sh') -replace '\\','/'
$extra = if ($env:STARUNLOCK_ARGS) { $env:STARUNLOCK_ARGS -split ' ' } else { @('-4','-p') }
& $bash $runsh @extra
