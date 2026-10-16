Set-StrictMode -Version Latest

# =============================================================================
#  UI.Console.ps1
#  Low-level console primitives for the interactive interface.
#  No external dependencies. Works in Windows Terminal, conhost.exe and
#  PowerShell 7 console.
# =============================================================================

#region --- Color palette (semantic, single source of truth) ---

$script:ADHCColors = @{
    Primary   = 'Cyan'
    Accent    = 'White'
    Success   = 'Green'
    Warning   = 'Yellow'
    Danger    = 'Red'
    Info      = 'Blue'
    Muted     = 'DarkGray'
    Highlight = 'Magenta'
}

function Get-ADHCColor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    if ($script:ADHCColors.ContainsKey($Name)) { return $script:ADHCColors[$Name] }
    return 'White'
}

#endregion

#region --- Unicode detection ---

$script:ADHCUnicodeSupported = $null

function Test-ADHCUnicodeSupport {
    <#
    .SYNOPSIS
        Returns $true if the current host can render Unicode box-drawing
        characters (█ ╔ ═ ╗ ║ ╚ ╝ etc.) reliably.
    #>
    [CmdletBinding()]
    param([switch]$Force)

    if ($null -ne $script:ADHCUnicodeSupported -and -not $Force) {
        return $script:ADHCUnicodeSupported
    }

    $supported = $false

    try {
        # PowerShell 7 exposes this: it is $true on Windows Terminal and on
        # conhost with VT enabled, $false in constrained hosts.
        if ($Host.UI -and ($Host.UI.PSObject.Properties.Name -contains 'SupportsVirtualTerminal')) {
            $supported = [bool]$Host.UI.SupportsVirtualTerminal
        }
    } catch { }

    if (-not $supported) {
        # Fall back to checking the output encoding. UTF-8 (65001) usually
        # means the console can render box-drawing.
        try {
            $cp = [Console]::OutputEncoding.CodePage
            if ($cp -eq 65001) { $supported = $true }
        } catch { }
    }

    $script:ADHCUnicodeSupported = $supported
    return $supported
}

function Get-ADHCBoxChars {
    <#
    .SYNOPSIS
        Returns a hashtable of box-drawing characters, Unicode or ASCII
        depending on terminal support.
    #>
    [CmdletBinding()]
    param()

    if (Test-ADHCUnicodeSupport) {
        return @{
            TopLeft     = [string][char]0x250C   # ┌
            TopRight    = [string][char]0x2510   # ┐
            BottomLeft  = [string][char]0x2514   # └
            BottomRight = [string][char]0x2518   # ┘
            Horizontal  = [string][char]0x2500   # ─
            Vertical    = [string][char]0x2502   # │
            TeeLeft     = [string][char]0x251C   # ├
            TeeRight    = [string][char]0x2524   # ┤
            Cross       = [string][char]0x253C   # ┼
            Bullet      = [string][char]0x2022   # •
            ArrowRight  = [string][char]0x25B8   # ▸
            CheckMark   = [string][char]0x2714   # ✔
            CrossMark   = [string][char]0x2718   # ✘
            Dot         = [string][char]0x00B7   # ·
        }
    }

    return @{
        TopLeft     = '+'
        TopRight    = '+'
        BottomLeft  = '+'
        BottomRight = '+'
        Horizontal  = '-'
        Vertical    = '|'
        TeeLeft     = '+'
        TeeRight    = '+'
        Cross       = '+'
        Bullet      = '*'
        ArrowRight  = '>'
        CheckMark   = 'x'
        CrossMark   = 'X'
        Dot         = '.'
    }
}

#endregion

#region --- Console primitives ---

function Initialize-ADHCConsole {
    <#
    .SYNOPSIS
        Prepares the console for the TUI: UTF-8 output encoding, sensible
        cursor visibility. Safe to call multiple times.
    #>
    [CmdletBinding()]
    param()

    try {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        [Console]::CursorVisible  = $true
    } catch { }

    # Clear the scrollback so the TUI starts on a clean screen.
    try { Clear-Host } catch { }
}

function Clear-ADHCScreen {
    [CmdletBinding()]
    param()
    try { Clear-Host } catch { }
}

function Get-ADHCConsoleWidth {
    [CmdletBinding()]
    param([int]$Default = 80)
    try {
        $w = [Console]::WindowWidth
        if ($w -le 0) { return $Default }
        return $w
    } catch {
        return $Default
    }
}

function Write-ADHCBlank {
    [CmdletBinding()]
    param([int]$Count = 1)
    for ($i = 0; $i -lt $Count; $i++) { Write-Host '' }
}

