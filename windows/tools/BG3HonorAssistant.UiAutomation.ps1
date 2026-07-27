Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class BG3NativeInput
{
    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetPhysicalCursorPos(int x, int y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(
        uint flags,
        uint dx,
        uint dy,
        uint data,
        UIntPtr extraInfo);
}
'@

# PER_MONITOR_AWARE_V2 keeps UI Automation bounds, screen capture, and injected
# pointer coordinates in the same physical-pixel coordinate space.
$null = [BG3NativeInput]::SetProcessDpiAwarenessContext([IntPtr](-4))

function Get-BG3Process {
    $processes = @(Get-Process -Name 'BG3HonorAssistant' -ErrorAction SilentlyContinue)
    $windowProcesses = @($processes | Where-Object { $_.MainWindowHandle -ne 0 })
    if ($windowProcesses.Count -eq 1) {
        return $windowProcesses[0]
    }
    if ($processes.Count -ne 1) {
        throw (
            "Expected exactly one BG3HonorAssistant UI process; found " +
            "$($processes.Count) processes and $($windowProcesses.Count) windows.")
    }

    return $processes[0]
}

function Get-BG3Window {
    param(
        [ValidateSet('Planner', 'Overlay', 'Any')]
        [string]$Surface = 'Planner'
    )

    $process = Get-BG3Process
    $condition = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
        $process.Id)
    $windows = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        $condition)
    $expectedName = switch ($Surface) {
        'Planner' { 'BG3 Honor Assistant' }
        'Overlay' { 'BG3 Honor Assistant overlay' }
        default { $null }
    }
    $matches = @(
        foreach ($candidate in $windows) {
            if ($null -eq $expectedName -or $candidate.Current.Name -eq $expectedName) {
                $candidate
            }
        })
    if ($matches.Count -ne 1) {
        throw (
            "Expected one $Surface window for process $($process.Id); " +
            "found $($matches.Count).")
    }
    $window = $matches[0]
    if ($null -eq $window) {
        throw "No top-level window was found for process $($process.Id)."
    }

    return $window
}

function Get-BG3Elements {
    param(
        [System.Windows.Automation.AutomationElement]$Root = (Get-BG3Window)
    )

    return $Root.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)
}

function Find-BG3Element {
    param(
        [string]$AutomationId,
        [string]$Name,
        [string]$Text,
        [System.Windows.Automation.ControlType]$ControlType,
        [switch]$IncludeOffscreen,
        [System.Windows.Automation.AutomationElement]$Root = (Get-BG3Window)
    )

    $matches = @()
    foreach ($element in Get-BG3Elements -Root $Root) {
        if (-not $IncludeOffscreen -and $element.Current.IsOffscreen) {
            continue
        }
        if (
            $PSBoundParameters.ContainsKey('AutomationId') -and
            $element.Current.AutomationId -ne $AutomationId
        ) {
            continue
        }
        if (
            $PSBoundParameters.ContainsKey('Name') -and
            $element.Current.Name -ne $Name
        ) {
            continue
        }
        if (
            $PSBoundParameters.ContainsKey('Text') -and
            $element.Current.Name -ne $Text
        ) {
            continue
        }
        if (
            $PSBoundParameters.ContainsKey('ControlType') -and
            $element.Current.ControlType -ne $ControlType
        ) {
            continue
        }
        $matches += $element
    }

    if ($matches.Count -ne 1) {
        $description = @(
            if ($PSBoundParameters.ContainsKey('AutomationId')) {
                "AutomationId='$AutomationId'"
            }
            if ($PSBoundParameters.ContainsKey('Name')) {
                "Name='$Name'"
            }
            if ($PSBoundParameters.ContainsKey('Text')) {
                "Text='$Text'"
            }
            if ($PSBoundParameters.ContainsKey('ControlType')) {
                "ControlType='$ControlType'"
            }
        ) -join ', '
        throw "Expected one visible element matching $description; found $($matches.Count)."
    }

    return $matches[0]
}

function Find-BG3Ancestor {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Automation.AutomationElement]$Element,
        [Parameter(Mandatory)]
        [System.Windows.Automation.ControlType]$ControlType
    )

    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $current = $Element
    while ($null -ne $current) {
        if ($current.Current.ControlType -eq $ControlType) {
            return $current
        }
        $current = $walker.GetParent($current)
    }

    throw "No $ControlType ancestor was found for '$($Element.Current.Name)'."
}

