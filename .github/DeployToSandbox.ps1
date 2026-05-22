param([hashtable] $parameters)

$marker = Join-Path $env:GITHUB_WORKSPACE "algo-custom-deploy-marker.txt"

$authPresent = [bool]$parameters.AuthContext
$authLengthGtZero = $false
if ($parameters.AuthContext) {
    $authLengthGtZero = ($parameters.AuthContext.Length -gt 0)
}

$appsCount = @($parameters.Apps).Count
$depsCount = @($parameters.Dependencies).Count


# Safe AuthContext introspection: prints type/property names only, never values.
$authContextTypeName = "null"
$authContextPropertyNames = ""
$authContextStringLength = 0

try {
    if ($parameters.AuthContext) {
        $authContextTypeName = $parameters.AuthContext.GetType().FullName
        $authContextStringLength = ([string]$parameters.AuthContext).Length

        try {
            $authContextPropertyNames = (
                $parameters.AuthContext.PSObject.Properties |
                Select-Object -ExpandProperty Name
            ) -join ","
        } catch {
            $authContextPropertyNames = "PROPERTY_ENUM_FAILED"
        }
    }
} catch {
    $authContextTypeName = "TYPE_INTROSPECTION_FAILED"
}

# Non-destructive authenticated proof using AuthContext.
# Does not print secrets, tokens, or response body.
$authContextAuthenticatedActionSucceeded = $false
$authContextAuthErrorType = ""
$targetEnvironment = $parameters.EnvironmentName

try {
    $rawAuth = [string]$parameters.AuthContext
    $authJson = $rawAuth

    # AL-Go/AuthContext values are commonly stored encoded. Try base64 JSON first if raw JSON parse fails.
    try {
        $authObj = $authJson | ConvertFrom-Json -ErrorAction Stop
    } catch {
        try {
            $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($rawAuth))
            $authObj = $decoded | ConvertFrom-Json -ErrorAction Stop
        } catch {
            throw "AuthContextParseFailed"
        }
    }

    $tenantId = $authObj.tenantId
    if (-not $tenantId) { $tenantId = $authObj.TenantId }

    $clientId = $authObj.clientId
    if (-not $clientId) { $clientId = $authObj.ClientId }

    $clientSecret = $authObj.clientSecret
    if (-not $clientSecret) { $clientSecret = $authObj.ClientSecret }

    if (-not $tenantId -or -not $clientId -or -not $clientSecret) {
        throw "MissingRequiredAuthFields"
    }

    $tokenUri = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
    $tokenBody = @{
        client_id     = $clientId
        client_secret = $clientSecret
        scope         = "https://api.businesscentral.dynamics.com/.default"
        grant_type    = "client_credentials"
    }

    $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenUri -Body $tokenBody -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop

    if (-not $tokenResponse.access_token) {
        throw "TokenMissing"
    }

    $headers = @{
        Authorization = "Bearer $($tokenResponse.access_token)"
        Accept        = "application/json"
    }

    # Non-destructive metadata query. Do not print response body.
    $adminUri = "https://api.businesscentral.dynamics.com/admin/v2.21/applications/businesscentral/environments"
    $metadataResponse = Invoke-RestMethod -Method Get -Uri $adminUri -Headers $headers -ErrorAction Stop

    $authContextAuthenticatedActionSucceeded = $true
} catch {
    $authContextAuthenticatedActionSucceeded = $false
    $authContextAuthErrorType = $_.Exception.Message
}


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
  "AUTHCONTEXT_TYPE_NAME=$authContextTypeName"
  "AUTHCONTEXT_STRING_LENGTH=$authContextStringLength"
  "AUTHCONTEXT_PROPERTY_NAMES=$authContextPropertyNames"
  "AUTHCONTEXT_JSON_PARSE_SUCCEEDED=$authContextParseSucceeded"
  "AUTHCONTEXT_HAS_CLIENT_ID=$authContextHasClientId"
  "AUTHCONTEXT_HAS_TENANT_ID=$authContextHasTenantId"
  "AUTHCONTEXT_HAS_SECRET_OR_CERTIFICATE=$authContextHasSecretOrCertificate"
  "APPS_COUNT=$appsCount"
  "DEPENDENCIES_COUNT=$depsCount"
  "ENVIRONMENT_TYPE=$($parameters.EnvironmentType)"
  "ENVIRONMENT_NAME=$($parameters.EnvironmentName)"
  "ARTIFACTS_REACHED_CUSTOM_SCRIPT=true"
  "AUTHCONTEXT_AUTHENTICATED_ACTION_SUCCEEDED=$authContextAuthenticatedActionSucceeded"
  "TARGET_ENVIRONMENT=$targetEnvironment"
  "AUTHCONTEXT_AUTH_ERROR_TYPE=$authContextAuthErrorType"
) | Set-Content -Path $marker -Encoding UTF8

Write-Host "===== AL-GO CUSTOM DEPLOY POC MARKER ====="
Get-Content $marker
Write-Host "===== END MARKER ====="
