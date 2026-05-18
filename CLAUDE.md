# CLAUDE.md — Mole for Mac 项目上下文

> Agent 速查手册。修改本项目前必读。

## 项目概览

**Mole** 是一款 macOS 系统维护工具，集成了磁盘清理、应用卸载、系统优化、磁盘分析、实时监控等功能，定位为 CleanMyMac + AppCleaner + DaisyDisk + iStat Menus 的开源替代。

- **仓库**: `tw93/mole`（GitHub），本地 fork 在 `~/Projects/mole-for-mac/`
- **许可证**: MIT
- **语言**: Bash（CLI 核心）+ Swift/SwiftUI（macOS GUI 应用）
- **版本**: 1.38.1（见 `mole` 文件 `VERSION` 变量）
- **入口**: `mo` 命令（别名 `mole`）
- **安装方式**: Homebrew (`brew install mole`) 或 `install.sh` 脚本

### 核心子命令

| 命令 | 功能 |
|------|------|
| `mo clean` | 深度清理缓存/日志/浏览器残留/开发工具 |
| `mo uninstall` | 智能卸载应用+残余文件 |
| `mo optimize` | 刷新缓存/重建服务/优化系统 |
| `mo analyze` | 磁盘空间可视化分析 |
| `mo status` | 实时系统健康监控面板 |
| `mo purge` | 清理项目构建产物（node_modules 等） |
| `mo installer` | 查找并删除安装包文件 |
| `mo touchid` | 配置 Touch ID for sudo |
| `mo completion` | Shell 自动补全 |
| `mo update` | 更新 Mole |
| `mo remove` | 卸载 Mole |

## 目录结构