function Invoke-BG3Element {
    param(
        [string]$AutomationId,
        [string]$Name,
        [string]$Text,
        [int]$DelayMilliseconds = 350
    )

    $parameters = @{
        ControlType = [System.Windows.Automation.ControlType]::Button
    }
    if ($PSBoundParameters.ContainsKey('AutomationId')) {
        $parameters.AutomationId = $AutomationId
    }
    elseif ($PSBoundParameters.ContainsKey('Name')) {
        $parameters.Name = $Name
    }
    elseif ($PSBoundParameters.ContainsKey('Text')) {
        $textElement = Find-BG3Element `
            -Text $Text `
            -ControlType ([System.Windows.Automation.ControlType]::Text)
        $button = Find-BG3Ancestor `
            -Element $textElement `
            -ControlType ([System.Windows.Automation.ControlType]::Button)
        $pattern = $button.GetCurrentPattern(
            [System.Windows.Automation.InvokePattern]::Pattern)
        $pattern.Invoke()
        Start-Sleep -Milliseconds $DelayMilliseconds
        return
    }
    else {
        throw 'Specify AutomationId, Name, or Text.'
    }

    $button = Find-BG3Element @parameters
    $invokePattern = $button.GetCurrentPattern(
        [System.Windows.Automation.InvokePattern]::Pattern)
    $invokePattern.Invoke()
    Start-Sleep -Milliseconds $DelayMilliseconds
}

function Expand-BG3Element {
    param(
        [Parameter(Mandatory)]
        [string]$AutomationId,
        [int]$DelayMilliseconds = 250
    )

    $element = Find-BG3Element -AutomationId $AutomationId
    $pattern = $element.GetCurrentPattern(
        [System.Windows.Automation.ExpandCollapsePattern]::Pattern)
    $pattern.Expand()
    Start-Sleep -Milliseconds $DelayMilliseconds
}

function Click-BG3Point {
    param(
        [Parameter(Mandatory)]
        [int]$X,
        [Parameter(Mandatory)]
        [int]$Y,
        [int]$DelayMilliseconds = 350
    )

    if (-not [BG3NativeInput]::SetPhysicalCursorPos($X, $Y)) {
        throw "SetPhysicalCursorPos failed for ($X, $Y)."
    }
    [BG3NativeInput]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    [BG3NativeInput]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds $DelayMilliseconds
}

function Click-BG3Element {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Automation.AutomationElement]$Element,
        [int]$DelayMilliseconds = 350
    )

    $rectangle = $Element.Current.BoundingRectangle
    if ($rectangle.Width -lt 1 -or $rectangle.Height -lt 1) {
        throw "Element '$($Element.Current.Name)' has invalid bounds: $rectangle."
    }
    Click-BG3Point `
        -X ([int][Math]::Round($rectangle.X + ($rectangle.Width / 2D))) `
        -Y ([int][Math]::Round($rectangle.Y + ($rectangle.Height / 2D))) `
        -DelayMilliseconds $DelayMilliseconds
}

function Capture-BG3Window {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [ValidateSet('Planner', 'Overlay', 'Any')]
        [string]$Surface = 'Planner'
    )

    $window = Get-BG3Window -Surface $Surface
    $rectangle = $window.Current.BoundingRectangle
    if ($rectangle.Width -lt 1 -or $rectangle.Height -lt 1) {
        throw "The app window has invalid bounds: $rectangle."
    }

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    }
    $bitmap = [System.Drawing.Bitmap]::new(
        [int][Math]::Ceiling($rectangle.Width),
        [int][Math]::Ceiling($rectangle.Height),
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CopyFromScreen(
                [int][Math]::Floor($rectangle.X),
                [int][Math]::Floor($rectangle.Y),
                0,
                0,
                $bitmap.Size,
                [System.Drawing.CopyPixelOperation]::SourceCopy)
        }
        finally {
            $graphics.Dispose()
        }
        $bitmap.Save(
            [System.IO.Path]::GetFullPath($Path),
            [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $bitmap.Dispose()
    }
}

function Assert-BG3Text {
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    Find-BG3Element `
        -Text $Text `
        -ControlType ([System.Windows.Automation.ControlType]::Text) |
        Out-Null
}
