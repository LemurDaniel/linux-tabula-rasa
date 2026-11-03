# NOTE:
#   Loaded by Use-PodeRoutes in Start-TabulaRasaServer. All routes need the session token.
#
#   POST   /api/jobs       { type, disk, partition?, serial? }   Starts a job, answers { id }.
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
        # The serial is the confirmation, see Resolve-TabulaRasaWipeMethod. USB and SD go through /api/replug.
        $wipeInfo = Resolve-TabulaRasaWipeMethod -Kind $Disk.Kind
        if ($wipeInfo.Confirmation -NE 'Serial') {
            Write-TabulaRasaWebError -StatusCode 400 -Message "Disk '$($Disk.Name)' is confirmed by replugging, use /api/replug."
            return
        }
        $confirmToken = [System.String]::IsNullOrEmpty($Disk.Serial) ? $Disk.Path : $Disk.Serial
        if ([System.String] $Request.serial -CNE $confirmToken) {
            Write-TabulaRasaWebError -StatusCode 403 -Message 'The serial does not match the disk, nothing was wiped.'
            return
        }
    }

    $jobs = Get-PodeState -Name 'Jobs'
    $Job  = Lock-PodeObject -Object $jobs -Return -ScriptBlock {
        New-TabulaRasaWebJob -Jobs $jobs -Type $type -DiskName $Disk.Name -PartitionName ([System.String] $Request.partition)
    }
    if ($null -EQ $Job) {
        Write-TabulaRasaWebError -StatusCode 409 -Message 'Another job is still running, wait for it or cancel it.'
        return
    }

    $null = Invoke-PodeTask -Name 'RunJob' -ArgumentList @{ JobId = $Job['Id'] }
    Write-PodeJsonResponse -StatusCode 202 -Value @{ id = $Job['Id'] }
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
