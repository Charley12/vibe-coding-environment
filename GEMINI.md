# Vibe Coding 規範速覽 (GEMINI.md)

> 本專案受嚴格後端架構與邊界約束規範，詳細規範請參閱 [`.gemini/rules.md`](file:///.gemini/rules.md)。

## 核心摘要

1. **架構分層 (Clean Architecture)**
   - 遵循 `Domain -> UseCase -> Controller -> Infrastructure` 單向依賴，禁止反向依賴。
   - Domain 層保持純粹，禁止包含 ORM 實體或 HTTP 上下文。
2. **邊界防護 (Boundary Protection)**
   - 所有外部請求第一道防線必須經過嚴格強型別 Schema 白名單校驗。
   - 狀態變更、金額計算、庫存扣減必須具備資料庫 Transaction 與冪等性 (Idempotency)。
   - 防範負數、零值、超長字串、時區偏差與並發 Race Condition；全面落實 IDOR 水平越權檢驗。
3. **三階段工作協議 (Three-Phase Protocol)**
   - **Phase 1 (規劃與邊界分析)**：禁止先寫代碼！根據 `specs/templates/task-spec.md` 產出 `specs/<TICKET>/spec.md` 與邊界矩陣，等待確認。
   - **Phase 2 (TDD 實作)**：將邊界條件化為 Red 測試案例，以最精簡代碼推進為 Green，再進行 Refactor。
   - **Phase 3 (驗證閉環)**：執行 `bash scripts/agent-verify.sh`，Typecheck、Lint、Test 全綠才算完成。
4. **禁止幽靈重構 (No Phantom Refactoring)**
   - 未經允許不得修改非需求範圍內的既有架構與公共介面。
5. **命令執行白名單與安全阻斷 (Command Permissions)**
   - 自動核准唯讀查詢 (`cat`, `ls`, `grep`, `git status/diff/log`)、型別檢查與測試 (`pnpm/npm/go/pytest`) 及 `scripts/agent-verify.sh`。
   - 涉及 `rm`, `git reset`, `git push`, `sudo`, `curl`, `wget` 必須提示人類確認，嚴禁擅自執行。詳見 [`.gemini/permissions.json`](file:///.gemini/permissions.json)。

