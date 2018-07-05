# ---------------------------------------------------------------------------------- 
    # <auto-generated>
    # Copyright (c) Microsoft Corporation. All rights reserved.
    # Licensed under the MIT License. See License.txt in the project root for
    # license information.
# ---------------------------------------------------------------------------------- 

$errorStream = New-Object -TypeName "System.Text.StringBuilder";
$outputStream = New-Object -TypeName "System.Text.StringBuilder";


function Get-SdkRepoRootDirectory {
    param(
        [string] $scriptPath
    )
    
    $currPath = $scriptPath
    if($scriptPath.Contains("\src\SDKs\") -or $scriptPath.Contains("\src\AzureStack\"))
    {
        while(![string]::IsNullOrEmpty($currPath) -and !(($currPath.EndsWith("\src\SDKs") -or $currPath.EndsWith("\src\AzureStack")) -and $(Test-Path "$currPath\..\..\.gitignore")))
        {
            $currPath = $(Split-Path $currPath -parent)
        }
    }
    return $currPath
}

function Get-InvokingScriptPath {
    $arr =$($(Get-PSCallStack).InvocationInfo.PSCommandPath)
    foreach ($p in $arr) {
        if(![string]::IsNullOrEmpty($p) -and ($p.Contains("\src\SDKs") -or $p.Contains("\src\AzureStack")))
        {
            return $(Split-Path $p -Parent)
        }
    }
    return $PSScriptRoot
}

function Write-InfoLog {
    param(
        [string] $msg
    )
    if([string]::IsNullOrEmpty($msg))
    {
        return
    }
    $outputStream.Append("$msg`n") | Out-Null
    Write-Host $msg
}

function Write-ErrorLog {
    param(
        [string] $msg
    )
    if([string]::IsNullOrEmpty($msg))
    {
        return
    }
    $errorStream.Append("$msg`n") | Out-Null
    Write-Error $msg
}

function Clear-OutputStreams {
    $errorStream.Clear() | Out-Null
    $outputStream.Clear() | Out-Null
}
function launchProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string] $command, 
        [string] $args)
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $command
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    
    if(![string]::IsNullOrEmpty($args))
    {
        $pinfo.Arguments = $args
    }
    
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $p.WaitForExit()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    <#
    # send std output to the console only
    # Display output produced by command invoked here in order to reduce the 
    # metadata logged. In case of errors however, we need to log them
    #>
    Write-Host $stdout 
    Write-ErrorLog $stderr
    if($p.ExitCode -ne 0)
    {
        throw [System.Exception] "Command $cmd $args returned $p.ExitCode"
    }
}

function Get-AutoRestHelp {
    Write-InfoLog "Fetching AutoRest help" 
    launchProcess "cmd.exe" "/c autorest.cmd --help"
}

function Install-AutoRest {
    param(
        [Parameter(Mandatory = $true)]
        $AutoRestVersion
    )
    
    Write-InfoLog "Installing AutoRest version: $AutoRestVersion" 
    
    Try {
        launchProcess "cmd.exe" "/c npm.cmd install -g autorest@$AutoRestVersion"
    }
    Catch [System.Exception] {
        Write-ErrorLog $_.Exception.ToString()
        throw [System.Exception] "AutoRest Installation failed"
    }
    Write-InfoLog "AutoRest installed successfully." 
}

