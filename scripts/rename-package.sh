#!/usr/bin/env bash
# Renames the Android package everywhere. Usage: scripts/rename-package.sh com.yadaplus.app
# Before running: add an Android app with the NEW package name in Firebase, download its google-services.json and put it in app/.
set -euo pipefail
cd "$(dirname "$0")/.."
NEW="${1:?usage: rename-package.sh new.package.name}"
OLD="com.nirog.app"
[[ "$NEW" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]] || { echo "invalid package name"; exit 1; }
[ "$NEW" != "$OLD" ] || { echo "already $OLD"; exit 1; }
OLD_DIR="app/src/main/java/${OLD//.//}"; NEW_DIR="app/src/main/java/${NEW//.//}"
[ -d "$OLD_DIR" ] || { echo "$OLD_DIR not found"; exit 1; }
mkdir -p "$(dirname "$NEW_DIR")"; git mv "$OLD_DIR" "$NEW_DIR"
find app/src/main/java -type d -empty -delete
grep -rIl --exclude-dir=.git --exclude-dir=build --exclude=google-services.json "$OLD" . | xargs sed -i "s/${OLD//./\\.}/$NEW/g"
if ! grep -q "\"package_name\": \"$NEW\"" app/google-services.json; then echo "WARNING: app/google-services.json is not for $NEW yet. Replace it with the file from Firebase."; fi
echo "Done. Review with: git diff --stat"
