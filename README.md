# DualAI iPhone App V1.2：可切換多家 API

不需自己的 Mac。GitHub Actions 的 macOS runner 會把 Swift App 編譯為 iPhone 的 ARM64 執行檔，再封裝成未簽署 IPA。這不是改副檔名，也不是直接可安裝的簽署 IPA。

## App 內容

- 內建手機版 HTML/CSS/JS，不需登入網站或網路就能使用示範。
- A/B 流程、支援的數學與教學範例、本機歷史紀錄。
- 原生分享介面匯出 JSON；原生確認介面清除紀錄。
- iOS 最低版本 16.0，iPhone/iPad。示範模式不呼叫 AI；真實模式由手機直接連線，無需電腦代理後端。專案不含任何真實 Key。
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

## API 管理與真正的連線測試

1. App 右上角點「API 管理」→「新增 API／模型」。
2. 選 OpenAI、Claude、Gemini 或 OpenAI 相容格式，填顯示名稱、模型 ID 與 Key。相容服務需填 HTTPS Base URL，例如 `https://你的服務/v1`，不要包含 `/chat/completions`。
3. 儲存只顯示「已設定 · 尚未測試」。按「測試連線」才會送出一個小型真實模型請求；可能產生 API 費用。
4. 只有 HTTP 成功、API JSON 可解析且模型文字非空，才記錄「最近連線測試成功」。畫面顯示 HTTP 狀態、延遲、回覆、供應商回報模型（若有）、token usage（若有）與測試時間。401/403、404、429、5xx、無效 JSON 或空文字皆標示失敗。未內建假的成功狀態。
5. 選擇 A 的模型；勾選 2–6 個不同端點／模型參與 B。先完成所選模型的連線測試，再啟用「使用真實 API」。未啟用時保留示範模式。

連線測試成功只代表該時間收到有效回覆，不能保證模型身份、回答正確或未來永遠在線。第三方相容端點可能只支援部分參數；必須實際測試。實際請求模型與供應商回報模型都保留於 ledger，並不聲稱能驗證模型權重身份。

Key 存在手機 Keychain（WhenUnlockedThisDeviceOnly），不交給 WKWebView、不放入 UserDefaults 或匯出 JSON。模型設定與測試摘要保存在本機 UserDefaults。更換端點需要重新輸入 Key；儲存設定會清除舊測試狀態，避免把過期測試當成新設定已連線。刪除設定也會刪除對應 Keychain 項目。

真實分析失敗就報錯，不回退為示範；費用未估算時顯示「未估算」，不捏造數值。A 共五次成功呼叫；B 共 2N+1 次，包含仲裁。停止會取消目前的手機任務，但供應商已接收的請求仍可能計費。

## 測試範圍

雲端建置先編譯並執行 Swift 離線 adapter/pipeline 測試，覆蓋四種 API 格式、HTTP 錯誤、2xx 空回覆／無效 JSON、端點驗證、交叉審查排除自己、完整 usage、判官、重複模型與匯出資料不含 Key，再編譯 iOS App。本次未取得真實 API Key，未宣稱供應商實連已通過；實體手機 UI、Keychain 與安裝仍待實機確認。

## 有 Mac 時

直接開啟 DualAI.xcodeproj，在 Signing & Capabilities 選自己的 Team 並設定唯一 Bundle Identifier，連接 iPhone 後 Run。也可執行 `bash scripts/build-unsigned.sh` 做無簽署封裝。

## 官方資料

- [GitHub-hosted runners](https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners)
- [macOS 15 runner](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)
- [Apple：在裝置執行 App](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html)
- [Sideloadly：Windows 側載與 Apple 帳號簽署](https://sideloadly.io/)
