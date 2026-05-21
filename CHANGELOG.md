# Changelog

## [0.12.0] - 2026-05-21

### Performance Optimizations (cont.)

- **SwiftUI ViewModel 拆分** (LUC-164)
  - MoleAppModel 拆分为 4 个专职 ViewModel: StatusModel, CleanModel, UninstallModel, AnalyzeModel
  - RootModel 统一管理，ContentView 各 Pane 使用独立 @EnvironmentObject
  - 大幅减少 @Published 属性变更导致的无关 View 重绘

## [0.11.0] - 2026-05-21

### Performance Optimizations

- **Engine 实例复用 + AppCacheCleaner 异步化** (LUC-162)
  - MoleAppModel 持久持有 4 个 Engine 实例（systemMonitor, uninstallEngine, diskScanner, cacheCleaner），消除重复创建
  - AppCacheCleaner 从 class 改为 actor，线程安全
  - isProcessRunning 使用 withCheckedContinuation 异步化

- **原生 API 替代 Process fork** (LUC-163)
  - AppDiscovery: PropertyListSerialization 直接读 Info.plist，替代 plutil fork
  - DiskScanner: lstat 合并 3 次 stat 调用
  - ResidualScanner: URL.resourceValues 替代 mdls fork
  - 所有原生 API 失败时自动 fallback 到 Process 方法

- **I/O 优化** (LUC-165)
  - CleanEngine 递归深度限制 maxDepth=8
  - PathValidator.validateAndInspect 批量方法合并 actor 调用（4→3次）
  - ScanCache 内存缓存层（NSCache 100条/10MB + TTL + modTime 校验）
  - HardwareCollector 永久缓存替代 10 分钟 TTL
  - readLastLines FileHandle 增量读取（最多 32KB）

## [0.10.2] - 2026-05-19

- Harden macOS app launch and updates
- Publish macOS app releases via CI
- Support macOS 13 app builds
