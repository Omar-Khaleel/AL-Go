# Account B — external fork PR commands

Replace `<ACCOUNT_B>` with the second GitHub username.

The second account must not be added as a collaborator to `Omar-Khaleel/AL-Go`.

## Fork

While logged in as Account B, fork:

`Omar-Khaleel/AL-Go`

The fork should be:

`<ACCOUNT_B>/AL-Go`

## Debian terminal

```bash
set -euo pipefail

ACCOUNT_B='<ACCOUNT_B>'
WORKDIR="$HOME/algo-account-b-proof"

rm -rf "$WORKDIR"
git clone "https://github.com/${ACCOUNT_B}/AL-Go.git" "$WORKDIR"
cd "$WORKDIR"

git remote add upstream https://github.com/Omar-Khaleel/AL-Go.git
git fetch upstream research/algo-two-account-pr-prod

git switch --create attack/algo-pr-prod-proof FETCH_HEAD

git apply SECURITY-RESEARCH/account-b-attacker.patch

printf '\nChanged files:\n'
git status --short

changed_files="$(git diff --name-only | sort)"
expected_files="$(printf '%s\n' app/Hello.al app/app.json | sort)"

if [ "$changed_files" != "$expected_files" ]; then
  echo 'Unexpected changed files. Stop.' >&2
  printf 'Expected:\n%s\nActual:\n%s\n' "$expected_files" "$changed_files" >&2
  exit 1
fi

if git diff --name-only | grep -q '^\.github/'; then
  echo 'A .github file changed. Stop.' >&2
  exit 1
fi

git diff --check

git add app/app.json app/Hello.al
git commit -m 'Add external fork AL-Go protected deployment proof app'
git push --set-upstream origin attack/algo-pr-prod-proof
```

## Open the pull request

Using GitHub CLI authenticated as Account B:

```bash
gh pr create \
  --repo Omar-Khaleel/AL-Go \
  --base research/algo-two-account-pr-prod \
  --head "${ACCOUNT_B}:attack/algo-pr-prod-proof" \
  --title '[EXTERNAL ACCOUNT] AL-Go protected deployment artifact proof' \
  --body 'Controlled two-account security research. This PR changes only app/app.json and app/Hello.al. It does not modify workflows, custom deployment scripts, repository settings, or secrets. Do not merge.'
```

Alternatively, open the PR in the GitHub web UI with:

- base repository: `Omar-Khaleel/AL-Go`
- base branch: `research/algo-two-account-pr-prod`
- head repository: `<ACCOUNT_B>/AL-Go`
- compare branch: `attack/algo-pr-prod-proof`

## Do not do any of the following

Account B must not:

- accept a collaborator invitation;
- push to `Omar-Khaleel/AL-Go`;
- change any `.github` file;
- receive an AuthContext;
- be added as an environment reviewer;
- approve or dispatch the protected deployment;
- merge the PR.

## Send back to Account A

Provide only:

- Account B username;
- PR URL or PR number;
- PR head SHA after the build starts.

Never provide passwords, tokens, cookies, private keys, or AuthContext values.