function Invoke-AutoRestCodeGenerationCommand {
param(
    [Parameter(Mandatory = $true)]
    [string] $ConfigFile,
    [Parameter(Mandatory = $false, HelpMessage ="Please provide an output directory for the generated code")]
    [string] $SdkRootDirectory,
    [Parameter(Mandatory=$false, HelpMessage ="Please provide an output directory for the generated code")]
    [string] $SdkGenerationDirectory,
    [Parameter(Mandatory = $false)]
    [string] $Namespace,
    [Parameter(Mandatory = $false)]
    [string] $ConfigFileTag,
    [Parameter(Mandatory = $true, HelpMessage ="Please provide a version for the AutoRest release")]
    [string] $AutoRestVersion,
    [Parameter(Mandatory = $false)]
    [string] $SdkGenerationType
    )
    
    Write-InfoLog "Generating CSharp code" 
    $cmd = "cmd.exe"
    $args = "/c autorest.cmd $configFile --csharp --version=$AutoRestVersion --reflect-api-versions"
    
    if(-not [string]::IsNullOrWhiteSpace($Namespace))
    {
        $args = $args + " --csharp.namespace=$Namespace"
    }

    if(-not [string]::IsNullOrWhiteSpace($ConfigFileTag))
    {
        $args = $args + " --tag=$ConfigFileTag"
    }

    if($SdkGenerationType -eq "multiapi")
    {
        $args = $args + " --multiapi"
    }

    if(-not [string]::IsNullOrWhiteSpace($SdkGenerationDirectory))
    {
        $args = $args + " --csharp.output-folder=$SdkGenerationDirectory"
    }
    elseif(-not [string]::IsNullOrWhiteSpace($SdkRootDirectory))
    {
        $args = $args + " --csharp-sdks-folder=$SdkRootDirectory"
    }
    
    Write-InfoLog "Executing AutoRest command" 
    Write-InfoLog "$cmd $args" 

    Try {
        launchProcess $cmd $args
    }
    Catch [System.Exception] {
        Write-ErrorLog $_.Exception.ToString()
        throw [System.Exception] "AutoRest code generation for $configFile failed. Please try again"
    }
    
    Try {
        Start-MetadataGeneration -AutoRestVersion $AutoRestVersion -SpecsRepoFork $SpecsRepoFork -SpecsRepoBranch $SpecsRepoBranch
    }
    Catch [System.Exception] {
        Write-ErrorLog $_.Exception.ToString()
        throw [System.Exception] "Metadata generation for $configFile failed. Please try again"
    }
}

function Start-MetadataGeneration {
    param(
        [Parameter(Mandatory = $true)]
        [string] $AutoRestVersion,
        [Parameter(Mandatory = $true)]
        [string] $SpecsRepoFork,
        [Parameter(Mandatory = $true)]
        [string] $SpecsRepoBranch
    )
    
    Write-InfoLog $([DateTime]::UtcNow.ToString('u').Replace('Z',' UTC')) 

    Write-InfoLog "" 
    Write-InfoLog "1) azure-rest-api-specs repository information" 
    Write-InfoLog "GitHub fork: $SpecsRepoFork" 
    Write-InfoLog "Branch:      $SpecsRepoBranch" 
    
    Try
    {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $op = (Invoke-RestMethod "https://api.github.com/repos/$($SpecsRepoFork)/azure-rest-api-specs/branches/$($SpecsRepoBranch)").commit.sha | Out-String
        Write-InfoLog "Commit:      $op" 
    }
    Catch [System.Exception]
    {
        Write-ErrorLog $_.Exception.ToString()
        throw $_
    }

    Write-InfoLog "" 
    Write-InfoLog "2) AutoRest information" 
    Write-InfoLog "Requested version: $AutoRestVersion" 
    
    Try
    {
        $op = $((npm list -g autorest) | Out-String).Replace("`n", " ").Replace("`r"," ").Trim()
        $tokens = $op.Split(" ")
        if($tokens.Length -gt 1)
        {
            $op = $tokens[$tokens.Length-1]
        }
        Write-InfoLog "Bootstrapper version:    $op" 
        Write-InfoLog "`n" 
    }
    Catch{}
    Try
    {
        $op = (autorest --list-installed | Where {$_ -like "*Latest Core Installed*"}).Split()[-1] | Out-String
        $op = $op.Replace("`n", " ").Replace("`r"," ").Trim()
        Write-InfoLog "Latest installed version:    $op" 
    }
    Catch{}
    Try
    {
        $op = (autorest --list-installed | Where {$_ -like "*@microsoft.azure/autorest-core*"} | Select -Last 1).Split('|')[3] | Out-String
        $op = $op.Replace("`n", " ").Replace("`r"," ").Trim()
        Write-InfoLog "Latest installed version:    $op" 
    }
    Catch{}
}

function Get-ErrorStream {
    $errorStream.ToString()
}

function Get-OutputStream {
    $outputStream.ToString()
}

<#

.SYNOPSIS
    Powershell script that generates the C# code for your sdk usin the config file provided

.DESCRIPTION
    This script:
    - fetches the config file from user/branch provided
    - Generates code based off the config file provided
    - into the directory path provided

.PARAMETER ResourceProvider
    The Resource provider for whom to generate the code; also helps determine path where config file is located in repo

