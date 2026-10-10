#!/usr/bin/env bash
# Fails if the repository contains something that looks like a server secret.
set -uo pipefail
cd "$(dirname "$0")/.."
bad=0
if git ls-files | grep -E '(^|/)\.env($|\.)' | grep -v '\.env\.example$'; then echo "ERROR: an .env file is tracked"; bad=1; fi
HITS=$(git grep -nIE 'sb_secret_[A-Za-z0-9_-]{10,}|service_role[^a-zA-Z_ ]*["'"'"' ]*[:=][ ]*["'"'"']eyJ' -- . ':!scripts/check-no-secrets.sh' ':!docs' ':!supabase' || true)
if [ -n "$HITS" ]; then echo "$HITS"; echo "ERROR: possible service-role secret in source"; bad=1; fi
# Any JWT in the tree must be an anon key (role != service_role).
for j in $(git grep -hoIE 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' -- . ':!docs' || true); do
  r=$(python3 -I -c "import sys,json,base64;p=sys.argv[1].split('.')[1];p+='='*(-len(p)%4);print(json.loads(base64.urlsafe_b64decode(p)).get('role',''))" "$j" 2>/dev/null)
  if [ "$r" = "service_role" ]; then echo "ERROR: a service_role JWT is committed"; bad=1; fi
done
[ $bad -eq 0 ] && echo "no server secrets found"
exit $bad
