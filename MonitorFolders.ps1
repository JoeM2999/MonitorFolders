param([String]$FileInputSettings)

function GetSettings {
  param([String] $settingsFile)
  $vals = (Get-Content $settingsFile)
  $settings=@("")*5
  $i=0

  foreach($v in $vals){
    $line = $v.split("|")
    $settings[$i]=$line[1]
    $i++
  }
  return $settings
}
function MyTestFunc {
  param([parameter(Mandatory=$true)][string]$str)
  return $str.ToUpper()    
}

function ProcessFile {
  param(
    [parameter(Mandatory=$true)][string]$source,
    [Parameter(Mandatory=$true)][string]$dest
  )
    write-host "Copying file $source to $dest" -ForegroundColor Green
    copy-item $source $dest -Force

    #Copy file to processed directory and add timestamp
    [string]$strippedFileName = [System.IO.Path]::GetFileNameWithoutExtension($source);
    [string]$extension = [System.IO.Path]::GetExtension($source);
    [string]$newFileName = $strippedFileName + "_" + [DateTime]::Now.ToString("yyyyMMdd-HHmmss") + $extension;
    [string]$newFilePath = [System.IO.Path]::Combine($Processed, $newFileName);

    write-host "Copying to processed folder: $newFilePath" -ForegroundColor Green
    Add-content $LogFile -Value "$((Get-Date).ToString("yyyy/MM/dd HH:mm:ss")) Copy to Processed folder: $($newFilePath)"
    copy-item $source $newFilePath -Force
    remove-item $source
} 
function Test-FileLock {
  param (
    [parameter(Mandatory=$true)][string]$Path
  )

  write-host "Entering Test-FileLock $Path"
  $oFile = New-Object System.IO.FileInfo $Path

  if ((Test-Path -Path $Path) -eq $false) {
    write-host "File is not locked"
    return $false
  }

  try {
    $oStream = $oFile.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

    if ($oStream) {
      $oStream.Close()
    }
    write-host "File is not locked"
    return $false
  } catch {
    # file is locked by a process.
    Start-Sleep -seconds 3
    return $true
  }
}

# find the path to the desktop folder:
$desktop = [Environment]::GetFolderPath('Desktop')

# specify the path to the folder you want to monitor:
#$ProductTypeId = "NIR2_OSG"
#$Path = "C:\temp\Bruker\data\Upgraded_Products(UP)"
#$Destination = "\\file183\SampleManager\IM-DATA\OSG\Lab_Instruments\NIR2\In"
#$Logs = "C:\temp\filetransfer\log\Upgraded_Products(UP)"
#$LogFile = [System.IO.Path]::Combine($Logs, $ProductTypeId) + ".log"
#$Processed = "C:\temp\filetransfer\processed\Upgraded_Products(UP)"
$settings = GetSettings($FileInputSettings)

$ProductTypeId = $settings[0].trim()
$Path = $settings[1].trim()
$Destination = $settings[2].trim()
$Logs = $settings[3].trim()
$LogFile = [System.IO.Path]::Combine($Logs, $ProductTypeId) + ".log"
$Processed = $settings[4].trim()


# Check for file lock
$global:isLocked = $true

# specify which files you want to monitor
$FileFilter = '*.log'  

# specify whether you want to monitor subfolders as well:
$IncludeSubfolders = $false

