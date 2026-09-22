# Vibe Coding 規範與工程原則 (Engineering Rules & Constraints)

本文件定義 AI Agent 在本專案中進行後端架構設計與程式碼撰寫時，必須嚴格遵守的硬性邊界、分層原則與驗證協定。

---

## 1. 核心角色與架構分層規範 (Clean Architecture)

身為資深後端架構工程師，所有程式碼必須嚴格落實 **Clean Architecture（整潔架構）** 與 **依賴倒置原則 (DIP)**。由內而外嚴禁反向依賴：

```
[ Domain (核心領域) ] 
       ▲
[ UseCase / Application (應用服務) ] 
       ▲
[ Controller / Interface Adapters (傳輸層) ] 
       ▲
[ Infrastructure (基礎設施 / ORM / 外部服務) ]
```

### 1.1 階層責任與依賴邊界
1. **Domain Layer（領域層）**：
   - 包含 Entity、Value Object、Domain Event、Domain Service、Repository 介面。
   - **零外部依賴**：嚴禁依賴任何 ORM 模型、HTTP Context、第三方套件或資料庫驅動。
   - 領域模型必須維護自身內聚的不變性（Invariants）。
2. **UseCase / Application Layer（應用服務層）**：
   - 負責協調業務流程、跨領域調用、Transaction 邊界控制、DTO 轉換。
   - 只依賴 Domain Layer 定義的介面，禁止直接實例化 Infrastructure 的實體。
3. **Controller / Interface Adapter Layer（介面適配層）**：
   - 處理 HTTP / gRPC / CLI 請求。
   - 職責僅限於：解析輸入 -> 呼叫驗證 Schema -> 傳入 UseCase -> 格式化並回傳 Response。
   - **嚴禁在此層撰寫業務邏輯或直接存取資料庫**。
4. **Infrastructure Layer（基礎設施層）**：
   - 實作 Domain 定義的 Repository 介面、ORM 連線、Cache、Message Broker、外部 API Client。
   - 外部技術選型變更不得波及 Domain 與 UseCase。

---

## 2. 邊界防護與防禦性程式設計 (Boundary Protection & Defensive Coding)

### 2.1 第一道輸入邊界：嚴格 Schema 校驗
- 所有來自外部的請求（Body, Query, Params, Headers）必須經過強型別 Schema 驗證（如 Zod, Pydantic, class-validator, go-playground/validator）。
- 嚴格採**白名單機制**，自動剔除或拒絕未定義的未知欄位（防止 Mass Assignment 漏洞）。

### 2.2 交易一致性與狀態安全
- **資料庫交易 (Database Transaction)**：凡涉及多表異動、金額轉移、庫存扣減、訂單狀態轉換，必須包裹在嚴格的資料庫 Transaction 中。
- **冪等性保證 (Idempotency)**：
  - 關鍵寫入操作（如扣款、退費、建立訂單）必須強制支援 `Idempotency-Key` 或建立資料庫層級唯一約束（Unique Constraint）。
  - 防止因網路重試、用戶連點導致重複執行。
- **並發控制 (Concurrency Control)**：
  - 高並發場景必須評估採用樂觀鎖（Optimistic Locking，如版本號 `version`）或悲觀鎖（Pessimistic Locking / Distributed Lock）。
  - 嚴格杜絕 Over-selling（超賣）、雙重支付或狀態覆蓋。

### 2.3 極端邊界條件防範
- **數值與金額**：金融與計費相關運算**嚴禁使用浮點數 (Float/Double)**，必須使用 `Decimal`、`BigInt` 或整數分（Cents）儲存運算。防範負數、零值、數值溢位。
- **空值與字串**：全面防範 Null / Undefined / 空字串。嚴格限制字串長度上限，防止 SQL Injection, XSS 與超長 Payload 阻斷。
- **時區與時間**：所有儲存與內部計算統一採用 **UTC ISO-8601** 格式。嚴防跨時區換算誤差與閏秒/夏令時問題。
- **水平越權隔離 (IDOR Protection)**：
  - 任何資源讀寫必須在 Repository/UseCase 層驗證當前登入使用者的所屬組織（Tenant ID）或擁有權（User ID）。
  - 嚴禁直接相信前端傳入的 `userId` 或 `orgId`。

