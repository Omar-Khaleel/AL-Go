# Draft — AL-Go custom deployment imports external PR artifacts into protected deployment identity without authoritative provenance

> Status: **Do not submit until the two-account runtime evidence fields are completed.**

Previous submission: `VULN-190103` / Case `118501`

Tested target:

- `microsoft/AL-Go-Actions`
- `microsoft/AL-Go-PTE`
- AL-Go Actions release: `v9.1`
- Research repository: `Omar-Khaleel/AL-Go`
- Trusted test branch: `research/algo-two-account-pr-prod`

## Suggested title

**AL-Go custom deployment bypasses PR-to-non-sandbox enforcement and passes external-fork artifacts with protected AuthContext without source provenance**

## Suggested classification

- Vulnerability type: Elevation of Privilege / deployment trust-boundary bypass
- Primary CWE candidate: CWE-863 — Incorrect Authorization
- Secondary CWE candidate: CWE-345 — Insufficient Verification of Data Authenticity
- Final CVSS: **TBD after runtime impact proof**

## Executive summary

AL-Go's trusted `PublishToEnvironment` workflow supports selecting artifacts from a pull request using `appVersion=PR_<id>`. It resolves the PR head commit, locates the latest successful `Pull Request Build`, downloads the resulting PR artifacts, enters a protected GitHub Environment, reads the environment `AuthContext`, and invokes the AL-Go Deploy action.

The Deploy action has two materially different authorization paths:

1. The built-in deployment path detects whether the Business Central target is a sandbox and refuses `PR_*` artifacts for non-sandbox environments.
2. The documented custom-deployment path executes `.github/DeployTo<EnvironmentType>.ps1` first and passes it `AuthContext`, Apps, Dependencies, and deployment settings.

The PR-to-non-sandbox restriction is located only in the built-in `else` path and is therefore not applied before custom deployment. In addition, the custom deployment parameter map omits authoritative artifact provenance such as `artifactsVersion`, PR ID, source repository, PR head SHA, producing workflow run ID, artifact digest, or attestation. A trusted custom deployment implementation therefore receives the external PR artifact and protected deployment credential but does not receive the authoritative context needed to reproduce AL-Go's built-in PR policy.

The new two-account proof uses an external fork account with no permission on the upstream repository. That account modifies only AL application source. It cannot modify the trusted workflows, custom deployment script, GitHub Environment, environment reviewer, or `AuthContext`. The external PR is built in an unprivileged PR workflow. A separate trusted `PublishToEnvironment` run on the protected base branch then imports the PR artifact into the protected custom deployment job.

## Why this is materially different from Case 118501

The previous report demonstrated an explicitly authorized feature branch executing its own custom deployment script with `AuthContext`. MSRC could reasonably classify that as a repository owner allowing a branch to define its deployment implementation.

This proof changes the attacker model:

- the attacker is an external fork user with upstream permission `none`;
- the attacker cannot modify any trusted workflow or deployment script;
- only AL application source is attacker-controlled;
- the artifact is produced in a secretless PR build;
- the protected job executes trusted base-branch code;
- the trusted AL-Go workflow itself imports the external artifact into that job;
- the custom extension receives protected `AuthContext` but no authoritative source provenance.

The trust mismatch is therefore between a trusted protected deployment job and a separately produced external-fork artifact, not between a branch and a script controlled by the same authorized writer.

## Relevant source flow

### 1. Trusted workflow accepts PR artifacts

`AL-Go-PTE/.github/workflows/PublishToEnvironment.yaml` exposes `appVersion`, including `PR_<PR Id>`.

The protected Deploy job:

1. checks out the trusted workflow ref;
2. reads environment secrets;
3. calls `GetArtifactsForDeployment` with the operator-supplied artifact version;
4. calls `Deploy` with the protected environment's secrets and the downloaded artifact folder.

### 2. PR source is resolved and its artifacts are downloaded

`AL-Go-Actions/GetArtifactsForDeployment/GetArtifactsForDeployment.ps1`:

- recognizes `PR_*`;
- obtains the current PR head SHA;
- locates the latest successful `Pull Request Build` for that SHA;
- downloads the PR Apps, TestApps, Dependencies, and PowerPlatformSolution artifacts.

### 3. Custom deployment runs before the built-in PR policy

