# DualAI 1.3 免費試玩

以既有原生 iOS 專案製作，最低 iOS 16；未簽名 IPA 需要另行簽名才可安裝。
API 管理：快速新增 Groq 回答與 Gemini 判官，填入各自的 Key，確認帳號未開啟付費，執行真實連線測試。A 選一個 Groq 回答者，B 勾選兩個不同 Groq 模型；Gemini 判官不勾選參與 B。
沒有內建 Key、Google 登入、伺服器每日額度；需自行申請供應商免費 API Key。App 無法驗證帳單或讀取剩餘額度。
試玩清單：Groq GPT-OSS 20B/120B，Gemini 3.8 Flash/3.6 Flash。供應商可改變模型可用性與免費方案；回覆錯誤即停止，沒有自動重試、換模型或轉付費。
Llama 聊天模型目前在 Groq 官方列表標為 Enterprise，未列入免費試玩清單。Meta AI 可複製資料手動複審，貼回結果標示未驗證來源，不計為 API 呼叫。
沒有外部事實檢索；獨立判官與較嚴格提示仍不能保證答案真實。
Key 保存在裝置 Keychain，報告不包含 Key。手動複審資料由使用者主動複製與貼入第三方。

官方資料（2026-10-11 檢查）：
- https://console.groq.com/docs/models
- https://ai.google.dev/gemini-api/docs/pricing

驗證：GitHub Actions 編譯 Swift fixture tests、Xcode iPhone Release、檢查 Mach-O ARM64 與 IPA ZIP。真實 API Key、iPhone 安裝與裝置 UI 尚未測試。