.PARAMETER Version
    The AutoRest version to use to generate the code, "latest" is recommended

.PARAMETER SpecsRepoFork
    The Rest Spec repo fork which contains the config file

.PARAMETER SpecsRepoBranch
    The Branch which contains the config file

.PARAMETER SpecsRepoName
    The name of the repo that contains the config file (Can only be either of azure-rest-api-specs or azure-rest-api-specs-pr)

.PARAMETER SdkRootDirectory
    The root path in csharp-sdks-folder in config file where to generate the code

.PARAMETER SdkDirectory
    The legacy sdk output directory

.PARAMETER SdkGenerationDirectory
    The path where to generate the code
    
.PARAMETER Namespace
    The C# namespace for sdk to generate

.PARAMETER ConfigFileTag
    The tag in config file for which to generate the sdk. Code generation fails if incorrect tags are provided
    
#>
function Start-AutoRestCodeGeneration {
    [CmdletBinding(DefaultParameterSetName="sdkRootDir")]
    Param(
        [Parameter(Mandatory = $true)]
        [string] $ResourceProvider,

        [Parameter(Mandatory=$false)]
        [string] $SpecsRepoFork = "Azure",

        [Parameter(Mandatory=$false)]
        [string] $SpecsRepoName = "azure-rest-api-specs",

        [Parameter(Mandatory = $false)]
        [string] $SpecsRepoBranch = "master",

        [Parameter(Mandatory = $false)]
        [string] $AutoRestVersion = "latest",

        [Parameter(ParameterSetName="sdkRootDir", Mandatory = $false, HelpMessage="The root directory equivalent to csharp-sdks-folder in config file. Eg.: Code will be generated in SdkRootDirectory/Compute/Management.Compute/Generated")]
        [string] $SdkRootDirectory,

        [Parameter(ParameterSetName="sdkOutputDir", Mandatory=$false, HelpMessage="The final directory where generrated code will go. Eg.: Code will be generated in sdkGenerationDirectory/Generated/")]
        [string] $SdkGenerationDirectory,

        [Parameter(ParameterSetName="sdkOutputDirLegacy", Mandatory=$false, HelpMessage="Legacy parameter same as SdkRootDirectory")]
        [string] $SdkDirectory,

        [Parameter(Mandatory = $false)]
        [string] $Namespace,

        [Parameter(Mandatory = $false)]
        [string] $ConfigFileTag,

        [Parameter(Mandatory = $false)]
        [ValidateSet("singleapi", "multiapi")]
        [string] $SdkGenerationType = "singleapi"
    )

    if(-not [string]::IsNullOrWhiteSpace($SdkDirectory)) {
        Start-CodeGeneration -ResourceProvider $ResourceProvider -SdkDirectory $SdkDirectory -Namespace $Namespace -ConfigFileTag $ConfigFileTag -SpecsRepoFork $SpecsRepoFork -SpecsRepoName $SpecsRepoName -SpecsRepoBranch $SpecsRepoBranch -SdkGenerationType $SdkGenerationType -AutoRestVersion $AutoRestVersion
    }
    elseif (-not [string]::IsNullOrWhiteSpace($SdkRootDirectory)) {
        Start-CodeGeneration -ResourceProvider $ResourceProvider -SdkRootDirectory $SdkRootDirectory -Namespace $Namespace -ConfigFileTag $ConfigFileTag -SpecsRepoFork $SpecsRepoFork -SpecsRepoName $SpecsRepoName -SpecsRepoBranch $SpecsRepoBranch -SdkGenerationType $SdkGenerationType -AutoRestVersion $AutoRestVersion
    }
    elseif (-not [string]::IsNullOrWhiteSpace($SdkGenerationDirectory)){
        Start-CodeGeneration -ResourceProvider $ResourceProvider -SdkGenerationDirectory $SdkGenerationDirectory -Namespace $Namespace -ConfigFileTag $ConfigFileTag -SpecsRepoFork $SpecsRepoFork -SpecsRepoName $SpecsRepoName -SpecsRepoBranch $SpecsRepoBranch -SdkGenerationType $SdkGenerationType -AutoRestVersion $AutoRestVersion
    }
    else {
        # default path which is the root directory of the RP in sdk repo
        $SdkDirectory = Get-SdkRepoRootDirectory($(Get-InvokingScriptPath))
        if([string]::IsNullOrEmpty($SdkDirectory))
        {
            Write-Error "Could not find default output directory since script is not run from a sdk repo, please provide one!"
        }
        Start-CodeGeneration -ResourceProvider $ResourceProvider -SdkDirectory $SdkDirectory -Namespace $Namespace -ConfigFileTag $ConfigFileTag -SpecsRepoFork $SpecsRepoFork -SpecsRepoName $SpecsRepoName -SpecsRepoBranch $SpecsRepoBranch -SdkGenerationType $SdkGenerationType -AutoRestVersion $AutoRestVersion
    }
}

