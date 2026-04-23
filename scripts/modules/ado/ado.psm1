<#
.SYNOPSIS
Initialize default headers With AccessToken.

.DESCRIPTION
Initialize default headers With AccessToken require to perform devops rest api call.

.PARAMETER PatToken
Optional. Pat Token with Service endpoint manage permission. 
If PatToken is not provided $env:SYSTEM_ACCESSTOKEN will be used. Make sure Project build service identity has granted 
required permissions to perform create or update service endpoint operatins.
For e.g. To create service connection in Defra-FFC project 'DEFRA-FFC Build Service (defragovuk)' identity should be granted 'Administrator' permissions at Service connection scope.

.EXAMPLE
.\Get-DefaultHeadersWithAccessToken
#> 
Function Get-DefaultHeadersWithAccessToken() {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $false)]
        [string]$PatToken
    )

    [string]$functionName = $MyInvocation.MyCommand    
    Write-Debug "${functionName}:Entered"
    
    [System.Collections.Generic.Dictionary[[String],[String]]]$accessTokenHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $accessTokenHeaders.Add("Content-Type", "application/json")
    
    if([string]::IsNullOrWhiteSpace($PatToken)) {
        $accessTokenHeaders.Add("Authorization", "Bearer $env:SYSTEM_ACCESSTOKEN")
    }
    else {
        $token = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($PatToken)"))
        $accessTokenHeaders.Add("Authorization", "Basic $token")
    }
    
    Write-Debug "${functionName}:Exited"
    return $accessTokenHeaders
}

<#
.SYNOPSIS
Initialize service endpoint proxy request body To verify Service endpoint.

.DESCRIPTION
Initialize service endpoint proxy request body To verify Service endpoint. It uses default 'endpointproxy-request-body.json' file to prepare request body.
https://learn.microsoft.com/en-us/rest/api/azure/devops/serviceendpoint/endpointproxy/execute-service-endpoint-request?view=azure-devops-rest-7.1&tabs=HTTP#request-body

.PARAMETER ServiceEndpointRequestBody
Mandatory. Service Endpoint Request Body

.EXAMPLE
.\Initialize-ProxyRequestBody -ServiceEndpointRequestBody <ServiceEndpointRequestBody>
#> 
Function Initialize-ProxyRequestBody() {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [string]$ServiceEndpointRequestBody
    )

    begin {
        [string]$functionName = $MyInvocation.MyCommand    
        Write-Debug "${functionName}:Entered"
    }

    process {
        Write-Debug "Building Service endpoint proxy Body..."
        [PSCustomObject]$serviceEndpointProxyDefaultConfig = Get-Content -Raw -Path (Join-Path -Path $PSScriptRoot -ChildPath "request-body/endpointproxy-request-body.json") | ConvertFrom-Json
        Write-Debug "serviceEndpointProxyDefaultConfig = $($serviceEndpointProxyDefaultConfig | ConvertTo-Json -Depth 10)"

        $serviceEndpointProxyDefaultConfig.serviceEndpointDetails = ($ServiceEndpointRequestBody | ConvertFrom-Json)
        
        $serviceEndpointProxyRequestBody = $serviceEndpointProxyDefaultConfig | ConvertTo-Json -Depth 10
        #Do not print serviceEndpointProxyRequestBody as it contains password/sensitive info
        Write-Debug "ServiceEndpointProxy RequestBody Payload Initialized."
        return $serviceEndpointProxyRequestBody
    }

    end {
        Write-Debug "${functionName}:Exited"
    }    
}

<#
.SYNOPSIS
Initialize service endpoint request body To create or update Service endpoint of ARM type. 

.DESCRIPTION
Initialize request body To create or update Service endpoint of ARM type. It uses default 'arm-serviceendpoint-request-body.json' file to prepare request body.
https://learn.microsoft.com/en-us/rest/api/azure/devops/serviceendpoint/endpoints/create?tabs=HTTP#request-body

.PARAMETER ArmServiceConnection
Mandatory. Service connection object(Coming from input config file)

.PARAMETER ProjectId
Mandatory. Azure devops project ID

.PARAMETER ProjectName
Mandatory. Azure devops project name

