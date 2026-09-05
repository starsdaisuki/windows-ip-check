#requires -Version 5.1
<#
.SYNOPSIS
Run the ORIGINAL xykt/IPQuality report on native Windows, including all modules.
.NOTES
First run prepares official Cygwin tools in LOCALAPPDATA. No WSL or Docker.
The upstream Bash script is downloaded unchanged and SHA256-verified; one documented
regex-portability patch is applied to a copy at launch (see New-IPQualityLaunchScript).
#>
[CmdletBinding()]
param(
    [switch]$IPv6,
    [switch]$English,
    [switch]$LibraryOnly,
    [string]$CacheRoot = ''
)

$script:UpstreamRevision = '3c0eb8856c67ad351020d1edd1bfd4e2515d32fe'
$script:UpstreamSha256 = 'ffb17dae790341c13023a94c5141775974dd73a3653ca5fba5c4648fc5588402'

function Get-IPQualityArguments([bool]$UseIPv6 = $false, [bool]$UseEnglish = $false) {
    # -n only skips Linux dependency installation; it is NOT lite mode.
    # -p keeps the complete report but disables uploading an online report.
    $values = @('-4', '-n', '-p')
    if ($UseIPv6) { $values[0] = '-6' }
    if ($UseEnglish) { $values += '-E' }
    return $values
}

function Get-IPQualityFile([string]$Url, [string]$Destination) {
    & $script:WindowsCurl -q --fail --silent --show-error --location --retry 2 `
        --connect-timeout 10 --max-time 120 --proto '=https' --proto-redir '=https' `
        --output $Destination --url $Url
    if ($LASTEXITCODE -ne 0) { throw 'Download failed. Keep Clash TUN enabled and retry.' }
}

function Test-IPQualityRuntime([string]$Runtime) {
    foreach ($name in @('bash','curl','jq','bc','dig','xargs','cygpath','netcat')) {
        # netcat is provided as nc.exe by the OpenBSD netcat package.
        if ($name -eq 'netcat') { $name = 'nc' }
        if (-not (Test-Path -LiteralPath (Join-Path $Runtime "bin/$name.exe"))) { return $false }
    }
    return $true
}

