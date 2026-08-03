# AL-Go two-account PR-to-protected-deployment proof

Date prepared: 2026-08-04

Target repository: `Omar-Khaleel/AL-Go`

Trusted base branch: `research/algo-two-account-pr-prod`

Previous MSRC submission: `VULN-190103` / Case `118501`

## Research question

Can an external GitHub account with no repository permission submit an AL application through a fork pull request, have that application built without secrets, and then have a trusted AL-Go `PublishToEnvironment` run pass the resulting PR artifact to a protected custom deployment job together with `AuthContext`, without giving the custom deployment extension authoritative artifact provenance?

## Trust model

### Account A — victim administrator

Account A owns `Omar-Khaleel/AL-Go` and exclusively controls:

- the trusted base branch;
- workflow and custom-deployment files;
- the `ProductionProof` GitHub Environment;
- `ProductionProof_AuthContext`;
- workflow dispatch and deployment approval;
- the disposable Business Central target environment.

### Account B — external attacker

Account B must:

- have no collaborator permission on `Omar-Khaleel/AL-Go`;
- fork the public repository;
- create a branch from `research/algo-two-account-pr-prod`;
- modify only `app/app.json` and `app/Hello.al`;
- open a PR targeting `research/algo-two-account-pr-prod`;
- never receive repository or environment secrets;
- never modify the trusted workflow or `.github/DeployToProductionProof.ps1`.

## Prepared trusted components

### Protected deployment settings

`.github/AL-Go-Settings.json` defines a `ProductionProof` deployment environment using custom environment type `ProductionProof` and a disposable Business Central target named `Sandbox`.

### Trusted custom deployment

`.github/DeployToProductionProof.ps1`:

- executes only from the trusted base branch checkout;
- receives `AuthContext`, Apps, Dependencies, and deployment settings from Microsoft AL-Go;
- records actor, workflow, source, file hashes, and parameter presence without printing credentials;
- proves the custom extension does not receive authoritative PR ID, source SHA, source repository, artifact run ID, artifact digest, or `artifactsVersion` parameters;
- requests a Business Central token and performs a harmless Admin API query;
- refuses to publish unless exactly one app filename contains `ALGoAttackerProof`;
- publishes only that marker app to the disposable target environment;
- writes a sanitized proof block to the job log and step summary.

### External PR build

`.github/workflows/ResearchPullRequestHandler.yaml` is a trusted base-branch workflow named `Pull Request Build`. It:

- runs only for PRs targeting `research/algo-two-account-pr-prod`;
- has read-only repository permissions;
- has `id-token: none`;
- receives no deployment secret;
- checks out the PR merge commit;
- uses Microsoft AL-Go v9.1 actions and the repository's AL-Go reusable build workflow;
- uploads PR artifacts using AL-Go's standard `PR<number>` artifact suffix.

## Account B patch

Account B must apply only this logical change:

### `app/app.json`

- Change `id` to `22222222-2222-4222-8222-222222222222`.
- Change `name` to `ALGoAttackerProof`.
- Change `publisher` to `ExternalAccountProof`.
- Change `version` to `1.0.0.1`.
- Change `brief` and `description` to identify the external-fork proof.

### `app/Hello.al`

- Change page object ID from `50100` to `50120`.
- Change page name and caption to `ALGo Attacker Proof Page`.
- Change the page message to `External fork artifact reached protected deployment identity`.

No `.github` file may be changed in Account B's PR.

## Required GitHub Environment configuration

Create a GitHub Environment named `ProductionProof` in `Omar-Khaleel/AL-Go`.

Configure:

- deployment branches: selected branch `research/algo-two-account-pr-prod` only;
- required reviewer: Account A only, when available on the plan;
- prevent self-review, when available;
- environment secret `ProductionProof_AuthContext` containing a base64-encoded AL-Go Business Central AuthContext for a disposable researcher-owned tenant;
- no secret or reviewer access for Account B.

The Business Central target remains the disposable environment named `Sandbox`. The GitHub Environment name and trust role are `ProductionProof`; using a sandbox tenant prevents customer or production impact while preserving the protected-identity boundary.

