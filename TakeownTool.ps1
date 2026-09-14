param(
    [string]$DriverPath,
    [string]$TargetPath,
    [switch]$ElevatedRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$repositoryRoot = Join-Path $env:windir 'System32\DriverStore\FileRepository'
$script:logBox = $null
$script:driverText = $null
$script:targetText = $null
$script:executeButton = $null

function Write-Log {
    param([string]$Message, [bool]$IsError = $false)
    if ($script:logBox -ne $null) {
        $script:logBox.AppendText("$(Get-Date -Format 'HH:mm:ss')  $Message`r`n")
        $script:logBox.SelectionStart = $script:logBox.TextLength
        $script:logBox.ScrollToCaret()
    }
    if ($IsError) {
        [System.Windows.Forms.MessageBox]::Show($Message, 'Takeown Tool', 'OK', 'Error') | Out-Null
    }
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-Elevated {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($script:driverText.Text) { $arguments += @('-DriverPath', "`"$($script:driverText.Text)`"") }
    if ($script:targetText.Text) { $arguments += @('-TargetPath', "`"$($script:targetText.Text)`"") }
    $arguments += '-ElevatedRun'
    Start-Process powershell.exe -Verb RunAs -ArgumentList ($arguments -join ' ')
}

function Invoke-Native {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList
    )
    $result = & $FilePath @ArgumentList 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath 失敗 (exit code $LASTEXITCODE)：$($result -join ' ')"
    }
    return $result
}

function Find-DriverPackage {
    param([string]$DriverFile, [string]$SearchRoot)
    $driverName = [IO.Path]::GetFileName($DriverFile)
    $directMatch = Join-Path $SearchRoot $driverName
    if (Test-Path -LiteralPath $directMatch -PathType Leaf) {
        return Get-Item -LiteralPath $SearchRoot
    }

    $folders = Get-ChildItem -LiteralPath $SearchRoot -Directory -Filter '*.inf_*' -ErrorAction Stop
    $matches = @($folders | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName $driverName) })
    if ($matches.Count -eq 0) {
        throw "在 $SearchRoot 找不到 $driverName。請將 takeown 路徑設為實際的 DriverStore package 資料夾。"
    }
    if ($matches.Count -gt 1) {
        throw "找到多個包含 $driverName 的 package，請把 takeown 路徑直接設為正確的 package 資料夾。"
    }
    return $matches[0]
}

function Get-InfVersion {
    param([string]$InfPath)
    $line = Get-Content -LiteralPath $InfPath | Where-Object { $_ -match '^\s*DriverVer\s*=' } | Select-Object -First 1
    if ($null -eq $line) { return $null }
    if ($line -match ',\s*([0-9]+(?:\.[0-9]+){1,3})\s*$') { return $Matches[1] }
    return $null
}

function Get-DeviceManagerVersions {
    param([string]$InfName)
    $devices = @(Get-CimInstance Win32_PnPSignedDriver -Filter "InfName='$InfName'" -ErrorAction SilentlyContinue)
    return @($devices | Where-Object { $_.DriverVersion } | Select-Object -ExpandProperty DriverVersion -Unique)
}