```
mole-for-mac/
├── mole                          # 1060 行 · CLI 主入口，命令路由、版本管理、更新流程
├── install.sh                    # 785 行 · 脚本安装器，支持版本选择
├── Makefile                      # 12 行 · 构建 macOS App 的快捷方式
├── README.md                     # 366 行 · 项目文档
├── CONTRIBUTING.md               # 142 行 · 贡献指南
├── SECURITY.md                   # 76 行 · 安全策略
├── SECURITY_AUDIT.md             # 312 行 · 安全审计文档
├── LICENSE                       · MIT 许可证
│
├── bin/                          # CLI 子命令脚本
│   ├── clean.sh                  # 1379 行 · clean 命令主逻辑
│   ├── uninstall.sh              # 1627 行 · uninstall 命令
│   ├── optimize.sh               # 331 行 · optimize 命令
│   ├── installer.sh              # 735 行 · installer 清理命令
│   ├── status.sh                 # 15 行 · status 命令入口
│   ├── analyze.sh                # 15 行 · analyze 命令入口
│   ├── purge.sh                  # 347 行 · purge 命令
│   ├── touchid.sh                # 382 行 · Touch ID 配置
│   ├── completion.sh             # 448 行 · Shell 补全设置
│   ├── clean.sh                  # 见上
│   └── status.sh                 # 见上
│
├── lib/                          # 核心库
│   ├── core/                     # 基础设施
│   │   ├── base.sh               # 918 行 · 颜色/图标常量、路径工具、基础函数
│   │   ├── common.sh             # 230 行 · 模块加载器，路径标准化
│   │   ├── commands.sh           # 18 行 · 命令列表注册表
│   │   ├── log.sh                # 452 行 · 日志系统
│   │   ├── file_ops.sh           # 975 行 · 安全文件操作（safe_remove 等）
│   │   ├── ui.sh                 # 505 行 · UI 工具函数
│   │   ├── help.sh               # 81 行 · 帮助文本渲染
│   │   ├── timeout.sh            # 264 行 · 超时控制
│   │   ├── sudo.sh               # 330 行 · sudo 管理
│   │   ├── app_protection.sh     # 1983 行 · 应用保护机制（最大文件）
│   │   ├── bundle_resolver.sh    # 102 行 · Bundle ID 解析
│   │   └── pkg_receipts.sh       # 144 行 · 包收据查询
│   ├── ui/                       # 交互 UI
│   │   ├── menu_paginated.sh     # 930 行 · 分页菜单
│   │   ├── menu_simple.sh        # 325 行 · 简单菜单
│   │   └── app_selector.sh       # 212 行 · 应用选择器
│   ├── clean/                    # 清理模块
│   │   ├── user.sh               # 2117 行 · 用户级清理（最大文件）
│   │   ├── dev.sh                # 1571 行 · 开发工具清理
│   │   ├── project.sh            # 1645 行 · 项目构建产物清理
│   │   ├── app_caches.sh         # 532 行 · 应用缓存清理
│   │   ├── system.sh             # 538 行 · 系统级清理
│   │   ├── caches.sh             # 499 行 · 通用缓存清理
│   │   ├── apps.sh               # 873 行 · 应用相关清理
│   │   ├── hints.sh              # 824 行 · 清理提示引擎
│   │   ├── brew.sh               # 127 行 · Homebrew 清理
│   │   ├── maven.sh              # 15 行 · Maven 清理
│   │   └── purge_shared.sh       # 167 行 · purge 共享逻辑
│   ├── uninstall/                # 卸载模块
│   │   ├── batch.sh              # 1161 行 · 批量卸载
│   │   ├── brew.sh               # 256 行 · Homebrew 卸载
│   │   └── file_selector.sh      # 317 行 · 文件选择器
│   ├── optimize/                 # 优化模块
│   │   ├── tasks.sh              # 1487 行 · 优化任务定义
│   │   ├── diagnostics.sh        # 419 行 · 诊断逻辑
│   │   └── maintenance.sh        # 71 行 · 维护任务
│   ├── manage/                   # 管理功能
│   │   ├── update.sh             # 169 行 · 更新逻辑
│   │   ├── whitelist.sh          # 454 行 · 白名单管理
│   │   └── purge_paths.sh        # 117 行 · purge 路径配置
│   └── check/                    # 检查功能
│       └── health_json.sh        # 195 行 · 健康检查 JSON 输出
│
├── macos/                        # macOS GUI 应用（Swift/SwiftUI）
│   ├── MoleApp/
│   │   ├── Sources/MoleApp/
│   │   │   ├── MoleApp.swift               # 34 行 · App 入口
│   │   │   ├── ContentView.swift            # 892 行 · 主界面
│   │   │   ├── MoleRuntime.swift            # 632 行 · CLI 运行时桥接
│   │   │   ├── WorkflowPanes.swift          # 740 行 · 工作流面板
│   │   │   ├── Models.swift                 # 267 行 · 数据模型
│   │   │   ├── Adapters/                    # CLI 适配器层
│   │   │   ├── CleanEngine/                 # 清理引擎 Swift 实现
│   │   │   ├── UninstallEngine/             # 卸载引擎 Swift 实现
│   │   │   ├── OptimizeEngine/              # 优化引擎 Swift 实现
│   │   │   ├── DiskAnalyzer/                # 磁盘分析器
│   │   │   └── SystemMonitor/               # 系统监控
│   │   └── Info.plist             # 44 行
│   ├── README.md                 # 52 行 · macOS App 文档
│   └── PLAN.md                   # 313 行 · GUI 开发计划
│
├── scripts/                      # 开发脚本
│   ├── test.sh                   # 332 行 · 测试运行器
│   ├── check.sh                  # 175 行 · 格式化+lint 检查
│   ├── build-macos-app.sh        # 86 行 · 构建 macOS App
│   ├── generate-macos-icon.sh    # 63 行 · 图标生成
│   ├── setup-quick-launchers.sh  # 433 行 · Raycast/Alfred 集成
│   └── update_homebrew_tap_formula.sh  # 120 行 · Homebrew formula 更新
│
├── tests/                        # BATS 测试套件（约 35 个 .bats 文件）
│   ├── core_*.bats               · 核心功能测试
│   ├── clean_*.bats              · 清理模块测试
│   ├── uninstall_*.bats          · 卸载模块测试
│   ├── optimize.bats             · 优化模块测试
│   ├── purge.bats                · purge 测试
│   ├── installer.bats            · installer 测试
│   ├── cli.bats                  · CLI 集成测试
│   ├── regression.bats           · 回归测试
│   ├── completion.bats           · 补全测试
│   └── *.sh                      · 测试辅助脚本
│
├── .github/workflows/            # CI/CD
│   ├── test.yml                  # 131 行 · 测试+安全检查
│   ├── check.yml                 # 99 行 · 格式化+lint
│   ├── release.yml               # 182 行 · 发布流程
│   ├── codeql.yml                # 52 行 · 安全扫描
│   └── update-contributors.yml   # 62 行 · 贡献者更新
│
├── .editorconfig                 # 25 行 · 缩进4空格(sh)、2空格(yaml)
├── .shellcheckrc                 # 7 行 · ShellCheck 忽略规则
├── .githooks/pre-commit          # 96 行 · pre-commit 钩子
└── .cursor/rules/mole-test-safety.mdc  # 11 行 · 测试安全规则
```

## 构建 & 开发命令

```bash
# 开发环境设置
brew install shfmt shellcheck bats-core coreutils parallel
git config core.hooksPath .githooks    # 启用 pre-commit 钩子

# 运行测试（必须通过 scripts/test.sh，它会自动设置安全环境变量）
./scripts/test.sh                      # 运行全部测试
./scripts/test.sh tests/clean_apps.bats  # 运行单个测试文件

# 格式化 + Lint
./scripts/check.sh                     # 格式化 + 检查
./scripts/check.sh --format            # 仅格式化
./scripts/check.sh --no-format         # 仅检查（不格式化）

# 构建 macOS App
make                                   # 或 ./scripts/build-macos-app.sh

# 直接运行（开发模式）
bash mole                              # 启动交互菜单
bash mole clean --dry-run              # 预览清理（安全）
```

