param([string]$CheckerPath = "$PSScriptRoot/../ipquality.ps1")
$ErrorActionPreference='Stop'
. $CheckerPath -LibraryOnly
$passed=0
function Assert($Condition,[string]$Message){
 if(-not $Condition){throw "FAIL: $Message"}
 $script:passed++; Write-Output "PASS: $Message"
}
Assert ([bool](Get-Command Get-IPQualityArguments -ErrorAction SilentlyContinue)) 'original complete-report runner exists'
$flags=@(Get-IPQualityArguments)
Assert (($flags -join ' ') -eq '-4 -n -p') 'default runs full IPv4 report with only install/upload disabled'
Assert ((@(Get-IPQualityArguments $true $true) -join ' ') -eq '-6 -n -p -E') 'IPv6 and language flags preserve full mode'
$code=New-IPQualityLaunchScript $flags '203.0.113.10' 'test-report.json'
Assert ($code.Contains('bash "$root/upstream-3c0eb8856c67ad351020d1edd1bfd4e2515d32fe.cygwin.sh" -4 -n -p -o')) 'execute the patched copy of the pinned upstream with full-report flags'
Assert ($code.Contains('sed ''s/\\<//g; s/\\>//g'' "$root/upstream-3c0eb8856c67ad351020d1edd1bfd4e2515d32fe.sh" > "$root/upstream-3c0eb8856c67ad351020d1edd1bfd4e2515d32fe.cygwin.sh"')) 'GNU word-boundary regex patch is applied to a copy; the checksum-verified upstream file is untouched'
Assert ($code.Contains('Windows/runtime exit mismatch')) 'check native runtime exit against Windows'
Assert ($code.Contains('command -v "$tool"')) 'verify runtime dependencies before launching'
Assert ($code.Contains('unset http_proxy https_proxy all_proxy')) 'avoid inherited proxy drift in TUN mode'
$rejected=$false
try{New-IPQualityLaunchScript @('-4',';whoami') '203.0.113.10' 'test.json'|Out-Null}catch{$rejected=$true}
Assert $rejected 'reject arbitrary shell arguments'
$rejected=$false
try{New-IPQualityLaunchScript $flags '$(whoami)' 'test.json'|Out-Null}catch{$rejected=$true}
Assert $rejected 'reject shell text in expected exit'
$rejected=$false
try{New-IPQualityLaunchScript $flags '203.0.113.10' '../escape.json'|Out-Null}catch{$rejected=$true}
Assert $rejected 'report file stays inside reports directory'
Assert ($script:UpstreamSha256 -match '^[a-f0-9]{64}$') 'pinned source has a SHA256 verification value'
Assert ($code.Contains('| tee "$root/reports/test-report.json.ansi"')) 'preserve upstream Lite diagnostic in local output'
Assert ($code.Contains('exit "${PIPESTATUS[0]}"')) 'retain actual upstream process status through tee'
Write-Output "$passed tests passed"
