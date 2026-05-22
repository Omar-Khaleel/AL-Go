param([hashtable] $parameters)

$marker = Join-Path $env:GITHUB_WORKSPACE "algo-custom-deploy-marker.txt"

$authPresent = [bool]$parameters.AuthContext
$authLengthGtZero = $false
if ($parameters.AuthContext) {
    $authLengthGtZero = ($parameters.AuthContext.Length -gt 0)
}

$appsCount = @($parameters.Apps).Count
$depsCount = @($parameters.Dependencies).Count

@(
  "CUSTOM_DEPLOY_SCRIPT_EXECUTED=true"
  "AUTHCONTEXT_PRESENT=$authPresent"
  "AUTHCONTEXT_LENGTH_GT_ZERO=$authLengthGtZero"
  "APPS_COUNT=$appsCount"
  "DEPENDENCIES_COUNT=$depsCount"
  "ENVIRONMENT_TYPE=$($parameters.EnvironmentType)"
  "ENVIRONMENT_NAME=$($parameters.EnvironmentName)"
  "ARTIFACTS_REACHED_CUSTOM_SCRIPT=true"
) | Set-Content -Path $marker -Encoding UTF8

Write-Host "===== AL-GO CUSTOM DEPLOY POC MARKER ====="
Get-Content $marker
Write-Host "===== END MARKER ====="