## 关键约定

### Bash 代码规范
- **Bash 3.2+ 兼容**（macOS 默认版本，不使用 Bash 4+ 特性如 `assoc_array`）
- **4 空格缩进**，UTF-8，LF 换行
- 所有脚本必须 `set -euo pipefail`
- 所有变量引用必须加引号 `"$variable"`
- 用 `[[ ]]` 而非 `[ ]` 做条件判断
- 函数名 `snake_case`，局部变量用 `local`，常量用 `readonly`
- 使用 BSD 命令而非 GNU（如 `stat -f%z` 而非 `stat --format`）

### 文件操作安全
- **永远不要直接使用 `rm -rf`**，必须通过 `safe_remove` / `validate_path` 等安全包装函数
- 如确需直接 `rm`，必须注释 `# SAFE: <reason>`
- 所有删除操作需路径校验 + 受保护目录检查
- CI 有专门的 `rm -rf` 不安全使用扫描（见 `.github/workflows/test.yml`）

### 测试安全
- **测试必须设置 `MOLE_TEST_NO_AUTH=1`**（通过 `scripts/test.sh` 自动设置）
- 测试不得触发真实的 `sudo`、Touch ID、密码弹窗、AppleScript 权限对话框
- 新增的 `sudo`/`osascript`/`launchctl` 使用必须受 `MOLE_TEST_MODE` / `MOLE_TEST_NO_AUTH` 保护
- `scripts/test.sh` 会自动创建 stub 替代 `sudo`/`osascript`/`launchctl`

### 模块加载机制
- `lib/core/common.sh` 是主加载器，按序加载所有核心模块
- 每个模块有防重复加载守卫：`MOLE_xxx_LOADED`
- `mole` 入口加载 `common.sh` + `commands.sh`，然后按子命令 source `bin/` 下对应脚本

### ShellCheck
- 项目使用 `.shellcheckrc` 配置，禁用了 SC2155/SC2034/SC2059/SC1091/SC2038
- CI 会运行 ShellCheck 检查（通过 `scripts/check.sh`）

## 已知坑点

1. **Bash 3.2 兼容性**: macOS 自带 Bash 3.2，不能用关联数组、`${var,,}` 小写转换等 Bash 4+ 特性
2. **BSD vs GNU**: `stat`、`date`、`sed` 等命令用 BSD 语法，不能用 GNU 扩展
3. **`rm -rf` 检查**: CI 有严格的 `rm -rf` 扫描，任何新增的 `rm -rf` 必须有安全注释或走 `safe_remove`
4. **iTerm2 兼容性**: 项目明确标注 iTerm2 有兼容性问题，推荐 Kaku/Alacritty/kitty/WezTerm/Ghostty/Warp
5. **`CLAUDE.md` 在 `.gitignore` 中**: 该文件不会被提交到仓库（本地专用）
6. **Swift GUI 是薄封装**: `macos/` 下的 SwiftUI 应用主要是调用 CLI runtime，核心逻辑仍在 Bash 中
7. **Homebrew 检测复杂**: `is_homebrew_install()` 需处理符号链接、Cellar 路径等多种情况
8. **并行测试**: 支持通过 `MOLE_TEST_JOBS` 环境变量控制并行度

## Agent 工作指南

### 修改代码前
1. 先读相关模块了解上下文（`lib/core/` → `lib/clean/` 等）
2. 跑 `./scripts/check.sh` 确认格式/lint 通过
3. 跑 `./scripts/test.sh` 确认测试通过

### 修改清理/卸载逻辑时
1. **安全第一**: 所有文件操作走 `safe_remove`，路径走 `validate_path`
2. 添加回归测试到 `tests/` 对应的 `.bats` 文件
3. 考虑受保护应用列表（`app_protection.sh`）
4. 运行 `mo <command> --dry-run` 验证预览模式

### 添加新子命令时
1. 在 `lib/core/commands.sh` 注册命令
2. 创建 `bin/<command>.sh` 实现逻辑
3. 在 `mole` 入口文件中添加路由
4. 添加 `--dry-run` 支持
5. 添加 BATS 测试

### 测试编写
- 使用 `bats-core` 框架
- 测试文件放在 `tests/` 目录
- 必须 `MOLE_TEST_NO_AUTH=1` 或通过 `scripts/test.sh` 运行
- 参考 `tests/core_safe_functions.bats` 了解安全测试模式

### 提交前检查清单
- [ ] `./scripts/check.sh` 通过
- [ ] `./scripts/test.sh` 通过
- [ ] 新 `rm -rf` 调用有 `# SAFE` 注释或走 `safe_remove`
- [ ] Bash 3.2 兼容（无 Bash 4+ 特性）
- [ ] BSD 命令语法
- [ ] 变量全部引号包裹
