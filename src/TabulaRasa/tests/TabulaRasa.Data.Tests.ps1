# NOTE:
#   Invoke-Pester -Path ./src/TabulaRasa/tests
#   Works on image files instead of disks. Get-TabulaRasaDirectory needs Linux paths, it is skipped elsewhere.

# Variables set in BeforeAll are used in the It blocks, the analyzer cannot follow Pester's scopes.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
param ()

# ===========================================================================
# ======================   INSPECT DATA ON THE DISK   =======================
# ===========================================================================
#
#   Get-TabulaRasaSampleOffset              Spreads aligned offsets, first and last block included.
#   Test-TabulaRasaDiskData                 Counts non-zero sample blocks in an image.
#   ConvertFrom-TabulaRasaPartitionLsblk    Partitions, or the disk itself as superfloppy.
#   ConvertFrom-TabulaRasaFlsBody           Deleted files from fls body lines, folders skipped.
#   Find-TabulaRasaFileSignature            Counts headers at sector starts, Quick, Deep, cancel.
#   Get-TabulaRasaDirectory                 Lists folders first, refuses '..' and links.
#   Format-TabulaRasaSize                   Decimal units as on disk labels.
#

BeforeAll {
    . $PSScriptRoot/BeforeAll.ps1
}

Describe 'Get-TabulaRasaSampleOffset' {
    It 'spreads aligned offsets with the first and the last block' {
        InModuleScope TabulaRasa {
            Get-TabulaRasaSampleOffset -SizeBytes 1048576 -BlockSize 4096 -SampleCount 3
            | Should -Be @(0, 258048, 520192, 782336, 1044480)
        }
    }

    It 'returns one offset for a disk smaller than a block' {
        InModuleScope TabulaRasa {
            Get-TabulaRasaSampleOffset -SizeBytes 1000 -BlockSize 4096 -SampleCount 8 | Should -Be @(0)
        }
    }
}

Describe 'Test-TabulaRasaDiskData' {
    BeforeAll {
        $SIZE_BYTES = 1048576   # 1 MiB, 256 blocks of 4 KiB
        $ImagePath  = Join-Path -Path $TestDrive -ChildPath 'disk.img'
    }

    BeforeEach {
        [System.IO.File]::WriteAllBytes($ImagePath, [System.Byte[]]::new($SIZE_BYTES))
    }

    It 'finds no data on a zeroed image' {
        $Result = Test-TabulaRasaDiskData -Path $ImagePath -SizeBytes $SIZE_BYTES -SampleCount 8
        $Result.SampleCount  | Should -Be 10
        $Result.NonZeroCount | Should -Be 0
        $Result.HasData      | Should -BeFalse
    }

    It 'finds data in the first and the last block' {
        $bytes = [System.IO.File]::ReadAllBytes($ImagePath)
        $bytes[10]               = 0xAB
        $bytes[$SIZE_BYTES - 10] = 0xCD
        [System.IO.File]::WriteAllBytes($ImagePath, $bytes)

        $Result = Test-TabulaRasaDiskData -Path $ImagePath -SizeBytes $SIZE_BYTES -SampleCount 8
        $Result.NonZeroCount | Should -Be 2
        $Result.HasData      | Should -BeTrue
    }
}

