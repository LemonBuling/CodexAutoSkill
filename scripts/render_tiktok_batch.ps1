param(
    [Parameter(Mandatory = $true)]
    [string]$Root,

    [Parameter(Mandatory = $true)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $true)]
    [string]$Ffmpeg,

    [Parameter(Mandatory = $true)]
    [string]$WorkDir,

    [Parameter(Mandatory = $true)]
    [string]$NamingRules,

    [switch]$StrictIntroTrim,
    [switch]$NoAudioNormalize
)

$ErrorActionPreference = "Stop"

function Invoke-Ffmpeg {
    param([string[]]$Arguments, [switch]$AllowFailure)
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $lines = & $Ffmpeg @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference
    $textLines = @($lines | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_.ToString() }
    })
    if ((-not $AllowFailure) -and $exitCode -ne 0) {
        throw ("ffmpeg failed with exit code {0}: {1}" -f $exitCode, ($textLines -join "`n"))
    }
    return $textLines
}

function Format-Time {
    param([double]$Seconds)
    return ("{0:0.###}" -f ([math]::Max(0.0, $Seconds)))
}

function Convert-ToSeconds {
    param([string]$Timestamp)
    if ($Timestamp -match '^(\d+):(\d+):(\d+(?:\.\d+)?)$') {
        return ([double]$Matches[1] * 3600.0) + ([double]$Matches[2] * 60.0) + [double]$Matches[3]
    }
    return [double]$Timestamp
}

function Get-MediaDuration {
    param([string]$Path)
    $lines = Invoke-Ffmpeg -Arguments @("-hide_banner", "-i", $Path) -AllowFailure
    foreach ($line in $lines) {
        if ($line -match 'Duration:\s*([0-9:\.]+)') { return Convert-ToSeconds $Matches[1] }
    }
    return 0.0
}

function Get-FolderNumber {
    param([string]$Name)
    if ($Name -match '(\d+)$') { return [int]$Matches[1] }
    return $null
}

function Test-IsClipFile {
    param([System.IO.FileInfo]$File)
    return ($File.BaseName -match '^\d+(?:\s*\(\d+\))?$')
}

function Get-ClipSortKey {
    param([System.IO.FileInfo]$File, [int]$Part)
    if ($File.BaseName -match '^(\d+)(?:\s*\((\d+)\))?$') {
        if ($Part -eq 1) { return [int]$Matches[1] }
        if ($Matches[2]) { return [int]$Matches[2] }
    }
    return 0
}

function Get-CaptionsFromReadme {
    param([string]$ReadmePath)
    $text = [System.IO.File]::ReadAllText($ReadmePath, [System.Text.Encoding]::UTF8)
    $captions = @{}
    $current = $null
    $stopPrefix = ([string][char]0x4EE5) + ([string][char]0x4E0A) + ([string][char]0x5B57) + ([string][char]0x5E55)
    foreach ($rawLine in ($text -split "`r?`n")) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { $current = $null; continue }
        if ($line.StartsWith($stopPrefix, [System.StringComparison]::Ordinal)) { break }
        if ($line -match '^\s*\D+?(\d+)\s*(?:\:|\uFF1A)\s*(.*)$') {
            $current = [int]$Matches[1]
            $captions[$current] = $Matches[2].Trim()
            continue
        }
        if ($null -ne $current -and $captions.ContainsKey($current)) {
            $captions[$current] = ($captions[$current] + " " + $line).Trim()
        }
    }
    return $captions
}

function Get-NamingRule {
    param([int]$Number, [array]$Rules)
    foreach ($rule in $Rules) {
        if ($Number -ge $rule.Start -and $Number -le $rule.End) {
            return [pscustomobject]@{ Prefix = $rule.Prefix; Index = ($Number - $rule.Start + 1) }
        }
    }
    throw ("No naming rule for material {0}" -f $Number)
}

function Convert-NamingRules {
    param([string]$Text)
    $rules = New-Object System.Collections.Generic.List[object]
    foreach ($part in ($Text -split ';')) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        if ($part -notmatch '^\s*(\d+)(?:-(\d+))?\s*=\s*(.+?)\s*$') {
            throw ("Invalid NamingRules part: {0}" -f $part)
        }
        $start = [int]$Matches[1]
        $end = if ($Matches[2]) { [int]$Matches[2] } else { $start }
        $rules.Add([pscustomobject]@{ Start = $start; End = $end; Prefix = $Matches[3].Trim() }) | Out-Null
    }
    return $rules.ToArray()
}

function New-OutputFileName {
    param([string]$Prefix, [int]$Index)
    $leftParen = [string][char]0xFF08
    $rightParen = [string][char]0xFF09
    return ("{0}{1}codex{2}{3}.mp4" -f $Prefix, $leftParen, $rightParen, $Index)
}

