param([hashtable] $parameters)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$marker = Join-Path $env:GITHUB_WORKSPACE "algo-boundary-v2-marker.txt"
$scriptPath = $MyInvocation.MyCommand.Path
$workflowPath = Join-Path $env:GITHUB_WORKSPACE ".github/workflows/CICD.yaml"

function Get-SafeFileHash([string] $path) {
    if ($path -and (Test-Path -LiteralPath $path)) {
        return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return "MISSING"
}

function Get-EnvValue([string] $name) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ($null -eq $value) { return "" }
    return [string]$value
}

function ConvertFrom-Base64Url([string] $value) {
    $normalized = $value.Replace('-', '+').Replace('_', '/')
    switch ($normalized.Length % 4) {
        2 { $normalized += '==' }
        3 { $normalized += '=' }
    }
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($normalized))
}

$authPresent = [bool]$parameters.AuthContext
$authParseSucceeded = $false
$authHasClientId = $false
$authHasTenantId = $false
$authHasSecretOrCertificate = $false
$tokenRequestSucceeded = $false
$tokenAudience = ""
$tokenHasApplicationIdentity = $false
$tokenRoleCount = 0
$adminQuerySucceeded = $false
$adminEnvironmentCount = 0
$targetEnvironmentFound = $false
$targetEnvironmentStatus = ""
$errorType = ""