`AL-Go-Actions/Deploy/Deploy.ps1`:

- reads and decodes `AuthContext`;
- resolves Apps from the downloaded artifacts;
- searches the trusted checkout for `.github/DeployTo<EnvironmentType>.ps1`;
- when present, constructs a parameter map containing `type`, `AuthContext`, `Apps`, `Dependencies`, and deployment settings;
- invokes the trusted custom script immediately.

The custom parameter map does **not** include the Deploy action's `artifactsVersion` input or another authoritative provenance object.

### 4. Built-in non-sandbox PR enforcement is unreachable from custom deployment

Only in the default-deployment `else` branch does AL-Go query the target's environment type and refuse deployment when:

- the target is not a sandbox; and
- `artifactsVersion` matches `PR_*`.

Because custom deployment returns through the earlier branch, that enforcement is not applied to custom environments and cannot be reliably reproduced by the custom extension from the supplied parameters.

## Threat model

### Victim administrator — Account A

Controls:

- upstream repository administration;
- trusted branch `research/algo-two-account-pr-prod`;
- trusted workflows and custom deployment script;
- GitHub Environment `ProductionProof`;
- required deployment review;
- `ProductionProof_AuthContext`;
- disposable Business Central tenant and target environment.

### External attacker — Account B

Has:

- upstream repository permission: **TBD / expected `none`**;
- a fork of the public repository;
- ability to open a pull request;
- control only over `app/app.json` and `app/Hello.al` in the proof PR.

Cannot:

- push to the trusted branch;
- modify upstream `.github` files;
- dispatch upstream workflows;
- read or use `ProductionProof_AuthContext`;
- approve `ProductionProof` deployment;
- directly query or modify the Business Central target.

## Reproduction

### Prerequisites

1. Two researcher-owned GitHub accounts.
2. A public controlled AL-Go repository.
3. A protected GitHub Environment named `ProductionProof`.
4. A disposable Business Central target named `Sandbox`.
5. `ProductionProof_AuthContext` scoped only to the disposable test tenant.

### Account A setup

1. Use trusted branch `research/algo-two-account-pr-prod`.
2. Configure `.github/AL-Go-Settings.json` with custom environment type `ProductionProof` and Business Central target `Sandbox`.
3. Keep `.github/DeployToProductionProof.ps1` immutable from Account B.
4. Configure `ProductionProof` to permit only the trusted branch and require Account A approval where supported.

### Account B actions

1. Fork `Omar-Khaleel/AL-Go`.
2. Create an attack branch from upstream `research/algo-two-account-pr-prod`.
3. Apply `SECURITY-RESEARCH/account-b-attacker.patch`.
4. Verify only these files changed:
   - `app/app.json`
   - `app/Hello.al`
5. Open a PR targeting `Omar-Khaleel:research/algo-two-account-pr-prod`.
6. Wait for the trusted `Pull Request Build` to finish successfully.

### Account A protected deployment

1. Record the PR number and head SHA.
2. Run `Publish To Environment` using ref `research/algo-two-account-pr-prod`.
3. Set:
   - `appVersion=PR_<PR number>`
   - `environmentName=ProductionProof`
   - `createEnvIfNotExists=false`
4. Approve the protected environment deployment as Account A.
5. Capture all workflow, job, artifact, and deployment identifiers.

## Expected secure behavior

Before any custom deployment script receives `AuthContext` or attacker-produced Apps, AL-Go should:

- determine authoritative artifact provenance;
- bind the artifact to the source repository, source SHA, PR ID, producing workflow, and digest;
- determine whether it originated from a PR or external fork;
- enforce the same PR-to-non-sandbox policy for both built-in and custom deployment;
- reject the deployment or require an explicit security-sensitive override.

At minimum, the trusted custom extension should receive an immutable provenance object sufficient to make the same decision.

## Actual behavior

Complete from the protected run:

