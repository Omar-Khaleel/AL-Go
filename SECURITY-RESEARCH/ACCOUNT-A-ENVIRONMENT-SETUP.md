# Account A — exact GitHub Environment setup

Repository: `Omar-Khaleel/AL-Go`

Environment name: `ProductionProof`

## GitHub UI

1. Open the repository.
2. Open **Settings**.
3. Open **Environments**.
4. Select **New environment**.
5. Enter `ProductionProof` and create it.
6. Under deployment branches and tags, choose **Selected branches and tags**.
7. Add this exact branch:

   `research/algo-two-account-pr-prod`

8. Do not allow the Account B fork branch.
9. Add Account A as a required reviewer if the repository plan supports environment reviewers.
10. Keep self-review enabled for this two-account test; disabling self-review would require a third trusted account.
11. Add environment secret:

   `ProductionProof_AuthContext`

12. Copy the value from the existing researcher-owned `Sandbox_AuthContext` or create a new AL-Go AuthContext scoped only to the disposable Business Central test tenant.
13. Never place the secret in a PR, workflow file, issue, log, screenshot, or chat message.

## Required evidence screenshots

Capture screenshots showing only configuration, never the secret value:

- environment name;
- selected deployment branch;
- required reviewer configuration, if enabled;
- secret name `ProductionProof_AuthContext` with its value hidden;
- Account B absent from reviewers and repository collaborators.

## Workflow dispatch after the external PR build succeeds

Open **Actions** → **Publish To Environment** → **Run workflow**.

Choose branch:

`research/algo-two-account-pr-prod`

Inputs:

- App version: `PR_<external PR number>`
- Environment name: `ProductionProof`
- Create environment if it does not exist: `false`

Do not use `main`, `setup-algo-poc`, the fork branch, or the PR merge ref for the protected deployment run.