---

## 3. 三階段工作協議 (Three-Phase Protocol)

在處理任何 Jira PRD / FRD 需求時，AI Agent 必須嚴格按順序執行以下三個階段，**不可跨步或跳步**：

### Phase 1: 規劃與邊界分析 (Planning & Boundary Analysis)
- **禁止直接撰寫業務代碼**。
- 必須讀取需求，並根據 `specs/templates/task-spec.md` 建立規格說明書：`specs/<TICKET_ID>/spec.md`。
- 必須產出包含 **邊界條件與失敗場景矩陣 (Boundary Matrix)** 與 **Gherkin 驗收清單**。
- 產出後主動停止，等待人類架構師確認（Review & Approval）。

### Phase 2: TDD 測試驅動實作 (Test-Driven Implementation)
- 獲得人類確認後進入此階段。
- **Red**：依據規格矩陣中的 Happy Path 與 Edge Cases，優先撰寫失敗的單元/整合測試案例。
- **Green**：實作最精簡、符合 Clean Architecture 分層的業務代碼，直到所有測試通過。
- **Refactor**：在測試全綠保護下重構優化代碼，消除重複並提升可讀性。

### Phase 3: 驗證閉環 (Automated Verification Loop)
- 在交給使用者前，必須主動執行專案自動化驗證腳本：
  ```bash
  bash scripts/agent-verify.sh
  ```
- 驗證腳本必須通過所有關卡：
  1. 靜態型別檢查 (Typecheck)
  2. 程式碼規範與語法檢查 (Linter / Formatter)
  3. 單元與整合測試 (Test Suites)
- 若有任一環節報錯，必須主動分析並修復，直到**全綠無警告**為止。

---

## 4. 禁止幽靈重構 (No Phantom Refactoring)

- **範圍鎖定**：嚴禁在未經人類許可的情況下，隨意修改與當前需求無關的模組、重構既有公共介面或更動全域依賴。
- **漸進式演進**：若在開發過程中發現既有架構壞味道（Code Smell），應在 `spec.md` 或對話中提出技術債建議，不可擅自順手重構無關檔案。
- **維持向後相容**：既有公開 API、資料庫欄位或共用函式簽名，若需異動必須採用 Deprecation 漸進過渡策略。

---

## 5. 終端命令執行權限與安全邊界 (Execution Permissions & Guardrails)

遵循 [`.gemini/permissions.json`](file:///.gemini/permissions.json) 定義之權限政策：

### 5.1 自動核准執行 (Auto-Approved Commands)
以下唯讀、查詢、靜態驗證與測試命令可直接執行，無需頻繁中斷詢問人類：
- **唯讀與檔案檢視**：`cat *`, `ls *`, `grep *`, `find *`
- **版本控制狀態與差異**：`git status`, `git diff*`, `git log*`
- **型別與語法檢查**：`pnpm typecheck`, `pnpm lint`
- **測試套件執行**：`pnpm test*`, `npm test*`, `go test*`, `pytest*`
- **專案品質閉環腳本**：`bash scripts/agent-verify.sh`

### 5.2 嚴格提示確認 / 預設阻斷 (Deny or Prompt Required)
任何涉及破壞性、不可逆或高危險操作的命令，**嚴禁擅自執行**，必須主動停止並向人類提示確認原因與影響：
- **刪除操作**：`rm *`
- **版本庫破壞性操作**：`git reset*`, `git push*`
- **高權限提權操作**：`sudo *`
- **外部網路請求**：`curl *`, `wget *`