```text
PR_NUMBER=<TBD>
PR_AUTHOR=<TBD>
PR_HEAD_REPOSITORY=<TBD>
PR_HEAD_SHA=<TBD>
UPSTREAM_PERMISSION=<TBD expected none>
PR_BUILD_RUN_ID=<TBD>
PR_ARTIFACT_ID=<TBD>
PR_ARTIFACT_NAME=<TBD>
PROTECTED_DEPLOYMENT_RUN_ID=<TBD>
PROTECTED_DEPLOYMENT_JOB_ID=<TBD>
GITHUB_WORKFLOW_REF=<TBD>
CUSTOM_SCRIPT_EXECUTED=<TBD expected true>
AUTHCONTEXT_PARSED=<TBD expected true>
ACCESS_TOKEN_REQUEST_SUCCEEDED=<TBD expected true>
BUSINESS_CENTRAL_ADMIN_QUERY_SUCCEEDED=<TBD expected true>
AUTHORITATIVE_PROVENANCE_PARAMETER_COUNT=<TBD expected 0>
ARTIFACTS_VERSION_PARAMETER_PRESENT=<TBD expected false>
SOURCE_SHA_PARAMETER_PRESENT=<TBD expected false>
SOURCE_REPOSITORY_PARAMETER_PRESENT=<TBD expected false>
PULL_REQUEST_ID_PARAMETER_PRESENT=<TBD expected false>
APP_FILENAME=<TBD expected ExternalAccountProof_ALGoAttackerProof_1.0.0.1.app>
APP_SHA256=<TBD>
PUBLISH_ATTEMPTED=<TBD expected true>
PUBLISH_SUCCEEDED=<TBD expected true>
```

The trusted custom deployment receives the external-fork app and protected `AuthContext`; the parameter map contains no authoritative PR or source provenance; the marker app is published to the disposable protected target.

## Negative controls

Complete and attach evidence for all controls:

1. Account B upstream permission is `none`.
2. Account B cannot dispatch the upstream workflow.
3. Account B cannot read the environment secret.
4. Account B cannot approve the environment.
5. Account B cannot directly obtain the protected Business Central token.
6. Account B cannot directly publish the app.
7. Account B's PR changes no `.github` file.
8. A non-marker app is rejected by the custom proof script before publish.
9. The PR build receives no environment secret and runs outside `ProductionProof`.

## Security impact

In a repository using AL-Go's documented custom deployment feature, trusted release automation can import artifacts produced from an external pull request into a protected deployment job and expose them to the environment deployment identity without applying AL-Go's built-in PR-to-non-sandbox restriction.

The practical impact depends on the custom deployment target and identity. A malicious application artifact may be published to a protected Business Central environment or supplied to another custom deployment backend with the rights of the protected deployment principal. This crosses the intended boundary between untrusted contribution artifacts and trusted release credentials.

The proof uses only researcher-owned accounts, a researcher-owned repository, and a disposable Business Central environment.

## Remediation

1. Move PR/non-sandbox enforcement before the custom-script branch in `Deploy.ps1`.
2. Treat custom deployment as an alternate transport, not an authorization-policy bypass.
3. Pass a structured immutable provenance object to custom deployment, including:
   - artifact version requested;
   - source repository;
   - PR number;
   - PR head SHA;
   - producing workflow and run ID;
   - artifact ID and digest;
   - fork status;
   - attestation verification status.
4. Bind environment approval to the exact artifact digest and source SHA.
5. Require an explicit setting such as `allowPullRequestArtifactsForProtectedCustomDeployment`, defaulting to `false`.
6. Reject external-fork artifacts by default for protected custom deployment.
7. Avoid passing raw reusable credentials to extension scripts where a narrowly scoped brokered deployment operation can be used.

## Evidence package checklist

- [ ] PR URL and metadata
- [ ] permission API response for Account B
- [ ] PR changed-file list
- [ ] PR build workflow URL
- [ ] PR build job logs
- [ ] PR artifact metadata and archive
- [ ] trusted branch commit and file hashes
- [ ] GitHub Environment screenshots/configuration
- [ ] deployment approval evidence
- [ ] protected deployment workflow URL
- [ ] sanitized custom deployment proof block
- [ ] Business Central marker-app verification
- [ ] direct-access negative controls
- [ ] SHA256SUMS.txt
- [ ] source call-chain excerpts with exact upstream commits

## Submission guidance

Reply to Case `118501` with the completed evidence and clearly state that the attacker model and vulnerable boundary are materially different from the original owner-controlled feature-branch proof. Open a new report only if MSRC explicitly requests it or if the final triage portal does not permit material evidence on the closed case.
