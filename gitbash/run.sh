#!/bin/bash
# windows-ip-check Git Bash launcher — runs xykt IPQuality (ip.sh) UNMODIFIED on Windows.
# Requires Git for Windows only. jq is bundled in bin/, and bc/nc/dig are shimmed in shim/.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Git Bash started as a plain (non-login) process does NOT have /usr/bin on PATH -> no sed/grep/awk.
export PATH="$HERE/shim:$HERE/bin:/usr/bin:/mingw64/bin:$PATH"
export TERM="${TERM:-xterm}"
if [ ! -s "$HERE/ip.sh" ] || [ -n "$STARUNLOCK_REFRESH" ]; then
  curl -sL --max-time 20 https://IP.Check.Place -o "$HERE/ip.sh" || { echo "download ip.sh failed"; exit 1; }
fi
# One portability patch (the only change to ip.sh): its IPv4 regex uses GNU word boundaries \< \>,
# which glibc accepts but MSYS/Cygwin regcomp does not -> every IP "invalid" -> calc_ip_net returns ""
# -> "" == "" -> "same /24 as the DNS server" -> every service mislabeled as DNS-unlock.
# The pattern is ^...\.{3}...$ anchored, so dropping the boundaries is semantically identical.
sed -i 's/\\<//g; s/\\>//g' "$HERE/ip.sh"
# -n: skip the OS/package-manager probe (there is no apt on Windows); everything else is stock.
exec bash "$HERE/ip.sh" -n "$@"