try {
    $rawAuth = [string]$parameters.AuthContext
    try {
        $authObj = $rawAuth | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $decodedAuth = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($rawAuth))
        $authObj = $decodedAuth | ConvertFrom-Json -ErrorAction Stop
    }

    $authParseSucceeded = $true
    $tenantId = $authObj.tenantId
    if (-not $tenantId) { $tenantId = $authObj.TenantId }
    $clientId = $authObj.clientId
    if (-not $clientId) { $clientId = $authObj.ClientId }
    $clientSecret = $authObj.clientSecret
    if (-not $clientSecret) { $clientSecret = $authObj.ClientSecret }
    $certificate = $authObj.certificate
    if (-not $certificate) { $certificate = $authObj.Certificate }

    $authHasClientId = [bool]$clientId
    $authHasTenantId = [bool]$tenantId
    $authHasSecretOrCertificate = [bool]($clientSecret -or $certificate)

    if (-not $tenantId -or -not $clientId -or -not $clientSecret) {
        throw "MissingRequiredClientCredentialFields"
    }

    $tokenResponse = Invoke-RestMethod `
        -Method Post `
        -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body @{
            client_id     = $clientId
            client_secret = $clientSecret
            scope         = "https://api.businesscentral.dynamics.com/.default"
            grant_type    = "client_credentials"
        } `
        -ErrorAction Stop

    if (-not $tokenResponse.access_token) {
        throw "AccessTokenMissing"
    }
    $tokenRequestSucceeded = $true

    try {
        $segments = ([string]$tokenResponse.access_token).Split('.')
        if ($segments.Count -ge 2) {
            $claims = (ConvertFrom-Base64Url $segments[1]) | ConvertFrom-Json -ErrorAction Stop
            $tokenAudience = [string]$claims.aud
            $tokenHasApplicationIdentity = [bool]($claims.appid -or $claims.azp)
            $tokenRoleCount = @($claims.roles).Count
        }
    }
    catch {
        # Claim decoding is supplemental and must not fail the authenticated proof.
    }

    $headers = @{
        Authorization = "Bearer $($tokenResponse.access_token)"
        Accept        = "application/json"
    }

    $adminUri = "https://api.businesscentral.dynamics.com/admin/v2.21/applications/businesscentral/environments"
    $metadataResponse = Invoke-RestMethod -Method Get -Uri $adminUri -Headers $headers -ErrorAction Stop
    $adminQuerySucceeded = $true

    $environmentItems = @()
    if ($null -ne $metadataResponse.value) {
        $environmentItems = @($metadataResponse.value)
    }
    else {
        $environmentItems = @($metadataResponse)
    }
    $adminEnvironmentCount = $environmentItems.Count

    $targetName = [string]$parameters.EnvironmentName
    $target = $environmentItems | Where-Object {
        ([string]$_.name -eq $targetName) -or
        ([string]$_.environmentName -eq $targetName)
    } | Select-Object -First 1

    if ($target) {
        $targetEnvironmentFound = $true
        if ($null -ne $target.status) {
            $targetEnvironmentStatus = [string]$target.status
        }
    }
}
catch {
    $errorType = $_.Exception.GetType().FullName
}

$appsCount = @($parameters.Apps).Count
$dependenciesCount = @($parameters.Dependencies).Count

@(
    "POC_VERSION=ALGO_BOUNDARY_V2"
    "CUSTOM_DEPLOY_SCRIPT_EXECUTED=true"
    "GITHUB_REPOSITORY=$(Get-EnvValue 'GITHUB_REPOSITORY')"
    "GITHUB_ACTOR=$(Get-EnvValue 'GITHUB_ACTOR')"
    "GITHUB_TRIGGERING_ACTOR=$(Get-EnvValue 'GITHUB_TRIGGERING_ACTOR')"
    "GITHUB_EVENT_NAME=$(Get-EnvValue 'GITHUB_EVENT_NAME')"
    "GITHUB_REF=$(Get-EnvValue 'GITHUB_REF')"
    "GITHUB_REF_NAME=$(Get-EnvValue 'GITHUB_REF_NAME')"
    "GITHUB_SHA=$(Get-EnvValue 'GITHUB_SHA')"
    "GITHUB_WORKFLOW=$(Get-EnvValue 'GITHUB_WORKFLOW')"
    "GITHUB_WORKFLOW_REF=$(Get-EnvValue 'GITHUB_WORKFLOW_REF')"
    "GITHUB_WORKFLOW_SHA=$(Get-EnvValue 'GITHUB_WORKFLOW_SHA')"
    "GITHUB_JOB=$(Get-EnvValue 'GITHUB_JOB')"
    "GITHUB_RUN_ID=$(Get-EnvValue 'GITHUB_RUN_ID')"
    "GITHUB_RUN_ATTEMPT=$(Get-EnvValue 'GITHUB_RUN_ATTEMPT')"
    "CUSTOM_SCRIPT_SHA256=$(Get-SafeFileHash $scriptPath)"
    "WORKFLOW_SHA256=$(Get-SafeFileHash $workflowPath)"
    "AUTHCONTEXT_PRESENT=$authPresent"
    "AUTHCONTEXT_JSON_PARSE_SUCCEEDED=$authParseSucceeded"
    "AUTHCONTEXT_HAS_CLIENT_ID=$authHasClientId"
    "AUTHCONTEXT_HAS_TENANT_ID=$authHasTenantId"
    "AUTHCONTEXT_HAS_SECRET_OR_CERTIFICATE=$authHasSecretOrCertificate"
    "ACCESS_TOKEN_REQUEST_SUCCEEDED=$tokenRequestSucceeded"
    "ACCESS_TOKEN_AUDIENCE=$tokenAudience"
    "ACCESS_TOKEN_HAS_APPLICATION_IDENTITY=$tokenHasApplicationIdentity"
    "ACCESS_TOKEN_ROLE_COUNT=$tokenRoleCount"
    "BUSINESS_CENTRAL_ADMIN_QUERY_SUCCEEDED=$adminQuerySucceeded"
    "BUSINESS_CENTRAL_ENVIRONMENT_COUNT=$adminEnvironmentCount"
    "TARGET_ENVIRONMENT_NAME=$($parameters.EnvironmentName)"
    "TARGET_ENVIRONMENT_FOUND=$targetEnvironmentFound"
    "TARGET_ENVIRONMENT_STATUS=$targetEnvironmentStatus"
    "APPS_COUNT=$appsCount"
    "DEPENDENCIES_COUNT=$dependenciesCount"
    "ENVIRONMENT_TYPE=$($parameters.EnvironmentType)"
    "ENVIRONMENT_NAME=$($parameters.EnvironmentName)"
    "AUTHENTICATED_PROOF_ERROR_TYPE=$errorType"
) | Set-Content -LiteralPath $marker -Encoding UTF8

Write-Host "===== AL-GO TRUST BOUNDARY V2 MARKER ====="
Get-Content -LiteralPath $marker
Write-Host "===== END AL-GO TRUST BOUNDARY V2 MARKER ====="
