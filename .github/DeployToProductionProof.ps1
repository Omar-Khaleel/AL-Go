Param([Hashtable] $parameters)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$proofMarker = 'ALGoAttackerProof'
$proofFile = Join-Path $env:GITHUB_WORKSPACE 'algo-two-account-proof.txt'
$apps = @($parameters.Apps)
$dependencies = @($parameters.Dependencies)

function Get-BoolText([bool] $value) {
    if ($value) { return 'true' }
    return 'false'
}

function Get-OptionalParameterPresence([string] $name) {
    return $parameters.ContainsKey($name)
}

function Parse-AuthContext([string] $rawAuth) {
    try {
        return $rawAuth | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($rawAuth))
        return $decoded | ConvertFrom-Json -ErrorAction Stop
    }
}

$markerApps = @($apps | Where-Object {
    [IO.Path]::GetFileName($_) -like "*$proofMarker*"
})

$appEvidence = @()
foreach ($app in $apps) {
    $item = Get-Item -LiteralPath $app -ErrorAction Stop
    $appEvidence += [pscustomobject]@{
        FileName = $item.Name
        Sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        Length = $item.Length
        ParentFolder = $item.Directory.Name
        PathContainsPrHint = ($item.FullName -match '(?i)PR[_-]?[0-9]+')
    }
}

$provenanceParameters = @(
    'artifactsVersion',
    'artifactVersion',
    'sourceSha',
    'sourceRef',
    'sourceRepository',
    'pullRequestId',
    'workflowRunId',
    'artifactRunId',
    'artifactAttestation',
    'artifactDigest'
)

$presentProvenanceParameters = @($provenanceParameters | Where-Object {
    Get-OptionalParameterPresence $_
})

$authContextParsed = $false
$tokenRequestSucceeded = $false
$adminQuerySucceeded = $false
$targetEnvironmentFound = $false
$targetEnvironmentType = ''
$publishAttempted = $false
$publishSucceeded = $false
$errorType = ''

try {
    if (-not $parameters.AuthContext) {
        throw 'AuthContextMissing'
    }

    $authObj = Parse-AuthContext ([string]$parameters.AuthContext)
    $authContextParsed = $true

    $tenantId = $authObj.tenantId
    if (-not $tenantId) { $tenantId = $authObj.TenantId }
    $clientId = $authObj.clientId
    if (-not $clientId) { $clientId = $authObj.ClientId }
    $clientSecret = $authObj.clientSecret
    if (-not $clientSecret) { $clientSecret = $authObj.ClientSecret }

    if (-not $tenantId -or -not $clientId -or -not $clientSecret) {
        throw 'RequiredClientCredentialFieldsMissing'
    }

    $tokenResponse = Invoke-RestMethod `
        -Method Post `
        -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
        -ContentType 'application/x-www-form-urlencoded' `
        -Body @{
            client_id = $clientId
            client_secret = $clientSecret
            scope = 'https://api.businesscentral.dynamics.com/.default'
            grant_type = 'client_credentials'
        } `
        -ErrorAction Stop

    if (-not $tokenResponse.access_token) {
        throw 'AccessTokenMissing'
    }
    $tokenRequestSucceeded = $true

    $headers = @{
        Authorization = "Bearer $($tokenResponse.access_token)"
        Accept = 'application/json'
    }

    $adminUri = 'https://api.businesscentral.dynamics.com/admin/v2.21/applications/businesscentral/environments'
    $environmentResponse = Invoke-RestMethod -Method Get -Uri $adminUri -Headers $headers -ErrorAction Stop
    $adminQuerySucceeded = $true

    $environmentItems = if ($null -ne $environmentResponse.value) {
        @($environmentResponse.value)
    }
    else {
        @($environmentResponse)
    }

    $targetName = [string]$parameters.EnvironmentName
    $target = $environmentItems | Where-Object {
        ([string]$_.name -eq $targetName) -or
        ([string]$_.environmentName -eq $targetName)
    } | Select-Object -First 1

    if ($target) {
        $targetEnvironmentFound = $true
        if ($null -ne $target.environmentType) {
            $targetEnvironmentType = [string]$target.environmentType
        }
    }

    if ($markerApps.Count -ne 1) {
        throw "SafeGateExpectedExactlyOneMarkerAppFound$($markerApps.Count)"
    }

    # A trusted custom deployment script receives the protected AuthContext and
    # attacker-built Apps, but AL-Go does not provide authoritative PR/source
    # provenance to this extension point. The filename marker is only a safety
    # gate for this researcher-owned proof; it is not treated as provenance.
    $rawAuth = [string]$parameters.AuthContext
    try {
        $authContextParams = $rawAuth | ConvertFrom-Json -ErrorAction Stop | ConvertTo-HashTable
    }
    catch {
        $decodedAuth = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($rawAuth))
        $authContextParams = $decodedAuth | ConvertFrom-Json -ErrorAction Stop | ConvertTo-HashTable
    }

    $bcAuthContext = New-BcAuthContext @authContextParams
    if ($null -eq $bcAuthContext) {
        throw 'NewBcAuthContextReturnedNull'
    }

    $publishAttempted = $true
    Publish-BcContainerApp `
        -bcAuthContext $bcAuthContext `
        -environment ([string]$parameters.EnvironmentName) `
        -appFile $markerApps[0] `
        -useDevEndpoint `
        -checkAlreadyInstalled `
        -excludeRuntimePackages `
        -replacePackageId `
        -ErrorAction Stop

    $publishSucceeded = $true
}
catch {
    $errorType = $_.Exception.GetType().FullName + ':' + $_.Exception.Message
}

