# LuLu_Plus

[English](README.md) | [简体中文](README_zh-Hans.md)

LuLu_Plus 是一款免費的開源 macOS 防火牆，由 [imonior](https://github.com/imonior) 開發，倉庫位址為
[github.com/imonior/LuLu-Plus](https://github.com/imonior/LuLu-Plus)。

**來源說明：** \
LuLu_Plus 衍生自 [Objective-See](https://objective-see.com) 的 [LuLu](https://github.com/objective-see/LuLu)，
基線為 2026 年 10 月 4 日的 master 分支程式碼（4.5.1 發佈之後、4.5.2 發佈之前），而非 4.5.1 標籤本身。出站防火牆、
規則模型、提醒流程以及系統擴充與網路擴充的整體架構均來自該專案。感謝 Patrick Wardle 與 Objective-See 將 LuLu
開源，本專案的全部工作都建立在其成果之上。

**本 fork 新增的內容：**

- 規則帶有方向（`both`、`outbound`、`inbound`）：規則清單會說明某條規則管哪個方向，新增/編輯視窗可以選擇它
- 入站連線會被判定並回報：對端主動連進來時有自己的提醒，也會落成自己的一條規則
- profile 可以指定它適用於哪些網路（網路介面、介面類型、ssid、bssid、閘道器），新增 profile 的精靈有專門一頁來寫這些條件
- 介面名稱與 bssid 等資訊由主程式取樣後透過 XPC 交給擴充：系統擴充無法彈出定位授權對話框，而讀取這些欄位必須具備該授權
- `LuLu_Plus/Tests` 下有一組測試，其中包含變異檢查：把每個已修的 bug 重新改壞，驗證測試確實會變紅

上游專案的產品頁、擷取圖與捐款入口都不再引用：本 fork 以自身倉庫為準，檢查項的說明見
[`LuLu_Plus/Tests/README.md`](LuLu_Plus/Tests/README.md)。

## 接管的舊安裝

本建置把規則、偏好設定與 profile 存放在 `/Library/Application Support/lulu_plus`。上一個名字的安裝在
`/Library/Objective-See/LuLu`，所以本建置的擴充首次啟動時會接管那份資料：`rules.plist`、`rules_v1.plist`、
`preferences.plist` 以及整個 `Profiles` 目錄都會被搬移，舊目錄在空了之後刪除。本建置不讀取的檔案一律原地保留，
仍在存放這些檔案的目錄也同樣保留。

只要 `/Applications/LuLu.app` 還在安裝，它的檔案就是*複製*而非搬移：那個防火牆執行期間會一直從該目錄讀取這些
檔案，把它們拿走就會讓它停止過濾。

有一種情況不接管：最初版本的安裝會把程式自身放在 `/Library/Objective-See/LuLu/LuLu.bundle`。本應用不會與它並存，
並在啟動時明確提示；必須先移除舊安裝。接管流程見
[`LuLu_Plus/Tests/README.md`](LuLu_Plus/Tests/README.md)，`run_install_migration_tests.sh` 會在暫存目錄樹上執行它。

## 檢查更新

更新檢查讀取本專案的最新 GitHub release
（[`api.github.com/repos/imonior/LuLu-Plus/releases/latest`](https://api.github.com/repos/imonior/LuLu-Plus/releases/latest)），
因此標記為 `v4.5.3` 的 release 才是 4.5.2 建置所報告的更新版本。標籤不是版本號時——`latest`、`nightly`、
`v4.5.3-rc1`——會被拒絕，而不是當成某個未來的發佈；版本號按數字比較，所以 `4.5.10` 正確地位於 `4.5.2` 之後。
「有新版本」視窗裡的按鈕開啟的是 release 頁面，不是 API 的回傳內容。

未認證時該 API 每個 IP 每小時只有 60 次；超出後檢查只是回報失敗。release 並不宣告自己需要哪個 macOS，所以檢查
也不會假裝知道：它只會說明存在新版本。

## 簽章身份

程式碼裡不再寫任何人的名字：兩半各自從「正在運行的這一份建置」的簽章上讀出它的 Team
（`SecCodeCopySelf` → 憑證末端的 team），據此建構要驗證的內容（`Shared/SigningIdentity.m`）。

- 擴充對每個連進來的用戶端下一道程式碼簽章要求：必須是本建置的主程式
  （`identifier "com.imonior.lulu-plus.app"`），且由同一個 Team 簽發（`certificate leaf [subject.OU] =
  "<TEAM>"`）。macOS 13 以上，這道要求連同 `info [CFBundleShortVersionString] >= "2.0.0"` 版本下限一起交給
  監聽器（`setConnectionCodeSigningRequirement:`）；不帶下限的那一道，擴充自己在連線的 audit token 上以
  `SecTaskValidateForRequirement` 執行。簽發給其他團隊的用戶端不可能相符——Apple 不會把它沒有簽發過的 team 寫進
  憑證——於是驗證回答 `errSecCSReqFailed`（-67050），連線根本不會建立。同一條路徑還要求簽章有效且啟用加固執行
  環境（`CS_VALID` 與 `CS_RUNTIME`），所以未簽章或 ad-hoc 建置的主程式會更早一步失敗。自身簽章裡沒有 team 的
  建置沒有可釘住的對象，要求便退化為只驗證 identifier——這是弱一些的檢查，也是僅剩能做的。
- 兩半相遇的 mach service 是推導出來的，不是寫死的：擴充監聽的名稱就是它 `Info.plist` 註冊的名稱
  （`NEMachServiceName`，寫作 `$(TeamIdentifierPrefix)com.imonior.lulu-plus`，建置時展開為真正簽章者的 Team），
  運行時從該檔案讀回；主程式則從自己內嵌的 system extension 裡讀同一個鍵。`Shared/consts.h` 裡的
  `DAEMON_MACH_SERVICE` 只是基礎名，僅在兩個檔案都讀不到時使用。兩處 application-group 權限也是同樣寫法。

於是任何 Developer ID 簽這個 fork 都無需改一行：兩半都認定實際簽章的那一個。簽章的*步驟*當然仍要寫明簽章者——
Xcode 建置看 `LuLu_Plus/LuLu_Plus.xcodeproj/project.pbxproj` 裡的 `DEVELOPMENT_TEAM`，發佈看
`DMG/createDMG.sh` 裡的 `codesign --sign` 身份——但程式碼不再需要。

這一切不能消除的是：Network Extension 與 System Extension 權限屬於*受限*權限——只有當建置帶著付費 Apple
Developer Program 會員簽發的 provisioning profile 時，系統才會認帳。用免費 Apple ID 簽的、未簽章的或 ad-hoc 的
建置都能編譯，但 macOS 不會載入它的 system extension，無論 XPC 驗證怎麼說。開發機可以被設定成接受本地簽章的擴充
（關閉 SIP、開啟 developer mode），但那是逐機設定，散佈的建置不能依賴它。

Bundle id 也已變動（`com.imonior.lulu-plus`、`.app`、`.extension`），而 TCC 是按 bundle id 記錄授權的：舊主程式
被允許的能力——ssid/bssid 條件所需的定位存取——都必須對新程式重新授權一次。
