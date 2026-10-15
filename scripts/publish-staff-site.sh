#!/bin/zsh
# Uploads a PaceBar DMG to the staff site and points PaceBar's tool page at it.
#   scripts/publish-staff-site.sh dist/PaceBar-1.2.0.dmg
#   scripts/publish-staff-site.sh --check     token and tool page only; changes nothing
# release.sh runs --check before building and the upload after notarizing, with PUBLISH=1.
#
# The DMG lives on the staff site, behind its Campus Outreach sign-in, rather than on GitHub, so
# it isn't a public download. Its stable address is /tools/pacebar/download, and Settings › About
# links to /tools/pacebar, so nothing in the app changes between releases.
#
# One-time setup: a staff-site admin creates an API token with only content:read, content:write
# and media:write, and a one-year expiry, then stores it in the login keychain:
#   security add-generic-password -s pacebar-staff-site -a release -w
# (it prompts for the token, so it never lands in shell history). The PaceBar tool entry must
# already exist; this only swaps its file.
#
# The token can edit any staff-site content, so it is never printed, written to disk, or put in
# a command line, where `ps` would show it: curl reads it from stdin.
set -euo pipefail

# Both overridable only to test against a local dev server (http://localhost:4321 and a keychain
# item holding a local token). Releases use the defaults.
SITE="${STAFF_SITE_URL:-https://staff-services.serve.campusoutreach.org}"
SLUG="pacebar"
# tools.download's hand-minted field id, the same on every staff-site database. An upload must
# name it: the site's global allowlist has no .dmg, and this field allows .dmg only.
FIELD_ID="01M0ZTTD0WNPKG000000000001"
KEYCHAIN_SERVICE="${STAFF_SITE_KEYCHAIN_SERVICE:-pacebar-staff-site}"
KEYCHAIN_ACCOUNT="release"

fail() { echo "staff site: $1" >&2; exit 1; }

if ! TOKEN="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null)"; then
    fail "no API token in the keychain. Add one with: security add-generic-password -s $KEYCHAIN_SERVICE -a $KEYCHAIN_ACCOUNT -w"
fi

# One API call. The Authorization header goes to curl as config on stdin, never as an argument.
api() {
    # Not `path`: in zsh that is tied to $PATH, and a local one hides curl.
    local method=$1 endpoint=$2
    shift 2
    printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" |
        curl --config - --silent --show-error --fail-with-body --max-time 300 \
            -X "$method" "$@" "$SITE/_emdash/api$endpoint"
}

# Reads JSON on stdin and prints one value. -I keeps Python from importing anything nearby.
json() { /usr/bin/python3 -I -c "import json, sys; d = json.load(sys.stdin); print($1)"; }

entry="$(api GET "/content/tools/$SLUG")" \
    || fail "couldn't read the $SLUG tool entry. Is the token valid and unexpired, and does $SITE/tools/$SLUG exist?"
ENTRY_ID="$(json "d['data']['item']['id']" <<<"$entry")"

if [[ "${1:-}" == "--check" ]]; then
    echo "Staff site: token works and /tools/$SLUG exists."
    exit 0
fi

DMG="${1:-}"
[[ -f "$DMG" && "$DMG" == *.dmg ]] || fail "pass the DMG to upload, e.g. dist/PaceBar-1.2.0.dmg"
NAME="${DMG:t}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Uploading $NAME to the staff site…"
api POST /media -F "file=@$DMG;type=application/x-apple-diskimage" -F "fieldId=$FIELD_ID" \
    >"$WORK/upload.json" || fail "upload failed: $(cat "$WORK/upload.json")"

# The value a file field stores: the shape the admin's file picker writes. Re-read the entry
# right before the update so its _rev is current; a stale one is rejected as a conflict.
api GET "/content/tools/$SLUG" >"$WORK/entry.json" || fail "couldn't re-read the tool entry"
/usr/bin/python3 -I - "$WORK/upload.json" "$WORK/entry.json" "$WORK/body.json" <<'PY'
import json, sys
upload, entry, body = sys.argv[1:4]
item = json.load(open(upload))["data"]["item"]
rev = json.load(open(entry))["data"]["_rev"]
value = {
    "id": item["id"], "provider": "local", "filename": item["filename"],
    "mimeType": item["mimeType"], "size": item["size"], "meta": {"storageKey": item["storageKey"]},
}
json.dump({"_rev": rev, "data": {"download": value}}, open(body, "w"))
PY

api PUT "/content/tools/$ENTRY_ID" -H "Content-Type: application/json" --data-binary "@$WORK/body.json" >/dev/null \
    || fail "couldn't update the tool entry"
# The update only writes a draft. Without publishing, the page keeps serving the old file.
api POST "/content/tools/$ENTRY_ID/publish" >/dev/null || fail "couldn't publish the tool entry"

# The API can't download the file back (the media route wants a browser session), so this
# checks the published entry names the file just uploaded.
entry="$(api GET "/content/tools/$SLUG")" || fail "couldn't read the tool entry back"
published="$(json "d['data']['item']['status'] + ' ' + ((d['data']['item']['data'].get('download') or {}).get('filename') or '')" <<<"$entry")"
[[ "$published" == "published $NAME" ]] || fail "the tool entry reads '$published', expected 'published $NAME'"

echo "Staff site: $SITE/tools/$SLUG now offers $NAME."
