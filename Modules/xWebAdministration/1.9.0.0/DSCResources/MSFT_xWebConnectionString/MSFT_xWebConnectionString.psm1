function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[String]$WebSite,

		[parameter(Mandatory = $true)]
		[String]$Name,

		[parameter(Mandatory = $true)]
		[String]$ConnectionString
	)

    # Normalized path for IIS: drive
    $IISPath = "IIS:\Sites\$WebSite"
    Assert-Input -PSPath $IISPath

    # Filter for the given name
    $filter = "connectionStrings/add[@Name='$Name']"

    Write-Verbose -Message "Get connectionString element with Name='$Name' in web.config for $PSPath ..."
    $connectionElement = Get-WebConfigurationProperty -PSPath $IISPath -Filter $filter -Name *
    
    [ordered]@{
        Ensure           = if($connectionElement){'Present'}else{'Absent'}
		WebSite          = $WebSite
		Name             = $connectionElement.Name
		ConnectionString = $connectionElement.ConnectionString
		ProviderName     = $connectionElement.ProviderName
	}
}

function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[String]$WebSite,

		[parameter(Mandatory = $true)]
		[String]$Name,

		[parameter(Mandatory = $true)]
		[String]$ConnectionString,

		[String]$ProviderName = 'System.Data.SqlClient',

        [ValidateSet('Present', 'Absent')]
        [string]$Ensure = 'Present'
	)

    ValidateProperty -WebSite $WebSite -Name $Name -ConnectionString $ConnectionString -ProviderName $ProviderName -Apply
}

function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[parameter(Mandatory = $true)]
		[String]$WebSite,

		[parameter(Mandatory = $true)]
		[String]$Name,

		[parameter(Mandatory = $true)]
		[String]$ConnectionString,

		[String]$ProviderName = 'System.Data.SqlClient',

        [ValidateSet('Present', 'Absent')]
        [string]$Ensure = 'Present'
	)

    ValidateProperty -WebSite $WebSite -Name $Name -ConnectionString $ConnectionString -ProviderName $ProviderName
}

#region Helper Function

# Internal function to throw terminating error with specified errroCategory, errorId and errorMessage
function New-TerminatingError
{
    param
    (
        [Parameter(Mandatory)]
        [String]$errorId,
        
        [Parameter(Mandatory)]
        [String]$errorMessage,

        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorCategory]$errorCategory
    )
    
    $exception = New-Object System.InvalidOperationException $errorMessage 
    $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, $errorId, $errorCategory, $null
    throw $errorRecord
}

function Assert-Input
{
	param
	(
		[parameter(Mandatory = $true)]
		[String]$PSPath
    )

    # Import WebAdministration module if present or throw error
    if(Import-Module ServerManager -PassThru -Verbose:$false -ErrorAction Ignore)
    {
    }
    else
    {
        $errorString = 'Please ensure that IIS (Web-Server) role is installed with its PowerShell module'
        New-TerminatingError -errorId 'MissingWebAdministrationModule' -errorMessage $errorString `
                             -errorCategory InvalidOperation
    }

    # Find Website name from the PSPath of IIS drive
    $WebSite = $($PSPath.Split('\')[-1])

    # Check website exists under IIS drive
    if(!(dir $PSPath -ErrorAction SilentlyContinue))
    {
        $errorString = "There is no website $WebSite"
        New-TerminatingError -errorId 'MissingWebSite' -errorMessage $errorString `
                             -errorCategory InvalidOperation
    }

    # Check if the folder conatins web.config file
    if(! ((Get-WebConfigFile -PSPath $PSPath).Name -eq 'web.config') )
    {
        $errorString = "Website $WebSite is missing web.config file"
        New-TerminatingError -errorId 'MissingWebConfigFile' -errorMessage $errorString `
                             -errorCategory InvalidOperation
    }
}

function ValidateProperty
{
	param
	(
		[parameter(Mandatory = $true)]
		[String]$WebSite,

		[parameter(Mandatory = $true)]
		[String]$Name,

		[parameter(Mandatory = $true)]
		[String]$ConnectionString,

		[parameter(Mandatory = $true)]
		[String]$ProviderName,

        [Switch]$Apply
	)

    $currentState = Get-TargetResource -WebSite $WebSite -Name $Name -ConnectionString $ConnectionString

    # Normalized path for IIS: drive
    $IISPath = "IIS:\Sites\$WebSite"
    
    # Filter for the given name
    $filter = "connectionStrings/add[@Name='$Name']"

    Write-Verbose -Message "connectionString element with Name='$Name' is $($currentState.Ensure) in web.config"
    
    # If connectionString element is present
    if($currentState.Ensure -eq 'Present')
    {
        # Validate various attributes, if the connectionStrings element should be present
        if($Ensure -eq 'Present')
        {
            #Check for connectiongstring attribute
            Write-Verbose -Message "Checking connectionString attribute for Name='$Name' ..."
            if($currentState.ConnectionString -ne $ConnectionString)
            {
                Write-Verbose -Message "connectionString attribute for Name='$Name' is not in desired state"
                Write-Debug -Message "connectionString expected $ConnectionString, but actual is $($currentState.ConnectionString)"
                if($Apply)
                {
                    Set-WebConfigurationProperty -PSPath $IISPath -Filter $filter -Name 'ConnectionString' -Value $ConnectionString
                    Write-Verbose -Message "connectionString attribute for Name='$Name' is now in desired state"
                    Write-Debug -Message "connectionString is set to $ConnectionString"
                }
                else
                {
                    return $false
                }
            }
            else
            {
                Write-Verbose -Message "connectionString attribute for Name='$Name' is in desired state"
            }

            #Check for providerName attribute
            Write-Verbose -Message "Checking providerName attribute for Name='$Name' ..."
            if($currentState.providerName -ne $ProviderName)
            {
                Write-Verbose -Message "providerName attribute for Name='$Name' is not in desired state." 
                Write-Debug -Message "providerName expected $ProviderName, but actual is $($currentState.ProviderName)"
                if($Apply)
                {
                    Set-WebConfigurationProperty -PSPath $IISPath -Filter $filter -Name 'ProviderName' -Value $ProviderName
                    Write-Verbose -Message "providerName attribute for Name='$Name' is now in desired state"
                    Write-Debug -Message "providerName is set to $ProviderName"
                }
                else
                {
                    return $false
                }
            }
            else
            {
                Write-Verbose -Message "providerName attribute for Name='$Name' is in desired state"
            }

            # If all the attributes are correct, return true for Test-TR function
            if(! $Apply){return $true}
        }

        # The element should not be present
        else
        {
            if($Apply)
            {
                Clear-WebConfiguration -PSPath $IISPath -Filter $filter
            }
            else
            {
                return $false
            }
        }
    }

    # If connectionString element is absent
    else
    {
        # If connectionStrings element should be present, add one
        if($Ensure -eq 'Present')
        {
            if($Apply)
            {
                # Element to add
                $item = @{Name=$Name;ConnectionString=$ConnectionString;ProviderName=$ProviderName}

                Write-Verbose -Message 'Adding a connectionString element in the web.config ...'
                Add-WebConfigurationProperty -PSPath $IISPath -Filter 'ConnectionStrings' -Name . -Value $item
                Write-Verbose -Message 'connectionString element successfully added to the web.config'
            }
            else
            {
                return $false
            }
        }
        else
        {
            # If connectionStrings element should be absent, return true for Test-TR function
            if(! $Apply){return $true}
    }
}
}

#endregion

Export-ModuleMember -Function *-TargetResource