function Invoke-DriverReplacement {
    $driverFile = $script:driverText.Text.Trim()
    $requestedTarget = $script:targetText.Text.Trim()
    if (-not (Test-Path -LiteralPath $driverFile -PathType Leaf)) { throw '請先拖入有效的 .sys 檔案。' }
    if ([IO.Path]::GetExtension($driverFile).ToLowerInvariant() -ne '.sys') { throw '拖入的檔案必須是 .sys driver。' }
    if (-not (Test-Path -LiteralPath $requestedTarget -PathType Container)) { throw 'takeown 資料夾路徑不存在。' }

    $package = Find-DriverPackage -DriverFile $driverFile -SearchRoot $requestedTarget
    $inf = Get-ChildItem -LiteralPath $package.FullName -Filter '*.inf' -File | Select-Object -First 1
    if ($null -eq $inf) { throw "找不到 $($package.FullName) 內的 INF 檔案。" }
    $infVersion = Get-InfVersion -InfPath $inf.FullName
    $deviceVersions = @(Get-DeviceManagerVersions -InfName $inf.Name)
    Write-Log "Package：$($package.Name)"
    Write-Log "INF：$($inf.Name)，DriverVer：$infVersion"
    Write-Log "Device Manager 版本：$(if ($deviceVersions.Count) { $deviceVersions -join ', ' } else { '未找到相同 INF 的裝置' })"
    if ($null -eq $infVersion -or $deviceVersions.Count -eq 0 -or $deviceVersions -notcontains $infVersion) {
        throw '版本核對未通過：INF DriverVer 必須與 Device Manager 顯示的版本一致。未進行任何修改。'
    }

    $targetDriver = Join-Path $package.FullName ([IO.Path]::GetFileName($driverFile))
    $originalDriver = Join-Path $package.FullName (([IO.Path]::GetFileNameWithoutExtension($driverFile)) + '_ori.sys')
    if (-not (Test-Path -LiteralPath $targetDriver -PathType Leaf)) { throw "package 內找不到原始 driver：$([IO.Path]::GetFileName($driverFile))" }
    if (Test-Path -LiteralPath $originalDriver) { throw "備份檔已存在：$([IO.Path]::GetFileName($originalDriver))。為避免覆蓋，流程已停止。" }

    $confirmation = [System.Windows.Forms.MessageBox]::Show(
        "版本已核對。`r`n`r`n將修改：$($package.FullName)`r`n啟用 testsigning，並寫入 GraphicsDrivers 設定。`r`n`r`n確定繼續嗎？",
        '最後確認', 'YesNo', 'Warning')
    if ($confirmation -ne 'Yes') { Write-Log '使用者取消執行。'; return }

    Write-Log '取得資料夾擁有權...'
    Invoke-Native 'takeown.exe' @('/f', $package.FullName, '/r', '/d', 'y') | Out-Null
    Write-Log '授予 Everyone 完整控制權...'
    Invoke-Native 'icacls.exe' @($package.FullName, '/grant', 'Everyone:(OI)(CI)F', '/t', '/c') | Out-Null
    Write-Log "備份原始 driver 為 $([IO.Path]::GetFileName($originalDriver))..."
    Move-Item -LiteralPath $targetDriver -Destination $originalDriver
    Copy-Item -LiteralPath $driverFile -Destination $targetDriver
    Write-Log '寫入 DisableVersionMismatchCheck...'
    Invoke-Native 'reg.exe' @('add', 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers', '/v', 'DisableVersionMismatchCheck', '/t', 'REG_DWORD', '/d', '0x1', '/f') | Out-Null
    Write-Log '啟用 testsigning...'
    Invoke-Native 'bcdedit.exe' @('/set', 'testsigning', 'on') | Out-Null
    Write-Log '完成。重新啟動 Windows 後，測試簽章狀態才會完整套用。'
    [System.Windows.Forms.MessageBox]::Show('驅動替換完成。請重新啟動 Windows。', 'Takeown Tool', 'OK', 'Information') | Out-Null
}

$form = New-Object Windows.Forms.Form
$form.Text = 'Takeown Tool - Driver Replacement'
$form.Size = New-Object Drawing.Size(760, 570)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object Drawing.Size(700, 500)

$title = New-Object Windows.Forms.Label
$title.Text = 'Driver Replacement / Takeown'
$title.Font = New-Object Drawing.Font('Segoe UI', 16, [Drawing.FontStyle]::Bold)
$title.Location = New-Object Drawing.Point(24, 18)
$title.AutoSize = $true
$form.Controls.Add($title)

$warning = New-Object Windows.Forms.Label
$warning.Text = '警告：此工具會修改 DriverStore、登錄檔與 boot configuration，僅限測試機使用。'
$warning.ForeColor = [Drawing.Color]::DarkRed
$warning.Location = New-Object Drawing.Point(26, 55)
$warning.AutoSize = $true
$form.Controls.Add($warning)

function Add-InputRow {
    param([string]$LabelText, [int]$Top, [string]$Value)
    $label = New-Object Windows.Forms.Label
    $label.Text = $LabelText
    $label.Location = New-Object Drawing.Point(26, $Top)
    $label.AutoSize = $true
    $form.Controls.Add($label)
    $box = New-Object Windows.Forms.TextBox
    $box.Location = New-Object Drawing.Point(26, ($Top + 22))
    $box.Size = New-Object Drawing.Size(670, 26)
    $box.AllowDrop = $true
    $box.Text = $Value
    $form.Controls.Add($box)
    return $box
}

$script:driverText = Add-InputRow '拖入要換上的 .sys driver（也可按右側按鈕選取）' 88 $DriverPath
$browseDriver = New-Object Windows.Forms.Button
$browseDriver.Text = '...'
$browseDriver.Location = New-Object Drawing.Point(704, 110)
$browseDriver.Size = New-Object Drawing.Size(35, 26)
$browseDriver.Add_Click({
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Filter = 'Driver files (*.sys)|*.sys|All files (*.*)|*.*'
    if ($dialog.ShowDialog() -eq 'OK') { $script:driverText.Text = $dialog.FileName }
})
$form.Controls.Add($browseDriver)

$initialTargetPath = $repositoryRoot
if ($TargetPath) { $initialTargetPath = $TargetPath }
$script:targetText = Add-InputRow 'takeown 資料夾路徑（可填 package 資料夾或 FileRepository）' 160 $initialTargetPath
$browseTarget = New-Object Windows.Forms.Button
$browseTarget.Text = '...'
$browseTarget.Location = New-Object Drawing.Point(704, 182)
$browseTarget.Size = New-Object Drawing.Size(35, 26)
$browseTarget.Add_Click({
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    if ($dialog.ShowDialog() -eq 'OK') { $script:targetText.Text = $dialog.SelectedPath }
})
$form.Controls.Add($browseTarget)

$script:logBox = New-Object Windows.Forms.TextBox
$script:logBox.Multiline = $true
$script:logBox.ReadOnly = $true
$script:logBox.ScrollBars = 'Vertical'
$script:logBox.Location = New-Object Drawing.Point(26, 245)
$script:logBox.Size = New-Object Drawing.Size(713, 220)
$form.Controls.Add($script:logBox)

$script:executeButton = New-Object Windows.Forms.Button
$script:executeButton.Text = 'Execute'
$script:executeButton.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
$script:executeButton.Location = New-Object Drawing.Point(26, 480)
$script:executeButton.Size = New-Object Drawing.Size(130, 36)
$script:executeButton.Add_Click({
    try {
        if (-not (Test-Administrator)) { Start-Elevated; $form.Close(); return }
        $script:executeButton.Enabled = $false
        Invoke-DriverReplacement
    } catch { Write-Log $_.Exception.Message $true; $script:executeButton.Enabled = $true }
})
$form.Controls.Add($script:executeButton)

$script:driverText.Add_DragEnter({ if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = 'Copy' } })
$script:driverText.Add_DragDrop({
    $files = $_.Data.GetData([Windows.Forms.DataFormats]::FileDrop)
    if ($files.Count -gt 0) { $script:driverText.Text = $files[0] }
})

$form.Add_Shown({
    Write-Log "FileRepository：$repositoryRoot"
    Write-Log '請確認拖入檔案與 takeown 路徑後按 Execute。'
    if ($ElevatedRun) { $form.BeginInvoke([Action]{ $script:executeButton.PerformClick() }) | Out-Null }
})
[void]$form.ShowDialog()