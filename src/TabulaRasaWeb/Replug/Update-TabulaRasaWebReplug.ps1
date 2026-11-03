function Update-TabulaRasaWebReplug {
    <#
    .SYNOPSIS
        Advances the replug confirmation of a USB stick or SD card with the current disk list.

    .DESCRIPTION
        The browser polls, every poll moves the state machine forward:

        > Unplug   Waits until the selected device is gone, then remembers the remaining disks.
        > Plug     Waits for new devices. Exactly one -> Ready, more than one -> Failed.
        > Ready    The device that came back is in Added, the wipe may start.
        > Failed   Timeout or more than one new device, Reason says which.

        Works on a plain hashtable (the Pode state 'Replug'), so it is testable without disks.

    .EXAMPLE
        PS> Update-TabulaRasaWebReplug -Replug $state -Disks @(Get-TabulaRasaDisk)
    #>

    # Only moves an in-memory state machine forward, nothing on disk changes. -WhatIf has no meaning here.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param (
        <#
        [Required]
        The replug state with Target, Phase, Baseline, Added, StartedAt. Changed in place.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.Collections.IDictionary]
        $Replug,

        <#
        [Required]
        The current disks from Get-TabulaRasaDisk. May be empty.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [AllowEmptyCollection()]
        [PSCustomObject[]]
        $Disks,

        <#
        [Optional]
        Seconds the whole replug may take. Default is 120.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [ValidateRange(10, 3600)]
        [System.Int32]
        $TimeoutSeconds = 120,

        <#
        [Optional]
        The current time, injectable for tests. Default is now.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [System.DateTime]
        $Now = [System.DateTime]::UtcNow
    )

    $currentNames = @($Disks | ForEach-Object { $_.Name })

    if ($Replug['Phase'] -IN @('Ready', 'Failed')) {
        return $Replug
    }
    if (($Now - $Replug['StartedAt']).TotalSeconds -GT $TimeoutSeconds) {
        $Replug['Phase']  = 'Failed'
        $Replug['Reason'] = "The device was not replugged within $TimeoutSeconds seconds."
        return $Replug
    }

    # Unplug
    if ($Replug['Phase'] -EQ 'Unplug' -AND $Replug['Target'] -NOTIN $currentNames) {
        Write-Verbose "[Update-TabulaRasaWebReplug] '$($Replug['Target'])' is gone -> waiting for the plug in."
        $Replug['Phase']    = 'Plug'
        $Replug['Baseline'] = $currentNames
        return $Replug
    }

    # Plug
    if ($Replug['Phase'] -EQ 'Plug') {
        $added = @($Disks | Where-Object { $_.Name -NOTIN $Replug['Baseline'] })
        if ($added.Count -EQ 1) {
            Write-Verbose "[Update-TabulaRasaWebReplug] '$($added[0].Name)' came back -> ready."
            $Replug['Phase'] = 'Ready'
            $Replug['Added'] = $added[0]
        }
        elseif ($added.Count -GT 1) {
            $Replug['Phase']  = 'Failed'
            $Replug['Reason'] = "$($added.Count) devices were plugged in, expected exactly one."
        }
    }

    return $Replug
}