.EXAMPLE
.\Initialize-RequestBody -ArmServiceConnection <ArmServiceConnectionObject> -ProjectId <ProjectID> -ProjectName <ProjectName>
#> 
Function Initialize-RequestBody() {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [object]$ArmServiceConnection,
        [Parameter(Mandatory)]
        [string]$ProjectId,
        [Parameter(Mandatory)]
        [string]$ProjectName
    )

    begin {
        [string]$functionName = $MyInvocation.MyCommand    
        Write-Debug "${functionName}:Entered"
        Write-Debug "${functionName}:ArmServiceConnection=$($ArmServiceConnection | ConvertTo-Json -Depth 10)"
        Write-Debug "${functionName}:ProjectId=$ProjectId"
        Write-Debug "${functionName}:ProjectName=$ProjectName"
    }

    process {        
        Write-Debug "Building Service connection Body for $($ArmServiceConnection.displayName)..."
        [PSCustomObject]$serviceEndpointDefaultConfig = Get-Content -Raw -Path (Join-Path -Path $PSScriptRoot -ChildPath "request-body/arm-serviceendpoint-request-body.json") | ConvertFrom-Json
        Write-Debug "serviceEndpointDefaultConfig = $($serviceEndpointDefaultConfig | ConvertTo-Json -Depth 10)"

        $serviceEndpointDefaultConfig.name = $ArmServiceConnection.displayName
        $serviceEndpointDefaultConfig.description = $ArmServiceConnection.description

        $serviceEndpointDefaultConfig.data.subscriptionId = $ArmServiceConnection.subscriptionId
        $serviceEndpointDefaultConfig.data.subscriptionName = $ArmServiceConnection.subscriptionName
    
        $serviceEndpointDefaultConfig.authorization.parameters.tenantid = $ArmServiceConnection.tenantId


        [string]$kvClientIdSecretName = ($ArmServiceConnection.keyVault.secrets | Where-Object { $_.type -eq 'ClientId' }).key
        [string]$kvClientPasswordSecretName = ($ArmServiceConnection.keyVault.secrets | Where-Object { $_.type -eq 'ClientSecret' }).key
    
        Write-Host "Fetching Keyvault secret $($kvClientIdSecretName) from $($ArmServiceConnection.keyVault.name)"
        [string]$spClientId = az keyvault secret show --name $kvClientIdSecretName --vault-name $ArmServiceConnection.keyVault.name --query "value" -o tsv
        if ($LASTEXITCODE -ne 0) {
            throw "Error Fetching Keyvault secret $($kvClientIdSecretName) from $($ArmServiceConnection.keyVault.name) with exit code $LASTEXITCODE"
        }
        else {
            Write-Debug "spClientId=$spClientId"
        }
    
        Write-Host "Fetching Keyvault secret $($kvClientPasswordSecretName) from $($ArmServiceConnection.keyVault.name)"
        [string]$spClientPassword = az keyvault secret show --name $kvClientPasswordSecretName --vault-name $ArmServiceConnection.keyVault.name --query "value" -o tsv
        if ($LASTEXITCODE -ne 0) {
            throw "Error Fetching Keyvault secret $($kvClientPasswordSecretName) from $($ArmServiceConnection.keyVault.name) with exit code $LASTEXITCODE"
        }

        $serviceEndpointDefaultConfig.authorization.parameters.serviceprincipalid = $spClientId
        $serviceEndpointDefaultConfig.authorization.parameters.serviceprincipalkey = $spClientPassword

        if (-not [string]::IsNullOrWhiteSpace($ArmServiceConnection.isShared)) {
            $serviceEndpointDefaultConfig.isShared = $ArmServiceConnection.isShared
        }
    
        #Set current ProjectReference to service endpoint
        $serviceEndpointDefaultConfig.serviceEndpointProjectReferences = $null
        [PSCustomObject]$selfprojectReference = New-Object -TypeName PSObject -Property @{ id = $ProjectId ; name = $ProjectName }
        [PSCustomObject]$currentProjectReference = New-Object -TypeName PSObject -Property @{ description = $ArmServiceConnection.description ; name = $ArmServiceConnection.displayName ; projectReference = $selfprojectReference }
        $serviceEndpointDefaultConfig.serviceEndpointProjectReferences = @( $currentProjectReference )

        [string]$serviceEndpointRequestBody = $serviceEndpointDefaultConfig | ConvertTo-Json -Depth 10
        #Do not print serviceEndpointRequestBody as it contains password/sensitive info
        Write-Debug "ServiceEndpointProxy RequestBody Payload Initialized"
        return $serviceEndpointRequestBody
    }

    end {
        Write-Debug "${functionName}:Exited"
    }    
}

