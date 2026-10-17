#!/usr/bin/env bash
# Writes the public client configuration (config.js) next to the bundled web app.
# Usage:  set -a; source .env; set +a; scripts/make-config.sh
# In GitHub Actions the values come from repository secrets (see docs/BACKEND.md).
set -euo pipefail
cd "$(dirname "$0")/.."
URL="${SUPABASE_URL:-}"; KEY="${SUPABASE_ANON_KEY:-}"; MAPS="${GOOGLE_MAPS_API_KEY:-}"

# Refuse server secrets. A service-role key must never be shipped inside an app.
if [[ "$KEY" == sb_secret_* ]]; then echo "ERROR: that looks like a secret key. Use the anon/publishable key." >&2; exit 1; fi
if [[ "$KEY" == eyJ* ]]; then
  ROLE=$(python3 -I - "$KEY" <<'PY'
import sys, json, base64
try:
    p = sys.argv[1].split(".")[1]; p += "=" * (-len(p) % 4)
    print(json.loads(base64.urlsafe_b64decode(p)).get("role", ""))
except Exception:
    print("")
PY
)
  if [[ "$ROLE" == "service_role" ]]; then echo "ERROR: SUPABASE_ANON_KEY is a service_role key. Refusing to write it into the app." >&2; exit 1; fi
fi
if [[ -n "$URL" && ! "$URL" =~ ^https://[a-z0-9-]+\.supabase\.(co|in)$ ]]; then echo "ERROR: SUPABASE_URL should look like https://xxxx.supabase.co" >&2; exit 1; fi

esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
BODY="window.NIROG_CONFIG = {
  supabaseUrl: \"$(esc "$URL")\",
  supabaseAnonKey: \"$(esc "$KEY")\",
  googleMapsKey: \"$(esc "$MAPS")\",
  patientAuth: \"${PATIENT_AUTH:-google}\",
  googleLogin: true
};"
if [[ -z "$URL" || -z "$KEY" ]]; then echo "No Supabase values supplied: keeping the committed config.js unchanged."; exit 0; fi
for d in app/src/main/assets/www web; do printf '%s\n' "$BODY" > "$d/config.js"; done
echo "config.js written for $URL"
