# NOTE:
#   Requires: nothing, works on a plain hashtable (the Pode state 'Jobs').
#
#   $job = New-TabulaRasaWebJob -Jobs $jobs -Type DeepScan -DiskName sdb
#   $job = New-TabulaRasaWebJob -Jobs $jobs -Type Deleted -DiskName sdb -PartitionName sdb1

#
#   Chapters:
#     REGISTER THE JOB   Refuses a second job, prunes old ones, adds the new one.
#

function New-TabulaRasaWebJob {
    <#
    .SYNOPSIS
        Registers a job in the job list and returns it, or returns $null while another job runs.

    .DESCRIPTION
        Only one job runs at a time: a scan next to a wipe of the same disk would read garbage,
        and two wipes would fight for the bus. The caller starts the Pode task for the returned job.

        Works on a plain hashtable (the Pode state 'Jobs'), so it is testable without a server.

    .EXAMPLE
        PS> $job = New-TabulaRasaWebJob -Jobs $jobs -Type DeepScan -DiskName sdb
    #>

    # Only adds an entry to an in-memory list, nothing on disk changes. -WhatIf has no meaning here.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param (
        <#
        [Required]
        The job list, id -> job. Changed in place.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.Collections.IDictionary]
        $Jobs,

        <#
        [Required]
        The job type, see Invoke-TabulaRasaWebJob.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [ValidateSet('Overview', 'Deleted', 'DeepScan', 'Wipe')]
        [System.String]
        $Type,

        <#
        [Required]
        The kernel name of the disk, e.g. 'sdb'.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.String]
        $DiskName,

        <#
        [Optional]
        The kernel name of the partition, required for Deleted.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [AllowEmptyString()]
        [System.String]
        $PartitionName = ''
    )

    $MAX_FINISHED_JOBS = 20

    # ===========================================================================
    # ==========================   REGISTER THE JOB   ===========================
    # ===========================================================================
    #
    #   1. One at a time   Refuses while another job runs.
    #   2. Prune           Keeps the list short: the oldest finished jobs go first.
    #   3. Register        Adds the new running job and returns it.
    #

    # ---------------------------------------------------------------------------
    # One at a time
    #   Refuses while another job runs.
    # ---------------------------------------------------------------------------

    if (@($Jobs.Values | Where-Object { $_['Status'] -EQ 'Running' }).Count -GT 0) {
        Write-Verbose "[New-TabulaRasaWebJob] Another job is running -> refusing '$Type' on '$DiskName'."
        return $null
    }

    # ---------------------------------------------------------------------------
    # Prune
    #   Keeps the list short: the oldest finished jobs go first.
    # ---------------------------------------------------------------------------

    $finished = @($Jobs.Values | Where-Object { $_['Status'] -NE 'Running' } | Sort-Object -Property { $_['StartedAt'] })
    foreach ($old in $finished | Select-Object -First ([System.Math]::Max(0, $finished.Count - $MAX_FINISHED_JOBS + 1))) {
        $Jobs.Remove($old['Id'])
    }

    # ---------------------------------------------------------------------------
    # Register
    #   Adds the new running job and returns it.
    # ---------------------------------------------------------------------------

    $Job = [System.Collections.Hashtable]::Synchronized(@{
        Id                = [System.Guid]::NewGuid().ToString('N').Substring(0, 12)
        Type              = $Type
        DiskName          = $DiskName
        PartitionName     = $PartitionName
        Status            = 'Running'
        Percent           = 0
        Hits              = @()
        Result            = $null
        Error             = $null
        IsCancelRequested = $false
        StartedAt         = [System.DateTime]::UtcNow
        EndedAt           = $null
    })
    $Jobs[$Job['Id']] = $Job

    return $Job
}