<#
.SYNOPSIS
Create or Update an Azure RM service endpoint (ServiceConnection).

.DESCRIPTION
Create an Azure RM type service endpoint (ServiceConnection). It also verifies the service endpoint using endpointproxy.

.PARAMETER ArmServiceConnection
Mandatory. Service connection object(Coming from input config file)

.PARAMETER ProjectId
Mandatory. Azure devops project ID

.PARAMETER ProjectName
Mandatory. Azure devops project name

.PARAMETER OrgnizationUri
Mandatory. Azure devops project Orgnization Uri

.EXAMPLE
.\Set-ServiceEndpoint -ArmServiceConnection <ArmServiceConnectionObject> -ProjectId <ProjectID> -ProjectName <ProjectName> OrgnizationUri <OrgnizationUri>
#> 
Function Set-ServiceEndpoint() {
    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [Parameter(ValueFromPipeline = $true)]
        [Object]$ArmServiceConnection,
        [Parameter(Mandatory)]
        [string]$ProjectId,
        [Parameter(Mandatory)]
        [string]$ProjectName,
        [Parameter(Mandatory)]
        [string]$OrgnizationUri
    )

    begin {
        [string]$functionName = $MyInvocation.MyCommand    
        Write-Debug "${functionName}:Entered"  
        Write-Debug "${functionName}:ProjectId=$ProjectId"
        Write-Debug "${functionName}:ProjectName=$ProjectName"
        Write-Debug "${functionName}:OrgnizationUri=$OrgnizationUri"     
    }

    process {    
        Write-Debug "${functionName}:ArmServiceConnection=$($ArmServiceConnection | ConvertTo-Json -Depth 10)"
        
        #Enable this when locally testing with Pat Token    
        # [Object]$headers = Get-DefaultHeadersWithAccessToken -PatToken $env:SYSTEM_ACCESSTOKEN
        
        [Object]$headers = Get-DefaultHeadersWithAccessToken

        [string]$serviceEndpointRequestBody = Initialize-RequestBody -ArmServiceConnection $ArmServiceConnection -ProjectId $ProjectId -ProjectName $ProjectName
       
        [string]$serviceEndpointName = $armServiceConnection.displayName
        Write-Debug "Check if $($serviceEndpointName) exists"
        [string]$existingServiceEndpointId = az devops service-endpoint list --query "[?name=='$serviceEndpointName'].id" -o tsv
        if ($LASTEXITCODE -ne 0) {
            throw "Error getting service endpoint Id for '$serviceEndpointName' using 'az devops service-endpoint list' command with exit code $LASTEXITCODE"
        }
        Write-Host "existingServiceEndpointId=$existingServiceEndpointId"
        
        if (-not $existingServiceEndpointId) {            
            [string]$createServiceEndpointUri = "$($OrgnizationUri)/$ProjectName/_apis/serviceendpoint/endpoints?api-version=7.0"
            Write-Host "Creating ServiceEndpoint $($serviceEndpointName). Post url = $($createServiceEndpointUri)"
            [Object]$response = Invoke-RestMethod -Uri $createServiceEndpointUri -Headers $headers -Method Post -Body $serviceEndpointRequestBody
            if ($LASTEXITCODE -ne 0) {
                throw "Error creating serviceEndpoint $($serviceEndpointName) with exit code $LASTEXITCODE"
            }

            Write-Host "Verifying ServiceEndpoint $($serviceEndpointName)"
            Test-ServiceEndpoint -ServiceEndpointId $response.id -ServiceEndpointRequestBody $serviceEndpointRequestBody -ProjectName $ProjectName -OrgnizationUri $OrgnizationUri
            Write-Host "ServiceEndpoint $($serviceEndpointName) Created and Verified succesfully. Service Endpoint Id = $($response.id)"
        }
        else {
            $existingServiceEndpointState = az devops service-endpoint list --query "[?name=='$serviceEndpointName']"
            if ($LASTEXITCODE -ne 0) {
                throw "Error getting service endpoint details for '$serviceEndpointName' using 'az devops service-endpoint list' command with exit code $LASTEXITCODE"
            }
            Write-Host "ServiceEndpoint state before Update : $(($existingServiceEndpointState | ConvertFrom-Json) | ConvertTo-Json -Depth 10)"

            [string]$updateServiceEndpointUri = "$($OrgnizationUri)/$ProjectName/_apis/serviceendpoint/endpoints/$($existingServiceEndpointId)?api-version=7.0"
            Write-Host "Updating ServiceEndpoint $($serviceEndpointName). Put url = $($updateServiceEndpointUri)"
            [Object]$response = Invoke-RestMethod -Uri $updateServiceEndpointUri -Headers $headers -Method Put -Body $serviceEndpointRequestBody
            if ($LASTEXITCODE -ne 0) {
                throw "Error updating serviceEndpoint $($serviceEndpointName) with exit code $LASTEXITCODE"
            }

            Write-Host "Verifying ServiceEndpoint $($serviceEndpointName)"
            Test-ServiceEndpoint -ServiceEndpointId $response.id -ServiceEndpointRequestBody $serviceEndpointRequestBody -ProjectName $ProjectName -OrgnizationUri $OrgnizationUri
            Write-Host "ServiceEndpoint $($serviceEndpointName) Updated and Verified succesfully. Service Endpoint Id = $($response.id)"
        }
    }

    end {
        Write-Debug "${functionName}:Exited"
    }    
}