function Measure-LineWidth {
    param([System.Drawing.Graphics]$Graphics, [System.Drawing.Font]$Font, [string]$Text)
    $flags = [System.Windows.Forms.TextFormatFlags]::NoPadding
    $size = [System.Windows.Forms.TextRenderer]::MeasureText([System.Drawing.IDeviceContext]$Graphics, [string]$Text, [System.Drawing.Font]$Font, [System.Drawing.Size]::Empty, $flags)
    return $size.Width
}

function Wrap-Text {
    param([System.Drawing.Graphics]$Graphics, [System.Drawing.Font]$Font, [string]$Text, [int]$MaxWidth)
    $words = $Text -split '\s+'
    $lines = New-Object System.Collections.Generic.List[string]
    $current = ""
    foreach ($word in $words) {
        if ([string]::IsNullOrWhiteSpace($word)) { continue }
        $candidate = if ($current.Length -eq 0) { $word } else { $current + " " + $word }
        if ((Measure-LineWidth -Graphics $Graphics -Font $Font -Text $candidate) -le $MaxWidth -or $current.Length -eq 0) {
            $current = $candidate
        }
        else {
            $lines.Add($current)
            $current = $word
        }
    }
    if ($current.Length -gt 0) { $lines.Add($current) }
    return $lines.ToArray()
}

function Draw-OutlinedText {
    param([System.Drawing.Graphics]$Graphics, [string]$Text, [System.Drawing.Font]$Font, [System.Drawing.Rectangle]$Rect)
    $flags = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::NoPadding
    foreach ($dx in ((-3)..3)) {
        foreach ($dy in ((-3)..3)) {
            if (($dx -ne 0) -or ($dy -ne 0)) {
                $outlineRect = New-Object System.Drawing.Rectangle(([int]$Rect.X + [int]$dx), ([int]$Rect.Y + [int]$dy), $Rect.Width, $Rect.Height)
                [System.Windows.Forms.TextRenderer]::DrawText([System.Drawing.IDeviceContext]$Graphics, [string]$Text, [System.Drawing.Font]$Font, [System.Drawing.Rectangle]$outlineRect, [System.Drawing.Color]::Black, [System.Windows.Forms.TextFormatFlags]$flags)
            }
        }
    }
    [System.Windows.Forms.TextRenderer]::DrawText([System.Drawing.IDeviceContext]$Graphics, [string]$Text, [System.Drawing.Font]$Font, [System.Drawing.Rectangle]$Rect, [System.Drawing.Color]::White, [System.Windows.Forms.TextFormatFlags]$flags)
}

