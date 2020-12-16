[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]
    $AppID,
    [Parameter(Mandatory)]
    [string]
    $TenantName
)

$resource = "https://graph.microsoft.com/";
$authUrl = "https://login.microsoftonline.com/$TenantName";



$postParams = @{ resource = "$resource"; client_id = "$AppID" }
$response = Invoke-RestMethod -Method POST -Uri "$authurl/oauth2/devicecode" -Body $postParams
Write-Host $response.message
#I got tired of manually copying the code, so I did string manipulation and stored the code in a variable and added to the clipboard automatically
$code = ($response.message -split "code " | Select-Object -Last 1) -split " to authenticate."
Set-Clipboard -Value $code
Add-Type -AssemblyName System.Windows.Forms

$form = New-Object -TypeName System.Windows.Forms.Form -Property @{ Width = 440; Height = 640 }
$web = New-Object -TypeName System.Windows.Forms.WebBrowser -Property @{ Width = 440; Height = 600; Url = "https://www.microsoft.com/devicelogin" }

$web.Add_DocumentCompleted($DocComp)
$web.DocumentText

$form.Controls.Add($web)
$form.Add_Shown({ $form.Activate() })
$web.ScriptErrorsSuppressed = $true

$form.AutoScaleMode = 'Dpi'
$form.text = "Graph API Authentication"
$form.ShowIcon = $False
$form.AutoSizeMode = 'GrowAndShrink'
$Form.StartPosition = 'CenterScreen'

$form.ShowDialog() | Out-Null
$tokenParams = @{ grant_type = "device_code"; resource = "$resource"; client_id = "$AppID"; code = "$($response.device_code)" }
$tokenResponse = $null

try
{
    $tokenResponse = Invoke-RestMethod -Method POST -Uri "$authurl/oauth2/token" -Body $tokenParams
}
catch [System.Net.WebException]
{
    if ($null -eq $_.Exception.Response)
    {
        throw
    }
    
    $result = $_.Exception.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($result)
    $reader.BaseStream.Position = 0
    $errBody = ConvertFrom-Json $reader.ReadToEnd();
    
    if ($errBody.Error -ne "authorization_pending")
    {
        throw
    }
}

If ($null -eq $tokenResponse)
{
    Write-Warning "Not Connected"
    return;
}
Write-Host -ForegroundColor Green "Connected"


$GroupsAuthHeader = @{
    Authorization = "Bearer $($tokenResponse.access_token)"
    ConsistencyLevel = "Eventual"
}

$groupsURI = 'https://graph.microsoft.com/v1.0/groups?$filter=groupTypes/any(c:c+eq+''Unified'')'

$GroupsRequest = Invoke-RestMethod -Uri $groupsURI -Headers $GroupsAuthHeader -Method GET -ContentType application/json

#debug
Write-Verbose "$(($GroupsRequest.Value).count)"

while ($GroupsRequest.'@odata.nextLink' -ne $null) {
    $GroupsRequest += Invoke-RestMethod -Uri $GroupsRequest.'@odata.nextLink' -Headers $GroupsAuthHeader -Method GET -ContentType application/json
}
Write-Verbose "$(($GroupsRequest.Value).count)"

$groupAuthHeader = @{
    Authorization = "Bearer $($tokenResponse.access_token)"
}
$unaccessibleGroups = @()
$plans = foreach ($group in $GroupsRequest.Value) {
    $GroupURI = "https://graph.microsoft.com/v1.0/groups/$($group.id)/planner/plans"
    Write-Verbose "Getting plans for $($group.id)"
    try {
        Invoke-RestMethod -Uri $GroupURI -Headers $groupAuthHeader -Method GET -ContentType application/json
    }
    catch {
        $unaccessibleGroups += $group.id
        Write-Error "Could not access $($group.id)"
    }
}
Write-Output $($plans.Value)
if ($unaccessibleGroups.count -ge 1) {
    Write-Error $unaccessibleGroups
}