<#

.SYNOPSIS
    Powershell script that generates the C# code for your sdk usin the config file provided

.DESCRIPTION
    This script:
    - fetches the config file from user/branch provided
    - Generates code based off the config file provided
    - into the directory path provided

.PARAMETER ResourceProvider
    The Resource provider for whom to generate the code; also helps determine path where config file is located in repo

.PARAMETER Version
    The AutoRest version to use to generate the code, "latest" is recommended

.PARAMETER LocalConfigFilePath
    The local Rest Spec config file for which to generate the sdk

.PARAMETER SdkRootDirectory
    The root path in csharp-sdks-folder in config file where to generate the code

.PARAMETER SdkGenerationDirectory
    The path that where the code will be generate (overrides output-folder specified in config file)
    
.PARAMETER Namespace
    The C# namespace for sdk to generate

.PARAMETER ConfigFileTag
    The tag in config file for which to generate the sdk. Code generation fails if incorrect tags are provided

#>
function Start-AutoRestCodeGenerationWithLocalConfig {
    [CmdletBinding(DefaultParameterSetName="sdkRootDir")]
    Param(
        [Parameter(Mandatory = $true)]
        [string] $ResourceProvider,

        [Parameter(Mandatory = $true, HelpMessage="The path to the config file")]
        [string] $LocalConfigFilePath,

        [Parameter(Mandatory = $false)]
        [string] $AutoRestVersion = "latest",

        [Parameter(ParameterSetName="sdkRootDir", Mandatory = $false, HelpMessage="The root directory equivalent to csharp-sdks-folder in config file. Eg.: Code will be generated in SdkRootDirectory/Compute/Management.Compute/Generated")]
        [string] $SdkRootDirectory,

        [Parameter(ParameterSetName="sdkOutputDir", Mandatory=$false, HelpMessage="The final directory where generrated code will go. Eg.: Code will be generated in sdkGenerationDirectory/Generated/")]
        [string] $SdkGenerationDirectory,

        [Parameter(ParameterSetName="sdkOutputDirLegacy", Mandatory=$false, HelpMessage="Legacy parameter same as SdkRootDirectory")]
        [string] $SdkDirectory,

        [Parameter(Mandatory = $false)]
        [string] $Namespace,

        [Parameter(Mandatory = $false)]
        [ValidateSet("singleapi", "multiapi")]
        [string] $SdkGenerationType = "singleapi"
    )

    if (-not [string]::IsNullOrWhiteSpace($SdkDirectory)) {
        $SdkRootDirectory = $SdkDirectory
    }
    if(-not [string]::IsNullOrWhiteSpace($SdkRootDirectory)) {
        Start-CodeGeneration -ResourceProvider $ResourceProvider -LocalConfigFilePath $LocalConfigFilePath -SdkRootDirectory $SdkRootDirectory -Namespace $Namespace -ConfigFileTag $ConfigFileTag -AutoRestVersion $AutoRestVersion
    }
    elseif(-not [string]::IsNullOrWhiteSpace($SdkGenerationDirectory)) {
        Start-CodeGeneration -ResourceProvider $ResourceProvider -LocalConfigFilePath $LocalConfigFilePath -SdkGenerationDirectory $SdkGenerationDirectory -Namespace $Namespace -ConfigFileTag $ConfigFileTag -AutoRestVersion $AutoRestVersion
    }
    else
    {
        Write-Error "Please provide an output directory for the generated code"
    }
}