function New-IPQualityLaunchScript([string[]]$Flags, [string]$ExpectedIP, [string]$ReportName) {
    if ($ExpectedIP -notmatch '^[0-9a-fA-F:.]+$') { throw 'Invalid exit IP' }
    if ($ReportName -notmatch '^[a-zA-Z0-9-]+\.json$') { throw 'Invalid report name' }
    foreach ($flag in $Flags) {
        if ($flag -notin @('-4','-6','-n','-p','-E')) { throw 'Unexpected upstream flag' }
    }
    $template = @'
#!/bin/bash
set -e
export PATH=/usr/bin:/bin:$PATH
export LANG=C.UTF-8 LC_ALL=C.UTF-8 TERM=xterm
# TUN uses OS routing. Do not accidentally inherit an unrelated shell proxy.
unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY
root="$(cd -- "$(dirname -- "$0")" && pwd)"
export PATH="$root/compat:$PATH"
for tool in bash curl jq bc nc dig xargs gzip timeout ss; do
    command -v "$tool" >/dev/null || { echo "Missing runtime tool: $tool"; exit 10; }
done
actual=$(curl __FAMILY__ -fsS --max-time 15 https://api64.ipify.org)
if [ "$actual" != '__EXPECTED__' ]; then
    echo "Windows/runtime exit mismatch: expected __EXPECTED__, got $actual"
    exit 20
fi
printf '\nWindows and native Bash exit agree: %s\n' "$actual"
printf 'Running original xykt/IPQuality - all report modules retained.\n\n'
set +e
# One documented portability patch, applied to a COPY after the checksum gate (the cached upstream stays pristine):
# upstream's IPv4 regex uses GNU word boundaries \< \>, which glibc accepts but Cygwin/BSD regcomp rejects,
# so check_ip_valide never matches, calc_ip_net returns "" on both sides, and every streaming row is
# mislabeled as "DNS" unlock instead of "Native". The pattern is ^...$-anchored, so dropping the two
# boundary tokens is semantically identical. Verified 2026-09-05 against a Linux run of the same exit IP.
sed 's/\\<//g; s/\\>//g' "$root/upstream-__REVISION__.sh" > "$root/upstream-__REVISION__.cygwin.sh"
bash "$root/upstream-__REVISION__.cygwin.sh" __FLAGS__ -o "$root/reports/__REPORT__" | tee "$root/reports/__REPORT__.ansi"
exit "${PIPESTATUS[0]}"
'@
    return $template.Replace('__FAMILY__', $Flags[0]).Replace('__EXPECTED__', $ExpectedIP).
        Replace('__REVISION__', $script:UpstreamRevision).Replace('__FLAGS__', ($Flags -join ' ')).
        Replace('__REPORT__', $ReportName)
}

function Start-IPQualityWindows {
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitOperatingSystem) {
        throw 'This launcher requires 64-bit Windows 10/11 and PowerShell 5.1 or newer.'
    }
    $script:WindowsCurl = (Get-Command curl.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    if (-not $CacheRoot) { $CacheRoot = Join-Path $env:LOCALAPPDATA 'WindowsIPCheck' }
    $CacheRoot = [IO.Path]::GetFullPath($CacheRoot)
    New-Item -ItemType Directory -Path $CacheRoot -Force | Out-Null
    $lock = [IO.File]::Open((Join-Path $CacheRoot 'run.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    try {
        $runtime = Join-Path $CacheRoot 'cygwin'
        if (-not (Test-IPQualityRuntime $runtime)) {
            Write-Output 'First run: downloading the official native Windows Bash tools (about 70 MB; usually a few minutes).'
            Write-Output 'This is automatic. No WSL, Docker, administrator prompt, system PATH or shortcuts are needed.'
            $setup = Join-Path $CacheRoot ('setup-' + [guid]::NewGuid().ToString('N') + '.exe')
            $checksums = Join-Path $CacheRoot ('sha512-' + [guid]::NewGuid().ToString('N') + '.txt')
            Get-IPQualityFile 'https://cygwin.com/setup-x86_64.exe' $setup
            Get-IPQualityFile 'https://cygwin.com/sha512.sum' $checksums
            $manifest = Get-Content -LiteralPath $checksums -Raw
            if ($manifest -notmatch '(?m)^([a-fA-F0-9]{128})\s+\*?setup-x86_64\.exe\s*$') { throw 'Official setup checksum missing' }
            $expected = $Matches[1]
            if ((Get-FileHash -LiteralPath $setup -Algorithm SHA512).Hash -ine $expected) { throw 'Cygwin setup checksum mismatch' }
            $setupArgs = @('--quiet-mode', '--no-admin', '--no-shortcuts', '--no-write-registry',
                '--no-replaceonreboot', '--only-site', '--site', 'https://mirrors.kernel.org/sourceware/cygwin/',
                '--root', $runtime, '--local-package-dir', (Join-Path $CacheRoot 'packages'),
                '--packages', 'bash,coreutils,grep,sed,gawk,findutils,gzip,curl,jq,bc,netcat,bind-utils,ca-certificates')
            # Pipeline waits for the GUI-subsystem installer even in PowerShell.
            & $setup @setupArgs | Out-Null
            $setupExit = $LASTEXITCODE
            if ($setupExit -ne 0 -or -not (Test-IPQualityRuntime $runtime)) {
                throw "Native runtime setup failed (exit=$setupExit). Retry to resume the cached download."
            }
        }
        $upstream = Join-Path $CacheRoot ("upstream-$script:UpstreamRevision.sh")
        if (-not (Test-Path -LiteralPath $upstream)) {
            $download = $upstream + '.' + [guid]::NewGuid().ToString('N') + '.download'
            Get-IPQualityFile "https://raw.githubusercontent.com/xykt/IPQuality/$script:UpstreamRevision/ip.sh" $download
            if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ine $script:UpstreamSha256) {
                throw 'Upstream script checksum mismatch'
            }
            [IO.File]::Move($download, $upstream)
        }
        if ((Get-FileHash -LiteralPath $upstream -Algorithm SHA256).Hash -ine $script:UpstreamSha256) {
            throw 'Cached upstream script has changed. Refusing to execute it.'
        }
        $compat = Join-Path $CacheRoot 'compat'
        $reports = Join-Path $CacheRoot 'reports'
        New-Item -ItemType Directory -Force -Path $compat,$reports | Out-Null
        # Upstream ss -tano is used only to look for TCP port 25. Query Windows'
        # real TCP table instead of pretending that Linux ss exists here.
        $netstat = (& (Join-Path $runtime 'bin/cygpath.exe') '-u' (Join-Path $env:SystemRoot 'System32/netstat.exe') | Out-String).Trim()
        if (-not $netstat -or $netstat -match "['`r`n]") { throw 'Cannot resolve native TCP tool path' }
        $ss = "#!/bin/bash`nexec '$netstat' -ano -p tcp`n"
        [IO.File]::WriteAllText((Join-Path $compat 'ss'), $ss, (New-Object Text.UTF8Encoding($false)))
        $bash = Join-Path $runtime 'bin/bash.exe'
        & (Join-Path $runtime 'bin/chmod.exe') '+x' (Join-Path $compat 'ss')
        if ($LASTEXITCODE -ne 0) { throw 'Could not prepare native TCP adapter' }
        $family = '-4'
        if ($IPv6) { $family = '-6' }
        $exitIP = (& $script:WindowsCurl -q $family -fsS --noproxy api64.ipify.org --max-time 15 https://api64.ipify.org | Out-String).Trim()
        $address = $null
        if ($LASTEXITCODE -ne 0 -or -not [Net.IPAddress]::TryParse($exitIP, [ref]$address)) { throw 'Windows exit-IP query failed' }
        $flags = @(Get-IPQualityArguments ([bool]$IPv6) ([bool]$English))
        $runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
        $reportName = "ipquality-$runId.json"
        $launcher = Join-Path $CacheRoot ("run-$runId.sh")
        $content = New-IPQualityLaunchScript $flags $exitIP $reportName
        [IO.File]::WriteAllText($launcher, $content.Replace("`r`n","`n"), (New-Object Text.UTF8Encoding($false)))
        Write-Output "Windows exit: $exitIP"
        Write-Output ('Local full JSON report: ' + (Join-Path $reports $reportName))
        # Native stderr contains upstream progress/diagnostics, not PS exceptions.
        $nativePreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & $bash --noprofile --norc $launcher
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $nativePreference }
        $reportPath = Join-Path $reports $reportName
        if (-not (Test-Path -LiteralPath $reportPath)) { throw "Original IPQuality produced no report (exit=$code)" }
        $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        foreach ($section in @('Head','Info','Type','Score','Factor','Media','Mail')) {
            if ($null -eq $report.PSObject.Properties[$section]) { throw "Incomplete upstream report: $section missing" }
        }
        $scoreCount = @($report.Score.PSObject.Properties | Where-Object { $null -ne $_.Value -and $_.Value -ne 'null' -and $_.Value -ne '' }).Count
        $ansiPath = $reportPath + '.ansi'
        if ((Test-Path -LiteralPath $ansiPath) -and (Get-Content -LiteralPath $ansiPath -Raw -Encoding UTF8).Contains('(Lite)')) {
            Write-Output 'UPSTREAM LIMITED (Lite): its lookup service failed. Full multi-source reputation was NOT obtained.'
        }
        Write-Output "Report sections present: 7/7; available score sources: $scoreCount/6. Empty sources are NOT clean scores."
        Write-Output ('Full report saved: ' + $reportPath)
    } finally { $lock.Dispose() }
}

if ($LibraryOnly) { return }
$previousEncoding = [Console]::OutputEncoding
$previousPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Stop'
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
    Start-IPQualityWindows
} finally {
    [Console]::OutputEncoding = $previousEncoding
    $ErrorActionPreference = $previousPreference
}