<#
.SYNOPSIS
Create an Azure Federated service endpoint (ServiceConnection).

.DESCRIPTION
Create an Azure Federated service endpoint (ServiceConnection).

.PARAMETER  FederatedEndpointJsonPath
Mandatory. Federated Service connection json file

.PARAMETER ProjectName
Mandatory. Azure devops project name

.PARAMETER OrgnizationUri
Mandatory. Azure devops project Orgnization Uri

.EXAMPLE
.\Set-FederatedServiceEndpoint -ArmServiceConnection <ArmServiceConnectionObject> -FederatedEndpointJsonPath <FederatedEndpointJsonPath> -ProjectName <ProjectName> OrgnizationUri <OrgnizationUri>
#> 
Function Set-FederatedServiceEndpoint() {
    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [Parameter(ValueFromPipeline = $true)]
        [Object]$ArmServiceConnection,
        [Parameter(Mandatory)]
        [string]$FederatedEndpointJsonPath, 
        [Parameter(Mandatory)]
        [string]$ProjectId,      
        [Parameter(Mandatory)]        
        [string]$ProjectName,
        [Parameter(Mandatory)]
        [string]$OrgnizationUri
    )

    begin {
        [string]$functionName = $MyInvocation.MyCommand    
        Write-Debug "${functionName}:Entered"       
        Write-Debug "${functionName}:FederatedEndpointJsonPath=$FederatedEndpointJsonPath"
        Write-Debug "${functionName}:ProjectName=$ProjectName"
        Write-Debug "${functionName}:OrgnizationUri=$OrgnizationUri"     
    }

    process {

        # Create ADO Service Connection

        $appReg = az ad app list --display-name $ArmServiceConnection.appRegName --query '[].{AppId:appId}' --output table

        $appClientId =  $appReg[2]
        Write-Host "appClientId: $appClientId"

        [PSCustomObject]$federatedserviceEndpoint = Get-Content -Raw -Path $FederatedEndpointJsonPath | ConvertFrom-Json
        $serviceConnectionName = $federatedServiceEndpoint.serviceEndpointProjectReferences[0].name

        Write-Host "Service connection name '$serviceConnectionName'"        
             
        Write-Debug "Check if $($serviceConnectionName) exists"
        $serviceConnectionId = az devops service-endpoint list --org $devopsOrgnizationUri --project $devopsProjectName --query "[?name=='$serviceConnectionName'].id" -o tsv
        if ($LASTEXITCODE -ne 0) {
            throw "Error getting service endpoint Id for '$serviceConnectionName' using 'az devops service-endpoint list' command with exit code $LASTEXITCODE"
        }

        Write-Host "Existing Service connection Id '$serviceConnectionId'"
        
        if ($serviceConnectionId) {
            Write-Output "ADO service connection $serviceConnectionName is already exist. No changes made."
        } else { 
            Write-Output "Creating ADO federated credential service connection $serviceConnectionName"      

            $jsonObj = Get-Content $FederatedEndpointJsonPath -raw | ConvertFrom-Json
            $jsonObj.authorization.parameters.serviceprincipalid =  $appClientId
            $jsonObj.serviceEndpointProjectReferences.projectReference | % {{$_.id=$ProjectId}}
            $jsonObj.serviceEndpointProjectReferences.projectReference | % {{$_.name=$ProjectName}}
            $jsonObj | ConvertTo-Json -depth 32| set-content $FederatedEndpointJsonPath

            az devops service-endpoint create --service-endpoint-configuration $FederatedEndpointJsonPath --org $OrgnizationUri --project $ProjectName
        }
    }
    end {
        Write-Debug "${functionName}:Exited"
    }    
}

