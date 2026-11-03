function Start-TabulaRasaServer {
    <#
    .SYNOPSIS
        Starts the Pode web server of the live system: the API under /api and the web UI under /.

    .DESCRIPTION
        Runs as root (tabula-rasa-server.service), it needs raw disk access and port 80.

        State shared by all route and task runspaces:
        - Session   The one device in control, see Enter-TabulaRasaWebSession.
        - Jobs      Long jobs (overview, deleted files, deep scan, wipe), see New-TabulaRasaWebJob.
        - Replug    The replug confirmation of USB sticks and SD cards, see Update-TabulaRasaWebReplug.

        Every /api route except info, qr and session requires the session token in the
        X-Session-Token header.

    .EXAMPLE
        PS> Import-Module /opt/tabula-rasa/TabulaRasaWeb
        PS> Start-TabulaRasaServer

    .EXAMPLE
        Local test on another port:

        PS> Start-TabulaRasaServer -Port 8080
    #>

    # Starts a long-running server, -WhatIf has no meaning here.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    # The parameters are used inside the Start-PodeServer script block, the analyzer does not look there.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '')]
    [CmdletBinding()]
    param (
        <#
        [Optional]
        The HTTP port. Default is 80, so the URL needs no port.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [ValidateRange(1, 65535)]
        [System.Int32]
        $Port = 80,

        <#
        [Optional]
        The TabulaRasa module folder. Default is the sibling folder of this module.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [System.String]
        $ModulePath = (Join-Path -Path $PSScriptRoot -ChildPath '../../TabulaRasa'),

        <#
        [Optional]
        Seconds without a request after which the session is free for another device. Default is 300.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [ValidateRange(10, 86400)]
        [System.Int32]
        $SessionTimeoutSeconds = 300,

        <#
        [Optional]
        For tests: a module imported after the others, its functions win (e.g. a Get-TabulaRasaDisk
        that offers loop devices, which the real one hides). Default is none.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [System.String]
        $ExtraModulePath = ''
    )

    $WEB_ROOT        = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path
    $CORE_MODULE     = (Resolve-Path -Path (Join-Path -Path $ModulePath -ChildPath 'TabulaRasa.psm1')).Path
    $WEB_MODULE      = Join-Path -Path $WEB_ROOT -ChildPath 'TabulaRasaWeb.psm1'
    $THREAD_COUNT    = 4
    $PUBLIC_PATHS    = @('/api/info', '/api/qr', '/api/session')

    Start-PodeServer -Threads $THREAD_COUNT -ScriptBlock {
        Add-PodeEndpoint -Address * -Port $Port -Protocol Http
        New-PodeLoggingMethod -Terminal | Enable-PodeErrorLogging

        # Both modules in every route and task runspace.
        Import-PodeModule -Path $CORE_MODULE
        Import-PodeModule -Path $WEB_MODULE
        if (-NOT [System.String]::IsNullOrEmpty($ExtraModulePath)) {
            Import-PodeModule -Path $ExtraModulePath
        }

        # Shared state
        $null = Set-PodeState -Name 'Session' -Value ([System.Collections.Hashtable]::Synchronized(@{ Token = $null; Address = $null; LastSeen = [System.DateTime]::MinValue }))
        $null = Set-PodeState -Name 'Jobs' -Value ([System.Collections.Hashtable]::Synchronized(@{}))
        $null = Set-PodeState -Name 'Replug' -Value ([System.Collections.Hashtable]::Synchronized(@{ Phase = 'Idle' }))
        $null = Set-PodeState -Name 'Config' -Value @{ SessionTimeoutSeconds = $SessionTimeoutSeconds }

        # Session lock: everything under /api except the public paths needs the owner's token.
        Add-PodeMiddleware -Name 'SessionLock' -Route '/api/*' -ArgumentList @(, $PUBLIC_PATHS) -ScriptBlock {
            param ($PublicPaths)
            if ($WebEvent.Path -IN $PublicPaths) {
                return $true
            }

            $session = Get-PodeState -Name 'Session'
            $token   = Get-PodeHeader -Name 'X-Session-Token'
            $timeout = (Get-PodeState -Name 'Config').SessionTimeoutSeconds
            $isValid = Lock-PodeObject -Object $session -Return -ScriptBlock {
                Test-TabulaRasaWebSession -Session $session -Token $token -TimeoutSeconds $timeout
            }
            if ($isValid) {
                return $true
            }

            Write-PodeJsonResponse -StatusCode 423 -Value @{ error = 'Another device controls the stick, or your session expired.' }
            return $false
        }

        # Long jobs run here, one at a time (see New-TabulaRasaWebJob).
        Add-PodeTask -Name 'RunJob' -ScriptBlock {
            param ($JobId)
            Invoke-TabulaRasaWebJob -Job (Get-PodeState -Name 'Jobs')[$JobId]
        }

        Use-PodeRoutes -Path (Join-Path -Path $WEB_ROOT -ChildPath 'routes')
        Add-PodeStaticRoute -Path '/' -Source (Join-Path -Path $WEB_ROOT -ChildPath 'public') -Defaults @('index.html')
    }
}
