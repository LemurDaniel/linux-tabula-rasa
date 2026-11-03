# NOTE:
#   Invoke-Pester -Path ./src/TabulaRasa.Tests
#   Parsers run on recorded tool output, the overwrite on an image file. No real disk is touched.

#
#   Chapters:
#     WIPE THE DISKS   hdparm and nvme parsers, overwrite, process wait.
#

# Variables set in BeforeAll are used in the It blocks, the analyzer cannot follow Pester's scopes.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
param ()

# ===========================================================================
# ===========================   WIPE THE DISKS   ============================
# ===========================================================================
#
#   ConvertFrom-TabulaRasaHdparmSecurity    Reads frozen, enabled, enhanced and the minutes.
#   ConvertFrom-TabulaRasaNvmeController    Reads the sanitize and format capabilities.
#   ConvertFrom-TabulaRasaNvmeSanitizeLog   Reads status and progress in flat and nested shape.
#   Invoke-TabulaRasaOverwrite              Zeroes an image completely, also an odd size.
#   Wait-TabulaRasaProcess                  Returns exit code and output, reports progress.
#   Invoke-TabulaRasaWipe                   Touches nothing with -WhatIf.
#

BeforeAll {
    . $PSScriptRoot/BeforeAll.ps1
}

Describe 'ConvertFrom-TabulaRasaHdparmSecurity' {
    BeforeAll {
        # Cut from 'hdparm -I' of a SATA SSD, tabs as hdparm prints them.
        $FrozenDrive = @(
            'Commands/features:'
            "`tEnabled`tSupported:"
            "`t   *`tSMART feature set"
            'Security: '
            "`tMaster password revision code = 65534"
            "`t`tsupported"
            "`tnot`tenabled"
            "`tnot`tlocked"
            "`t`tfrozen"
            "`tnot`texpired: security count"
            "`t`tsupported: enhanced erase"
            "`t2min for SECURITY ERASE UNIT. 4min for ENHANCED SECURITY ERASE UNIT."
            'Logical Unit WWN Device Identifier: 5002538e40a0c0f1'
        )
    }

    It 'reads a frozen drive with enhanced erase and both durations' {
        $Security = InModuleScope TabulaRasa -Parameters @{ Text = $FrozenDrive } { $Text | ConvertFrom-TabulaRasaHdparmSecurity }
        $Security.IsSupported          | Should -BeTrue
        $Security.IsEnabled            | Should -BeFalse
        $Security.IsLocked             | Should -BeFalse
        $Security.IsFrozen             | Should -BeTrue
        $Security.IsEnhancedSupported  | Should -BeTrue
        $Security.EraseMinutes         | Should -Be 2
        $Security.EnhancedEraseMinutes | Should -Be 4
    }

    It 'reads a not frozen drive without enhanced erase and a ">508min" duration' {
        $text = @(
            'Security: '
            "`t`tsupported"
            "`tnot`tenabled"
            "`tnot`tlocked"
            "`tnot`tfrozen"
            "`t>508min for SECURITY ERASE UNIT."
        )
        $Security = InModuleScope TabulaRasa -Parameters @{ Text = $text } { $Text | ConvertFrom-TabulaRasaHdparmSecurity }
        $Security.IsFrozen             | Should -BeFalse
        $Security.IsEnhancedSupported  | Should -BeFalse
        $Security.EraseMinutes         | Should -Be 508
        $Security.EnhancedEraseMinutes | Should -BeNullOrEmpty
    }

    It 'reports nothing supported for a drive without a Security section' {
        $Security = InModuleScope TabulaRasa { @('Model Number: USB bridge', 'Serial Number: 123') | ConvertFrom-TabulaRasaHdparmSecurity }
        $Security.IsSupported | Should -BeFalse
    }
}

Describe 'ConvertFrom-TabulaRasaNvmeController' {
    It 'reads sanicap <Sanicap> and fna <Fna>' -ForEach @(
        @{ Sanicap = 3; Fna = 4; Crypto = $true;  Block = $true;  Overwrite = $false; FormatCrypto = $true }
        @{ Sanicap = 2; Fna = 0; Crypto = $false; Block = $true;  Overwrite = $false; FormatCrypto = $false }
        @{ Sanicap = 0; Fna = 4; Crypto = $false; Block = $false; Overwrite = $false; FormatCrypto = $true }
        @{ Sanicap = 7; Fna = 7; Crypto = $true;  Block = $true;  Overwrite = $true;  FormatCrypto = $true }
    ) {
        $json = "{ ""vid"": 5197, ""sanicap"": $Sanicap, ""fna"": $Fna }"
        $Capability = InModuleScope TabulaRasa -Parameters @{ Json = $json } { ConvertFrom-TabulaRasaNvmeController -Json $Json }
        $Capability.IsCryptoErase       | Should -Be $Crypto
        $Capability.IsBlockErase        | Should -Be $Block
        $Capability.IsOverwrite         | Should -Be $Overwrite
        $Capability.IsFormatCryptoErase | Should -Be $FormatCrypto
    }
}

