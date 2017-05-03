﻿data LocalizedData
{
    # culture="en-US"
    ConvertFrom-StringData @'
    PathNotFoundError=The path '{0}' either does not exist or is not a valid file system path.
    ExpandArchiveInValidDestinationPath=The path '{0}' is not a valid file system directory path.
    InvalidZipFileExtensionError={0} is not a supported archive file format. {1} is the only supported archive file format.
    ArchiveFileIsReadOnly=The attributes of the archive file {0} is set to 'ReadOnly' hence it cannot be updated. If you intend to update the existing archive file, remove the 'ReadOnly' attribute on the archive file else use -Force parameter to override and create a new archive file.
    ZipFileExistError=The archive file {0} already exists. Use the -Update parameter to update the existing archive file or use the -Force parameter to overwrite the existing archive file.
    DuplicatePathFoundError=The input to {0} parameter contains a duplicate path '{1}'. Provide a unique set of paths as input to {2} parameter.
    ArchiveFileIsEmpty=The archive file {0} is empty.
    CompressProgressBarText=The archive file '{0}' creation is in progress...
    ExpandProgressBarText=The archive file '{0}' expansion is in progress...
    AppendArchiveFileExtensionMessage=The archive file path '{0}' supplied to the DestinationPath parameter does not include .zip extension. Hence .zip is appended to the supplied DestinationPath path and the archive file would be created at '{1}'.
    AddItemtoArchiveFile=Adding '{0}'.
    CreateFileAtExpandedPath=Created '{0}'.
    InvalidArchiveFilePathError=The archive file path '{0}' specified as input to the {1} parameter is resolving to multiple file system paths. Provide a unique path to the {2} parameter where the archive file has to be created.
    InvalidExpandedDirPathError=The directory path '{0}' specified as input to the DestinationPath parameter is resolving to multiple file system paths. Provide a unique path to the Destination parameter where the archive file contents have to be expanded.
    FileExistsError=Failed to create file '{0}' while expanding the archive file '{1}' contents as the file '{2}' already exists. Use the -Force parameter if you want to overwrite the existing directory '{3}' contents when expanding the archive file.
    DeleteArchiveFile=The partially created archive file '{0}' is deleted as it is not usable.
    InvalidDestinationPath=The destination path '{0}' does not contain a valid archive file name.
    PreparingToCompressVerboseMessage=Preparing to compress...
    PreparingToExpandVerboseMessage=Preparing to expand...
    ItemDoesNotAppearToBeAValidZipArchive=File '{0}' does not appear to be a valid zip archive.
'@
}

Import-LocalizedData  LocalizedData -filename ArchiveResources

$zipFileExtension = ".zip"

