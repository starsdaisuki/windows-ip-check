#requires -Version 5.1
<#
.SYNOPSIS
Native Windows IP inspection. Requires Windows 10 1803+ curl.exe, no WSL.
.EXAMPLE
.\ipquality.ps1 -CheckExitOnly -Proxy http://127.0.0.1:7897
.EXAMPLE
.\ipquality.ps1 -Proxy http://127.0.0.1:7897 -ExpectedIP $verifiedExit
.NOTES
IPv4 only. No administrator rights, installs, uploads, or account credentials.
Data providers necessarily receive the queried IP. Demo APIs may rate-limit.
Without -Proxy, curl uses OS routing (including TUN), NOT Windows system proxy.
curl config/environment proxy settings are disabled for deterministic routing.
Exit codes: 0 completed, 2 egress invalid/changed, 3 all providers unavailable.
#>
[CmdletBinding()]
param(
    [string]$Proxy = '',
    [string]$ExpectedIP = '',
    [switch]$CheckExitOnly,
    [switch]$Json,
    [ValidateRange(2, 30)][int]$TimeoutSec = 10,
    [switch]$LibraryOnly
)

function Get-SUField($Object, [string]$Path) {
    $value = $Object
    foreach ($name in $Path.Split('.')) {
        if ($null -eq $value) { return $null }
        $prop = $value.PSObject.Properties[$name]
        if ($null -eq $prop) { return $null }
        $value = $prop.Value
    }
    return $value
}

function Test-SUIPv4([string]$Value) {
    if ($Value -notmatch '^(\d{1,3}\.){3}\d{1,3}$') { return $false }
    $address = $null
    if (-not [Net.IPAddress]::TryParse($Value, [ref]$address)) { return $false }
    # Reject shorthand, octal, and private/local results from proxy interception.
    if ($address.ToString() -cne $Value) { return $false }
    $b = $address.GetAddressBytes()
    return -not ($b[0] -eq 0 -or $b[0] -eq 10 -or $b[0] -eq 127 -or
        $b[0] -ge 224 -or ($b[0] -eq 169 -and $b[1] -eq 254) -or
        ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or
        ($b[0] -eq 192 -and $b[1] -eq 168) -or
        ($b[0] -eq 198 -and $b[1] -in @(18,19)) -or
        ($b[0] -eq 192 -and $b[1] -eq 0 -and $b[2] -eq 2) -or
        ($b[0] -eq 198 -and $b[1] -eq 51 -and $b[2] -eq 100) -or
        ($b[0] -eq 203 -and $b[1] -eq 0 -and $b[2] -eq 113) -or
        ($b[0] -eq 192 -and $b[1] -eq 88 -and $b[2] -eq 99) -or
        ($b[0] -eq 192 -and $b[1] -eq 0 -and $b[2] -eq 0 -and $b[3] -notin @(9,10)) -or
        ($b[0] -eq 100 -and $b[1] -ge 64 -and $b[1] -le 127))
}

function Invoke-SUHttp([string]$Url) {
    $ErrorActionPreference = 'Continue'
    # -q MUST be first: ignore .curlrc. Arguments are never shell-evaluated.
    $curlArgs = @('-q', '-4', '--silent', '--show-error',
        '--proto', '=https',
        '--connect-timeout', '5', '--max-time', "$TimeoutSec",
        '--max-filesize', '1048576', '--user-agent', 'StarUnlock-IP/0.1',
        '--write-out', "`nSTARUNLOCK_HTTP:%{http_code}")
    # A nonmatching reserved domain overrides NO_PROXY without an empty argv
    # element (Windows PowerShell 5.1 drops empty native arguments).
    if ($Proxy) { $curlArgs += @('--proxy', $Proxy, '--noproxy', 'starunlock.invalid') }
    # No redirects: the exact host bypasses environment proxies without a '*'
    # argument that PowerShell on Unix may expand into local filenames.
    else { $curlArgs += @('--noproxy', ([Uri]$Url).DnsSafeHost) }
    $curlArgs += @('--url', $Url)
    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        # PS5.1 wraps native stderr as ErrorRecord; do not mistake it for data.
        $output = @(& $script:SUCurl @curlArgs 2>&1)
        $code = $LASTEXITCODE
        $body = ($output | ForEach-Object { $_.ToString() }) -join "`n"
        if ($code -eq 0 -and $body -match '(?s)^(.*)\nSTARUNLOCK_HTTP:(\d{3})$') {
            $http = [int]$Matches[2]
            if ($http -ge 200 -and $http -lt 300) { return $Matches[1] }
            if ($http -lt 500) { throw "HTTP $http (no IP verdict)" }
        }
    }
    # Do not echo curl stderr: a proxy URL could contain credentials.
    throw "Request failed (curl=$code); no IP verdict"
}

