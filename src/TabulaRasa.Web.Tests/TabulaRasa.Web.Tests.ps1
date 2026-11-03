# NOTE:
#   Invoke-Pester -Path ./src/TabulaRasa.Web.Tests
#   Tests the server logic on plain hashtables, no Pode server and no disks needed.

#
#   Chapters:
#     CONTROL SESSION REPLUG AND JOBS   Session lock, replug state machine, job list.
#

# Variables set in BeforeAll are used in the It blocks, the analyzer cannot follow Pester's scopes.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
param ()

# ===========================================================================
# ===================   CONTROL SESSION REPLUG AND JOBS   ===================
# ===========================================================================
#
#   Enter-TabulaRasaWebSession    Grants, refreshes, denies, expires and lets the kiosk take over.
#   Test-TabulaRasaWebSession     Accepts only the owner's live token.
#   Exit-TabulaRasaWebSession     Releases only for the owner.
#   Update-TabulaRasaWebReplug    Unplug -> Plug -> Ready, fails on two devices and on timeout.
#   New-TabulaRasaWebJob          One job at a time, finished jobs are trimmed.
#

BeforeAll {
    . $PSScriptRoot/BeforeAll.ps1
    $T0 = [System.DateTime]::new(2026, 1, 1, 12, 0, 0, [System.DateTimeKind]::Utc)
}

Describe 'Enter-TabulaRasaWebSession' {
    BeforeEach {
        $Session = @{ Token = $null; Address = $null; LastSeen = [System.DateTime]::MinValue }
    }

    It 'grants the first claim' {
        $Result = Enter-TabulaRasaWebSession -Session $Session -ClientAddress '192.168.1.20' -Now $T0
        $Result.IsGranted     | Should -BeTrue
        $Result.Token.Length  | Should -Be 32
        $Session['Address']   | Should -Be '192.168.1.20'
    }

    It 'denies a second device with the owner and the seconds left' {
        $null   = Enter-TabulaRasaWebSession -Session $Session -ClientAddress '192.168.1.20' -Now $T0
        $Result = Enter-TabulaRasaWebSession -Session $Session -ClientAddress '192.168.1.30' -Now $T0.AddSeconds(60)
        $Result.IsGranted    | Should -BeFalse
        $Result.OwnerAddress | Should -Be '192.168.1.20'
        $Result.SecondsLeft  | Should -Be 240
    }

    It 'keeps the token for the owner and refreshes the idle timer' {
        $first  = Enter-TabulaRasaWebSession -Session $Session -ClientAddress '192.168.1.20' -Now $T0
        $Result = Enter-TabulaRasaWebSession -Session $Session -Token $first.Token -ClientAddress '192.168.1.20' -Now $T0.AddSeconds(200)
        $Result.Token        | Should -Be $first.Token
        $Session['LastSeen'] | Should -Be $T0.AddSeconds(200)
    }

    It 'grants another device once the owner was idle too long' {
        $first  = Enter-TabulaRasaWebSession -Session $Session -ClientAddress '192.168.1.20' -Now $T0
        $Result = Enter-TabulaRasaWebSession -Session $Session -ClientAddress '192.168.1.30' -Now $T0.AddSeconds(301)
        $Result.IsGranted | Should -BeTrue
        $Result.Token     | Should -Not -Be $first.Token
    }

    It 'lets the local kiosk take over, but not a remote device' {
        $null = Enter-TabulaRasaWebSession -Session $Session -ClientAddress '192.168.1.20' -Now $T0
        (Enter-TabulaRasaWebSession -Session $Session -ClientAddress '192.168.1.30' -IsTakeover $true -Now $T0).IsGranted | Should -BeFalse
        (Enter-TabulaRasaWebSession -Session $Session -ClientAddress '127.0.0.1' -IsLocal $true -IsTakeover $true -Now $T0).IsGranted | Should -BeTrue
        $Session['Address'] | Should -Be '127.0.0.1'
    }
}

