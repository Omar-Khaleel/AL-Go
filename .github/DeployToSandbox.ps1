param([hashtable] $parameters)

$marker = Join-Path $env:GITHUB_WORKSPACE "algo-custom-deploy-marker.txt"

$authPresent = [bool]$parameters.AuthContext
$authLengthGtZero = $false
if ($parameters.AuthContext) {
    $authLengthGtZero = ($parameters.AuthContext.Length -gt 0)
}

$appsCount = @($parameters.Apps).Count
$depsCount = @($parameters.Dependencies).Count

# Parse AuthContext structure without printing secret values
$authContextParseSucceeded = $false
$authContextHasClientId = $false
$authContextHasTenantId = $false
$authContextHasSecretOrCertificate = $false

try {
    if ($parameters.AuthContext) {
        $authObj = $parameters.AuthContext | ConvertFrom-Json -ErrorAction Stop
        $authContextParseSucceeded = $true
        $authContextHasClientId = [bool]($authObj.clientId -or $authObj.ClientId -or $authObj.clientID)
        $authContextHasTenantId = [bool]($authObj.tenantId -or $authObj.TenantId -or $authObj.tenantID)
        $authContextHasSecretOrCertificate = [bool]($authObj.clientSecret -or $authObj.ClientSecret -or $authObj.certificate -or $authObj.Certificate)
    }
} catch {
    $authContextParseSucceeded = $false
}


@(
  "CUSTOM_DEPLOY_SCRIPT_EXECUTED=true"
  "AUTHCONTEXT_PRESENT=$authPresent"
  "AUTHCONTEXT_LENGTH_GT_ZERO=$authLengthGtZero"
  "AUTHCONTEXT_JSON_PARSE_SUCCEEDED=$authContextParseSucceeded"
  "AUTHCONTEXT_HAS_CLIENT_ID=$authContextHasClientId"
  "AUTHCONTEXT_HAS_TENANT_ID=$authContextHasTenantId"
  "AUTHCONTEXT_HAS_SECRET_OR_CERTIFICATE=$authContextHasSecretOrCertificate"
  "APPS_COUNT=$appsCount"
  "DEPENDENCIES_COUNT=$depsCount"
  "ENVIRONMENT_TYPE=$($parameters.EnvironmentType)"
  "ENVIRONMENT_NAME=$($parameters.EnvironmentName)"
  "ARTIFACTS_REACHED_CUSTOM_SCRIPT=true"
) | Set-Content -Path $marker -Encoding UTF8

Write-Host "===== AL-GO CUSTOM DEPLOY POC MARKER ====="
Get-Content $marker
Write-Host "===== END MARKER ====="
