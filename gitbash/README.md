# Git Bash edition — same original `ip.sh`, ~1 MB instead of 70 MB

For machines that already have **Git for Windows**. No Cygwin download; `ip.sh` is fetched from
`https://IP.Check.Place` at run time and executed as-is (plus the same one-line regex patch as the main launcher).

```powershell
irm https://raw.githubusercontent.com/starsdaisuki/windows-ip-check/v3/gitbash/win.ps1 | iex
```

Extra flags: `$env:STARUNLOCK_ARGS="-6"; irm ... | iex` (default `-4 -p`). Unpacks to `%LOCALAPPDATA%\WindowsIPCheck\gitbash`.
`jq.exe` is downloaded from jq's official GitHub release, not stored in this repo.

## What the shims cover

| missing on Git Bash | shim | script usage |
|---|---|---|
| `jq` | jq 1.7.1 release binary | all parsing |
| `bc` | awk | coordinate conversion only |
| `nc` | bash `/dev/tcp` | port-25 probes only |
| `dig` | Cloudflare DoH (JSON) | 4 call shapes incl. the 423-entry DNSBL sweep |
| `nslookup` | Windows `nslookup.exe` re-laid-out | localized Windows prints `名称:`; script greps `Name:` |
| `ss` | `netstat -ano` | `ss -tano \| grep :25` only |
| `date` | `TZ=Asia/Shanghai` → `CST-8` | MSYS has no zoneinfo; report time would show UTC |

Git Bash started as a plain process has no `/usr/bin` on PATH; `run.sh` adds it.

## Known differences vs a Linux run of the same exit IP
- Port-25 may read “可用” where Linux says “阻断”: upstream `nc -s <exitIP>` binds a source address the host doesn't own and fails; the shim can't bind it and actually connects. Not an IP property.
- TikTok region label can differ (`[ALISG]` vs `[JP]`): it follows the client fingerprint (Windows curl), not the IP.
- `(Lite)` in the title = the author's aggregation API rate-limited this IP (observed: first run of the day full, later runs Lite). Retry later.
