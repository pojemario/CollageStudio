#!/bin/zsh
# crashcheck.sh <device-udid> [out-dir]
#
# Pulls CollageStudio's crash reports and the app's own diagnostics log off a
# connected phone and prints, for each crash not seen before, the app version,
# the exception and the top of the crashing thread.
#   - iOS crash reports: devicectl domain systemCrashLogs (CollageStudio-*.ips)
#   - the app's trail: Library/Logs/Diagnostics (session.log, crash-*.log)
# Crashes already reported are remembered in <out-dir>/seen.txt.
set -u
DEV=${1:?device udid}
OUT=${2:-$HOME/Library/Caches/CollageStudio-crashes/$DEV}
mkdir -p "$OUT/ips"
touch "$OUT/seen.txt"

names=$(xcrun devicectl device info files --device "$DEV" --domain-type systemCrashLogs 2>/dev/null \
  | awk '{print $1}' | grep -E '(^|/)CollageStudio-.*\.ips$')
new=()
for n in ${(f)names}; do
  grep -qxF "$n" "$OUT/seen.txt" && continue
  xcrun devicectl device copy from --device "$DEV" --domain-type systemCrashLogs \
    --source "$n" --destination "$OUT/ips/${n:t}" >/dev/null 2>&1 && new+=("$OUT/ips/${n:t}")
  echo "$n" >> "$OUT/seen.txt"
done

# (devicectl wants a destination that doesn't exist yet; the folder's files land in it)
rm -rf "$OUT/diag"
xcrun devicectl device copy from --device "$DEV" --domain-type appDataContainer \
  --domain-identifier com.collagestudio.app --source Library/Logs/Diagnostics \
  --destination "$OUT/diag" >/dev/null 2>&1

echo "== ${#new[@]} new crash report(s)"
for f in $new; do
  python3 -I - "$f" <<'EOF'
import json, sys
raw = open(sys.argv[1]).read()
head, _, body = raw.partition('\n')
h, j = json.loads(head), json.loads(body)
print(f"--- {sys.argv[1].split('/')[-1]}  v{h.get('app_version')} ({h.get('build_version')})")
e = j.get('exception', {})
print(f"    {e.get('type')} {e.get('signal')}  {j.get('termination', {}).get('indicator', '')}")
imgs, th = j['usedImages'], j['threads'][j['faultingThread']]
for fr in th['frames'][:14]:
    img = imgs[fr['imageIndex']].get('name', '?')
    print(f"    {img:28} {fr.get('symbol', hex(fr.get('imageOffset', 0)))}")
EOF
done

echo "== diagnostics ($OUT/diag)"
for f in $OUT/diag/crash-*.log(N); do
  echo "--- ${f:t} (last lines)"; tail -n 12 "$f"
done
[[ -f $OUT/diag/session.log ]] && { echo "--- session.log (last lines)"; tail -n 5 "$OUT/diag/session.log"; }