function Write-ADHCColor {
    <#
    .SYNOPSIS
        Writes text with a named color from the semantic palette.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Text = '',
        [string]$Color = 'Accent',
        [switch]$NoNewline
    )
    $c = Get-ADHCColor -Name $Color
    if ($NoNewline) { Write-Host $Text -ForegroundColor $c -NoNewline }
    else            { Write-Host $Text -ForegroundColor $c }
}

function Write-ADHCTitle {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)
    Write-Host $Text -ForegroundColor (Get-ADHCColor -Name 'Primary')
}

function Write-ADHCMuted {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text, [switch]$NoNewline)
    if ($NoNewline) { Write-Host $Text -ForegroundColor (Get-ADHCColor -Name 'Muted') -NoNewline }
    else            { Write-Host $Text -ForegroundColor (Get-ADHCColor -Name 'Muted') }
}

#endregion

#region --- Box drawing ---

function Write-ADHCBox {
    <#
    .SYNOPSIS
        Draws a framed box with optional title and body lines.

    .PARAMETER Lines
        Body lines. Each line is written as-is (no wrapping).

    .PARAMETER Title
        Optional centered title on the top border.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines = @(),
        [string]$Title,
        [string]$Color = 'Primary'
    )
    
    $ch = Get-ADHCBoxChars
    $c  = Get-ADHCColor -Name $Color

    # Compute inner width from longest line and title.
    $inner = 0
    foreach ($l in $Lines) {
        if ($l -and $l.Length -gt $inner) { $inner = $l.Length }
    }
    if ($Title -and $Title.Length -gt $inner) { $inner = $Title.Length }

    # Padding: 2 spaces on each side.
    $inner += 2

    # Top border with optional title.
    if ($Title) {
        $titleText   = " $Title "
        $sidePad     = $inner - $titleText.Length
        $leftPad     = [math]::Floor($sidePad / 2)
        $rightPad    = $sidePad - $leftPad
        $topLine     = $ch.TopLeft + ($ch.Horizontal * $leftPad) + $titleText + ($ch.Horizontal * $rightPad) + $ch.TopRight
    } else {
        $topLine = $ch.TopLeft + ($ch.Horizontal * $inner) + $ch.TopRight
    }

    Write-Host $topLine -ForegroundColor $c

    foreach ($l in $Lines) {
        $pad = $inner - $l.Length
        $line = $ch.Vertical + ' ' + $l + (' ' * ($pad - 1)) + $ch.Vertical
        Write-Host $line -ForegroundColor $c
    }

    $botLine = $ch.BottomLeft + ($ch.Horizontal * $inner) + $ch.BottomRight
    Write-Host $botLine -ForegroundColor $c
}

function Write-ADHCMenuOption {
    <#
    .SYNOPSIS
        Writes a menu row like:  [1] Descrição aqui
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Text,
        [string]$Color = 'Accent'
    )
    $c = Get-ADHCColor -Name $Color
    Write-Host ('  [{0}] ' -f $Key) -ForegroundColor (Get-ADHCColor -Name 'Primary') -NoNewline
    Write-Host $Text -ForegroundColor $c
}

#endregion

#region --- Input ---

function Read-ADHCKey {
    <#
    .SYNOPSIS
        Waits for a single key press and returns it as an uppercase string.
        Returns $null on Ctrl+C / Escape when -AllowEsc is set.
    #>
    [CmdletBinding()]
    param([switch]$AllowEsc)

    while ($true) {
        try {
            $key = [Console]::ReadKey($true)
        } catch {
            return $null
        }

        if ($key.Key -eq [ConsoleKey]::Escape -and $AllowEsc) { return $null }
        if ($key.KeyChar -eq [char]0) { continue }

        return ([string]$key.KeyChar).ToUpperInvariant()
    }
}

function Read-ADHCLine {
    <#
    .SYNOPSIS
        Reads a full line of text with a styled prompt.
    #>
    [CmdletBinding()]
    param([string]$Prompt = '> ')
    Write-Host $Prompt -ForegroundColor (Get-ADHCColor -Name 'Primary') -NoNewline
    return [Console]::ReadLine()
}

function Wait-ADHCEnter {
    [CmdletBinding()]
    param([string]$Message = 'Pressione Enter para continuar...')
    Write-Host ''
    Write-Host $Message -ForegroundColor (Get-ADHCColor -Name 'Muted') -NoNewline
    [void][Console]::ReadLine()
}

#endregion