# specify the file or folder properties you want to monitor:
$AttributeFilter = [IO.NotifyFilters]::FileName, [IO.NotifyFilters]::LastWrite 
try
{
  $watcher = New-Object -TypeName System.IO.FileSystemWatcher -Property @{
    Path = $Path
    Filter = $FileFilter
    IncludeSubdirectories = $IncludeSubfolders
    NotifyFilter = $AttributeFilter
  }

  # define the code that should execute when a change occurs:
  $action = {
    # the code is receiving this to work with:
    
    # change type information:
    $details = $event.SourceEventArgs
    $Name = $details.Name
    $FullPath = $details.FullPath
    $OldFullPath = $details.OldFullPath
    $OldName = $details.OldName

    
    # type of change:
    $ChangeType = $details.ChangeType
    
    # when the change occured:
    $Timestamp = $event.TimeGenerated
    
    # save information to a global variable for testing purposes
    # so you can examine it later
    # MAKE SURE YOU REMOVE THIS IN PRODUCTION!
    #$global:all = $details
    
    # now you can define some action to take based on the
    # details about the change event:
    
    # let's compose a message:
    $text = "{0} was {1} at {2}" -f $FullPath, $ChangeType, $Timestamp
    Write-Host ""
    Write-Host $text -ForegroundColor DarkYellow
    
    # you can also execute code based on change type here:
    switch ($ChangeType)
    {
      'Changed'  { "CHANGE" 
      #Check if file is locked or not
      # $global:IsLocked = Test-FileLock $FullPath
      }
      'Created'  { "CREATED" 
      while($global:IsLocked -eq $true){
        $global:IsLocked = Test-FileLock $FullPath
        Write-Host "$FullPath is locked. Waiting"
        # Start-Sleep in contrast would NOT work and ignore incoming events
        Wait-Event -Timeout 1
        # write a dot to indicate we are still monitoring:
        Write-Host "." -NoNewline
      }
      
      #copy the file if it is not locked
      if($global:isLocked -ne $true) {
        try {
          ProcessFile $FullPath $Destination
          $global:isLocked = $true
        }
        catch {
          write-host "Something went wrong" -ForegroundColor Red
        }
      } 
    }
      'Deleted'  { "DELETED"
        # to illustrate that ALL changes are picked up even if
        # handling an event takes a lot of time, we artifically
        # extend the time the handler needs whenever a file is deleted
        # Write-Host "Deletion Handler Start" -ForegroundColor Gray
        # Start-Sleep -Seconds 4    
        # Write-Host "Deletion Handler End" -ForegroundColor Gray
      }
      'Renamed'  { 
        # this executes only when a file was renamed
        $text = "File {0} was renamed to {1}" -f $OldName, $Name
        Write-Host $text -ForegroundColor Yellow
      }
        
      # any unhandled change types surface here:
      default   { Write-Host $_ -ForegroundColor Red -BackgroundColor White }
    }
  }

  # subscribe your event handler to all event types that are
  # important to you. Do this as a scriptblock so all returned
  # event handlers can be easily stored in $handlers:
  $handlers = . {
    Register-ObjectEvent -InputObject $watcher -EventName Changed  -Action $action 
    Register-ObjectEvent -InputObject $watcher -EventName Created  -Action $action 
    Register-ObjectEvent -InputObject $watcher -EventName Deleted  -Action $action 
    Register-ObjectEvent -InputObject $watcher -EventName Renamed  -Action $action 
  }

  # monitoring starts now:
  $watcher.EnableRaisingEvents = $true

  Write-Host "Watching for changes to $Path"

  # since the FileSystemWatcher is no longer blocking PowerShell
  # we need a way to pause PowerShell while being responsive to
  # incoming events. Use an endless loop to keep PowerShell busy:
  do
  {
    # Wait-Event waits for a second and stays responsive to events
    # Start-Sleep in contrast would NOT work and ignore incoming events
    Wait-Event -Timeout 1

    # write a dot to indicate we are still monitoring:
    Write-Host "." -NoNewline
        
  } while ($true)
}
finally
{
  # this gets executed when user presses CTRL+C:
  
  # stop monitoring
  $watcher.EnableRaisingEvents = $false
  
  # remove the event handlers
  $handlers | ForEach-Object {
    Unregister-Event -SourceIdentifier $_.Name
  }
  
  # event handlers are technically implemented as a special kind
  # of background job, so remove the jobs now:
  $handlers | Remove-Job
  
  # properly dispose the FileSystemWatcher:
  $watcher.Dispose()
  
  Write-Warning "Event Handler disabled, monitoring ends."
}

