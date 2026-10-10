# DualAI iPhone App（雲端 Mac 建置）

不需自己的 Mac。GitHub Actions 的 macOS runner 會把 Swift App 編譯為 iPhone 的 ARM64 執行檔，再封裝成未簽署 IPA。這不是改副檔名，也不是直接可安裝的簽署 IPA。

## App 內容

- 內建手機版 HTML/CSS/JS，不需登入網站或網路就能使用示範。
- A/B 流程、支援的數學與教學範例、本機歷史紀錄。
- 原生分享介面匯出 JSON；原生確認介面清除紀錄。
- iOS 最低版本 16.0，iPhone/iPad。示範模式不呼叫 AI，未包含真實 API 後端或任何 Key。
- 沒有推播、帳號註冊、追蹤 SDK 或第三方 Swift 套件。

## 雲端建置

1. 建立私人 GitHub repository，勾選 Add a README file（保留初始 commit，方便連接器上傳）。
2. 將本專案上傳到 repository 根目錄，包含 `.github/workflows/build-ios.yml`。
3. Push 到 main 會觸發 `Build DualAI IPA`。也可從 Actions → Build DualAI IPA → Run workflow 啟動。
4. 成功後，在該次 run 的 Artifacts 下載 `DualAI-unsigned-IPA`，解壓取得 `DualAI-unsigned.ipa` 與 SHA256。

雲端建置只需要 GitHub，不需要把 Apple 密碼、簽署證書或 API Key 放到 repository。私有 repository 的 Actions 使用量仍受帳號額度限制；若需要加購，請自行決定，不會自動設定付費。

## Windows 安裝

1. 從 [Sideloadly 官方網站](https://sideloadly.io/) 下載 Windows 版，依工具要求準備 Apple 裝置連線元件。
2. 以 USB 連接 iPhone，解鎖並在手機上信任這台電腦。
3. 將 `DualAI-unsigned.ipa` 拖入 Sideloadly，選擇自己的裝置。
4. 由你自行在工具內登入 Apple 帳號，完成簽署及安裝；不要把密碼傳給聊天助理。
5. 依 iPhone 實際提示完成開發者模式或開發者 App 信任。一般免費帳號的側載需定期重新簽署，依工具與帳號的實際狀態為準。

沒有實體 iPhone 與 Apple 簽署設定，因此安裝、原生分享及首次啟動需在裝置上驗證；雲端編譯成功也不等於已通過實機測試。

## 有 Mac 時

直接開啟 DualAI.xcodeproj，在 Signing & Capabilities 選自己的 Team 並設定唯一 Bundle Identifier，連接 iPhone 後 Run。也可執行 `bash scripts/build-unsigned.sh` 做無簽署封裝。

## 官方資料

- [GitHub-hosted runners](https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners)
- [macOS 15 runner](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)
- [Apple：在裝置執行 App](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html)
- [Sideloadly：Windows 側載與 Apple 帳號簽署](https://sideloadly.io/)
