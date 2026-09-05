# Standalone tests: PowerShell 5.1/7, no Pester or network required.
param([string]$CheckerPath = "$PSScriptRoot/../ipquality.ps1")
$ErrorActionPreference = 'Stop'
. $CheckerPath -LibraryOnly
$script:passed = 0
function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:passed++
    Write-Output "PASS: $Message"
}
$target = '1.1.1.1'
$info = '{"data":{"ip":"1.1.1.1","country":"JP","privacy":{"vpn":false,"hosting":true}}}' | ConvertFrom-Json
$row = Convert-SUProvider IPinfo $info $target
Assert ($row.risk_fields.vpn -ceq $false -and $row.risk_fields.hosting -ceq $true) 'preserve true and false risk fields'
Assert ($null -eq $row.risk_fields.proxy) 'absent risk is unknown, never false'
$free = '{"ip":"1.1.1.1","country":"Japan","asn":"AS64500 Example"}' | ConvertFrom-Json
$row = Convert-SUProvider ipapi.is $free $target
Assert (-not $row.risk_available -and $row.country -eq 'Japan') 'free-tier geolocation does not claim risk coverage'
$failed = $false
try { Convert-SUProvider IPinfo $info '8.8.8.8' | Out-Null } catch { $failed=$true }
Assert $failed 'provider returning another IP is rejected'
Assert (-not (Test-SUIPv4 '<html>blocked</html>')) 'WAF page is not an IP'
Assert (-not (Test-SUIPv4 '127.0.0.1') -and -not (Test-SUIPv4 '10.0.0.1')) 'local/private exit replies are rejected'
Assert (-not (Test-SUIPv4 '198.18.0.1') -and -not (Test-SUIPv4 '203.0.113.10')) 'fake-IP and documentation ranges are not public exits'

function Reset-Mock {
    $script:scenario='good'; $script:exitCalls=0; $script:providerCalls=0
    $script:ExpectedIP=''; $script:CheckExitOnly=$false
}
function Invoke-SUHttp([string]$Url) {
    if ($Url -eq 'https://api.ipify.org' -or $Url -like '*/cdn-cgi/trace') {
        $script:exitCalls++
        $ip='1.1.1.1'
        if (($script:scenario -eq 'split' -and $Url -like '*/trace') -or
            ($script:scenario -eq 'changed' -and $script:exitCalls -gt 2)) { $ip='8.8.8.8' }
        if ($script:scenario -eq 'timeout') { throw 'Request timeout' }
        if ($Url -like '*/trace') { return "ip=$ip`nloc=JP`n" }
        return $ip
    }
    $script:providerCalls++
    if ($script:scenario -eq 'allfail') { throw 'HTTP 403 (no IP verdict)' }
    if ($Url -like 'https://ipinfo.io/*') {
        if ($script:scenario -eq 'html') { return '<html>Challenge</html>' }
        return '{"data":{"ip":"1.1.1.1","country":"JP","privacy":{"vpn":false}}}'
    }
    if ($Url -like 'https://api.ipapi.is/*') { return '{"ip":"1.1.1.1","country":"Japan"}' }
    if ($Url -like 'https://api.db-ip.com/*') { return '{"ipAddress":"1.1.1.1","countryCode":"JP"}' }
    throw 'Unexpected endpoint'
}
Reset-Mock
$r=Invoke-SUInspection
Assert ($r.status -eq 'COMPLETE' -and $r.providers.Count -eq 3 -and $script:exitCalls -eq 4) 'end-to-end with pre/post exit checks'
Reset-Mock
$script:ExpectedIP='9.9.9.9'
$r=Invoke-SUInspection
Assert ($r.status -eq 'EXPECTED-IP-MISMATCH' -and $script:providerCalls -eq 0) 'wrong expected exit stops before database queries'
Reset-Mock
$script:scenario='split'
$r=Invoke-SUInspection
Assert ($r.exit_code -eq 2 -and $script:providerCalls -eq 0) 'split exits stop before database queries'
Reset-Mock
$script:scenario='timeout'
$r=Invoke-SUInspection
Assert ($r.exit_code -eq 2 -and $script:providerCalls -eq 0) 'exit timeout is not a clean result'
Reset-Mock
$script:scenario='changed'
$r=Invoke-SUInspection
Assert ($r.status -eq 'EGRESS-CHANGED-OR-UNVERIFIED' -and $r.exit_code -eq 2) 'mid-run IP change invalidates the run'
Reset-Mock
$script:scenario='html'
$r=Invoke-SUInspection
Assert ($r.status -eq 'PARTIAL' -and $r.providers[0].status -eq 'PROBE-FAIL') 'HTML/WAF response is probe failure, never blocked'
Reset-Mock
$script:scenario='allfail'
$r=Invoke-SUInspection
Assert ($r.exit_code -eq 3 -and $r.status -eq 'ALL-PROBES-FAILED') 'all providers unavailable is nonzero, never clean'
Reset-Mock
$script:CheckExitOnly=$true
$r=Invoke-SUInspection
Assert ($r.status -eq 'EXIT-VERIFIED' -and $script:providerCalls -eq 0) 'exit-only mode never contacts databases'
Write-Output "$script:passed tests passed"