Describe 'ConvertFrom-TabulaRasaPartitionLsblk' {
    It 'returns the partitions of a partitioned disk' {
        $json = '{"blockdevices":[{"name":"sdb","path":"/dev/sdb","type":"disk","size":32000000000,"fstype":null,"label":null,
                  "children":[{"name":"sdb1","path":"/dev/sdb1","type":"part","size":524288000,"fstype":"vfat","label":"EFI"},
                              {"name":"sdb2","path":"/dev/sdb2","type":"part","size":31475712000,"fstype":"ntfs","label":"Windows"}]}]}'
        $Partitions = InModuleScope TabulaRasa -Parameters @{ Json = $json } { ConvertFrom-TabulaRasaPartitionLsblk -Json $Json }

        $Partitions.Name       | Should -Be @('sdb1', 'sdb2')
        $Partitions.FileSystem | Should -Be @('vfat', 'ntfs')
        $Partitions[1].Label   | Should -Be 'Windows'
    }

    It 'returns the disk itself when it holds a file system without partitions' {
        $json = '{"blockdevices":[{"name":"sdc","path":"/dev/sdc","type":"disk","size":8000000000,"fstype":"exfat","label":"STICK"}]}'
        $Partitions = @(InModuleScope TabulaRasa -Parameters @{ Json = $json } { ConvertFrom-TabulaRasaPartitionLsblk -Json $Json })

        $Partitions.Count       | Should -Be 1
        $Partitions[0].Path     | Should -Be '/dev/sdc'
        $Partitions[0].SizeBytes | Should -Be 8000000000
    }

    It 'returns nothing for an empty disk' {
        $json = '{"blockdevices":[{"name":"sdd","path":"/dev/sdd","type":"disk","size":8000000000,"fstype":null,"label":null}]}'
        @(InModuleScope TabulaRasa -Parameters @{ Json = $json } { ConvertFrom-TabulaRasaPartitionLsblk -Json $Json }).Count
        | Should -Be 0
    }
}

Describe 'ConvertFrom-TabulaRasaFlsBody' {
    BeforeAll {
        $BodyLines = @(
            '0|/Users/x/IMG_0042.jpg (deleted)|1234-128-1|r/rrwxrwxrwx|0|0|2483011|1700000000|1699000000|1699000000|1698000000'
            '0|/Users/x/Old Folder (deleted)|1300-144-1|d/drwxrwxrwx|0|0|0|1700000000|1699000000|1699000000|1698000000'
            '0|/a|b.txt (deleted-realloc)|77-128-1|r/rrw-r--r--|0|0|12|0|0|0|0'
            '0|/$OrphanFiles/OrphanFile-14 (deleted)|14|-/r---------|0|0|0|0|0|0|0'
            'broken line'
        )
        $Files = @(InModuleScope TabulaRasa -Parameters @{ Lines = $BodyLines } { $Lines | ConvertFrom-TabulaRasaFlsBody })
    }

    It 'skips folders, empty orphans and broken lines' {
        $Files.Count | Should -Be 2
    }

    It 'strips the deleted marker and reads size and date' {
        $Files[0].Path          | Should -Be '/Users/x/IMG_0042.jpg'
        $Files[0].SizeBytes     | Should -Be 2483011
        $Files[0].LastWriteTime | Should -Be ([System.DateTimeOffset]::FromUnixTimeSeconds(1699000000).LocalDateTime)
    }

    It "keeps a '|' inside the name and leaves a missing date empty" {
        $Files[1].Path          | Should -Be '/a|b.txt'
        $Files[1].LastWriteTime | Should -BeNullOrEmpty
    }
}

