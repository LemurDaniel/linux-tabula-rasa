# NOTE:
#   Loaded by Use-PodeRoutes in Start-TabulaRasaServer. All routes need the session token.
#
#   POST   /api/replug           { disk }   Starts the replug confirmation of a USB stick or SD card.
#   GET    /api/replug           Advances and returns the state (poll every second).
#   POST   /api/replug/confirm   Starts the wipe of the device that came back, answers { id }.
#   DELETE /api/replug           Aborts the replug.

#
#   Chapters:
#     REPLUG ROUTES   The physical confirmation of USB sticks and SD cards.
#

# ===========================================================================
# ============================   REPLUG ROUTES   ============================
# ===========================================================================
#
#   POST /api/replug           Resets the state to Unplug for the selected device.
#   GET /api/replug            Runs Update-TabulaRasaWebReplug with the current disks.
#   POST /api/replug/confirm   Only in phase Ready: registers the wipe job.
#   DELETE /api/replug         Back to Idle.
#

Add-PodeRoute -Method Post -Path '/api/replug' -ScriptBlock {
    $Disk = Resolve-TabulaRasaWebDisk -Name ([System.String] $WebEvent.Data.disk)
    if ($null -EQ $Disk) {
        Write-TabulaRasaWebError -StatusCode 404 -Message "Disk '$($WebEvent.Data.disk)' must be plugged in."
        return
    }
    if ((Resolve-TabulaRasaWipeMethod -Kind $Disk.Kind).Confirmation -NE 'Replug') {
        Write-TabulaRasaWebError -StatusCode 400 -Message "Disk '$($Disk.Name)' is confirmed by its serial, use /api/jobs."
        return
    }

    $replug = Get-PodeState -Name 'Replug'
    Lock-PodeObject -Object $replug -ScriptBlock {
        $replug['Phase']     = 'Unplug'
        $replug['Target']    = $Disk.Name
        $replug['Baseline']  = @()
        $replug['Added']     = $null
        $replug['Reason']    = $null
        $replug['StartedAt'] = [System.DateTime]::UtcNow
    }
    Write-PodeJsonResponse -Value @{ phase = 'Unplug'; target = $Disk.Name }
}

Add-PodeRoute -Method Get -Path '/api/replug' -ScriptBlock {
    $replug = Get-PodeState -Name 'Replug'
    $disks  = @(Get-TabulaRasaDisk)
    $null = Lock-PodeObject -Object $replug -Return -ScriptBlock {
        if ($replug['Phase'] -NE 'Idle') {
            Update-TabulaRasaWebReplug -Replug $replug -Disks $disks
        }
    }
    Write-PodeJsonResponse -Depth 4 -Value @{
        phase  = $replug['Phase']
        target = $replug['Target']
        added  = $replug['Added']
        reason = $replug['Reason']
    }
}

Add-PodeRoute -Method Post -Path '/api/replug/confirm' -ScriptBlock {
    $replug = Get-PodeState -Name 'Replug'
    if ($replug['Phase'] -NE 'Ready') {
        Write-TabulaRasaWebError -StatusCode 409 -Message "The replug must be in phase 'Ready', it is in '$($replug['Phase'])'."
        return
    }

    $added = $replug['Added']
    $jobs  = Get-PodeState -Name 'Jobs'
    $Job   = Lock-PodeObject -Object $jobs -Return -ScriptBlock {
        New-TabulaRasaWebJob -Jobs $jobs -Type Wipe -DiskName $added.Name
    }
    if ($null -EQ $Job) {
        Write-TabulaRasaWebError -StatusCode 409 -Message 'Another job is still running, wait for it or cancel it.'
        return
    }

    $replug['Phase'] = 'Idle'
    $null = Invoke-PodeTask -Name 'RunJob' -ArgumentList @{ JobId = $Job['Id'] }
    Write-PodeJsonResponse -StatusCode 202 -Value @{ id = $Job['Id'] }
}

Add-PodeRoute -Method Delete -Path '/api/replug' -ScriptBlock {
    (Get-PodeState -Name 'Replug')['Phase'] = 'Idle'
    Write-PodeJsonResponse -Value @{ phase = 'Idle' }
}