Describe 'ConvertFrom-TabulaRasaNvmeSanitizeLog' {
    It 'reads <Name>' -ForEach @(
        @{ Name = 'flat, in progress';           Json = '{ "sprog": 32768, "sstat": 2 }';                                 Status = 'InProgress'; Percent = 50 }
        @{ Name = 'flat, success with flags';    Json = '{ "sprog": 65535, "sstat": 257 }';                               Status = 'Success';    Percent = 100 }
        @{ Name = 'nested, object status';       Json = '{ "nvme0": { "sprog": 65535, "sstat": { "status": 1 } } }';      Status = 'Success';    Percent = 100 }
        @{ Name = 'nested, failed';              Json = '{ "nvme0": { "sprog": 0, "sstat": 3 } }';                         Status = 'Failed';     Percent = 0 }
        @{ Name = 'no deallocate counts as done'; Json = '{ "sprog": 65535, "sstat": 4 }';                                Status = 'Success';    Percent = 100 }
    ) {
        $Log = InModuleScope TabulaRasa -Parameters @{ Json = $Json } { ConvertFrom-TabulaRasaNvmeSanitizeLog -Json $Json }
        $Log.Status  | Should -Be $Status
        $Log.Percent | Should -Be $Percent
    }

    It 'refuses a log without sstat' {
        { InModuleScope TabulaRasa { ConvertFrom-TabulaRasaNvmeSanitizeLog -Json '{ "nvme0": { "other": 1 } }' } }
        | Should -Throw -ExceptionType ([System.IO.InvalidDataException])
    }
}

Describe 'Invoke-TabulaRasaOverwrite' {
    It 'zeroes an image of an odd size completely and reports the progress' {
        $sizeBytes = 9MB + 1536   # more than two chunks, not a multiple of the chunk size
        $image     = Join-Path -Path $TestDrive -ChildPath 'overwrite.img'
        $bytes     = [System.Byte[]]::new($sizeBytes)
        [System.Random]::new(11).NextBytes($bytes)
        [System.IO.File]::WriteAllBytes($image, $bytes)

        $percents = [System.Collections.Generic.List[System.Int32]]::new()
        $Result = InModuleScope TabulaRasa -Parameters @{ Image = $image; Size = $sizeBytes; Percents = $percents } {
            Invoke-TabulaRasaOverwrite -Path $Image -SizeBytes $Size -OnProgress { param ($Percent) $Percents.Add($Percent) }
        }

        $Result.BytesWritten | Should -Be $sizeBytes
        (Get-Item -Path $image).Length | Should -Be $sizeBytes
        [System.Linq.Enumerable]::SequenceEqual([System.IO.File]::ReadAllBytes($image), [System.Byte[]]::new($sizeBytes)) | Should -BeTrue
        $percents[-1] | Should -Be 100
    }
}

Describe 'Wait-TabulaRasaProcess' {
    It 'returns exit code and output and reports an estimated progress' {
        $pwsh     = (Get-Process -Id $PID).Path
        $percents = [System.Collections.Generic.List[System.Int32]]::new()
        $Result = InModuleScope TabulaRasa -Parameters @{ Pwsh = $pwsh; Percents = $percents } {
            $WaitCall = @{
                FilePath         = $Pwsh
                ArgumentList     = @('-NoProfile', '-Command', "Start-Sleep -Milliseconds 2500; 'done'; exit 3")
                EstimatedSeconds = 2
                OnProgress       = { param ($Percent) $Percents.Add($Percent) }
            }
            Wait-TabulaRasaProcess @WaitCall
        }

        $Result.ExitCode       | Should -Be 3
        $Result.Output.Trim()  | Should -Be 'done'
        $percents.Count        | Should -BeGreaterThan 0
        ($percents | Measure-Object -Maximum).Maximum | Should -BeLessOrEqual 99
    }
}

Describe 'Invoke-TabulaRasaWipe' {
    It 'touches nothing with -WhatIf' {
        { Invoke-TabulaRasaWipe -Path '/dev/null-test' -Method Overwrite -WhatIf } | Should -Not -Throw
    }
}