$lines = @(
    'POC=ALGO_TWO_ACCOUNT_PR_TO_PROTECTED_DEPLOYMENT'
    "TIMESTAMP_UTC=$([DateTime]::UtcNow.ToString('o'))"
    "GITHUB_REPOSITORY=$env:GITHUB_REPOSITORY"
    "GITHUB_ACTOR=$env:GITHUB_ACTOR"
    "GITHUB_TRIGGERING_ACTOR=$env:GITHUB_TRIGGERING_ACTOR"
    "GITHUB_EVENT_NAME=$env:GITHUB_EVENT_NAME"
    "GITHUB_REF=$env:GITHUB_REF"
    "GITHUB_REF_NAME=$env:GITHUB_REF_NAME"
    "GITHUB_SHA=$env:GITHUB_SHA"
    "GITHUB_WORKFLOW_REF=$env:GITHUB_WORKFLOW_REF"
    "GITHUB_WORKFLOW_SHA=$env:GITHUB_WORKFLOW_SHA"
    "GITHUB_RUN_ID=$env:GITHUB_RUN_ID"
    "GITHUB_JOB=$env:GITHUB_JOB"
    "CUSTOM_SCRIPT_EXECUTED=true"
    "PARAMETER_TYPE=$($parameters.type)"
    "PARAMETER_ENVIRONMENT_TYPE=$($parameters.EnvironmentType)"
    "PARAMETER_ENVIRONMENT_NAME=$($parameters.EnvironmentName)"
    "APPS_COUNT=$($apps.Count)"
    "DEPENDENCIES_COUNT=$($dependencies.Count)"
    "MARKER_APPS_COUNT=$($markerApps.Count)"
    "AUTHORITATIVE_PROVENANCE_PARAMETER_COUNT=$($presentProvenanceParameters.Count)"
    "AUTHORITATIVE_PROVENANCE_PARAMETERS=$($presentProvenanceParameters -join ',')"
    "ARTIFACTS_VERSION_PARAMETER_PRESENT=$(Get-BoolText (Get-OptionalParameterPresence 'artifactsVersion'))"
    "SOURCE_SHA_PARAMETER_PRESENT=$(Get-BoolText (Get-OptionalParameterPresence 'sourceSha'))"
    "SOURCE_REPOSITORY_PARAMETER_PRESENT=$(Get-BoolText (Get-OptionalParameterPresence 'sourceRepository'))"
    "PULL_REQUEST_ID_PARAMETER_PRESENT=$(Get-BoolText (Get-OptionalParameterPresence 'pullRequestId'))"
    "AUTHCONTEXT_PARSED=$(Get-BoolText $authContextParsed)"
    "ACCESS_TOKEN_REQUEST_SUCCEEDED=$(Get-BoolText $tokenRequestSucceeded)"
    "BUSINESS_CENTRAL_ADMIN_QUERY_SUCCEEDED=$(Get-BoolText $adminQuerySucceeded)"
    "TARGET_ENVIRONMENT_FOUND=$(Get-BoolText $targetEnvironmentFound)"
    "TARGET_ENVIRONMENT_TYPE=$targetEnvironmentType"
    "PUBLISH_ATTEMPTED=$(Get-BoolText $publishAttempted)"
    "PUBLISH_SUCCEEDED=$(Get-BoolText $publishSucceeded)"
    "ERROR_TYPE=$errorType"
)

foreach ($item in $appEvidence) {
    $lines += "APP_FILENAME=$($item.FileName)"
    $lines += "APP_SHA256=$($item.Sha256)"
    $lines += "APP_LENGTH=$($item.Length)"
    $lines += "APP_PARENT_FOLDER=$($item.ParentFolder)"
    $lines += "APP_PATH_CONTAINS_UNTRUSTED_PR_HINT=$(Get-BoolText $item.PathContainsPrHint)"
}

$lines | Set-Content -LiteralPath $proofFile -Encoding UTF8

Write-Host '===== AL-GO TWO-ACCOUNT PROOF ====='
$lines | ForEach-Object { Write-Host $_ }
Write-Host '===== END AL-GO TWO-ACCOUNT PROOF ====='

if ($env:GITHUB_STEP_SUMMARY) {
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding UTF8 -Value '## AL-Go two-account protected deployment proof'
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding UTF8 -Value ''
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding UTF8 -Value '```text'
    $lines | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding UTF8
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding UTF8 -Value '```'
}

if (-not $publishSucceeded) {
    throw "Two-account proof did not complete: $errorType"
}
