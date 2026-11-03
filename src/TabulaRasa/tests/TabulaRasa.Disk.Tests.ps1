# NOTE:
#   Invoke-Pester -Path ./src/TabulaRasa/tests
#   Runs on Windows and Linux, nothing here touches a real disk.

# Variables set in BeforeAll are used in the It blocks, the analyzer cannot follow Pester's scopes.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
param ()

# ===========================================================================
# ==================   DETECT DISKS AND PICK WIPE METHOD   ==================
# ===========================================================================
#
#   Resolve-TabulaRasaDiskKind     Maps name, transport and rotation to a kind.
#   ConvertFrom-TabulaRasaLsblk    Parses lsblk JSON, skips non-disks, reads both flag formats.
#   Resolve-TabulaRasaWipeMethod   Maps every kind to its method, confirmation and warning.
#   Compare-TabulaRasaDiskSet      Finds added and removed disks for the replug confirmation.
#

BeforeAll {
    . $PSScriptRoot/BeforeAll.ps1
}

Describe 'Resolve-TabulaRasaDiskKind' {
    It 'resolves <Name> over <Transport> (rotational: <IsRotational>) to <Expected>' -ForEach @(
        @{ Name = 'mmcblk0'; Transport = '';     IsRotational = $false; Expected = 'SdCard' }
        @{ Name = 'sdc';     Transport = 'usb';  IsRotational = $false; Expected = 'Usb' }
        @{ Name = 'sdc';     Transport = 'usb';  IsRotational = $true;  Expected = 'Usb' }
        @{ Name = 'nvme0n1'; Transport = 'nvme'; IsRotational = $false; Expected = 'Nvme' }
        @{ Name = 'sda';     Transport = 'sata'; IsRotational = $true;  Expected = 'Hdd' }
        @{ Name = 'sda';     Transport = 'sata'; IsRotational = $false; Expected = 'SataSsd' }
        @{ Name = 'vda';     Transport = '';     IsRotational = $false; Expected = 'Unknown' }
    ) {
        InModuleScope TabulaRasa -Parameters $_ {
            Resolve-TabulaRasaDiskKind -Name $Name -Transport $Transport -IsRotational $IsRotational
            | Should -Be $Expected
        }
    }
}

Describe 'ConvertFrom-TabulaRasaLsblk' {
    BeforeAll {
        $LsblkJson = @'
{
   "blockdevices": [
      {"name": "loop0", "path": "/dev/loop0", "type": "loop", "size": 1048576, "model": null, "serial": null, "tran": null, "rota": false, "rm": false},
      {"name": "zram0", "path": "/dev/zram0", "type": "disk", "size": 1048576, "model": null, "serial": null, "tran": null, "rota": false, "rm": false},
      {"name": "sr0", "path": "/dev/sr0", "type": "rom", "size": 1048576, "model": "DVD", "serial": "X", "tran": "sata", "rota": true, "rm": true},
      {"name": "sda", "path": "/dev/sda", "type": "disk", "size": 500107862016, "model": "Samsung SSD 870 EVO 500GB ", "serial": "S5Y1NX0R ", "tran": "sata", "rota": false, "rm": false},
      {"name": "sdb", "path": "/dev/sdb", "type": "disk", "size": 1000204886016, "model": "WDC WD10EZEX", "serial": "WD-WCC6Y", "tran": "sata", "rota": "1", "rm": "0"},
      {"name": "sdc", "path": "/dev/sdc", "type": "disk", "size": 0, "model": "Card Reader", "serial": "", "tran": "usb", "rota": false, "rm": true}
   ]
}
'@
        $Disks = InModuleScope TabulaRasa -Parameters @{ Json = $LsblkJson } {
            ConvertFrom-TabulaRasaLsblk -Json $Json
        }
    }

    It 'keeps only real disks with a size' {
        $Disks.Name | Should -Be @('sda', 'sdb')
    }

    It 'trims model and serial' {
        $Disks[0].Model  | Should -Be 'Samsung SSD 870 EVO 500GB'
        $Disks[0].Serial | Should -Be 'S5Y1NX0R'
    }

    It 'reads JSON booleans and "0"/"1" flags' {
        $Disks[0].Kind | Should -Be 'SataSsd'
        $Disks[1].Kind | Should -Be 'Hdd'
        $Disks[1].IsRemovable | Should -BeFalse
    }
}

Describe 'Resolve-TabulaRasaWipeMethod' {
    It 'picks <Method> with <Confirmation> for <Kind>, complete: <IsComplete>' -ForEach @(
        @{ Kind = 'Hdd';     Method = 'Overwrite';      Confirmation = 'Serial'; IsComplete = $true }
        @{ Kind = 'SataSsd'; Method = 'AtaSecureErase'; Confirmation = 'Serial'; IsComplete = $true }
        @{ Kind = 'Nvme';    Method = 'NvmeSanitize';   Confirmation = 'Serial'; IsComplete = $true }
        @{ Kind = 'Usb';     Method = 'Overwrite';      Confirmation = 'Replug'; IsComplete = $false }
        @{ Kind = 'SdCard';  Method = 'Overwrite';      Confirmation = 'Replug'; IsComplete = $false }
        @{ Kind = 'Unknown'; Method = 'Overwrite';      Confirmation = 'Serial'; IsComplete = $false }
    ) {
        $WipeInfo = Resolve-TabulaRasaWipeMethod -Kind $Kind
        $WipeInfo.Method       | Should -Be $Method
        $WipeInfo.Confirmation | Should -Be $Confirmation
        $WipeInfo.IsComplete   | Should -Be $IsComplete
        ($null -NE $WipeInfo.Warning) | Should -Be (-NOT $IsComplete)
    }
}

Describe 'Compare-TabulaRasaDiskSet' {
    It 'finds the unplugged and the plugged in disk by name' {
        $before = @([PSCustomObject]@{ Name = 'sda' }, [PSCustomObject]@{ Name = 'sdc' })
        $after  = @([PSCustomObject]@{ Name = 'sda' }, [PSCustomObject]@{ Name = 'sdd' })

        $Result = Compare-TabulaRasaDiskSet -Before $before -After $after
        $Result.Removed.Name | Should -Be 'sdc'
        $Result.Added.Name   | Should -Be 'sdd'
    }

    It 'handles an empty list before the replug' {
        $Result = Compare-TabulaRasaDiskSet -Before @() -After @([PSCustomObject]@{ Name = 'sdc' })
        $Result.Added.Name    | Should -Be 'sdc'
        $Result.Removed.Count | Should -Be 0
    }
}

Describe 'Invoke-TabulaRasaWipe' {
    It 'touches nothing with -WhatIf' {
        { Invoke-TabulaRasaWipe -Path '/dev/null-test' -Method Overwrite -WhatIf } | Should -Not -Throw
    }

    It 'throws NotImplementedException while the methods are scaffolded' {
        { Invoke-TabulaRasaWipe -Path '/dev/null-test' -Method Overwrite -Confirm:$false }
        | Should -Throw -ExceptionType ([System.NotImplementedException])
    }
}