function Get-SUEgress {
    $observations = @()
    foreach ($endpoint in @(
        @('ipify', 'https://api.ipify.org'),
        @('Cloudflare', 'https://www.cloudflare.com/cdn-cgi/trace')
    )) {
        try {
            $body = Invoke-SUHttp $endpoint[1]
            $ip = $body.Trim()
            if ($endpoint[0] -eq 'Cloudflare') {
                if ($body -notmatch '(?m)^ip=([^\r\n]+)') { throw 'Missing trace IP' }
                $ip = $Matches[1].Trim()
            }
            if (-not (Test-SUIPv4 $ip)) { throw 'Invalid/non-public IPv4 response' }
            $observations += [pscustomobject]@{ source=$endpoint[0]; ip=$ip; error=$null }
        } catch {
            $observations += [pscustomobject]@{ source=$endpoint[0]; ip=$null; error=$_.Exception.Message }
        }
    }
    $ips = @($observations | Where-Object { $_.ip } | Select-Object -ExpandProperty ip -Unique)
    $valid = @($observations | Where-Object { $_.ip }).Count -eq 2 -and $ips.Count -eq 1
    $ip = $null
    if ($valid) { $ip = $ips[0] }
    return [pscustomobject]@{ verified=$valid; ip=$ip; observations=$observations }
}

function Convert-SUProvider([string]$Name, $Data, [string]$TargetIP) {
    $risk = [ordered]@{}
    $type = $null
    $companyType = $null
    $asn = $null
    switch ($Name) {
        'IPinfo' {
            $d = Get-SUField $Data 'data'
            $ip = Get-SUField $d 'ip'
            $country = Get-SUField $d 'country'
            $asn = Get-SUField $d 'org'
            $type = Get-SUField $d 'asn.type'
            $companyType = Get-SUField $d 'company.type'
            foreach ($key in @('vpn','proxy','tor','relay','hosting')) {
                $v = Get-SUField $d "privacy.$key"
                if ($v -is [bool]) { $risk[$key] = $v }
            }
        }
        'ipapi.is' {
            $ip = Get-SUField $Data 'ip'
            $country = Get-SUField $Data 'location.country_code'
            if (-not $country) { $country = Get-SUField $Data 'country' }
            $asn = Get-SUField $Data 'asn.asn'
            if (-not $asn) { $asn = Get-SUField $Data 'asn' }
            $type = Get-SUField $Data 'asn.type'
            $companyType = Get-SUField $Data 'company.type'
            foreach ($key in @('is_proxy','is_vpn','is_tor','is_datacenter','is_abuser')) {
                $v = Get-SUField $Data $key
                if ($v -is [bool]) { $risk[$key] = $v }
            }
            $score = Get-SUField $Data 'company.abuser_score'
            if ($null -ne $score) { $risk['company_abuser_score_raw'] = $score }
        }
        'DB-IP' {
            $ip = Get-SUField $Data 'ipAddress'
            $country = Get-SUField $Data 'countryCode'
        }
        default { throw 'Unknown provider' }
    }
    if ($ip -cne $TargetIP) { throw 'Response IP missing or differs from target' }
    if (-not ($country -is [string]) -or -not $country.Trim()) { throw 'Missing country field' }
    return [pscustomobject]@{
        source=$Name; status='INFO'; ip=$ip; country=$country; asn=$asn
        asn_type=$type; company_type=$companyType
        risk_fields=[pscustomobject]$risk; risk_available=($risk.Count -gt 0); error=$null
    }
}

