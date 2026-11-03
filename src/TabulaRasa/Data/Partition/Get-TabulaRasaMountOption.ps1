function Get-TabulaRasaMountOption {
    <#
    .SYNOPSIS
        Returns the kernel driver and the read-only options for every file system that can be opened.

    .DESCRIPTION
        'ro' alone is not enough for journaling file systems: ext4 and xfs replay their journal
        on mount, which writes to the disk. noload, norecovery and nologreplay skip that.
        Mount-TabulaRasaPartition also sets the block device read-only, so a missed option fails
        the mount instead of writing.

        Not listed, so not mountable: crypto_LUKS (encrypted), LVM2_member, swap, apfs.

    .EXAMPLE
        PS> (Get-TabulaRasaMountOption)['ext4']
    #>

    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param ()

    return @{
        ext2     = @{ Type = 'ext2';     Options = 'ro,noload' }
        ext3     = @{ Type = 'ext3';     Options = 'ro,noload' }
        ext4     = @{ Type = 'ext4';     Options = 'ro,noload' }
        xfs      = @{ Type = 'xfs';      Options = 'ro,norecovery' }
        btrfs    = @{ Type = 'btrfs';    Options = 'ro,rescue=nologreplay' }
        ntfs     = @{ Type = 'ntfs3';    Options = 'ro' }
        vfat     = @{ Type = 'vfat';     Options = 'ro' }
        exfat    = @{ Type = 'exfat';    Options = 'ro' }
        hfsplus  = @{ Type = 'hfsplus';  Options = 'ro' }
        iso9660  = @{ Type = 'iso9660';  Options = 'ro' }
    }
}
