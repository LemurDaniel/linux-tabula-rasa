function Invoke-TabulaRasaWebJob {
    <#
    .SYNOPSIS
        Runs one long job of the web UI and writes progress, result or error into the job.

    .DESCRIPTION
        Runs inside a Pode task, the browser polls the job via GET /api/jobs/:id.

        > Overview   Get-TabulaRasaDataOverview
        > Deleted    Get-TabulaRasaDeletedFile for one partition
        > DeepScan   Find-TabulaRasaFileSignature -Mode Deep, stops when IsCancelRequested is set
        > Wipe       Invoke-TabulaRasaWipe with the method of the disk kind

        The disk is resolved again by name: between the request and the start it may be gone.
        Status ends as Done, Cancelled or Failed (Error holds the message).

    .EXAMPLE
        PS> $job = @{ Id = 'a1'; Type = 'DeepScan'; DiskName = 'sdb'; Status = 'Running'; Percent = 0; IsCancelRequested = $false }
        PS> Invoke-TabulaRasaWebJob -Job $job
    #>

    # Wipe confirmation happens in the route (serial) or the replug state machine before the job exists.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param (
        <#
        [Required]
        The job with Type, DiskName, PartitionName (Deleted only), Status, Percent, IsCancelRequested.
        Changed in place.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.Collections.IDictionary]
        $Job
    )

    try {
        $Disk = Get-TabulaRasaDisk | Where-Object -Property Name -EQ -Value $Job['DiskName']
        if ($null -EQ $Disk) {
            throw [System.InvalidOperationException]::new("Disk '$($Job['DiskName'])' must still be plugged in.")
        }

        Write-Verbose "[Invoke-TabulaRasaWebJob] Job '$($Job['Id'])': $($Job['Type']) on '$($Disk.Path)'."
        switch ($Job['Type']) {
            'Overview' {
                $Job['Result'] = Get-TabulaRasaDataOverview -Disk $Disk
            }
            'Deleted' {
                $partition = Get-TabulaRasaPartition -Path $Disk.Path | Where-Object -Property Name -EQ -Value $Job['PartitionName']
                if ($null -EQ $partition) {
                    throw [System.InvalidOperationException]::new("Partition '$($Job['PartitionName'])' must exist on '$($Disk.Path)'.")
                }
                $Job['Result'] = Get-TabulaRasaDeletedFile -Path $partition.Path
            }
            'DeepScan' {
                # Closure: the callback runs inside the TabulaRasa module and still needs this $Job.
                $onProgress = {
                    param ($Percent, $Hits)
                    $Job['Percent'] = $Percent
                    $Job['Hits']    = $Hits
                    return -NOT $Job['IsCancelRequested']
                }.GetNewClosure()
                $Job['Result'] = Find-TabulaRasaFileSignature -Path $Disk.Path -SizeBytes $Disk.SizeBytes -Mode Deep -OnProgress $onProgress
                if ($Job['Result'].IsCancelled) {
                    $Job['Status'] = 'Cancelled'
                    return
                }
            }
            'Wipe' {
                $method = (Resolve-TabulaRasaWipeMethod -Kind $Disk.Kind).Method
                Invoke-TabulaRasaWipe -Path $Disk.Path -Method $method -Confirm:$false
                $Job['Result'] = [PSCustomObject]@{ Path = $Disk.Path; Method = $method }
            }
            default {
                throw [System.ArgumentException]::new("Job type '$($Job['Type'])' must be one of: Overview, Deleted, DeepScan, Wipe.")
            }
        }

        $Job['Percent'] = 100
        $Job['Status']  = 'Done'
    }
    catch {
        # Reported to the browser instead of rethrown: the task has no caller that could show it.
        Write-Verbose "[Invoke-TabulaRasaWebJob] Job '$($Job['Id'])' failed: $($_.Exception.Message)"
        $Job['Error']  = $_.Exception.Message
        $Job['Status'] = 'Failed'
    }
    finally {
        $Job['EndedAt'] = [System.DateTime]::UtcNow
    }
}