function Invoke-SUInspection {
    $before = Get-SUEgress
    $report = [pscustomobject]@{
        version='0.1.0'; timestamp_utc=[DateTime]::UtcNow.ToString('o'); ipv=4
        routing=$(if ($Proxy) { 'explicit-proxy' } else { 'os-route-no-system-proxy' })
        status='EGRESS-UNVERIFIED'; exit_code=2; egress_before=$before
        expected_ip=$ExpectedIP; providers=@(); egress_after=$null
        notes=@('No overall clean-IP score. Missing fields are unknown, never false.',
            'Two exit checks cannot prove every destination uses the same route.',
            'Database lookups explicitly query the verified target IP.',
            'No streaming, DNSBL, SMTP, or IPv6 coverage in this first version.')
    }
    if (-not $before.verified) { return $report }
    if ($ExpectedIP -and $before.ip -cne $ExpectedIP) {
        $report.status = 'EXPECTED-IP-MISMATCH'
        return $report
    }
    if ($CheckExitOnly) {
        $report.status='EXIT-VERIFIED'; $report.exit_code=0
        return $report
    }
    $target = $before.ip
    foreach ($provider in @(
        @('IPinfo', "https://ipinfo.io/widget/demo/$target"),
        @('ipapi.is', "https://api.ipapi.is/?q=$target"),
        @('DB-IP', "https://api.db-ip.com/v2/free/$target")
    )) {
        try {
            $data = (Invoke-SUHttp $provider[1]) | ConvertFrom-Json -ErrorAction Stop
            $report.providers += Convert-SUProvider $provider[0] $data $target
        } catch {
            $report.providers += [pscustomobject]@{
                source=$provider[0]; status='PROBE-FAIL'; ip=$target; country=$null
                asn=$null; asn_type=$null; company_type=$null; risk_fields=$null
                risk_available=$false; error=$_.Exception.Message
            }
        }
    }
    $report.egress_after = Get-SUEgress
    if (-not $report.egress_after.verified -or $report.egress_after.ip -cne $target) {
        $report.status='EGRESS-CHANGED-OR-UNVERIFIED'
        return $report
    }
    $good = @($report.providers | Where-Object { $_.status -eq 'INFO' }).Count
    if ($good -eq 0) { $report.status='ALL-PROBES-FAILED'; $report.exit_code=3 }
    elseif ($good -lt $report.providers.Count) { $report.status='PARTIAL'; $report.exit_code=0 }
    else { $report.status='COMPLETE'; $report.exit_code=0 }
    return $report
}

if ($LibraryOnly) { return }
if ($ExpectedIP -and -not (Test-SUIPv4 $ExpectedIP)) { throw 'ExpectedIP must be a public IPv4 address' }
if ($Proxy) {
    $uri = $null
    if (-not [Uri]::TryCreate($Proxy, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @('http','https','socks5','socks5h') -or -not $uri.Host) {
        throw 'Proxy must be an http(s):// or socks5(h):// URL'
    }
}
$curlName = 'curl'
if ($env:OS -eq 'Windows_NT') { $curlName = 'curl.exe' }
$script:SUCurl = (Get-Command $curlName -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$result = Invoke-SUInspection
if ($Json) { $result | ConvertTo-Json -Depth 12 }
else {
    Write-Output "StarUnlock IP (IPv4) | $($result.status)"
    Write-Output "Route: $($result.routing) | Verified IP: $($result.egress_before.ip)"
    $result.egress_before.observations | Format-Table source,ip,error -AutoSize | Out-String -Width 140 | Write-Output
    foreach ($row in $result.providers) {
        Write-Output "[$($row.status)] $($row.source): country=$($row.country) ASN=$($row.asn)"
        Write-Output "  ASN type=$($row.asn_type); company type=$($row.company_type)"
        if ($row.risk_available) { Write-Output ('  Risk fields: ' + ($row.risk_fields | ConvertTo-Json -Compress)) }
        else { Write-Output '  Risk fields: UNKNOWN / NOT PROVIDED' }
        if ($row.error) { Write-Output "  $($row.error)" }
    }
    if ($result.exit_code -eq 2) { Write-Output 'Exit validation failed. Do not use this run as an IP-quality verdict.' }
    Write-Output 'INFO = provider claims; PROBE-FAIL = no verdict. No overall clean/dirty score.'
    Write-Output 'Scope: three providers; no streaming, DNSBL, SMTP, or IPv6. No online report uploaded.'
}
# Piped download (irm ... | iex) must not exit the user's interactive shell.
# File callers still receive the documented native process exit code.
if ($MyInvocation.MyCommand.CommandType -eq 'ExternalScript') { exit $result.exit_code }