Describe 'Find-TabulaRasaFileSignature' {
    BeforeAll {
        $SIZE_BYTES = 8388608   # 8 MiB, two deep chunks
        $ImagePath  = Join-Path -Path $TestDrive -ChildPath 'carve.img'

        # Headers at sector starts: 2x JPEG, 1x PDF, 1x MP4 (magic at offset 4). One JPEG off-sector, not counted.
        $bytes = [System.Byte[]]::new($SIZE_BYTES)
        $write = { param ($Offset, [System.Byte[]] $Magic) [System.Array]::Copy($Magic, 0, $bytes, $Offset, $Magic.Length) }
        & $write 0       ([System.Convert]::FromHexString('FFD8FFE0'))
        & $write 4194816 ([System.Convert]::FromHexString('FFD8FFE1'))   # second chunk, sector 8193
        & $write 1024    ([System.Convert]::FromHexString('255044462D312E37'))
        & $write 2052    ([System.Convert]::FromHexString('6674797069736F6D'))
        & $write 3001    ([System.Convert]::FromHexString('FFD8FFE0'))
        [System.IO.File]::WriteAllBytes($ImagePath, $bytes)
    }

    It 'counts every header at a sector start in deep mode' {
        $Result = Find-TabulaRasaFileSignature -Path $ImagePath -SizeBytes $SIZE_BYTES -Mode Deep
        $Result.BytesScanned | Should -Be $SIZE_BYTES
        ($Result.Hits | Where-Object Type -EQ 'JPEG').Count             | Should -Be 2
        ($Result.Hits | Where-Object Type -EQ 'PDF').Count              | Should -Be 1
        ($Result.Hits | Where-Object Type -EQ 'MP4 / MOV / HEIC').Count | Should -Be 1
        $Result.Hits[0].Type | Should -Be 'JPEG'
    }

    It 'finds the header in the first sampled block in quick mode' {
        $Result = Find-TabulaRasaFileSignature -Path $ImagePath -SizeBytes $SIZE_BYTES -Mode Quick
        ($Result.Hits | Where-Object Type -EQ 'PDF').Count | Should -Be 1
        $Result.IsCancelled | Should -BeFalse
    }

    It 'stops when OnProgress returns $false' {
        $Result = Find-TabulaRasaFileSignature -Path $ImagePath -SizeBytes $SIZE_BYTES -Mode Deep -OnProgress { $false }
        $Result.IsCancelled  | Should -BeTrue
        $Result.BytesScanned | Should -Be 4194304
    }
}

Describe 'Get-TabulaRasaDirectory' -Skip:(-NOT $IsLinux) {
    BeforeAll {
        $MountPoint = Join-Path -Path $TestDrive -ChildPath 'mnt'
        $null = New-Item -ItemType Directory -Path "$MountPoint/Users/x" -Force
        Set-Content -Path "$MountPoint/readme.txt" -Value 'hello'

        # The link leaves the mount point, but stays inside the TestDrive: Pester follows links
        # when it cleans up, a link to /etc would make it walk (or as root even delete) /etc.
        $Outside = Join-Path -Path $TestDrive -ChildPath 'outside'
        $null = New-Item -ItemType Directory -Path $Outside
        Set-Content -Path "$Outside/secret.txt" -Value 'not reachable'
        $null = New-Item -ItemType SymbolicLink -Path "$MountPoint/escape" -Target $Outside
    }

    It 'lists folders first and marks links' {
        $Entries = Get-TabulaRasaDirectory -MountPoint $MountPoint
        $Entries.Name | Should -Be @('Users', 'escape', 'readme.txt')
        ($Entries | Where-Object Name -EQ 'escape').IsDirectory | Should -BeFalse
        ($Entries | Where-Object Name -EQ 'escape').IsLink      | Should -BeTrue
    }

    It 'returns relative paths for the next level' {
        (Get-TabulaRasaDirectory -MountPoint $MountPoint -RelativePath 'Users').RelativePath | Should -Be 'Users/x'
    }

    It 'refuses to leave the mount point via ..' {
        { Get-TabulaRasaDirectory -MountPoint $MountPoint -RelativePath '../..' }
        | Should -Throw -ExceptionType ([System.UnauthorizedAccessException])
    }

    It 'refuses to follow a symbolic link' {
        { Get-TabulaRasaDirectory -MountPoint $MountPoint -RelativePath 'escape' }
        | Should -Throw -ExceptionType ([System.UnauthorizedAccessException])
    }
}

Describe 'Format-TabulaRasaSize' {
    It 'formats <Bytes> as <Expected>' -ForEach @(
        @{ Bytes = 512;           Expected = '512 B' }
        @{ Bytes = 1500;          Expected = '1.5 KB' }
        @{ Bytes = 500107862016;  Expected = '500.1 GB' }
        @{ Bytes = 2000398934016; Expected = '2.0 TB' }
    ) {
        InModuleScope TabulaRasa -Parameters $_ {
            # Invariant culture, the live system runs with C.UTF-8 and the test machine may not.
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture
            Format-TabulaRasaSize -Bytes $Bytes | Should -Be $Expected
        }
    }
}
