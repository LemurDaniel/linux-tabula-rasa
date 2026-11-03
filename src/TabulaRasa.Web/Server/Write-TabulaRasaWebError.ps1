# NOTE:
#   Requires: Pode, called inside a route of Start-TabulaRasaServer.
#
#   Write-TabulaRasaWebError -StatusCode 404 -Message "Disk 'sdx' must be plugged in."

function Write-TabulaRasaWebError {
    <#
    .SYNOPSIS
        Answers an API request with an error status and a JSON body { error: '...' }.

    .EXAMPLE
        PS> Write-TabulaRasaWebError -StatusCode 404 -Message "Disk 'sdx' must be plugged in."
    #>

    [CmdletBinding()]
    param (
        <#
        [Required]
        The HTTP status code, e.g. 404.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [ValidateRange(400, 599)]
        [System.Int32]
        $StatusCode,

        <#
        [Required]
        The message the web UI shows to the user.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.String]
        $Message
    )

    Write-Verbose "[Write-TabulaRasaWebError] $StatusCode $Message"
    Write-PodeJsonResponse -StatusCode $StatusCode -Value @{ error = $Message }
}
