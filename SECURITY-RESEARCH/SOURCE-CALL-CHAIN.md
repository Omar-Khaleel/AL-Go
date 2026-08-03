# AL-Go PR artifact to custom protected deployment call chain

Prepared: 2026-08-04

## Upstream references

### `microsoft/AL-Go-PTE`

File: `.github/workflows/PublishToEnvironment.yaml`

Observed blob SHA: `4c9d43e654690b8dcc6fd0d9312e0f8c45f5842d`

Relevant behavior:

1. `workflow_dispatch` accepts `appVersion`, explicitly including `PR_<PR Id>`.
2. The Deploy job is bound to `environment: ${{ matrix.environment }}`.
3. The job reads `<environment>-AuthContext`, `<environment>_AuthContext`, or `AuthContext`.
4. It invokes `GetArtifactsForDeployment` using `github.event.inputs.appVersion`.
5. It invokes `Deploy` with the environment secrets and the same `artifactsVersion` input.

This creates a trusted protected job that can intentionally select a PR artifact.

## PR artifact resolution

### `microsoft/AL-Go-Actions/GetArtifactsForDeployment/GetArtifactsForDeployment.ps1`

Release: `v9.1`

Observed blob SHA: `52cc7be24212ebccf70771ca4bb449aa354a0982`

For `artifactsVersion -like "PR_*"`, the action:

1. extracts the PR number;
2. calls `GetLatestCommitShaFromPRId`;
3. calls `FindLatestPRRun` for that commit;
4. requires the latest `Pull Request Build` to be completed and successful;
5. obtains PR workflow artifacts;
6. downloads the PR artifact set into `.artifacts`.

### `microsoft/AL-Go-Actions/GetArtifactsForDeployment/GetArtifactsForDeployment.psm1`

Release: `v9.1`

Observed blob SHA: `c354e9e7b5f2a80e2308c9cc92e07261e6da08d2`

`FindLatestPRRun` accepts workflow runs named `Pull Request Build` with event `pull_request` or `pull_request_target`.

`GetLatestCommitShaFromPRId` obtains the current PR head SHA through the GitHub pulls API.

`DownloadPRArtifacts` downloads and unpacks the artifact archive selected from the PR run.

## Protected secret and custom script boundary

### `microsoft/AL-Go-Actions/Deploy/Deploy.ps1`

Release: `v9.1`

Observed blob SHA: `7851dcd5c077ccf80a33d617495590b86548d8f4`

The action:

1. obtains the deployment settings for the selected GitHub Environment;
2. reads and decodes the selected environment's `AuthContext`;
3. resolves Apps and Dependencies from the downloaded artifact directory;
4. searches the trusted checkout for `.github/DeployTo<EnvironmentType>.ps1`;
5. if the custom script exists, creates this parameter map:

```powershell
$parameters = @{
    "type" = $type
    "AuthContext" = $authContext
    "Apps" = $apps
    "Dependencies" = $dependencies
} + $deploymentSettings
```

6. invokes the custom script immediately:

```powershell
. $customScript -parameters $parameters
```

## Missing provenance at the extension boundary

The Deploy action itself receives `artifactsVersion`, but the custom-script parameter map does not include it.

The parameter map also does not include an authoritative:

- PR number;
- PR head SHA;
- source repository;
- fork status;
- producing workflow ID;
- producing workflow run ID;
- artifact ID;
- artifact digest;
- artifact attestation result.

A custom deployment implementation receives the protected credential and artifact paths but cannot reliably distinguish a release artifact from an external PR artifact using the supplied trusted parameters.

Artifact folder or filename patterns are not an authorization boundary and are not a substitute for provenance passed from the action that performed the GitHub API resolution.

## Built-in guard is below the custom branch

When no custom script exists, `Deploy.ps1` enters the default-deployment `else` branch, creates a Business Central auth context, queries the target environment, and determines:

```powershell
$sandboxEnvironment = ($response.environmentType -eq 1)
```

It then refuses PR deployment to a non-sandbox target:

```powershell
elseif (!$sandboxEnvironment -and $artifactsVersion -like "PR_*") {
    Write-Host "::Warning::Ignoring environment ... as deploying from a PR is only supported in sandbox environments"
}
```

This check is not executed when a custom deployment script exists because the script is invoked in the earlier branch.

## Documented custom-deployment contract

Microsoft's AL-Go customization documentation describes custom deployment as a supported feature and shows a `.github/DeployTo<EnvironmentType>.ps1` script receiving and parsing `parameters.authContext`.

Therefore the vulnerability theory is not that receiving `AuthContext` is undocumented. The theory is the inconsistent authorization policy and missing provenance at the supported extension boundary:

- built-in deployment enforces PR-to-non-sandbox policy;
- custom deployment bypasses that code path;
- the extension is not given the trusted provenance needed to enforce the same policy.

## Research implementation

Trusted branch: `research/algo-two-account-pr-prod`

Prepared files:

- `.github/workflows/ResearchPullRequestHandler.yaml`
- `.github/AL-Go-Settings.json`
- `.github/DeployToProductionProof.ps1`
- `SECURITY-RESEARCH/account-b-attacker.patch`
- `SECURITY-RESEARCH/TWO-ACCOUNT-PR-PRODUCTION-PLAN.md`
- `SECURITY-RESEARCH/MSRC-REPORT-DRAFT.md`

The runtime proof must demonstrate an external fork account with permission `none`, an app-only PR, a successful secretless PR build, and a separate protected deployment run using the trusted base branch and `ProductionProof` environment.