## Execution sequence

1. Account B forks `Omar-Khaleel/AL-Go`.
2. Account B creates its attack branch from upstream `research/algo-two-account-pr-prod`.
3. Account B applies only the two app-source modifications above.
4. Account B opens a PR against `Omar-Khaleel:research/algo-two-account-pr-prod`.
5. Confirm PR metadata shows a different head repository and Account B as author.
6. Confirm Account B has repository permission `none`.
7. Confirm `Pull Request Build` succeeds and creates the Apps artifact.
8. Record PR number, PR head SHA, merge SHA, workflow run ID, artifact ID, artifact name, artifact digest where available, and all job IDs.
9. From Account A, run `Publish To Environment` from ref `research/algo-two-account-pr-prod` with:
   - `appVersion`: `PR_<PR number>`
   - `environmentName`: `ProductionProof`
   - `createEnvIfNotExists`: `false`
10. Approve the `ProductionProof` deployment only from Account A.
11. Capture the custom deployment proof block.
12. Confirm all of the following:
   - external PR artifact filename contains `ALGoAttackerProof`;
   - custom script receives the protected `AuthContext`;
   - Business Central token request succeeds;
   - Admin API query succeeds;
   - `AUTHORITATIVE_PROVENANCE_PARAMETER_COUNT=0`;
   - `ARTIFACTS_VERSION_PARAMETER_PRESENT=false`;
   - `SOURCE_SHA_PARAMETER_PRESENT=false`;
   - `SOURCE_REPOSITORY_PARAMETER_PRESENT=false`;
   - `PULL_REQUEST_ID_PARAMETER_PRESENT=false`;
   - publish is attempted and succeeds;
   - the marker app appears in the disposable Business Central environment.

## Negative controls

### Account B direct environment access

Account B must be unable to:

- view `ProductionProof_AuthContext`;
- dispatch `PublishToEnvironment` in the upstream repository;
- approve the environment deployment;
- push to the trusted base branch;
- create or modify an upstream workflow;
- perform the Business Central Admin API query using its own identity;
- publish the marker app directly to the target tenant.

### Non-marker artifact

Running the same trusted deployment with an app that does not contain `ALGoAttackerProof` must fail at the custom script safety gate before publishing.

### Provenance visibility

The custom deployment parameter list must be captured in sanitized form to establish that Microsoft AL-Go passes the PR artifact and protected AuthContext but omits authoritative artifact provenance needed to apply the product's PR-to-non-sandbox policy at the custom-deployment boundary.

## Reportability gate

### Reportable

Proceed only if the two-account run demonstrates:

- Account B has no upstream permission;
- Account B controls only application source;
- the trusted base-branch workflow creates the PR artifact;
- the protected deployment job is authorized using Account A's environment;
- the trusted custom extension receives the external artifact and protected AuthContext;
- the extension receives no authoritative provenance parameters;
- a harmless authorization-sensitive operation and marker-app publication succeed.

### Not reportable

Stop if:

- Account B needs upstream write permission;
- Account B modifies a trusted workflow or custom deployment script;
- the artifact cannot be built from a fork PR;
- GitHub withholds required build functionality such that Account A must execute attacker code in a secret-bearing PR job;
- AL-Go now supplies or enforces authoritative PR provenance before invoking the custom deployment script;
- the operation succeeds only because Account A intentionally modifies the trusted deployment script to accept the exact attacker PR.

## Intended MSRC delta

This experiment does not repeat the old claim that an explicitly authorized feature branch receives `AuthContext`.

The new claim, if validated, is:

> A trusted AL-Go PublishToEnvironment run can import an artifact produced from an external fork PR into a protected custom deployment job and pass it alongside the environment AuthContext, while the custom deployment boundary bypasses AL-Go's built-in PR-to-non-sandbox enforcement and does not receive authoritative source provenance needed to reproduce that enforcement.

This is materially different evidence for Case `118501` and should be submitted as a reply to the existing case unless MSRC requests a new report.