function Start-CodeGeneration {
    Param(
        [string] $ResourceProvider,
        [string] $SpecsRepoFork = "Azure",
        [string] $SpecsRepoName = "azure-rest-api-specs",
        [string] $SpecsRepoBranch = "master",
        [string] $AutoRestVersion = "latest",
        [string] $SdkRootDirectory,
        [string] $SdkDirectory,
        [string] $SdkGenerationDirectory,
        [string] $Namespace,
        [string] $ConfigFileTag,
        [string] $LocalConfigFilePath,
        [string] $SdkGenerationType
    )
    $localSdkRepoDirectory = Get-SdkRepoRootDirectory($(Get-InvokingScriptPath))
    
    if(-not [string]::IsNullOrWhiteSpace($LocalConfigFilePath)) {
        
        if($localSdkRepoDirectory -ne $null)
        {
            Remove-Item "$localSdkRepoDirectory\_metadata\$($ResourceProvider.Replace("/","_")).txt" -ErrorAction SilentlyContinue
        }
        
        $logFile = [System.IO.Path]::GetTempFileName()+".txt";
        Write-Warning "!!!!!WARNING!!!!!!" 
        Write-Warning "======================================================================================================================================" 
        Write-Warning "Generating code using a local REST spec at location $LocalConfigFilePath. PRs with code generated using this spec will not be accepted" 
        Write-Warning "======================================================================================================================================"
        
        $configFile = $LocalConfigFilePath
    }
    else
    {
        if ($SpecsRepoName.EndsWith("-pr")) {
            Write-Error "If you are generating code from private spec repo: $(SpecsRepoName) Please use AutoRest CLI. Code generation skipped."
            return
        }

        if([string]::IsNullOrEmpty($localSdkRepoDirectory)) {
            $logFile = [System.IO.Path]::GetTempFileName()+".txt";
        }
        else {
            $localSdkRepoDirectory = Resolve-Path -Path "$localSdkRepoDirectory\..\SDKs"
            if(!(Test-Path -Path "$localSdkRepoDirectory\_metadata"))
            {
                New-Item -ItemType Directory -Path "$localSdkRepoDirectory\_metadata"
            }
            $logFile = "$localSdkRepoDirectory\_metadata\$($ResourceProvider.Replace("/","_").Replace('\','_')).txt"    
        }
        
        if(!$(Test-Path -Path $logFile))
        {
            Write-Warning "Creating new file log file: $logFile"
            New-Item -Path $logFile -ItemType File
        }
        
        $configFile="https://github.com/$SpecsRepoFork/$SpecsRepoName/blob/$SpecsRepoBranch/specification/$ResourceProvider/readme.md"
    }

    if(-not [string]::IsNullOrWhiteSpace($SdkDirectory)) {
        $SdkRootDirectory = $SdkDirectory
    }

    try {
        Install-AutoRest $AutoRestVersion
        Write-InfoLog "Commencing code generation"  
        
        if(-not [string]::IsNullOrWhiteSpace($SdkRootDirectory)) {
            Invoke-AutoRestCodeGenerationCommand -ConfigFile $configFile -SdkRootDirectory $SdkRootDirectory -AutoRestVersion $AutoRestVersion -Namespace $Namespace -ConfigFileTag $ConfigFileTag -SdkGenerationType $SdkGenerationType
        }
        elseif(-not [string]::IsNullOrWhiteSpace($SdkGenerationDirectory)) {
            Invoke-AutoRestCodeGenerationCommand -ConfigFile $configFile -SdkGenerationDirectory $SdkGenerationDirectory -AutoRestVersion $AutoRestVersion -Namespace $Namespace -ConfigFileTag $ConfigFileTag -SdkGenerationType $SdkGenerationType
        }
        else {
            Write-ErrorLog "Could not find an output directory to generate code, aborting."
            return
        }
    }
    catch {
        Write-ErrorLog $_.ToString() 
        Write-ErrorLog $_.ToString() 
    }
    finally {
        Get-OutputStream | Out-File -FilePath $logFile -Encoding utf8 | Out-Null
        Get-ErrorStream | Out-File -FilePath $logFile -Append -Encoding utf8 | Out-Null
        Clear-OutputStreams
        Write-Host "Log file can be found at location $logFile"
    }
}


export-modulemember -function Start-AutoRestCodeGeneration
export-modulemember -function Start-AutoRestCodeGenerationWithLocalConfig
export-modulemember -function Get-AutoRestHelp
export-modulemember -function Install-AutoRest
