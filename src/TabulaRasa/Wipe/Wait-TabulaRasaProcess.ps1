# NOTE:
#   Requires: the program to run on the PATH (e.g. hdparm), root when the program needs it.
#
#   Wait-TabulaRasaProcess -FilePath hdparm -ArgumentList '--user-master', 'u', '--security-erase', 'TabulaRasa', '/dev/sda' -EstimatedSeconds 120

function Wait-TabulaRasaProcess {
    <#
    .SYNOPSIS
        Runs a native command that blocks for minutes and reports an estimated progress meanwhile.

    .DESCRIPTION
        hdparm --security-erase returns only when the drive is done and prints no progress.
        The drive itself names the expected duration (hdparm -I), so the progress is the elapsed
        share of that estimate, capped at 99 % until the command really returns.
        The arguments go to the process one by one, never through a shell.

    .EXAMPLE
        PS> Wait-TabulaRasaProcess -FilePath hdparm -ArgumentList '--user-master', 'u', '--security-erase', 'TabulaRasa', '/dev/sda' -EstimatedSeconds 120 -OnProgress { param ($Percent) $Percent }
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        <#
        [Required]
        The program, e.g. 'hdparm'.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.String]
        $FilePath,

        <#
        [Optional]
        The arguments, one entry each.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [System.String[]]
        $ArgumentList = @(),

        <#
        [Optional]
        The expected duration. 0 means unknown, then no progress is reported.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [ValidateRange(0, [System.Int32]::MaxValue)]
        [System.Int32]
        $EstimatedSeconds = 0,

        <#
        [Optional]
        Called with the estimated percentage about once a second.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [System.Management.Automation.ScriptBlock]
        $OnProgress = $null
    )

    $POLL_MS     = 1000
    $MAX_PERCENT = 99

    $StartInfo = [System.Diagnostics.ProcessStartInfo]::new($FilePath)
    foreach ($argument in $ArgumentList) {
        $StartInfo.ArgumentList.Add($argument)
    }
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError  = $true
    $StartInfo.UseShellExecute        = $false

    Write-Verbose "[Wait-TabulaRasaProcess] Starting '$FilePath $($ArgumentList -join ' ')', estimated $EstimatedSeconds s."
    $process = [System.Diagnostics.Process]::Start($StartInfo)
    try {
        # Read both streams in the background, a full pipe buffer would block the process.
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask  = $process.StandardError.ReadToEndAsync()
        $stopwatch  = [System.Diagnostics.Stopwatch]::StartNew()

        while (-NOT $process.WaitForExit($POLL_MS)) {
            if ($null -NE $OnProgress -AND $EstimatedSeconds -GT 0) {
                $null = & $OnProgress ([System.Math]::Min($MAX_PERCENT, [System.Math]::Floor(100 * $stopwatch.Elapsed.TotalSeconds / $EstimatedSeconds)))
            }
        }
        $process.WaitForExit()

        return [PSCustomObject]@{
            ExitCode = $process.ExitCode
            Output   = $outputTask.GetAwaiter().GetResult()
            Error    = $errorTask.GetAwaiter().GetResult()
            Seconds  = [System.Math]::Round($stopwatch.Elapsed.TotalSeconds)
        }
    }
    finally {
        $process.Dispose()
    }
}
