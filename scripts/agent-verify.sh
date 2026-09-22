#!/usr/bin/env bash
# ==============================================================================
# agent-verify.sh
# 
# 自動化驗證閉環腳本 (Automated Verification Loop)
# 自動偵測專案後端語言與套件管理工具，依序執行：
# 1. 靜態型別檢查 (Typecheck)
# 2. 語法與風格檢查 (Lint)
# 3. 單元與整合測試 (Test Suite)
#
# 任何步驟失敗將立即以非零狀態碼中斷 (set -euo pipefail)。
# ==============================================================================

set -euo pipefail

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_step() {
    echo -e "\n${BLUE}${BOLD}==>${NC} ${BOLD}$1${NC}"
}

log_success() {
    echo -e "${GREEN}✔ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

log_error() {
    echo -e "${RED}✖ $1${NC}"
}

echo -e "${BOLD}====================================================${NC}"
echo -e "${BOLD}     Antigravity 後端自動化品質驗證閉環 (Verify)      ${NC}"
echo -e "${BOLD}====================================================${NC}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# 偵測套件管理器 (Node.js)
detect_node_pm() {
    if [ -f "pnpm-lock.yaml" ] && command -v pnpm &> /dev/null; then
        echo "pnpm"
    elif [ -f "yarn.lock" ] && command -v yarn &> /dev/null; then
        echo "yarn"
    elif [ -f "bun.lockb" ] || [ -f "bun.lock" ] && command -v bun &> /dev/null; then
        echo "bun"
    elif [ -f "package-lock.json" ] && command -v npm &> /dev/null; then
        echo "npm"
    elif command -v pnpm &> /dev/null; then
        echo "pnpm"
    elif command -v yarn &> /dev/null; then
        echo "yarn"
    elif command -v bun &> /dev/null; then
        echo "bun"
    else
        echo "npm"
    fi
}

# 檢查 package.json 是否具備特定 script
has_package_script() {
    local script_name="$1"
    if [ ! -f "package.json" ]; then
        return 1
    fi
    # 簡易 grep 檢查
    grep -q "\"$script_name\"[[:space:]]*:" package.json
}

# ------------------------------------------------------------------------------
# 語言偵測與驗證流程
# ------------------------------------------------------------------------------

DETECTED_LANG=""

# 1. Node.js / TypeScript 專案
if [ -f "package.json" ]; then
    DETECTED_LANG="Node/TypeScript"
    PM=$(detect_node_pm)
    log_step "偵測到 Node.js/TypeScript 專案，使用套件管理器: ${PM}"

    # 1.1 Typecheck
    log_step "[1/3] 執行靜態型別檢查 (Typecheck)..."
    if has_package_script "typecheck"; then
        $PM run typecheck
        log_success "Typecheck 通過 (npm script: typecheck)"
    elif has_package_script "type-check"; then
        $PM run type-check
        log_success "Typecheck 通過 (npm script: type-check)"
    elif [ -f "tsconfig.json" ]; then
        if command -v npx &> /dev/null; then
            npx tsc --noEmit
            log_success "Typecheck 通過 (npx tsc --noEmit)"
        else
            log_warning "未找到 npx，跳過獨立 tsc 檢查"
        fi
    else
        log_warning "未設定 TypeScript 或未找到 tsconfig.json，跳過 Typecheck"
    fi

    # 1.2 Lint
    log_step "[2/3] 執行代碼風格與語法檢查 (Lint)..."
    if has_package_script "lint"; then
        $PM run lint
        log_success "Lint 檢查通過"
    elif has_package_script "check"; then
        $PM run check
        log_success "Lint/Check 檢查通過"
    else
        log_warning "package.json 中未定義 lint 腳本，跳過 Lint"
    fi

    # 1.3 Test Suite
    log_step "[3/3] 執行測試套件 (Test Suites)..."
    if has_package_script "test"; then
        $PM run test
        log_success "測試套件全數通過！"
    else
        log_warning "package.json 中未定義 test 腳本"
    fi

# 2. Go 專案
elif [ -f "go.mod" ]; then
    DETECTED_LANG="Go"
    log_step "偵測到 Go 專案"

    # 2.1 Typecheck & Vet
    log_step "[1/3] 執行 Go Vet 與靜態分析..."
    go vet ./...
    log_success "go vet 通過"

    # 2.2 Lint
    log_step "[2/3] 執行 Linter 檢查..."
    if command -v golangci-lint &> /dev/null; then
        golangci-lint run ./...
        log_success "golangci-lint 通過"
    else
        log_warning "系統未安裝 golangci-lint，建議安裝以強化靜態檢查"
    fi

    # 2.3 Tests
    log_step "[3/3] 執行 Go 測試 (含 Race Detector)..."
    go test -race -v ./...
    log_success "Go 測試套件全數通過！"

# 3. Python 專案
elif [ -f "pyproject.toml" ] || [ -f "requirements.txt" ] || [ -f "Pipfile" ] || [ -f "poetry.lock" ] || [ -f "uv.lock" ]; then
    DETECTED_LANG="Python"
    log_step "偵測到 Python 專案"

    # 判斷 Python 執行環境
    PY_RUNNER="python"
    if command -v uv &> /dev/null && [ -f "uv.lock" ]; then
        PY_RUNNER="uv run"
    elif command -v poetry &> /dev/null && [ -f "poetry.lock" ]; then
        PY_RUNNER="poetry run"
    elif command -v pipenv &> /dev/null && [ -f "Pipfile" ]; then
        PY_RUNNER="pipenv run"
    fi

    # 3.1 Typecheck
    log_step "[1/3] 執行靜態型別檢查 (mypy/pyright)..."
    if command -v mypy &> /dev/null || ($PY_RUNNER mypy --version &> /dev/null); then
        $PY_RUNNER mypy .
        log_success "mypy 型別檢查通過"
    else
        log_warning "未安裝 mypy，跳過型別檢查"
    fi

    # 3.2 Lint
    log_step "[2/3] 執行代碼品質與 Linter 檢查 (ruff/flake8)..."
    if command -v ruff &> /dev/null || ($PY_RUNNER ruff --version &> /dev/null); then
        $PY_RUNNER ruff check .
        log_success "ruff linter 通過"
    elif command -v flake8 &> /dev/null || ($PY_RUNNER flake8 --version &> /dev/null); then
        $PY_RUNNER flake8 .
        log_success "flake8 通過"
    else
        log_warning "未安裝 ruff 或 flake8，跳過 Lint"
    fi

    # 3.3 Tests
    log_step "[3/3] 執行單元與整合測試 (pytest)..."
    if command -v pytest &> /dev/null || ($PY_RUNNER pytest --version &> /dev/null); then
        $PY_RUNNER pytest -v
        log_success "pytest 測試套件全數通過！"
    else
        $PY_RUNNER -m unittest discover -s .
        log_success "unittest 測試套件全數通過！"
    fi

# 4. Java / Kotlin 專案
elif [ -f "pom.xml" ]; then
    DETECTED_LANG="Java (Maven)"
    log_step "偵測到 Java Maven 專案"

    log_step "[1/2] 執行編譯與檢查..."
    mvn clean compile -DskipTests=true
    log_success "編譯成功"

    log_step "[2/2] 執行測試套件..."
    mvn test
    log_success "Maven 測試套件全數通過！"

elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
    DETECTED_LANG="Java/Kotlin (Gradle)"
    log_step "偵測到 Gradle 專案"

    GRADLE_CMD="./gradlew"
    if [ ! -f "$GRADLE_CMD" ]; then
        GRADLE_CMD="gradle"
    fi

    log_step "[1/2] 執行代碼檢查 (check)..."
    $GRADLE_CMD check -x test
    log_success "Gradle check 通過"

    log_step "[2/2] 執行測試套件 (test)..."
    $GRADLE_CMD test
    log_success "Gradle 測試套件全數通過！"

# 5. Rust 專案
elif [ -f "Cargo.toml" ]; then
    DETECTED_LANG="Rust"
    log_step "偵測到 Rust 專案"

    log_step "[1/3] 執行型別與編譯檢查 (cargo check)..."
    cargo check --all-targets
    log_success "cargo check 通過"

    log_step "[2/3] 執行 Clippy 靜態檢查..."
    cargo clippy --all-targets -- -D warnings
    log_success "cargo clippy 通過"

    log_step "[3/3] 執行測試套件 (cargo test)..."
    cargo test
    log_success "cargo test 全數通過！"

else
    log_warning "目前目錄尚未偵測到支援的後端專案結構 (Node.js, Go, Python, Java, Rust)。"
    log_warning "請先初始化後端專案結構或依賴檔案（如 package.json, go.mod, pyproject.toml 等）。"
    exit 0
fi

echo -e "\n${GREEN}${BOLD}====================================================${NC}"
echo -e "${GREEN}${BOLD}  🎉 所有品質與邊界檢查全數通過！(Language: ${DETECTED_LANG}) ${NC}"
echo -e "${GREEN}${BOLD}====================================================${NC}"
exit 0
