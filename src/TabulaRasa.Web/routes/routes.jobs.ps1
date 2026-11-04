# NOTE:
#   Loaded by Use-PodeRoutes in Start-TabulaRasaServer. All routes need the session token.
#
#   POST   /api/jobs       { type, disk, partition?, serial? }   Starts a job, answers { id }.
#   GET    /api/jobs       The running jobs, so a reloaded page or another device resumes them.
#   GET    /api/jobs/:id   Status, percent, hits and result of a job.
#   DELETE /api/jobs/:id   Asks a running deep scan to stop.

#
#   Chapters:
#     JOB ROUTES   Start, poll and cancel the long jobs.
#

# ===========================================================================
# =============================   JOB ROUTES   ==============================
# ===========================================================================
#
#   POST /api/jobs       Validates the request, registers the job, starts the task.
#   GET /api/jobs        Lists the running jobs.
#   GET /api/jobs/:id    Returns the job as the browser polls it.
#   DELETE /api/jobs/:id Sets IsCancelRequested, the deep scan stops at the next percent.
#

Add-PodeRoute -Method Post -Path '/api/jobs' -ScriptBlock {
    $Request = $WebEvent.Data
    $Disk    = Resolve-TabulaRasaWebDisk -Name ([System.String] $Request.disk)
    if ($null -EQ $Disk) {
        Write-TabulaRasaWebError -StatusCode 404 -Message "Disk '$($Request.disk)' must be plugged in."
        return
    }

    # Validations per job type
    $type = [System.String] $Request.type
    if ($type -NOTIN @('Overview', 'Deleted', 'DeepScan', 'Wipe')) {
        Write-TabulaRasaWebError -StatusCode 400 -Message "Job type '$type' must be one of: Overview, Deleted, DeepScan, Wipe."
        return
    }
    if ($type -EQ 'Deleted' -AND [System.String]::IsNullOrEmpty($Request.partition)) {
        Write-TabulaRasaWebError -StatusCode 400 -Message "Job type 'Deleted' needs a 'partition'."
        return
    }
    if ($type -EQ 'Wipe') {
        # The browser sends the serial it showed: a different disk under the same name (swapped
        # in the meantime) is refused. USB and SD go through /api/replug.
        $wipeInfo = Resolve-TabulaRasaWipeMethod -Kind $Disk.Kind
        if ($wipeInfo.Confirmation -NE 'Serial') {
            Write-TabulaRasaWebError -StatusCode 400 -Message "Disk '$($Disk.Name)' is confirmed by replugging, use /api/replug."
            return
        }
        $confirmToken = [System.String]::IsNullOrEmpty($Disk.Serial) ? $Disk.Path : $Disk.Serial
        if ([System.String] $Request.serial -CNE $confirmToken) {
            Write-TabulaRasaWebError -StatusCode 409 -Message 'The disk changed since the page showed it, nothing was wiped. Reload the disks.'
            return
        }
    }

    $jobs = Get-PodeState -Name 'Jobs'
    $Job  = Lock-PodeObject -Object $jobs -Return -ScriptBlock {
        New-TabulaRasaWebJob -Jobs $jobs -Type $type -DiskName $Disk.Name -PartitionName ([System.String] $Request.partition)
    }
    if ($null -EQ $Job) {
        $running = @($jobs.Values | Where-Object { $_['Status'] -EQ 'Running' })[0]
        Write-TabulaRasaWebError -StatusCode 409 -Message "Only one job runs at a time: '$($running['Type'])' on '$($running['DiskName'])' is still running. Open that disk to follow or stop it."
        return
    }

    $null = Invoke-PodeTask -Name 'RunJob' -ArgumentList @{ JobId = $Job['Id'] }
    Write-PodeJsonResponse -StatusCode 202 -Value @{ id = $Job['Id'] }
}

Add-PodeRoute -Method Get -Path '/api/jobs' -ScriptBlock {
    $running = @((Get-PodeState -Name 'Jobs').Values | Where-Object { $_['Status'] -EQ 'Running' })
    Write-PodeJsonResponse -Value @{
        jobs = @($running | ForEach-Object {
                @{ id = $_['Id']; type = $_['Type']; disk = $_['DiskName']; partition = $_['PartitionName'] }
            })
    }
}

Add-PodeRoute -Method Get -Path '/api/jobs/:id' -ScriptBlock {
    $Job = (Get-PodeState -Name 'Jobs')[$WebEvent.Parameters['id']]
    if ($null -EQ $Job) {
        Write-TabulaRasaWebError -StatusCode 404 -Message "Job '$($WebEvent.Parameters['id'])' must exist, finished jobs are kept for a while only."
        return
    }

    Write-PodeJsonResponse -Depth 8 -Value @{
        id        = $Job['Id']
        type      = $Job['Type']
        disk      = $Job['DiskName']
        partition = $Job['PartitionName']
        status    = $Job['Status']
        percent   = $Job['Percent']
        hits      = @($Job['Hits'])
        result    = $Job['Result']
        error     = $Job['Error']
    }
}

Add-PodeRoute -Method Delete -Path '/api/jobs/:id' -ScriptBlock {
    $Job = (Get-PodeState -Name 'Jobs')[$WebEvent.Parameters['id']]
    if ($null -EQ $Job) {
        Write-TabulaRasaWebError -StatusCode 404 -Message "Job '$($WebEvent.Parameters['id'])' must exist."
        return
    }
    $Job['IsCancelRequested'] = $true
    Write-PodeJsonResponse -StatusCode 202 -Value @{ id = $Job['Id']; isCancelRequested = $true }
}