<#
.SYNOPSIS
Verify service endpoint (ServiceConnection).

.DESCRIPTION
Verify service endpoint (ServiceConnection) is setup correctly using endpointproxy post api. This api returns 200(OK) response if configuration (for e.g. ServicePrincipal key or clientID) is 
correct or else returns 400.

.PARAMETER ServiceEndpointId
Mandatory. Service Endpoint Id.

.PARAMETER ServiceEndpointRequestBody
Mandatory. Service Endpoint Request Body

.PARAMETER ProjectName
Mandatory. Azure devops project name

.PARAMETER OrgnizationUri
Mandatory. Azure devops project Orgnization Uri

.EXAMPLE
.\Test-ServiceEndpoint -ServiceEndpointId <ServiceEndpointId> -ServiceEndpointRequestBody <ServiceEndpointRequestBody> -ProjectName <ProjectName> OrgnizationUri <OrgnizationUri>
#> 
Function Test-ServiceEndpoint() {
    [CmdletBinding()]
    Param(
        [ValidateNotNullOrEmpty()]
        [Parameter(ValueFromPipeline = $true)]
        [Object]$ServiceEndpointId,
        [Parameter(Mandatory)]
        [string]$ServiceEndpointRequestBody,
        [Parameter(Mandatory)]
        [string]$ProjectName,
        [Parameter(Mandatory)]
        [string]$OrgnizationUri
    )

    begin {
        [string]$functionName = $MyInvocation.MyCommand    
        Write-Debug "${functionName}:Entered" 
        Write-Debug "${functionName}:ServiceEndpointId=$ServiceEndpointId"
        Write-Debug "${functionName}:ProjectName=$ProjectName"
        Write-Debug "${functionName}:OrgnizationUri=$OrgnizationUri"     
    }

    process {        
        #Enable this when locally testing with Pat Token    
        # [Object]$headers = Get-DefaultHeadersWithAccessToken -PatToken $env:SYSTEM_ACCESSTOKEN

        [Object]$headers = Get-DefaultHeadersWithAccessToken

        [string]$serviceEndpointProxyRequestBody = Initialize-ProxyRequestBody -ServiceEndpointRequestBody $ServiceEndpointRequestBody
        
        [string]$endpointProxyServiceEndpointUri = "$($OrgnizationUri)/$ProjectName/_apis/serviceendpoint/endpointproxy?endpointId=$($ServiceEndpointId)&api-version=7.0"
        Write-Debug "Verifying ServiceEndpoint $($ServiceEndpointId). Put url = $($endpointProxyServiceEndpointUri)"
        $response = Invoke-RestMethod -Uri $endpointProxyServiceEndpointUri -Headers $headers -Method Post -Body $serviceEndpointProxyRequestBody
        if ($response.StatusCode -ne [system.net.httpstatuscode]::ok) {
            throw "Error Verifying serviceEndpoint $($ServiceEndpointId). ErrorMessage = $($response.errorMessage)"
        }
        Write-Debug "$($ServiceEndpointId) Verified. Service Endpoint Id = $($ServiceEndpointId)"
    }

    end {
        Write-Debug "${functionName}:Exited"
    }    
}



