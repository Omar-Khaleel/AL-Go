# AL-Go deployment boundary re-evaluation

Date: 2026-08-04

Previous MSRC submission: `VULN-190103` / Case `118501`

Research branch: `feature/algo-boundary-v2`

## Decision

**OUTCOME C — the original claim is not ready for resubmission.**

The original proof correctly demonstrates that AL-Go executes `.github/DeployTo<EnvironmentType>.ps1` and passes `AuthContext`, Apps, Dependencies, and deployment settings to that script. However, Microsoft documents custom deployment as an intentional extension mechanism and explicitly documents that the custom script receives the authentication context.

The old proof used a branch that was explicitly included in the deployment `Branches` setting. It therefore proves that an authorized deployment branch can run its custom deployment implementation with the configured deployment identity. It does not yet prove that a lower-trust actor crossed a boundary they could not cross through an equivalent workflow or repository change.

Increasing the proof from “AuthContext is present” to “the credential can issue a token and query Business Central” improves impact evidence, but it does not repair the missing attacker model.

## Changes made in this research branch

The custom deployment proof was hardened to record only sanitized evidence:

- actor and triggering actor;
- event, ref, source SHA, workflow ref, and workflow SHA;
- custom-script and workflow SHA-256 digests;
- AuthContext structure booleans;
- successful application-token acquisition;
- token audience and role count without printing the token;
- successful Business Central Admin API metadata query;
- target-environment presence and status;
- application and dependency counts.

No credential, token, secret value, or response body is printed.

## Why the original attacker model still fails

A user who can write arbitrary files to an unprotected branch can ordinarily also add or change a workflow on that branch. Unless repository rules make the trusted workflow immutable while independently allowing that user to control only the custom deployment hook, AL-Go is not giving that actor a capability they do not already possess.

A reportable proof must demonstrate all of the following at the same time:

1. The low-trust account cannot modify or create workflows that enter the protected GitHub Environment.
2. The account cannot read the environment secret or request the environment-scoped OIDC identity directly.
3. The account cannot approve the deployment.
4. The account can nevertheless control a script, setting, source ref, or artifact that AL-Go promotes into the protected deployment job.
5. The promoted input performs an authorization-sensitive operation unavailable to the low-trust account.

The currently connected GitHub installation contains only the owner account, so a genuine two-account permission boundary could not be demonstrated through the connector.

## Stronger source-level candidate discovered

A distinct candidate exists in the trusted `PublishToEnvironment` path:

1. `PublishToEnvironment.yaml` accepts `appVersion=PR_<id>`.
2. `GetArtifactsForDeployment` resolves the PR head and downloads artifacts from the latest successful PR build.
3. The deployment job enters the selected GitHub Environment and reads its AuthContext.
4. `Deploy.ps1` checks for `.github/DeployTo<EnvironmentType>.ps1` first.
5. When a custom script exists, AL-Go invokes it immediately with AuthContext and the downloaded PR artifacts.
6. The built-in rule that refuses PR artifacts for a non-sandbox environment exists only in the default-deployment `else` branch.

This means a custom deployment implementation does not receive AL-Go's built-in “PR artifacts are sandbox-only” enforcement.

### Current severity assessment

**Promising design inconsistency, but not yet a vulnerability.**

Custom deployment deliberately replaces the built-in deployment implementation. Microsoft can reasonably argue that the trusted custom script owns all policy enforcement. A report needs an end-to-end scenario showing that an authorized operator reasonably expects the platform's PR-to-production restriction to remain enforced and that an untrusted PR can cause a production action without the operator knowingly authorizing that exact code.

## Artifact extraction escalation result

The PR-artifact download path uses PowerShell `Expand-Archive`. A simple ZIP traversal using `../` is not a credible escalation because Microsoft.PowerShell.Archive added canonical destination containment checks in version 1.2.2. A safe runner control workflow remains in this branch for manual execution, but connector-generated GitHub events did not start Actions runs during this review.

## Exact next experiment required

Use two controlled GitHub accounts and a disposable Business Central sandbox or a harmless Azure OIDC test resource.

The useful experiment is not another owner-controlled branch run. It must use:

- Account A: repository/environment administrator and deployment reviewer;
- Account B: the minimum lower-trust role;
- immutable trusted workflows on `main`;
- an environment identity unavailable to Account B;
- a lower-trust PR artifact or repository input selected by a trusted `PublishToEnvironment` run;
- a negative control showing Account B cannot perform the same operation directly;
- one harmless authorization-sensitive action using the protected identity.

If Account B must be given workflow-write capability, if an administrator knowingly approves the malicious ref, or if the trusted custom script itself explicitly deploys PR artifacts to production, stop and classify the candidate as by design.

## Submission recommendation

Do not open a duplicate of `VULN-190103` based only on the stronger token/API markers. Reply to Case `118501` only after obtaining materially new two-account evidence or a distinct cross-ref policy bypass in `PublishToEnvironment`.