<############################################################################################
# The Compress-Archive cmdlet can be used to zip/compress one or more files/directories.
############################################################################################>
function Compress-Archive
{
    [CmdletBinding(
    DefaultParameterSetName="Path",
    SupportsShouldProcess=$true,
    HelpUri="https://go.microsoft.com/fwlink/?LinkID=393252")]
    [OutputType([System.IO.File])]
    param
    (
        [parameter (mandatory=$true, Position=0, ParameterSetName="Path", ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [parameter (mandatory=$true, Position=0, ParameterSetName="PathWithForce", ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [parameter (mandatory=$true, Position=0, ParameterSetName="PathWithUpdate", ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path,

        [parameter (mandatory=$true, ParameterSetName="LiteralPath", ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$true)]
        [parameter (mandatory=$true, ParameterSetName="LiteralPathWithForce", ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$true)]
        [parameter (mandatory=$true, ParameterSetName="LiteralPathWithUpdate", ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias("PSPath")]
        [string[]] $LiteralPath,

        [parameter (mandatory=$true,
        Position=1,
        ValueFromPipeline=$false,
        ValueFromPipelineByPropertyName=$false)]
        [ValidateNotNullOrEmpty()]
        [string] $DestinationPath,

        [parameter (
        mandatory=$false,
        ValueFromPipeline=$false,
        ValueFromPipelineByPropertyName=$false)]
        [ValidateSet("Optimal","NoCompression","Fastest")]
        [string]
        $CompressionLevel = "Optimal",

        [parameter(mandatory=$true, ParameterSetName="PathWithUpdate", ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
        [parameter(mandatory=$true, ParameterSetName="LiteralPathWithUpdate", ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
        [switch]
        $Update = $false,

        [parameter(mandatory=$true, ParameterSetName="PathWithForce", ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
        [parameter(mandatory=$true, ParameterSetName="LiteralPathWithForce", ValueFromPipeline=$false, ValueFromPipelineByPropertyName=$false)]
        [switch]
        $Force = $false,

        [switch]
        $PassThru = $false
    )

    BEGIN
    {
        # Ensure the destination path is in a non-PS-specific format
        $DestinationPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($DestinationPath)

        $inputPaths = @()
        $destinationParentDir = [system.IO.Path]::GetDirectoryName($DestinationPath)
        if($null -eq $destinationParentDir)
        {
            $errorMessage = ($LocalizedData.InvalidDestinationPath -f $DestinationPath)
            ThrowTerminatingErrorHelper "InvalidArchiveFilePath" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $DestinationPath
        }

        if($destinationParentDir -eq [string]::Empty)
        {
            $destinationParentDir = '.'
        }

        $archiveFileName = [system.IO.Path]::GetFileName($DestinationPath)
        $destinationParentDir = GetResolvedPathHelper $destinationParentDir $false $PSCmdlet

        if($destinationParentDir.Count -gt 1)
        {
            $errorMessage = ($LocalizedData.InvalidArchiveFilePathError -f $DestinationPath, "DestinationPath", "DestinationPath")
            ThrowTerminatingErrorHelper "InvalidArchiveFilePath" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $DestinationPath
        }

        IsValidFileSystemPath $destinationParentDir | Out-Null
        $DestinationPath = Join-Path -Path $destinationParentDir -ChildPath $archiveFileName

        # GetExtension API does not validate for the actual existence of the path.
        $extension = [system.IO.Path]::GetExtension($DestinationPath)

        # If user does not specify an extension, we append the .zip extension automatically.
        If($extension -eq [string]::Empty)
        {
            $DestinationPathWithOutExtension = $DestinationPath
            $DestinationPath = $DestinationPathWithOutExtension + $zipFileExtension
            $appendArchiveFileExtensionMessage = ($LocalizedData.AppendArchiveFileExtensionMessage -f $DestinationPathWithOutExtension, $DestinationPath)
            Write-Verbose $appendArchiveFileExtensionMessage
        }

        $archiveFileExist = Test-Path -LiteralPath $DestinationPath -PathType Leaf

        if($archiveFileExist -and ($Update -eq $false -and $Force -eq $false))
        {
            $errorMessage = ($LocalizedData.ZipFileExistError -f $DestinationPath)
            ThrowTerminatingErrorHelper "ArchiveFileExists" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $DestinationPath
        }

        # If archive file already exists and if -Update is specified, then we check to see
        # if we have write access permission to update the existing archive file.
        if($archiveFileExist -and $Update -eq $true)
        {
            $item = Get-Item -Path $DestinationPath
            if($item.Attributes.ToString().Contains("ReadOnly"))
            {
                $errorMessage = ($LocalizedData.ArchiveFileIsReadOnly -f $DestinationPath)
                ThrowTerminatingErrorHelper "ArchiveFileIsReadOnly" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidOperation) $DestinationPath
            }
        }

        $isWhatIf = $psboundparameters.ContainsKey("WhatIf")
        if(!$isWhatIf)
        {
            $preparingToCompressVerboseMessage = ($LocalizedData.PreparingToCompressVerboseMessage)
            Write-Verbose $preparingToCompressVerboseMessage

            $progressBarStatus = ($LocalizedData.CompressProgressBarText -f $DestinationPath)
            ProgressBarHelper "Compress-Archive" $progressBarStatus 0 100 100 1
        }
    }
    PROCESS
    {
        if($PsCmdlet.ParameterSetName -eq "Path" -or
        $PsCmdlet.ParameterSetName -eq "PathWithForce" -or
        $PsCmdlet.ParameterSetName -eq "PathWithUpdate")
        {
            $inputPaths += $Path
        }

        if($PsCmdlet.ParameterSetName -eq "LiteralPath" -or
        $PsCmdlet.ParameterSetName -eq "LiteralPathWithForce" -or
        $PsCmdlet.ParameterSetName -eq "LiteralPathWithUpdate")
        {
            $inputPaths += $LiteralPath
        }
    }
    END
    {
        # If archive file already exists and if -Force is specified, we delete the
        # existing archive file and create a brand new one.
        if(($PsCmdlet.ParameterSetName -eq "PathWithForce" -or
        $PsCmdlet.ParameterSetName -eq "LiteralPathWithForce") -and $archiveFileExist)
        {
            Remove-Item -Path $DestinationPath -Force -ErrorAction Stop
        }

        # Validate Source Path depending on parameter set being used.
        # The specified source path contains one or more files or directories that needs
        # to be compressed.
        $isLiteralPathUsed = $false
        if($PsCmdlet.ParameterSetName -eq "LiteralPath" -or
        $PsCmdlet.ParameterSetName -eq "LiteralPathWithForce" -or
        $PsCmdlet.ParameterSetName -eq "LiteralPathWithUpdate")
        {
            $isLiteralPathUsed = $true
        }

        ValidateDuplicateFileSystemPath $PsCmdlet.ParameterSetName $inputPaths
        $resolvedPaths = GetResolvedPathHelper $inputPaths $isLiteralPathUsed $PSCmdlet
        IsValidFileSystemPath $resolvedPaths | Out-Null

        $sourcePath = $resolvedPaths;

        # CSVHelper: This is a helper function used to append comma after each path specified by
        # the $sourcePath array. The comma separated paths are displayed in the -WhatIf message.
        $sourcePathInCsvFormat = CSVHelper $sourcePath
        if($pscmdlet.ShouldProcess($sourcePathInCsvFormat))
        {
            try
            {
                # StopProcessing is not available in Script cmdlets. However the pipeline execution
                # is terminated when ever 'CTRL + C' is entered by user to terminate the cmdlet execution.
                # The finally block is executed whenever pipeline is terminated.
                # $isArchiveFileProcessingComplete variable is used to track if 'CTRL + C' is entered by the
                # user.
                $isArchiveFileProcessingComplete = $false

                $numberOfItemsArchived = CompressArchiveHelper $sourcePath $DestinationPath $CompressionLevel $Update

                $isArchiveFileProcessingComplete = $true
            }
            finally
            {
                # The $isArchiveFileProcessingComplete would be set to $false if user has typed 'CTRL + C' to
                # terminate the cmdlet execution or if an unhandled exception is thrown.
                # $numberOfItemsArchived contains the count of number of files or directories add to the archive file.
                # If the newly created archive file is empty then we delete it as it's not usable.
                if(($isArchiveFileProcessingComplete -eq $false) -or
                ($numberOfItemsArchived -eq 0))
                {
                    $DeleteArchiveFileMessage = ($LocalizedData.DeleteArchiveFile -f $DestinationPath)
                    Write-Verbose $DeleteArchiveFileMessage

                    # delete the partial archive file created.
                    if (Test-Path $DestinationPath) {
                        Remove-Item -LiteralPath $DestinationPath -Force -Recurse -ErrorAction SilentlyContinue
                    }
                }
                elseif ($PassThru)
                {
                    Get-Item -LiteralPath $DestinationPath
                }
            }
        }
    }
}

<############################################################################################
# The Expand-Archive cmdlet can be used to expand/extract an zip file.
############################################################################################>
function Expand-Archive
{
    [CmdletBinding(
    DefaultParameterSetName="Path",
    SupportsShouldProcess=$true,
    HelpUri="https://go.microsoft.com/fwlink/?LinkID=393253")]
    [OutputType([System.IO.FileSystemInfo])]
    param
    (
        [parameter (
        mandatory=$true,
        Position=0,
        ParameterSetName="Path",
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [parameter (
        mandatory=$true,
        ParameterSetName="LiteralPath",
        ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias("PSPath")]
        [string] $LiteralPath,

        [parameter (mandatory=$false,
        Position=1,
        ValueFromPipeline=$false,
        ValueFromPipelineByPropertyName=$false)]
        [ValidateNotNullOrEmpty()]
        [string] $DestinationPath,

        [parameter (mandatory=$false,
        ValueFromPipeline=$false,
        ValueFromPipelineByPropertyName=$false)]
        [switch] $Force,

        [switch]
        $PassThru = $false
    )

    BEGIN
    {
       $isVerbose = $psboundparameters.ContainsKey("Verbose")
       $isConfirm = $psboundparameters.ContainsKey("Confirm")

        $isDestinationPathProvided = $true
        if($DestinationPath -eq [string]::Empty)
        {
            $resolvedDestinationPath = $pwd
            $isDestinationPathProvided = $false
        }
        else
        {
            $destinationPathExists = Test-Path -Path $DestinationPath -PathType Container
            if($destinationPathExists)
            {
                $resolvedDestinationPath = GetResolvedPathHelper $DestinationPath $false $PSCmdlet
                if($resolvedDestinationPath.Count -gt 1)
                {
                    $errorMessage = ($LocalizedData.InvalidExpandedDirPathError -f $DestinationPath)
                    ThrowTerminatingErrorHelper "InvalidDestinationPath" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $DestinationPath
                }

                # At this point we are sure that the provided path resolves to a valid single path.
                # Calling Resolve-Path again to get the underlying provider name.
                $suppliedDestinationPath = Resolve-Path -Path $DestinationPath
                if($suppliedDestinationPath.Provider.Name-ne "FileSystem")
                {
                    $errorMessage = ($LocalizedData.ExpandArchiveInValidDestinationPath -f $DestinationPath)
                    ThrowTerminatingErrorHelper "InvalidDirectoryPath" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $DestinationPath
                }
            }
            else
            {
                $createdItem = New-Item -Path $DestinationPath -ItemType Directory -Confirm:$isConfirm -Verbose:$isVerbose -ErrorAction Stop
                if($createdItem -ne $null -and $createdItem.PSProvider.Name -ne "FileSystem")
                {
                    Remove-Item "$DestinationPath" -Force -Recurse -ErrorAction SilentlyContinue
                    $errorMessage = ($LocalizedData.ExpandArchiveInValidDestinationPath -f $DestinationPath)
                    ThrowTerminatingErrorHelper "InvalidDirectoryPath" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $DestinationPath
                }

                $resolvedDestinationPath = GetResolvedPathHelper $DestinationPath $true $PSCmdlet
            }
        }

        $isWhatIf = $psboundparameters.ContainsKey("WhatIf")
        if(!$isWhatIf)
        {
            $preparingToExpandVerboseMessage = ($LocalizedData.PreparingToExpandVerboseMessage)
            Write-Verbose $preparingToExpandVerboseMessage

            $progressBarStatus = ($LocalizedData.ExpandProgressBarText -f $DestinationPath)
            ProgressBarHelper "Expand-Archive" $progressBarStatus 0 100 100 1
        }
    }
    PROCESS
    {
        switch($PsCmdlet.ParameterSetName)
        {
            "Path"
            {
                $resolvedSourcePaths = GetResolvedPathHelper $Path $false $PSCmdlet

                if($resolvedSourcePaths.Count -gt 1)
                {
                    $errorMessage = ($LocalizedData.InvalidArchiveFilePathError -f $Path, $PsCmdlet.ParameterSetName, $PsCmdlet.ParameterSetName)
                    ThrowTerminatingErrorHelper "InvalidArchiveFilePath" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $Path
                }
            }
            "LiteralPath"
            {
                $resolvedSourcePaths = GetResolvedPathHelper $LiteralPath $true $PSCmdlet

                if($resolvedSourcePaths.Count -gt 1)
                {
                    $errorMessage = ($LocalizedData.InvalidArchiveFilePathError -f $LiteralPath, $PsCmdlet.ParameterSetName, $PsCmdlet.ParameterSetName)
                    ThrowTerminatingErrorHelper "InvalidArchiveFilePath" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $LiteralPath
                }
            }
        }

        ValidateArchivePathHelper $resolvedSourcePaths

        if($pscmdlet.ShouldProcess($resolvedSourcePaths))
        {
            $expandedItems = @()

            try
            {
                # StopProcessing is not available in Script cmdlets. However the pipeline execution
                # is terminated when ever 'CTRL + C' is entered by user to terminate the cmdlet execution.
                # The finally block is executed whenever pipeline is terminated.
                # $isArchiveFileProcessingComplete variable is used to track if 'CTRL + C' is entered by the
                # user.
                $isArchiveFileProcessingComplete = $false

                # The User has not provided a destination path, hence we use '$pwd\ArchiveFileName' as the directory where the
                # archive file contents would be expanded. If the path '$pwd\ArchiveFileName' already exists then we use the
                # Windows default mechanism of appending a counter value at the end of the directory name where the contents
                # would be expanded.
                if(!$isDestinationPathProvided)
                {
                    $archiveFile = New-Object System.IO.FileInfo $resolvedSourcePaths
                    $resolvedDestinationPath = Join-Path -Path $resolvedDestinationPath -ChildPath $archiveFile.BaseName
                    $destinationPathExists = Test-Path -LiteralPath $resolvedDestinationPath -PathType Container

                    if(!$destinationPathExists)
                    {
                        New-Item -Path $resolvedDestinationPath -ItemType Directory -Confirm:$isConfirm -Verbose:$isVerbose -ErrorAction Stop | Out-Null
                    }
                }

                ExpandArchiveHelper $resolvedSourcePaths $resolvedDestinationPath ([ref]$expandedItems) $Force $isVerbose $isConfirm

                $isArchiveFileProcessingComplete = $true
            }
            finally
            {
                # The $isArchiveFileProcessingComplete would be set to $false if user has typed 'CTRL + C' to
                # terminate the cmdlet execution or if an unhandled exception is thrown.
                if($isArchiveFileProcessingComplete -eq $false)
                {
                    if($expandedItems.Count -gt 0)
                    {
                        # delete the expanded file/directory as the archive
                        # file was not completely expanded.
                        $expandedItems | % { Remove-Item "$_" -Force -Recurse }
                    }
                }
                elseif ($PassThru -and $expandedItems.Count -gt 0)
                {
                    # Return the expanded items, being careful to remove trailing directory separators from
                    # any folder paths for consistency
                    $trailingDirSeparators = '\' + [System.IO.Path]::DirectorySeparatorChar + '+$'
                    Get-Item -LiteralPath ($expandedItems -replace $trailingDirSeparators)
                }
            }
        }
    }
}

<############################################################################################
# GetResolvedPathHelper: This is a helper function used to resolve the user specified Path.
# The path can either be absolute or relative path.
############################################################################################>
function GetResolvedPathHelper
{
    param
    (
        [string[]] $path,
        [boolean] $isLiteralPath,
        [System.Management.Automation.PSCmdlet]
        $callerPSCmdlet
    )

    $resolvedPaths =@()

    # null and empty check are are already done on Path parameter at the cmdlet layer.
    foreach($currentPath in $path)
    {
        try
        {
            if($isLiteralPath)
            {
                $currentResolvedPaths = Resolve-Path -LiteralPath $currentPath -ErrorAction Stop
            }
            else
            {
                $currentResolvedPaths = Resolve-Path -Path $currentPath -ErrorAction Stop
            }
        }
        catch
        {
            $errorMessage = ($LocalizedData.PathNotFoundError -f $currentPath)
            $exception = New-Object System.InvalidOperationException $errorMessage, $_.Exception
            $errorRecord = CreateErrorRecordHelper "ArchiveCmdletPathNotFound" $null ([System.Management.Automation.ErrorCategory]::InvalidArgument) $exception $currentPath
            $callerPSCmdlet.ThrowTerminatingError($errorRecord)
        }

        foreach($currentResolvedPath in $currentResolvedPaths)
        {
            $resolvedPaths += $currentResolvedPath.ProviderPath
        }
    }

    $resolvedPaths
}

function Add-CompressionAssemblies {
    Add-Type -AssemblyName System.IO.Compression
    if ($psedition -eq "Core")
    {
        Add-Type -AssemblyName System.IO.Compression.ZipFile
    }
    else
    {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
    }
}

function IsValidFileSystemPath
{
    param
    (
        [string[]] $path
    )

    $result = $true;

    # null and empty check are are already done on Path parameter at the cmdlet layer.
    foreach($currentPath in $path)
    {
        if(!([System.IO.File]::Exists($currentPath) -or [System.IO.Directory]::Exists($currentPath)))
        {
            $errorMessage = ($LocalizedData.PathNotFoundError -f $currentPath)
            ThrowTerminatingErrorHelper "PathNotFound" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $currentPath
        }
    }

    return $result;
}


function ValidateDuplicateFileSystemPath
{
    param
    (
        [string] $inputParameter,
        [string[]] $path
    )

    $uniqueInputPaths = @()

    # null and empty check are are already done on Path parameter at the cmdlet layer.
    foreach($currentPath in $path)
    {
        $currentInputPath = $currentPath.ToUpper()
        if($uniqueInputPaths.Contains($currentInputPath))
        {
            $errorMessage = ($LocalizedData.DuplicatePathFoundError -f $inputParameter, $currentPath, $inputParameter)
            ThrowTerminatingErrorHelper "DuplicatePathFound" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $currentPath
        }
        else
        {
            $uniqueInputPaths += $currentInputPath
        }
    }
}

function CompressionLevelMapper
{
    param
    (
        [string] $compressionLevel
    )

    $compressionLevelFormat = [System.IO.Compression.CompressionLevel]::Optimal

    # CompressionLevel format is already validated at the cmdlet layer.
    switch($compressionLevel.ToString())
    {
        "Fastest"
        {
            $compressionLevelFormat = [System.IO.Compression.CompressionLevel]::Fastest
        }
        "NoCompression"
        {
            $compressionLevelFormat = [System.IO.Compression.CompressionLevel]::NoCompression
        }
    }

    return $compressionLevelFormat
}

function CompressArchiveHelper
{
    param
    (
        [string[]] $sourcePath,
        [string]   $destinationPath,
        [string]   $compressionLevel,
        [bool]     $isUpdateMode
    )

    $numberOfItemsArchived = 0
    $sourceFilePaths = @()
    $sourceDirPaths = @()

    foreach($currentPath in $sourcePath)
    {
        $result = Test-Path -LiteralPath $currentPath -Type Leaf
        if($result -eq $true)
        {
            $sourceFilePaths += $currentPath
        }
        else
        {
            $sourceDirPaths += $currentPath
        }
    }

    # The Source Path contains one or more directory (this directory can have files under it) and no files to be compressed.
    if($sourceFilePaths.Count -eq 0 -and $sourceDirPaths.Count -gt 0)
    {
        $currentSegmentWeight = 100/[double]$sourceDirPaths.Count
        $previousSegmentWeight = 0
        foreach($currentSourceDirPath in $sourceDirPaths)
        {
            $count = CompressSingleDirHelper $currentSourceDirPath $destinationPath $compressionLevel $true $isUpdateMode $previousSegmentWeight $currentSegmentWeight
            $numberOfItemsArchived += $count
            $previousSegmentWeight += $currentSegmentWeight
        }
    }

    # The Source Path contains only files to be compressed.
    elseIf($sourceFilePaths.Count -gt 0 -and $sourceDirPaths.Count -eq 0)
    {
        # $previousSegmentWeight is equal to 0 as there are no prior segments.
        # $currentSegmentWeight is set to 100 as all files have equal weightage.
        $previousSegmentWeight = 0
        $currentSegmentWeight = 100

        $numberOfItemsArchived = CompressFilesHelper $sourceFilePaths $destinationPath $compressionLevel $isUpdateMode $previousSegmentWeight $currentSegmentWeight
    }
    # The Source Path contains one or more files and one or more directories (this directory can have files under it) to be compressed.
    elseif($sourceFilePaths.Count -gt 0 -and $sourceDirPaths.Count -gt 0)
    {
        # each directory is considered as an individual segments & all the individual files are clubed in to a separate segment.
        $currentSegmentWeight = 100/[double]($sourceDirPaths.Count +1)
        $previousSegmentWeight = 0

        foreach($currentSourceDirPath in $sourceDirPaths)
        {
            $count = CompressSingleDirHelper $currentSourceDirPath $destinationPath $compressionLevel $true $isUpdateMode $previousSegmentWeight $currentSegmentWeight
            $numberOfItemsArchived += $count
            $previousSegmentWeight += $currentSegmentWeight
        }

        $count = CompressFilesHelper $sourceFilePaths $destinationPath $compressionLevel $isUpdateMode $previousSegmentWeight $currentSegmentWeight
        $numberOfItemsArchived += $count
    }

    return $numberOfItemsArchived
}

function CompressFilesHelper
{
    param
    (
        [string[]] $sourceFilePaths,
        [string]   $destinationPath,
        [string]   $compressionLevel,
        [bool]     $isUpdateMode,
        [double]   $previousSegmentWeight,
        [double]   $currentSegmentWeight
    )

    $numberOfItemsArchived = ZipArchiveHelper $sourceFilePaths $destinationPath $compressionLevel $isUpdateMode $null $previousSegmentWeight $currentSegmentWeight

    return $numberOfItemsArchived
}

function CompressSingleDirHelper
{
    param
    (
        [string] $sourceDirPath,
        [string] $destinationPath,
        [string] $compressionLevel,
        [bool]   $useParentDirAsRoot,
        [bool]   $isUpdateMode,
        [double] $previousSegmentWeight,
        [double] $currentSegmentWeight
    )

    [System.Collections.Generic.List[System.String]]$subDirFiles = @()

    if($useParentDirAsRoot)
    {
        $sourceDirInfo = New-Object -TypeName System.IO.DirectoryInfo -ArgumentList $sourceDirPath
        $sourceDirFullName = $sourceDirInfo.Parent.FullName

        # If the directory is present at the drive level the DirectoryInfo.Parent include directory separator. example: C:\
        # On the other hand if the directory exists at a deper level then DirectoryInfo.Parent
        # has just the path (without an ending directory separator). example C:\source
        if($sourceDirFullName.Length -eq 3)
        {
            $modifiedSourceDirFullName = $sourceDirFullName
        }
        else
        {
            $modifiedSourceDirFullName = $sourceDirFullName + [System.IO.Path]::DirectorySeparatorChar
        }
    }
    else
    {
        $sourceDirFullName = $sourceDirPath
        $modifiedSourceDirFullName = $sourceDirFullName + [System.IO.Path]::DirectorySeparatorChar
    }

    $dirContents = Get-ChildItem -LiteralPath $sourceDirPath -Recurse
    foreach($currentContent in $dirContents)
    {
        $isContainer = $currentContent -is [System.IO.DirectoryInfo]
        if(!$isContainer)
        {
            $subDirFiles.Add($currentContent.FullName)
        }
        else
        {
            # The currentContent points to a directory.
            # We need to check if the directory is an empty directory, if so such a
            # directory has to be explicitly added to the archive file.
            # if there are no files in the directory the GetFiles() API returns an empty array.
            $files = $currentContent.GetFiles()
            if($files.Count -eq 0)
            {
                $subDirFiles.Add($currentContent.FullName + [System.IO.Path]::DirectorySeparatorChar)
            }
        }
    }

    $numberOfItemsArchived = ZipArchiveHelper $subDirFiles.ToArray() $destinationPath $compressionLevel $isUpdateMode $modifiedSourceDirFullName $previousSegmentWeight $currentSegmentWeight

    return $numberOfItemsArchived
}

function ZipArchiveHelper
{
    param
    (
        [System.Collections.Generic.List[System.String]] $sourcePaths,
        [string]   $destinationPath,
        [string]   $compressionLevel,
        [bool]     $isUpdateMode,
        [string]   $modifiedSourceDirFullName,
        [double]   $previousSegmentWeight,
        [double]   $currentSegmentWeight
    )

    $numberOfItemsArchived = 0
    $fileMode = [System.IO.FileMode]::Create
    $result = Test-Path -LiteralPath $DestinationPath -Type Leaf
    if($result -eq $true)
    {
        $fileMode = [System.IO.FileMode]::Open
    }

    Add-CompressionAssemblies

    try
    {
        # At this point we are sure that the archive file has write access.
        $archiveFileStreamArgs = @($destinationPath, $fileMode)
        $archiveFileStream = New-Object -TypeName System.IO.FileStream -ArgumentList $archiveFileStreamArgs

        $zipArchiveArgs = @($archiveFileStream, [System.IO.Compression.ZipArchiveMode]::Update, $false)
        $zipArchive = New-Object -TypeName System.IO.Compression.ZipArchive -ArgumentList $zipArchiveArgs

        $currentEntryCount = 0
        $progressBarStatus = ($LocalizedData.CompressProgressBarText -f $destinationPath)
        $bufferSize = 4kb
        $buffer = New-Object Byte[] $bufferSize

        foreach($currentFilePath in $sourcePaths)
        {
            if($modifiedSourceDirFullName -ne $null -and $modifiedSourceDirFullName.Length -gt 0)
            {
                $index = $currentFilePath.IndexOf($modifiedSourceDirFullName, [System.StringComparison]::OrdinalIgnoreCase)
                $currentFilePathSubString = $currentFilePath.Substring($index, $modifiedSourceDirFullName.Length)
                $relativeFilePath = $currentFilePath.Replace($currentFilePathSubString, "").Trim()
            }
            else
            {
                $relativeFilePath = [System.IO.Path]::GetFileName($currentFilePath)
            }

            # Update mode is selected.
            # Check to see if archive file already contains one or more zip files in it.
            if($isUpdateMode -eq $true -and $zipArchive.Entries.Count -gt 0)
            {
                $entryToBeUpdated = $null

                # Check if the file already exists in the archive file.
                # If so replace it with new file from the input source.
                # If the file does not exist in the archive file then default to
                # create mode and create the entry in the archive file.

                foreach($currentArchiveEntry in $zipArchive.Entries)
                {
                    if($currentArchiveEntry.FullName -eq $relativeFilePath)
                    {
                        $entryToBeUpdated = $currentArchiveEntry
                        break
                    }
                }

                if($entryToBeUpdated -ne $null)
                {
                    $addItemtoArchiveFileMessage = ($LocalizedData.AddItemtoArchiveFile -f $currentFilePath)
                    $entryToBeUpdated.Delete()
                }
            }

            $compression = CompressionLevelMapper $compressionLevel

            # If a directory needs to be added to an archive file,
            # by convention the .Net API's expect the path of the directory
            # to end with directory separator to detect the path as an directory.
            if(!$relativeFilePath.EndsWith([System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase))
            {
                try
                {
                    try
                    {
                        $currentFileStream = [System.IO.File]::Open($currentFilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
                    }
                    catch
                    {
                        # Failed to access the file. Write a non terminating error to the pipeline
                        # and move on with the remaining files.
                        $exception = $_.Exception
                        if($null -ne $_.Exception -and
                        $null -ne $_.Exception.InnerException)
                        {
                            $exception = $_.Exception.InnerException
                        }
                        $errorRecord = CreateErrorRecordHelper "CompressArchiveUnauthorizedAccessError" $null ([System.Management.Automation.ErrorCategory]::PermissionDenied) $exception $currentFilePath
                        Write-Error -ErrorRecord $errorRecord
                    }

                    if($null -ne $currentFileStream)
                    {
                        $srcStream = New-Object System.IO.BinaryReader $currentFileStream

                        $currentArchiveEntry = $zipArchive.CreateEntry($relativeFilePath, $compression)

                        # Updating  the File Creation time so that the same timestamp would be retained after expanding the compressed file.
                        # At this point we are sure that Get-ChildItem would succeed.
                        $currentArchiveEntry.LastWriteTime = (Get-Item -LiteralPath $currentFilePath).LastWriteTime

                        $destStream = New-Object System.IO.BinaryWriter $currentArchiveEntry.Open()

                        while($numberOfBytesRead = $srcStream.Read($buffer, 0, $bufferSize))
                        {
                            $destStream.Write($buffer, 0, $numberOfBytesRead)
                            $destStream.Flush()
                        }

                        $numberOfItemsArchived += 1
                        $addItemtoArchiveFileMessage = ($LocalizedData.AddItemtoArchiveFile -f $currentFilePath)
                    }
                }
                finally
                {
                    If($null -ne $currentFileStream)
                    {
                        $currentFileStream.Dispose()
                    }
                    If($null -ne $srcStream)
                    {
                        $srcStream.Dispose()
                    }
                    If($null -ne $destStream)
                    {
                        $destStream.Dispose()
                    }
                }
            }
            else
            {
                $currentArchiveEntry = $zipArchive.CreateEntry("$relativeFilePath", $compression)
                $numberOfItemsArchived += 1
                $addItemtoArchiveFileMessage = ($LocalizedData.AddItemtoArchiveFile -f $currentFilePath)
            }

            if($null -ne $addItemtoArchiveFileMessage)
            {
                Write-Verbose $addItemtoArchiveFileMessage
            }

            $currentEntryCount += 1
            ProgressBarHelper "Compress-Archive" $progressBarStatus $previousSegmentWeight $currentSegmentWeight $sourcePaths.Count  $currentEntryCount
        }
    }
    finally
    {
        If($null -ne $zipArchive)
        {
            $zipArchive.Dispose()
        }

        If($null -ne $archiveFileStream)
        {
            $archiveFileStream.Dispose()
        }

        # Complete writing progress.
        Write-Progress -Activity "Compress-Archive" -Completed
    }

    return $numberOfItemsArchived
}

<############################################################################################
# ValidateArchivePathHelper: This is a helper function used to validate the archive file
# path & its file format. The only supported archive file format is .zip
############################################################################################>
function ValidateArchivePathHelper
{
    param
    (
        [string] $archiveFile
    )

    if(-not [System.IO.File]::Exists($archiveFile))
    {
        $errorMessage = ($LocalizedData.PathNotFoundError -f $archiveFile)
        ThrowTerminatingErrorHelper "PathNotFound" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidArgument) $archiveFile
    }
}

<############################################################################################
# ExpandArchiveHelper: This is a helper function used to expand the archive file contents
# to the specified directory.
############################################################################################>
function ExpandArchiveHelper
{
    param
    (
        [string]  $archiveFile,
        [string]  $expandedDir,
        [ref]     $expandedItems,
        [boolean] $force,
        [boolean] $isVerbose,
        [boolean] $isConfirm
    )

    Add-CompressionAssemblies

    try
    {
        # The existence of archive file has already been validated by ValidateArchivePathHelper
        # before calling this helper function.
        $archiveFileStreamArgs = @($archiveFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
        $archiveFileStream = New-Object -TypeName System.IO.FileStream -ArgumentList $archiveFileStreamArgs

        $zipArchiveArgs = @($archiveFileStream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
        try
        {
            $zipArchive = New-Object -TypeName System.IO.Compression.ZipArchive -ArgumentList $zipArchiveArgs
        }
        catch [System.IO.InvalidDataException]
        {
            # Failed to open the file for reading as a zip archive. Wrap the exception
            # and re-throw it indicating it does not appear to be a valid zip file.
            $exception = $_.Exception
            if($null -ne $_.Exception -and
               $null -ne $_.Exception.InnerException)
            {
                $exception = $_.Exception.InnerException
            }
            # Load the WindowsBase.dll assembly to get access to the System.IO.FileFormatException class
            [System.Reflection.Assembly]::Load('WindowsBase,Version=4.0.0.0,Culture=neutral,PublicKeyToken=31bf3856ad364e35')
            $invalidFileFormatException = New-Object -TypeName System.IO.FileFormatException -ArgumentList @(
                ($LocalizedData.ItemDoesNotAppearToBeAValidZipArchive -f $archiveFile)
                $exception
            )
            throw $invalidFileFormatException
        }

        if($zipArchive.Entries.Count -eq 0)
        {
            $archiveFileIsEmpty = ($LocalizedData.ArchiveFileIsEmpty -f $archiveFile)
            Write-Verbose $archiveFileIsEmpty
            return
        }

        $currentEntryCount = 0
        $progressBarStatus = ($LocalizedData.ExpandProgressBarText -f $archiveFile)

        # The archive entries can either be empty directories or files.
        foreach($currentArchiveEntry in $zipArchive.Entries)
        {
            $currentArchiveEntryPath = Join-Path -Path $expandedDir -ChildPath $currentArchiveEntry.FullName
            $extension = [system.IO.Path]::GetExtension($currentArchiveEntryPath)

            # The current archive entry is an empty directory
            # The FullName of the Archive Entry representing a directory would end with a trailing directory separator.
            if($extension -eq [string]::Empty -and
            $currentArchiveEntryPath.EndsWith([System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase))
            {
                $pathExists = Test-Path -LiteralPath $currentArchiveEntryPath

                # The current archive entry expects an empty directory.
                # Check if the existing directory is empty. If it's not empty
                # then it means that user has added this directory by other means.
                if($pathExists -eq $false)
                {
                    New-Item $currentArchiveEntryPath -Type Directory -Confirm:$isConfirm | Out-Null

                    if(Test-Path -LiteralPath $currentArchiveEntryPath -PathType Container)
                    {
                        $addEmptyDirectorytoExpandedPathMessage = ($LocalizedData.AddItemtoArchiveFile -f $currentArchiveEntryPath)
                        Write-Verbose $addEmptyDirectorytoExpandedPathMessage

                        $expandedItems.Value += $currentArchiveEntryPath
                    }
                }
            }
            else
            {
                try
                {
                    $currentArchiveEntryFileInfo = New-Object -TypeName System.IO.FileInfo -ArgumentList $currentArchiveEntryPath
                    $parentDirExists = Test-Path -LiteralPath $currentArchiveEntryFileInfo.DirectoryName -PathType Container

                    # If the Parent directory of the current entry in the archive file does not exist, then create it.
                    if($parentDirExists -eq $false)
                    {
                        # note that if any ancestor of this directory doesn't exist, we don't recursively create each one as New-Item
                        # takes care of this already, so only one DirectoryInfo is returned instead of one for each parent directory
                        # that only contains directories
                        New-Item $currentArchiveEntryFileInfo.DirectoryName -Type Directory -Confirm:$isConfirm | Out-Null

                        if(!(Test-Path -LiteralPath $currentArchiveEntryFileInfo.DirectoryName -PathType Container))
                        {
                            # The directory referred by $currentArchiveEntryFileInfo.DirectoryName was not successfully created.
                            # This could be because the user has specified -Confirm parameter when Expand-Archive was invoked
                            # and authorization was not provided when confirmation was prompted. In such a scenario,
                            # we skip the current file in the archive and continue with the remaining archive file contents.
                            Continue
                        }

                        $expandedItems.Value += $currentArchiveEntryFileInfo.DirectoryName
                    }

                    $hasNonTerminatingError = $false

                    # Check if the file in to which the current archive entry contents
                    # would be expanded already exists.
                    if($currentArchiveEntryFileInfo.Exists)
                    {
                        if($force)
                        {
                            Remove-Item -LiteralPath $currentArchiveEntryFileInfo.FullName -Force -ErrorVariable ev -Verbose:$isVerbose -Confirm:$isConfirm
                            if($ev -ne $null)
                            {
                                $hasNonTerminatingError = $true
                            }

                            if(Test-Path -LiteralPath $currentArchiveEntryFileInfo.FullName -PathType Leaf)
                            {
                                # The file referred by $currentArchiveEntryFileInfo.FullName was not successfully removed.
                                # This could be because the user has specified -Confirm parameter when Expand-Archive was invoked
                                # and authorization was not provided when confirmation was prompted. In such a scenario,
                                # we skip the current file in the archive and continue with the remaining archive file contents.
                                Continue
                            }
                        }
                        else
                        {
                            # Write non-terminating error to the pipeline.
                            $errorMessage = ($LocalizedData.FileExistsError -f $currentArchiveEntryFileInfo.FullName, $archiveFile, $currentArchiveEntryFileInfo.FullName, $currentArchiveEntryFileInfo.FullName)
                            $errorRecord = CreateErrorRecordHelper "ExpandArchiveFileExists" $errorMessage ([System.Management.Automation.ErrorCategory]::InvalidOperation) $null $currentArchiveEntryFileInfo.FullName
                            Write-Error -ErrorRecord $errorRecord
                            $hasNonTerminatingError = $true
                        }
                    }

                    if(!$hasNonTerminatingError)
                    {
                        # The ExtractToFile() method doesn't handle whitespace correctly, strip whitespace which is consistent with how Explorer handles archives
                        # There is an edge case where an archive contains files whose only difference is whitespace, but this is uncommon and likely not legitimate
                        [string[]] $parts = $currentArchiveEntryPath.Split([System.IO.Path]::DirectorySeparatorChar) | % { $_.Trim() }
                        $currentArchiveEntryPath = [string]::Join([System.IO.Path]::DirectorySeparatorChar, $parts)

                        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($currentArchiveEntry, $currentArchiveEntryPath, $false)

                        # Add the expanded file path to the $expandedItems array,
                        # to keep track of all the expanded files created while expanding the archive file.
                        # If user enters CTRL + C then at that point of time, all these expanded files
                        # would be deleted as part of the clean up process.
                        $expandedItems.Value += $currentArchiveEntryPath

                        $addFiletoExpandedPathMessage = ($LocalizedData.CreateFileAtExpandedPath -f $currentArchiveEntryPath)
                        Write-Verbose $addFiletoExpandedPathMessage
                    }
                }
                finally
                {
                    If($null -ne $destStream)
                    {
                        $destStream.Dispose()
                    }

                    If($null -ne $srcStream)
                    {
                        $srcStream.Dispose()
                    }
                }
            }

            $currentEntryCount += 1
            # $currentSegmentWeight is Set to 100 giving equal weightage to each file that is getting expanded.
            # $previousSegmentWeight is set to 0 as there are no prior segments.
            $previousSegmentWeight = 0
            $currentSegmentWeight = 100
            ProgressBarHelper "Expand-Archive" $progressBarStatus $previousSegmentWeight $currentSegmentWeight $zipArchive.Entries.Count  $currentEntryCount
        }
    }
    finally
    {
        If($null -ne $zipArchive)
        {
            $zipArchive.Dispose()
        }

        If($null -ne $archiveFileStream)
        {
            $archiveFileStream.Dispose()
        }

        # Complete writing progress.
        Write-Progress -Activity "Expand-Archive" -Completed
    }
}

<############################################################################################
# ProgressBarHelper: This is a helper function used to display progress message.
# This function is used by both Compress-Archive & Expand-Archive to display archive file
# creation/expansion progress.
############################################################################################>
function ProgressBarHelper
{
    param
    (
        [string] $cmdletName,
        [string] $status,
        [double] $previousSegmentWeight,
        [double] $currentSegmentWeight,
        [int]    $totalNumberofEntries,
        [int]    $currentEntryCount
    )

    if($currentEntryCount -gt 0 -and
       $totalNumberofEntries -gt 0 -and
       $previousSegmentWeight -ge 0 -and
       $currentSegmentWeight -gt 0)
    {
        $entryDefaultWeight = $currentSegmentWeight/[double]$totalNumberofEntries

        $percentComplete = $previousSegmentWeight + ($entryDefaultWeight * $currentEntryCount)
        Write-Progress -Activity $cmdletName -Status $status -PercentComplete $percentComplete
    }
}

<############################################################################################
# CSVHelper: This is a helper function used to append comma after each path specified by
# the SourcePath array. This helper function is used to display all the user supplied paths
# in the WhatIf message.
############################################################################################>
function CSVHelper
{
    param
    (
        [string[]] $sourcePath
    )

    # SourcePath has already been validated by the calling function.
    if($sourcePath.Count -gt 1)
    {
        $sourcePathInCsvFormat = "`n"
        for($currentIndex=0; $currentIndex -lt $sourcePath.Count; $currentIndex++)
        {
            if($currentIndex -eq $sourcePath.Count - 1)
            {
                $sourcePathInCsvFormat += $sourcePath[$currentIndex]
            }
            else
            {
                $sourcePathInCsvFormat += $sourcePath[$currentIndex] + "`n"
            }
        }
    }
    else
    {
        $sourcePathInCsvFormat = $sourcePath
    }

    return $sourcePathInCsvFormat
}

<############################################################################################
# ThrowTerminatingErrorHelper: This is a helper function used to throw terminating error.
############################################################################################>
function ThrowTerminatingErrorHelper
{
    param
    (
        [string] $errorId,
        [string] $errorMessage,
        [System.Management.Automation.ErrorCategory] $errorCategory,
        [object] $targetObject,
        [Exception] $innerException
    )

    if($innerException -eq $null)
    {
        $exception = New-object System.IO.IOException $errorMessage
    }
    else
    {
        $exception = New-Object System.IO.IOException $errorMessage, $innerException
    }

    $exception = New-Object System.IO.IOException $errorMessage
    $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, $errorId, $errorCategory, $targetObject
    $PSCmdlet.ThrowTerminatingError($errorRecord)
}

<############################################################################################
# CreateErrorRecordHelper: This is a helper function used to create an ErrorRecord
############################################################################################>
function CreateErrorRecordHelper
{
    param
    (
        [string] $errorId,
        [string] $errorMessage,
        [System.Management.Automation.ErrorCategory] $errorCategory,
        [Exception] $exception,
        [object] $targetObject
    )

    if($null -eq $exception)
    {
        $exception = New-Object System.IO.IOException $errorMessage
    }

    $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, $errorId, $errorCategory, $targetObject
    return $errorRecord
}

# SIG # Begin signature block
# MIIasAYJKoZIhvcNAQcCoIIaoTCCGp0CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUMGD0MtaOGo1zqq/4e97dwKbd
# f26gghWDMIIEwzCCA6ugAwIBAgITMwAAALbYAJUMg2JtoQAAAAAAtjANBgkqhkiG
# 9w0BAQUFADB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwHhcNMTYwOTA3MTc1ODQ0
# WhcNMTgwOTA3MTc1ODQ0WjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNO
# OjMxQzUtMzBCQS03QzkxMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAlitSnGveWTDN
# e1jrQZjYpA9N4OXmCTtz/jy98iVz0ro/f2ELzjwkrzQycPykmlVlOxzzzaSIBmqK
# HiWJXU9m6mU0WS8/O8GV2U8d9PA057wJ/6+3ptVocqSANSNpXip5qKRl5P1Wac0Z
# 5oJ1NOXPnu1J4slB7ssE2ifDwS+0kHkTU3FdKeh8dAoC7GoQU0aFQdPFikvh7YRa
# gwPzzPVs96zCJdIY4gPGqdi8ajX3xrJI4th7QdO98fpj8f1CBJtlELMDiaMwUu0e
# 2VLTFE1sl1cyer4afcTuf+ENNRyiH+LJ5nHRK3/zkTYpjv8G/tfp3swk2ha9tsPP
# ddCge17XYQIDAQABo4IBCTCCAQUwHQYDVR0OBBYEFOjzQTSj/oQgLDnBEUwqsxz4
# 7wKyMB8GA1UdIwQYMBaAFCM0+NlSRnAK7UD7dvuzK7DDNbMPMFQGA1UdHwRNMEsw
# SaBHoEWGQ2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3Rz
# L01pY3Jvc29mdFRpbWVTdGFtcFBDQS5jcmwwWAYIKwYBBQUHAQEETDBKMEgGCCsG
# AQUFBzAChjxodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY3Jv
# c29mdFRpbWVTdGFtcFBDQS5jcnQwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQEFBQADggEBAGotNN2Ff2yTVo4VKnHCmG+PxMuqhs1ke1JE5bQu3bGRgIWX
# riEZvWVqgDUihF4GmcPRHatBE9qtM5ewhDuSIGBf/5rqskW00Q4Kgb7mDtx/sOV7
# wNXJ0HjFgyNRqVDVxVE6uZ8bCTi+TjhfuIBZj85UbdfG/qtPkQkzgmaK83dgLPEH
# T8Je8gd7orVPNkI3lqkQbQ8X4ZISiP+heRsPYtlgeMGvnle5ssGzB2O5Ozt527Fa
# Ztpxi32uN1Qk8hV7xM+Z4ujOGqJFxVQfCGlMU0tXTvaRNoNpKWSp2fjYHyasLXAU
# y7ZhZHq7qWAilzmqCFYZIDPJmjUtm1/hqhqqqxQwggTtMIID1aADAgECAhMzAAAB
# QJap7nBW/swHAAEAAAFAMA0GCSqGSIb3DQEBBQUAMHkxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xIzAhBgNVBAMTGk1pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBMB4XDTE2MDgxODIwMTcxN1oXDTE3MTEwMjIwMTcxN1owgYMxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDTALBgNVBAsTBE1PUFIx
# HjAcBgNVBAMTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBANtLi+kDal/IG10KBTnk1Q6S0MThi+ikDQUZWMA81ynd
# ibdobkuffryavVSGOanxODUW5h2s+65r3Akw77ge32z4SppVl0jII4mzWSc0vZUx
# R5wPzkA1Mjf+6fNPpBqks3m8gJs/JJjE0W/Vf+dDjeTc8tLmrmbtBDohlKZX3APb
# LMYb/ys5qF2/Vf7dSd9UBZSrM9+kfTGmTb1WzxYxaD+Eaxxt8+7VMIruZRuetwgc
# KX6TvfJ9QnY4ItR7fPS4uXGew5T0goY1gqZ0vQIz+lSGhaMlvqqJXuI5XyZBmBre
# ueZGhXi7UTICR+zk+R+9BFF15hKbduuFlxQiCqET92ECAwEAAaOCAWEwggFdMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQWBBSc5ehtgleuNyTe6l6pxF+QHc7Z
# ezBSBgNVHREESzBJpEcwRTENMAsGA1UECxMETU9QUjE0MDIGA1UEBRMrMjI5ODAz
# K2Y3ODViMWMwLTVkOWYtNDMxNi04ZDZhLTc0YWU2NDJkZGUxYzAfBgNVHSMEGDAW
# gBTLEejK0rQWWAHJNy4zFha5TJoKHzBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8v
# Y3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNDb2RTaWdQQ0Ff
# MDgtMzEtMjAxMC5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY0NvZFNpZ1BDQV8wOC0z
# MS0yMDEwLmNydDANBgkqhkiG9w0BAQUFAAOCAQEAa+RW49cTHSBA+W3p3k7bXR7G
# bCaj9+UJgAz/V+G01Nn5XEjhBn/CpFS4lnr1jcmDEwxxv/j8uy7MFXPzAGtOJar0
# xApylFKfd00pkygIMRbZ3250q8ToThWxmQVEThpJSSysee6/hU+EbkfvvtjSi0lp
# DimD9aW9oxshraKlPpAgnPWfEj16WXVk79qjhYQyEgICamR3AaY5mLPuoihJbKwk
# Mig+qItmLPsC2IMvI5KR91dl/6TV6VEIlPbW/cDVwCBF/UNJT3nuZBl/YE7ixMpT
# Th/7WpENW80kg3xz6MlCdxJfMSbJsM5TimFU98KNcpnxxbYdfqqQhAQ6l3mtYDCC
# BbwwggOkoAMCAQICCmEzJhoAAAAAADEwDQYJKoZIhvcNAQEFBQAwXzETMBEGCgmS
# JomT8ixkARkWA2NvbTEZMBcGCgmSJomT8ixkARkWCW1pY3Jvc29mdDEtMCsGA1UE
# AxMkTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5MB4XDTEwMDgz
# MTIyMTkzMloXDTIwMDgzMTIyMjkzMloweTELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEjMCEGA1UEAxMaTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQ
# Q0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCycllcGTBkvx2aYCAg
# Qpl2U2w+G9ZvzMvx6mv+lxYQ4N86dIMaty+gMuz/3sJCTiPVcgDbNVcKicquIEn0
# 8GisTUuNpb15S3GbRwfa/SXfnXWIz6pzRH/XgdvzvfI2pMlcRdyvrT3gKGiXGqel
# cnNW8ReU5P01lHKg1nZfHndFg4U4FtBzWwW6Z1KNpbJpL9oZC/6SdCnidi9U3RQw
# WfjSjWL9y8lfRjFQuScT5EAwz3IpECgixzdOPaAyPZDNoTgGhVxOVoIoKgUyt0vX
# T2Pn0i1i8UU956wIAPZGoZ7RW4wmU+h6qkryRs83PDietHdcpReejcsRj1Y8wawJ
# XwPTAgMBAAGjggFeMIIBWjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTLEejK
# 0rQWWAHJNy4zFha5TJoKHzALBgNVHQ8EBAMCAYYwEgYJKwYBBAGCNxUBBAUCAwEA
# ATAjBgkrBgEEAYI3FQIEFgQU/dExTtMmipXhmGA7qDFvpjy82C0wGQYJKwYBBAGC
# NxQCBAweCgBTAHUAYgBDAEEwHwYDVR0jBBgwFoAUDqyCYEBWJ5flJRP8KuEKU5VZ
# 5KQwUAYDVR0fBEkwRzBFoEOgQYY/aHR0cDovL2NybC5taWNyb3NvZnQuY29tL3Br
# aS9jcmwvcHJvZHVjdHMvbWljcm9zb2Z0cm9vdGNlcnQuY3JsMFQGCCsGAQUFBwEB
# BEgwRjBEBggrBgEFBQcwAoY4aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9j
# ZXJ0cy9NaWNyb3NvZnRSb290Q2VydC5jcnQwDQYJKoZIhvcNAQEFBQADggIBAFk5
# Pn8mRq/rb0CxMrVq6w4vbqhJ9+tfde1MOy3XQ60L/svpLTGjI8x8UJiAIV2sPS9M
# uqKoVpzjcLu4tPh5tUly9z7qQX/K4QwXaculnCAt+gtQxFbNLeNK0rxw56gNogOl
# VuC4iktX8pVCnPHz7+7jhh80PLhWmvBTI4UqpIIck+KUBx3y4k74jKHK6BOlkU7I
# G9KPcpUqcW2bGvgc8FPWZ8wi/1wdzaKMvSeyeWNWRKJRzfnpo1hW3ZsCRUQvX/Ta
# rtSCMm78pJUT5Otp56miLL7IKxAOZY6Z2/Wi+hImCWU4lPF6H0q70eFW6NB4lhhc
# yTUWX92THUmOLb6tNEQc7hAVGgBd3TVbIc6YxwnuhQ6MT20OE049fClInHLR82zK
# wexwo1eSV32UjaAbSANa98+jZwp0pTbtLS8XyOZyNxL0b7E8Z4L5UrKNMxZlHg6K
# 3RDeZPRvzkbU0xfpecQEtNP7LN8fip6sCvsTJ0Ct5PnhqX9GuwdgR2VgQE6wQuxO
# 7bN2edgKNAltHIAxH+IOVN3lofvlRxCtZJj/UBYufL8FIXrilUEnacOTj5XJjdib
# Ia4NXJzwoq6GaIMMai27dmsAHZat8hZ79haDJLmIz2qoRzEvmtzjcT3XAH5iR9HO
# iMm4GPoOco3Boz2vAkBq/2mbluIQqBC0N1AI1sM9MIIGBzCCA++gAwIBAgIKYRZo
# NAAAAAAAHDANBgkqhkiG9w0BAQUFADBfMRMwEQYKCZImiZPyLGQBGRYDY29tMRkw
# FwYKCZImiZPyLGQBGRYJbWljcm9zb2Z0MS0wKwYDVQQDEyRNaWNyb3NvZnQgUm9v
# dCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkwHhcNMDcwNDAzMTI1MzA5WhcNMjEwNDAz
# MTMwMzA5WjB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwggEiMA0GCSqGSIb3DQEB
# AQUAA4IBDwAwggEKAoIBAQCfoWyx39tIkip8ay4Z4b3i48WZUSNQrc7dGE4kD+7R
# p9FMrXQwIBHrB9VUlRVJlBtCkq6YXDAm2gBr6Hu97IkHD/cOBJjwicwfyzMkh53y
# 9GccLPx754gd6udOo6HBI1PKjfpFzwnQXq/QsEIEovmmbJNn1yjcRlOwhtDlKEYu
# J6yGT1VSDOQDLPtqkJAwbofzWTCd+n7Wl7PoIZd++NIT8wi3U21StEWQn0gASkdm
# EScpZqiX5NMGgUqi+YSnEUcUCYKfhO1VeP4Bmh1QCIUAEDBG7bfeI0a7xC1Un68e
# eEExd8yb3zuDk6FhArUdDbH895uyAc4iS1T/+QXDwiALAgMBAAGjggGrMIIBpzAP
# BgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBQjNPjZUkZwCu1A+3b7syuwwzWzDzAL
# BgNVHQ8EBAMCAYYwEAYJKwYBBAGCNxUBBAMCAQAwgZgGA1UdIwSBkDCBjYAUDqyC
# YEBWJ5flJRP8KuEKU5VZ5KShY6RhMF8xEzARBgoJkiaJk/IsZAEZFgNjb20xGTAX
# BgoJkiaJk/IsZAEZFgltaWNyb3NvZnQxLTArBgNVBAMTJE1pY3Jvc29mdCBSb290
# IENlcnRpZmljYXRlIEF1dGhvcml0eYIQea0WoUqgpa1Mc1j0BxMuZTBQBgNVHR8E
# STBHMEWgQ6BBhj9odHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9k
# dWN0cy9taWNyb3NvZnRyb290Y2VydC5jcmwwVAYIKwYBBQUHAQEESDBGMEQGCCsG
# AQUFBzAChjhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY3Jv
# c29mdFJvb3RDZXJ0LmNydDATBgNVHSUEDDAKBggrBgEFBQcDCDANBgkqhkiG9w0B
# AQUFAAOCAgEAEJeKw1wDRDbd6bStd9vOeVFNAbEudHFbbQwTq86+e4+4LtQSooxt
# YrhXAstOIBNQmd16QOJXu69YmhzhHQGGrLt48ovQ7DsB7uK+jwoFyI1I4vBTFd1P
# q5Lk541q1YDB5pTyBi+FA+mRKiQicPv2/OR4mS4N9wficLwYTp2OawpylbihOZxn
# LcVRDupiXD8WmIsgP+IHGjL5zDFKdjE9K3ILyOpwPf+FChPfwgphjvDXuBfrTot/
# xTUrXqO/67x9C0J71FNyIe4wyrt4ZVxbARcKFA7S2hSY9Ty5ZlizLS/n+YWGzFFW
# 6J1wlGysOUzU9nm/qhh6YinvopspNAZ3GmLJPR5tH4LwC8csu89Ds+X57H2146So
# dDW4TsVxIxImdgs8UoxxWkZDFLyzs7BNZ8ifQv+AeSGAnhUwZuhCEl4ayJ4iIdBD
# 6Svpu/RIzCzU2DKATCYqSCRfWupW76bemZ3KOm+9gSd0BhHudiG/m4LBJ1S2sWo9
# iaF2YbRuoROmv6pH8BJv/YoybLL+31HIjCPJZr2dHYcSZAI9La9Zj7jkIeW1sMpj
# tHhUBdRBLlCslLCleKuzoJZ1GtmShxN1Ii8yqAhuoFuMJb+g74TKIdbrHk/Jmu5J
# 4PcBZW+JC33Iacjmbuqnl84xKf8OxVtc2E0bodj6L54/LlUWa8kTo/0xggSXMIIE
# kwIBATCBkDB5MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSMw
# IQYDVQQDExpNaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQQITMwAAAUCWqe5wVv7M
# BwABAAABQDAJBgUrDgMCGgUAoIGwMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEE
# MBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBRs
# mDZ9ejFdfh1Zmt07YWMuyAamXTBQBgorBgEEAYI3AgEMMUIwQKAWgBQAUABvAHcA
# ZQByAFMAaABlAGwAbKEmgCRodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vUG93ZXJT
# aGVsbCAwDQYJKoZIhvcNAQEBBQAEggEAHnkW8V1H1o1UUWMYdVW0D83cRlarQOMN
# LtRJBumJHlqhni7JnDVDdMuiVoGBMJ+cqpA5IqGRFVvVBlZUIC0H8j7UHUU1zsyh
# 7k9WxCuLpGSs++5ZHa/SrmF9NxUpJmp6rRW5sYnCR3nNqhrWITaXEd8IjlJPnKNx
# 2tj70KSt71zWYijxyBNc68c1wsn16RW8Qwk1KsJo9j/gNExGe/HX3KocON5w2kth
# FGA4YL2PekHL2VxJ9+h81Eq9h1K2gbZbzVDIipV5+BdJ+S7GQb/TlTynS5vHfu5x
# KwbfQ7rJfQbGjxSHwvIQS5xwOoM0q4tximBULfqpRVYNnZYM+Li/06GCAigwggIk
# BgkqhkiG9w0BCQYxggIVMIICEQIBATCBjjB3MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSEwHwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0ECEzMAAAC22ACVDINibaEAAAAAALYwCQYFKw4DAhoFAKBdMBgGCSqGSIb3DQEJ
# AzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTE3MDMxNzIxMjEwOFowIwYJ
# KoZIhvcNAQkEMRYEFI+I/OHGVcqPZJf6I6IoF2+xNyjSMA0GCSqGSIb3DQEBBQUA
# BIIBAAZhAuZtG+zUhPw1V6o4B0OmCZDXaLHgb3gVtsB0Fgk7iNGy6WxGEl5sdgTX
# JN5bAsfnlleWRZLfHgmBnJfC1lNouLp2M2EHncUcUyZ0XPx4T3PRmnhB4LTBaY1I
# G161i2wiXZnpu84ITV1Kxe8b6ONe4FwgTjfoTcLt8tAdS3mqj4PcbdLPUsy9ALEH
# fqP1gYaap+BNBhgOrTlOMKYJLUucqJaTF73zlfeIk6t+AifUW35yOy81lD+5TV4+
# F3NaBhbIHCj8zxcdUv6pTp733CTJPhLlflWEEoBfNTn6JTMX+yEMr0y9HtFOmxDU
# QQ/wvTMuHX2L1F0Lzx/If6aPmwc=
# SIG # End signature block
