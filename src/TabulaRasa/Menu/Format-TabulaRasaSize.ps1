function Format-TabulaRasaSize {
    <#
    .SYNOPSIS
        Formats a byte count in decimal units, the units printed on disk labels.

    .EXAMPLE
        PS> Format-TabulaRasaSize -Bytes 500107862016
        500.1 GB
    #>

    [CmdletBinding()]
    [OutputType([System.String])]
    param (
        <#
        [Required]
        The byte count.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.Int64]
        $Bytes
    )

    $UNITS = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')

    $value = [System.Double] $Bytes
    $unit  = 0
    while ($value -GE 1000 -AND $unit -LT $UNITS.Count - 1) {
        $value /= 1000
        $unit++
    }

    return $unit -EQ 0 ? "$Bytes B" : ('{0:N1} {1}' -f $value, $UNITS[$unit])
}