function New-SubtitlePng {
    param([string]$Text, [string]$OutputPath)
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    $width = 1080
    $height = 1920
    $maxTextWidth = 760
    $fontSize = 48
    $bitmap = New-Object System.Drawing.Bitmap($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $font = New-Object System.Drawing.Font("Arial", $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    [string[]]$lines = @(Wrap-Text -Graphics $graphics -Font $font -Text $Text -MaxWidth $maxTextWidth)
    while ($lines.Count -gt 4 -and $fontSize -gt 34) {
        $font.Dispose()
        $fontSize -= 3
        $font = New-Object System.Drawing.Font("Arial", $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        [string[]]$lines = @(Wrap-Text -Graphics $graphics -Font $font -Text $Text -MaxWidth $maxTextWidth)
    }
    $lineHeight = [int]($fontSize * 1.22)
    $blockHeight = $lineHeight * $lines.Count
    $top = [int](300 - ($blockHeight / 2))
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $rect = New-Object System.Drawing.Rectangle(0, ($top + $i * $lineHeight), $width, $lineHeight)
        Draw-OutlinedText -Graphics $graphics -Text $lines[$i] -Font $font -Rect $rect
    }
    $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $font.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
}

function New-TrimPlan {
    param([array]$Clips, [double]$Target, [switch]$StrictIntro)
    $weights = New-Object System.Collections.Generic.List[double]
    for ($i = 0; $i -lt $Clips.Count; $i++) {
        $w = 1.0
        if ($i -eq 0 -or $i -eq ($Clips.Count - 1)) { $w = 1.16 }
        if ([double]$Clips[$i].Duration -lt 2.2) { $w *= 0.86 }
        $weights.Add($w)
    }
    $sumWeights = ($weights | Measure-Object -Sum).Sum
    $plan = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $Clips.Count; $i++) {
        $duration = [double]$Clips[$i].Duration
        $safeDuration = [math]::Max(0.35, $duration - 0.08)
        $desired = $Target * ([double]$weights[$i] / [double]$sumWeights)
        $minKeep = [math]::Min($safeDuration, [math]::Max(0.85, [math]::Min(1.55, $safeDuration)))
        $keep = [math]::Min($safeDuration, [math]::Max($minKeep, $desired))
        $plan.Add([pscustomobject]@{ File = $Clips[$i].File; Duration = $duration; Keep = $keep }) | Out-Null
    }
    for ($i = 0; $i -lt $plan.Count; $i++) {
        $clip = $plan[$i]
        $minimumStart = 0.05
        if ($StrictIntro -and $i -eq 0 -and [double]$clip.Duration -gt 2.2) {
            $minimumStart = [math]::Min(([double]$clip.Duration - 0.60), [math]::Max(0.80, ([double]$clip.Duration * 0.38)))
        }
        $available = [math]::Max(0.35, ([double]$clip.Duration - $minimumStart - 0.02))
        $keep = [math]::Min([math]::Max(0.35, $clip.Keep), $available)
        $start = [math]::Max($minimumStart, [double]$clip.Duration - $keep - 0.04)
        $end = [math]::Min([double]$clip.Duration - 0.02, $start + $keep)
        if (($end - $start) -lt 0.30) { $start = 0.02; $end = [math]::Max(0.32, [double]$clip.Duration - 0.02) }
        $clip | Add-Member -MemberType NoteProperty -Name Start -Value $start
        $clip | Add-Member -MemberType NoteProperty -Name End -Value $end
    }
    return $plan
}

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$resolvedWork = (Resolve-Path -LiteralPath $WorkDir).Path
$resolvedOutput = $OutputRoot
$runStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$tempRoot = Join-Path $resolvedWork ("tiktok_material_cleaner_tmp_" + $runStamp)
$reportPath = Join-Path $resolvedWork ("tiktok_material_cleaner_report_" + $runStamp + ".csv")
$rules = Convert-NamingRules -Text $NamingRules

$readmeFile = Get-ChildItem -LiteralPath $resolvedRoot -File | Where-Object { $_.Name -like "README*.txt" -or $_.Name -like "README *.txt" } | Select-Object -First 1
if ($null -eq $readmeFile) { throw "Missing README file." }
$readmeText = [System.IO.File]::ReadAllText($readmeFile.FullName, [System.Text.Encoding]::UTF8)
$captions = Get-CaptionsFromReadme -ReadmePath $readmeFile.FullName
$jianCan = ([string][char]0x7B80) + ([string][char]0x9910)
$useJianCan = $readmeText.Contains($jianCan)

$ctaFile = Get-ChildItem -LiteralPath $resolvedRoot -File -Filter "*.png" | Sort-Object Name | Select-Object -First 1
$ctaPath = if ($null -ne $ctaFile) { $ctaFile.FullName } else { $null }

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null

$folders = Get-ChildItem -LiteralPath $resolvedRoot -Directory |
    Where-Object { $n = Get-FolderNumber $_.Name; $null -ne $n -and $captions.ContainsKey($n) } |
    Sort-Object { Get-FolderNumber $_.Name }
if ($folders.Count -eq 0) { throw "No material folders found." }

$results = New-Object System.Collections.Generic.List[object]

foreach ($folderInfo in $folders) {
    $folderNumber = Get-FolderNumber $folderInfo.Name
    $folderPath = $folderInfo.FullName
    $safeFolder = "item_{0:00}" -f $folderNumber
    $folderTemp = Join-Path $tempRoot $safeFolder
    New-Item -ItemType Directory -Path $folderTemp -Force | Out-Null

    $videoFiles = Get-ChildItem -LiteralPath $folderPath -File |
        Where-Object { (Test-IsClipFile -File $_) -and $_.Extension -match '^\.(mov|mp4|m4v)$' } |
        Sort-Object { Get-ClipSortKey -File $_ -Part 1 }, { Get-ClipSortKey -File $_ -Part 2 }, Name
    if ($videoFiles.Count -eq 0) { throw ("No numeric clips in {0}" -f $folderPath) }

    $musicFile = Get-ChildItem -LiteralPath $folderPath -File |
        Where-Object { -not (Test-IsClipFile -File $_) -and $_.Extension -match '^\.(mp4|mov|m4a|wav)$' } |
        Sort-Object Name |
        Select-Object -First 1
    if ($null -eq $musicFile) { throw ("Missing music file in {0}" -f $folderPath) }

    $clips = New-Object System.Collections.Generic.List[object]
    foreach ($vf in $videoFiles) {
        $clips.Add([pscustomobject]@{ File = $vf.Name; Path = $vf.FullName; Duration = (Get-MediaDuration -Path $vf.FullName) }) | Out-Null
    }

    $totalDuration = ($clips | Measure-Object Duration -Sum).Sum
    $target = [math]::Min(18.5, [math]::Max(15.0, $totalDuration - 0.6))
    $plan = New-TrimPlan -Clips $clips.ToArray() -Target $target -StrictIntro:$StrictIntroTrim

    $parts = New-Object System.Collections.Generic.List[string]
    $partIndex = 0
    foreach ($row in $plan) {
        $partIndex += 1
        $inputPath = Join-Path $folderPath $row.File
        $partPath = Join-Path $folderTemp ("part_{0:00}.mp4" -f $partIndex)
        $clipDuration = [double]$row.End - [double]$row.Start
        Invoke-Ffmpeg -Arguments @(
            "-y", "-hide_banner", "-loglevel", "warning",
            "-i", $inputPath,
            "-ss", (Format-Time ([double]$row.Start)),
            "-t", (Format-Time $clipDuration),
            "-map", "0:v:0",
            "-an",
            "-vf", "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,fps=30,format=yuv420p",
            "-c:v", "mpeg4",
            "-q:v", "3",
            $partPath
        ) | Out-Null
        $parts.Add($partPath) | Out-Null
    }

    $concatPath = Join-Path $folderTemp "concat.txt"
    $concatLines = @($parts | ForEach-Object { "file '{0}'" -f $_.Replace("'", "''") })
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($concatPath, $concatLines, $utf8NoBom)

    $sequencePath = Join-Path $folderTemp ($safeFolder + "_sequence.mp4")
    Invoke-Ffmpeg -Arguments @("-y", "-hide_banner", "-loglevel", "warning", "-f", "concat", "-safe", "0", "-i", $concatPath, "-c", "copy", $sequencePath) | Out-Null

    $durationSeconds = Get-MediaDuration -Path $sequencePath
    $subtitlePath = Join-Path $folderTemp ($safeFolder + "_subtitle.png")
    New-SubtitlePng -Text $captions[$folderNumber] -OutputPath $subtitlePath

    $nameRule = Get-NamingRule -Number $folderNumber -Rules $rules
    $outputName = New-OutputFileName -Prefix $nameRule.Prefix -Index $nameRule.Index
    $outputPath = Join-Path $resolvedOutput $outputName
    $ctaStart = Format-Time ([math]::Max(0.0, [math]::Round($durationSeconds / 2.0, 2)))

    Write-Host ("Rendering {0}: {1:0.00}s -> {2}" -f $folderInfo.Name, $durationSeconds, $outputPath)

    $baseFilter = if ($useJianCan) {
        "[0:v]fps=30,format=yuv420p,colorlevels=rimin=0.012:gimin=0.012:bimin=0.012:rimax=0.988:gimax=0.988:bimax=0.988:preserve=lum,colorcorrect=saturation=1.16,cas=strength=0.08[base]"
    }
    else {
        "[0:v]fps=30,format=yuv420p[base]"
    }

    $filter = if ($ctaPath) {
        "$baseFilter;[2:v]format=rgba[sub];[base][sub]overlay=0:0[tmp];[3:v]scale=1080:1920,format=rgba[cta];[tmp][cta]overlay=0:0:enable='gte(t,$ctaStart)'[v]"
    }
    else {
        "$baseFilter;[2:v]format=rgba[sub];[base][sub]overlay=0:0[v]"
    }

    $ffArgs = @(
        "-y", "-hide_banner", "-loglevel", "warning",
        "-i", $sequencePath,
        "-stream_loop", "-1", "-i", $musicFile.FullName,
        "-loop", "1", "-i", $subtitlePath
    )
    if ($ctaPath) { $ffArgs += @("-loop", "1", "-i", $ctaPath) }
    $ffArgs += @(
        "-filter_complex", $filter,
        "-map", "[v]",
        "-map", "1:a:0",
        "-t", (Format-Time $durationSeconds),
        "-shortest",
        "-c:v", "mpeg4",
        "-q:v", "3",
        "-c:a", "aac",
        "-b:a", "160k",
        "-movflags", "+faststart"
    )
    if (-not $NoAudioNormalize) {
        $ffArgs += @("-af", "loudnorm=I=-16:TP=-1.5:LRA=11")
    }
    $ffArgs += $outputPath
    Invoke-Ffmpeg -Arguments $ffArgs | Out-Null

    $outputDuration = Get-MediaDuration -Path $outputPath
    $outputItem = Get-Item -LiteralPath $outputPath
    $results.Add([pscustomobject]@{
        Folder = $folderInfo.Name
        Clips = $videoFiles.Count
        Duration = "{0:0.00}" -f $outputDuration
        SizeMB = "{0:0.00}" -f ($outputItem.Length / 1MB)
        Music = $musicFile.Name
        FileName = $outputItem.Name
        Output = $outputPath
    }) | Out-Null
}

$results | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8
$results | Format-Table -AutoSize
Write-Host ("Report: {0}" -f $reportPath)