Describe 'Test-TabulaRasaWebSession and Exit-TabulaRasaWebSession' {
    BeforeEach {
        $Session = @{ Token = $null; Address = $null; LastSeen = [System.DateTime]::MinValue }
        $Token   = (Enter-TabulaRasaWebSession -Session $Session -ClientAddress '192.168.1.20' -Now $T0).Token
    }

    It 'accepts the owner token and refuses a foreign or empty one' {
        Test-TabulaRasaWebSession -Session $Session -Token $Token -Now $T0.AddSeconds(10) | Should -BeTrue
        Test-TabulaRasaWebSession -Session $Session -Token 'foreign' -Now $T0           | Should -BeFalse
        Test-TabulaRasaWebSession -Session $Session -Token '' -Now $T0                  | Should -BeFalse
    }

    It 'refuses and clears an expired session' {
        Test-TabulaRasaWebSession -Session $Session -Token $Token -Now $T0.AddSeconds(301) | Should -BeFalse
        $Session['Token'] | Should -BeNullOrEmpty
    }

    It 'releases only for the owner' {
        Exit-TabulaRasaWebSession -Session $Session -Token 'foreign' | Should -BeFalse
        Exit-TabulaRasaWebSession -Session $Session -Token $Token    | Should -BeTrue
        $Session['Token'] | Should -BeNullOrEmpty
    }
}

Describe 'Update-TabulaRasaWebReplug' {
    BeforeAll {
        $sda = [PSCustomObject]@{ Name = 'sda' }
        $sdc = [PSCustomObject]@{ Name = 'sdc' }
        $sdd = [PSCustomObject]@{ Name = 'sdd' }
    }

    BeforeEach {
        $Replug = @{ Phase = 'Unplug'; Target = 'sdc'; Baseline = @(); Added = $null; Reason = $null; StartedAt = $T0 }
    }

    It 'walks Unplug -> Plug -> Ready and takes the device that came back' {
        (Update-TabulaRasaWebReplug -Replug $Replug -Disks @($sda, $sdc) -Now $T0.AddSeconds(1))['Phase'] | Should -Be 'Unplug'
        (Update-TabulaRasaWebReplug -Replug $Replug -Disks @($sda) -Now $T0.AddSeconds(2))['Phase']       | Should -Be 'Plug'
        (Update-TabulaRasaWebReplug -Replug $Replug -Disks @($sda) -Now $T0.AddSeconds(3))['Phase']       | Should -Be 'Plug'
        (Update-TabulaRasaWebReplug -Replug $Replug -Disks @($sda, $sdd) -Now $T0.AddSeconds(4))['Phase'] | Should -Be 'Ready'
        $Replug['Added'].Name | Should -Be 'sdd'
    }

    It 'fails when two devices are plugged in' {
        $null = Update-TabulaRasaWebReplug -Replug $Replug -Disks @() -Now $T0.AddSeconds(1)
        $null = Update-TabulaRasaWebReplug -Replug $Replug -Disks @($sdc, $sdd) -Now $T0.AddSeconds(2)
        $Replug['Phase']  | Should -Be 'Failed'
        $Replug['Reason'] | Should -BeLike '2 devices*'
    }

    It 'fails after the timeout' {
        $null = Update-TabulaRasaWebReplug -Replug $Replug -Disks @($sdc) -Now $T0.AddSeconds(121)
        $Replug['Phase'] | Should -Be 'Failed'
    }
}

Describe 'New-TabulaRasaWebJob' {
    It 'registers a running job' {
        $jobs = @{}
        $Job  = New-TabulaRasaWebJob -Jobs $jobs -Type DeepScan -DiskName sdb
        $Job['Status']   | Should -Be 'Running'
        $Job['Id'].Length | Should -Be 12
        $jobs.Count      | Should -Be 1
    }

    It 'refuses a second job while one runs' {
        $jobs = @{}
        $null = New-TabulaRasaWebJob -Jobs $jobs -Type DeepScan -DiskName sdb
        New-TabulaRasaWebJob -Jobs $jobs -Type Overview -DiskName sdc | Should -BeNullOrEmpty
    }

    It 'keeps at most 20 finished jobs' {
        $jobs = @{}
        for ($index = 0; $index -LT 25; $index++) {
            $job = New-TabulaRasaWebJob -Jobs $jobs -Type Overview -DiskName sdb
            $job['Status']    = 'Done'
            $job['StartedAt'] = $T0.AddSeconds($index)
        }
        $jobs.Count | Should -BeLessOrEqual 20
    }
}
