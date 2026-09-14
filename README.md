# TakeownTool

Windows driver replacement helper with a drag-and-drop GUI.

## 使用方式

1. 雙擊 `Run-TakeownTool.cmd`。
2. 將要替換的 `.sys` 拖入第一個欄位。
3. 第二個欄位預設為 `C:\Windows\System32\DriverStore\FileRepository`，也可以直接填入特定的 `*.inf_*` package 資料夾。
4. 按 `Execute`。工具會要求系統管理員權限，找到包含該 `.sys` 的 package，核對 INF `DriverVer` 與 `Win32_PnPSignedDriver` 的 Device Manager 版本。
5. 只有版本一致且使用者再次確認後，才會執行 `takeown`、`icacls`、原始檔備份、driver 複製、登錄檔設定與 `bcdedit /set testsigning on`。

原始 driver 會保留為 `<driver-name>_ori.sys`；若備份檔已存在，工具會停止以避免覆寫。

若需要單一執行檔，請以 PowerShell 執行 `Build-TakeownTool.ps1`。它使用 Windows 內建 IExpress 產生 `TakeownTool.exe`；執行檔是自解壓縮啟動器，原始 `TakeownTool.ps1` 仍應與它一起保留，方便檢查和重新封裝。

## 注意事項

- 這會修改受保護的 Windows DriverStore、HKLM 與 BCD，請只在有完整備份的測試機使用。
- `testsigning on` 通常需要重新啟動才會生效，也會降低 Windows 驅動簽章防護。
- 工具使用 PowerShell WinForms，不需要安裝第三方套件。若要產生單一 `.exe`，可在有 .NET SDK 的環境中使用 PS2EXE 等受信任的封裝工具；目前專案刻意保留原始 `.ps1` 方便稽核每一個系統操作。