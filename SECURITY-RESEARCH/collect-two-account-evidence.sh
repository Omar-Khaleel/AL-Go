#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  collect-two-account-evidence.sh \
    --account-b <username> \
    --pr <number> \
    --pr-run <run-id> \
    --deploy-run <run-id>

Requirements:
  - Debian/Linux shell
  - git
  - gh authenticated as Account A with access to Omar-Khaleel/AL-Go
  - jq
EOF
}

ACCOUNT_B=''
PR_NUMBER=''
PR_RUN_ID=''
DEPLOY_RUN_ID=''
REPO='Omar-Khaleel/AL-Go'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --account-b)
      ACCOUNT_B="${2:?missing username}"
      shift 2
      ;;
    --pr)
      PR_NUMBER="${2:?missing PR number}"
      shift 2
      ;;
    --pr-run)
      PR_RUN_ID="${2:?missing PR run id}"
      shift 2
      ;;
    --deploy-run)
      DEPLOY_RUN_ID="${2:?missing deployment run id}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

for value_name in ACCOUNT_B PR_NUMBER PR_RUN_ID DEPLOY_RUN_ID; do
  if [[ -z "${!value_name}" ]]; then
    echo "Missing required value: $value_name" >&2
    usage >&2
    exit 2
  fi
done

command -v gh >/dev/null
command -v jq >/dev/null
command -v git >/dev/null
command -v sha256sum >/dev/null

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ROOT="$(pwd)/algo-two-account-evidence-${TIMESTAMP}"
RAW="$ROOT/raw"
ARTIFACTS="$ROOT/artifacts"
LOGS="$ROOT/logs"
mkdir -p "$RAW" "$ARTIFACTS" "$LOGS"

api_json() {
  local endpoint="$1"
  local output="$2"
  gh api \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    "$endpoint" > "$output"
}

printf 'Collecting repository and pull request metadata...\n'
api_json "/repos/$REPO" "$RAW/repository.json"
api_json "/repos/$REPO/pulls/$PR_NUMBER" "$RAW/pull-request.json"
api_json "/repos/$REPO/pulls/$PR_NUMBER/files?per_page=100" "$RAW/pull-request-files.json"
api_json "/repos/$REPO/collaborators/$ACCOUNT_B/permission" "$RAW/account-b-permission.json"

printf 'Collecting PR build run metadata...\n'
api_json "/repos/$REPO/actions/runs/$PR_RUN_ID" "$RAW/pr-build-run.json"
api_json "/repos/$REPO/actions/runs/$PR_RUN_ID/jobs?per_page=100" "$RAW/pr-build-jobs.json"
api_json "/repos/$REPO/actions/runs/$PR_RUN_ID/artifacts?per_page=100" "$RAW/pr-build-artifacts.json"

printf 'Collecting protected deployment run metadata...\n'
api_json "/repos/$REPO/actions/runs/$DEPLOY_RUN_ID" "$RAW/protected-deploy-run.json"
api_json "/repos/$REPO/actions/runs/$DEPLOY_RUN_ID/jobs?per_page=100" "$RAW/protected-deploy-jobs.json"
api_json "/repos/$REPO/actions/runs/$DEPLOY_RUN_ID/artifacts?per_page=100" "$RAW/protected-deploy-artifacts.json"

printf 'Collecting logs...\n'
gh run view "$PR_RUN_ID" --repo "$REPO" --log > "$LOGS/pr-build.log"
gh run view "$DEPLOY_RUN_ID" --repo "$REPO" --log > "$LOGS/protected-deploy.log"

printf 'Downloading workflow artifacts...\n'
(
  cd "$ARTIFACTS"
  mkdir -p pr-build protected-deploy
  gh run download "$PR_RUN_ID" --repo "$REPO" --dir pr-build || true
  gh run download "$DEPLOY_RUN_ID" --repo "$REPO" --dir protected-deploy || true
)

PR_AUTHOR="$(jq -r '.user.login' "$RAW/pull-request.json")"
PR_HEAD_REPO="$(jq -r '.head.repo.full_name' "$RAW/pull-request.json")"
PR_HEAD_SHA="$(jq -r '.head.sha' "$RAW/pull-request.json")"
PR_BASE_REF="$(jq -r '.base.ref' "$RAW/pull-request.json")"
PERMISSION="$(jq -r '.permission' "$RAW/account-b-permission.json")"
CHANGED_FILES="$(jq -r '.[].filename' "$RAW/pull-request-files.json" | sort)"

EXPECTED_FILES="$(printf '%s\n' app/Hello.al app/app.json | sort)"

cat > "$ROOT/CONTROL-RESULTS.md" <<EOF
# Two-account control results

- Timestamp UTC: $TIMESTAMP
- Repository: $REPO
- Account B requested username: $ACCOUNT_B
- PR number: $PR_NUMBER
- PR author: $PR_AUTHOR
- PR head repository: $PR_HEAD_REPO
- PR head SHA: $PR_HEAD_SHA
- PR base ref: $PR_BASE_REF
- Account B upstream permission: $PERMISSION
- PR build run ID: $PR_RUN_ID
- Protected deployment run ID: $DEPLOY_RUN_ID

## Changed files

\`\`\`text
$CHANGED_FILES
\`\`\`

## Expected changed files

\`\`\`text
$EXPECTED_FILES
\`\`\`
EOF

if [[ "$PR_AUTHOR" != "$ACCOUNT_B" ]]; then
  echo "PR author mismatch: expected $ACCOUNT_B, got $PR_AUTHOR" >&2
  exit 1
fi

if [[ "$PR_HEAD_REPO" == "$REPO" ]]; then
  echo 'The PR is not from an external fork.' >&2
  exit 1
fi

if [[ "$PERMISSION" != 'none' ]]; then
  echo "Account B permission is not none: $PERMISSION" >&2
  exit 1
fi

if [[ "$PR_BASE_REF" != 'research/algo-two-account-pr-prod' ]]; then
  echo "Unexpected PR base ref: $PR_BASE_REF" >&2
  exit 1
fi

if [[ "$CHANGED_FILES" != "$EXPECTED_FILES" ]]; then
  echo 'The PR changed unexpected files.' >&2
  printf 'Expected:\n%s\nActual:\n%s\n' "$EXPECTED_FILES" "$CHANGED_FILES" >&2
  exit 1
fi

if grep -RInE \
  --exclude='SHA256SUMS.txt' \
  --exclude='*.app' \
  '(client[_-]?secret[[:space:]]*[:=][[:space:]]*[^*[:space:]]|access[_-]?token[[:space:]]*[:=][[:space:]]*eyJ|Authorization:[[:space:]]*Bearer[[:space:]]+eyJ|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,})' \
  "$ROOT"; then
  echo 'Potential unredacted secret or JWT pattern found. Evidence package was not created.' >&2
  exit 1
fi

find "$ROOT" -type f ! -name SHA256SUMS.txt -print0 \
  | sort -z \
  | xargs -0 sha256sum \
  > "$ROOT/SHA256SUMS.txt"

ARCHIVE="${ROOT}.tar.gz"
tar -C "$(dirname "$ROOT")" -czf "$ARCHIVE" "$(basename "$ROOT")"
sha256sum "$ARCHIVE" > "${ARCHIVE}.sha256"

printf '\nEvidence directory: %s\n' "$ROOT"
printf 'Evidence archive: %s\n' "$ARCHIVE"
printf 'Archive checksum: %s\n' "${ARCHIVE}.sha256"