<#
.SYNOPSIS
Trigger a new build and wait for completion; on failure, surface child run logs and artifacts.

.DESCRIPTION
Queues via Build REST API, polls until completed, then on failure fetches timeline issues, log tails, and uploads a zip of all logs.

.PARAMETER organisationUri
Mandatory. Azure DevOps organization collection URI.

.PARAMETER projectName
Mandatory. Azure DevOps project name.

.PARAMETER buildDefinitionId
Mandatory. Build definition id.

.PARAMETER requestBody
Mandatory. JSON body containing templateParameters (and optional wrapper); templateParameters are passed to the queue request.

.EXAMPLE
New-BuildRun -organisationUri $uri -projectName 'CCoE-Infrastructure' -buildDefinitionId 4634 -requestBody $requestBodyJson
#>
Function New-BuildRun() {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)][string]$organisationUri,
        [Parameter(Mandatory)][string]$projectName,
        [Parameter(Mandatory)][int]$buildDefinitionId,
        [Parameter(Mandatory)][string]$requestBody
    )

    begin {
        [string]$functionName = $MyInvocation.MyCommand
        Write-Host "${functionName} started at $([datetime]::UtcNow.ToString('u'))"
        Write-Host "${functionName}:organisationUri=$organisationUri"
        Write-Host "${functionName}:projectName=$projectName"
        Write-Host "${functionName}:buildDefinitionId=$buildDefinitionId"
        Write-Host "${functionName}:requestBody=$requestBody"
    }

    process {
        # ---- Config ----
        $PollSeconds = 10
        $TimeoutSecs = 1800
        $TailLines   = 80
        $MaxLogs     = 12

        # ---- URLs / headers ----
        $OrgBase = $organisationUri.TrimEnd('/') + '/'
        $ProjEnc = [System.Uri]::EscapeDataString($projectName)
        $apiVerBuild = "7.1-preview.7"
        $headers = Get-DefaultHeadersWithAccessToken

        # ---- Queue child build ----
        $queueUri  = "$OrgBase$ProjEnc/_apis/build/builds?api-version=$apiVerBuild"
        $queueBody = @{
            definition         = @{ id = $buildDefinitionId }
            templateParameters = (ConvertFrom-Json -InputObject $requestBody).templateParameters
        } | ConvertTo-Json -Depth 10

        $queued = Invoke-RestMethod -Method Post -Uri $queueUri -Headers $headers -Body $queueBody -ContentType "application/json" -ErrorAction Stop

        if (-not $queued.id) {
            Write-Warning "Queue response didn't include an 'id'. Full response follows:"
            $queued | ConvertTo-Json -Depth 10
            throw "Failed to queue child build (no id returned)."
        }

        $buildId = $queued.id
        $webUrl  = $queued._links.web.href
        if (-not $webUrl) { $webUrl = "$OrgBase$ProjEnc/_build/results?buildId=${buildId}" }

        Write-Host "Queued child buildId: $buildId"
        Write-Host "Child run URL: $webUrl"

        # ---- Poll until completed or timeout ----
        $elapsed = 0
        $status  = $queued.status
        $result  = $queued.result

        do {
            Start-Sleep -Seconds $PollSeconds
            $elapsed += $PollSeconds

            $statusUrl = "$OrgBase$ProjEnc/_apis/build/builds/${buildId}?api-version=$apiVerBuild"
            Write-Verbose "Status Url: $statusUrl"
            $build  = Invoke-RestMethod -Method Get -Uri $statusUrl -Headers $headers -ErrorAction Stop
            $status = $build.status
            $result = $build.result

            Write-Host "Child status: $status, result: $result"

            if ($elapsed -ge $TimeoutSecs) {
                Write-Host "##vso[task.logissue type=error]Child build exceeded timeout ($TimeoutSecs s)."
                throw "Child build $buildId timed out after $TimeoutSecs seconds."
            }

            $statusCompleted = [string]::Equals([string]$status, 'completed', [System.StringComparison]::OrdinalIgnoreCase)
        } while (-not $statusCompleted)

        # ---- Success path ----
        if ([string]::Equals([string]$result, 'succeeded', [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "$($build.definition.name) build $buildId completed successfully."
            Write-Host "Child run: $webUrl"
            return
        }

        # ---- Failure path: timeline + targeted log tails + zip all logs ----
        Write-Host "Child build FAILED. Collecting summary information..."

        # Fetch timeline and logs index using the URLs Azure DevOps returned
        $timeline = $null; $logsIdx = $null
        try {
            $timelineUrl = "$($build._links.timeline.href)"
            Write-Verbose "timelineUrl: $timelineUrl"
            $timeline = Invoke-RestMethod -Method Get -Uri $timelineUrl -Headers $headers -ErrorAction Stop
        } catch { Write-Verbose "Timeline unavailable: $($_.Exception.Message)" }

        try {
            $logsIndexUrl = "$($build.logs.url)".TrimEnd('/')
            Write-Verbose "logsIndexUrl: $logsIndexUrl"
            $logsIdx = Invoke-RestMethod -Method Get -Uri $logsIndexUrl -Headers $headers -ErrorAction Stop
        } catch { Write-Verbose "Logs index unavailable: $($_.Exception.Message)" }

        # Quick human summary from timeline issues
        if ($timeline -and $timeline.records) {
            $issues = @()
            foreach ($rec in $timeline.records) {
                if ($rec.issues) {
                    foreach ($i in $rec.issues) {
                        $issues += "[{0}] {1}: {2}" -f $rec.name, $i.type, ($i.message -replace "`r|`n",' ')
                    }
                }
            }
            if ($issues.Count -gt 0) {
                Write-Host "Timeline issues:"
                $issues | ForEach-Object { Write-Host $_ }
            }
        }

        # Helper: tail a specific log id (derive URL on the fly; prefer index entry if found)
        function local:Show-LogTail {
            param([Parameter(Mandatory)][int]$LogId,
                  [Parameter(Mandatory)][string]$Title)

            $entry = $null
            if ($logsIdx -and $logsIdx.value) {
                $entry = $logsIdx.value | Where-Object { [string]$_.id -eq [string]$LogId } | Select-Object -First 1
            }
            $logTextUrl = if ($entry -and $entry.url) { $entry.url } else { "$logsIndexUrl/$LogId" }

            try {
                Write-Verbose "Fetching log $LogId from $logTextUrl"
                $logText = Invoke-RestMethod -Method Get -Uri $logTextUrl -Headers $headers -ErrorAction Stop
                $tail    = ($logText -split "`n") | Select-Object -Last $TailLines
                Write-Host "`n----- Log ${LogId}: $Title (last $TailLines lines) -----"
                $tail | ForEach-Object { Write-Host $_ }
                Write-Host "----- End log $LogId -----"
                return $true
            } catch {
                Write-Verbose "Failed to fetch log ${LogId}: $($_.Exception.Message)"
                return $false
            }
        }

        # Pick target timeline records (failed/canceled/partial or with issues) + their children
        $targetRecords = @()
        if ($timeline -and $timeline.records) {
            Write-Verbose "Found $($timeline.records.Count) timeline records."
            $targetRecords = $timeline.records | Where-Object {
                $_.result -in @("failed","canceled","partiallySucceeded") -or $_.issues
            }

            if ($targetRecords.Count -gt 0) {
                $targetIds = $targetRecords.id
                $children  = $timeline.records | Where-Object { $_.parentId -and ($targetIds -contains $_.parentId) }
                $targetRecords += $children
            }

            $targetRecords = $targetRecords |
                Sort-Object @{Expression={ $_.order }}, @{Expression={ $_.log.id }} |
                Select-Object -Unique
            Write-Verbose "Targeted records: $($targetRecords.Count)"
        }

        # Show tails for targeted logs first
        $shown = 0
        if ($targetRecords.Count -gt 0) {
            foreach ($rec in $targetRecords) {
                if ($shown -ge $MaxLogs) { break }
                $logId = $rec.log.id
                if ($null -ne $logId) {
                    if (Show-LogTail -LogId $logId -Title $rec.name) { $shown++ }
                }
            }
        }

        # Fallback: latest logs if nothing shown
        if ($shown -eq 0 -and $logsIdx -and $logsIdx.value) {
            Write-Verbose "No targeted logs shown; falling back to latest logs."
            $latest = $logsIdx.value | Sort-Object id -Descending | Select-Object -First ([Math]::Min($MaxLogs, $logsIdx.value.Count))
            foreach ($l in $latest) {
                if ($shown -ge $MaxLogs) { break }
                if (Show-LogTail -LogId $l.id -Title "LogId $($l.id)") { $shown++ }
            }
        }

        # ---- ZIP **all** logs and publish as artifact + job attachment ----
        try {
            # Map logId -> friendly name from timeline
            $nameByLogId = @{}
            if ($timeline -and $timeline.records) {
                foreach ($rec in $timeline.records) {
                    if ($rec.log -and $null -ne $rec.log.id -and $rec.name -and -not $nameByLogId.ContainsKey([string]$rec.log.id)) {
                        $nameByLogId[[string]$rec.log.id] = $rec.name
                    }
                }
            }

            $workDir = if ($env:Agent_TempDirectory) { $env:Agent_TempDirectory } elseif ($env:TEMP) { $env:TEMP } else { $PWD }
            $logsDir = Join-Path $workDir ("child-{0}-logs" -f $buildId)
            if (Test-Path $logsDir) { Remove-Item -Recurse -Force $logsDir }
            New-Item -ItemType Directory -Path $logsDir | Out-Null

            function local:Sanitize-FileName([string]$name) {
                if ([string]::IsNullOrWhiteSpace($name)) { return "" }
                foreach ($c in [IO.Path]::GetInvalidFileNameChars()) {
                    $name = $name.Replace([string]$c, '_')
                }
                return $name.Trim()
            }

            $downloaded = 0
            if ($logsIdx -and $logsIdx.value) {
                foreach ($l in ($logsIdx.value | Sort-Object id)) {
                    $id  = $l.id
                    $url = if ($l.url) { $l.url } elseif ($l._links.self.href) { $l._links.self.href } else { "$logsIndexUrl/$id" }
                    $friendly = ""
                    if ($nameByLogId.ContainsKey([string]$id)) { $friendly = " - " + (Sanitize-FileName $nameByLogId[[string]$id]) }
                    $file = Join-Path $logsDir ("{0:D4}{1}.log" -f $id, $friendly)
                    try {
                        $text = Invoke-RestMethod -Method Get -Uri $url -Headers $headers -ErrorAction Stop
                        [System.IO.File]::WriteAllText($file, [string]$text, [System.Text.Encoding]::UTF8)
                        $downloaded++
                    } catch { Write-Verbose "Failed to fetch log ${id}: $($_.Exception.Message)" }
                }
            }

            $zipPath = Join-Path $workDir ("child-{0}-logs.zip" -f $buildId)
            if (Test-Path $zipPath) { Remove-Item -Force $zipPath }

            if ((Get-ChildItem -Path $logsDir -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) {
                Compress-Archive -Path (Join-Path $logsDir '*') -DestinationPath $zipPath -Force
                Write-Host "Created archive: $zipPath ($downloaded logs)"
                $artifactName = "child-${buildId}-logs"
                Write-Host "##vso[artifact.upload artifactname=$artifactName;]$zipPath"
                Write-Host "##vso[task.uploadfile]$zipPath"
            } else {
                Write-Host "No logs were downloaded to zip."
            }
        } catch {
            Write-Verbose "Zipping/publishing logs failed: $($_.Exception.Message)"
        }

        Write-Error "See child run for full details: $webUrl"
        Write-Host "##vso[task.logissue type=error]$($build.definition.name) build $buildId failed (result=$result)."
        throw "Child build failed (buildId=$buildId, result=$result)."
    }

    end {
        Write-Verbose "${functionName}:Exited"
    }
}