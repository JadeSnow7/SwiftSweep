# SwiftSweep Documentation

欢迎阅读 SwiftSweep 项目文档。本文档体系旨在展示项目的技术架构、设计决策与工程实践。

## 📚 技术规格书 (Tech Specs)

按照大厂标准工程文档组织，涵盖核心架构、业务引擎与基础设施。

### 核心架构
- [TS_001: 核心架构与并发模型](tech_specs/TS_001_CORE_ARCHITECTURE.md)
  - 涉及 Actor 调度器、I/O 追踪、无锁并发设计。
- [TS_008: 解耦架构规范 (UDF)](tech_specs/TS_008_DECOUPLED_ARCHITECTURE.md)
  - 分层规范：Render/State/Scheduler/Execution。

### 业务引擎
- [TS_003: 多媒体分析引擎](tech_specs/TS_003_MEDIA_ENGINE.md)
  - pHash 感知哈希、LSH 相似检索、高性能缩略图。
- [TS_004: 包管理与 Git 分析](tech_specs/TS_004_PACKAGE_MANAGER.md)
  - 多生态 (Brew/npm/pip) 扫描、Git 仓库空间分析。
- [TS_005: 智能建议引擎](tech_specs/TS_005_INSIGHTS_ENGINE.md)
  - 申明式规则引擎、置信度评分、证据链设计。
- [TS_006: 安全卸载引擎](tech_specs/TS_006_SECURE_UNINSTALL.md)
  - XPC 特权服务、文件关联查找、安全路径校验。

### 扩展与集成
- [TS_002: 插件生态与 Sys AI Box](tech_specs/TS_002_PLUGIN_ECOSYSTEM.md)
  - Data Pack 插件架构、OAuth 2.0 设备配对、软硬协同。

### DevOps
- [TS_007: CI/CD 流水线](tech_specs/TS_007_CI_CD_PIPELINE.md)
  - Xcode Cloud 自动化构建、公证 (Notarization)、证书管理。

## 🗺️ 其他文档

- [User Manual](../README.md): 用户功能手册与安装指南。
- [System Design](DESIGN_SYSTEM.md): 系统总体架构与模块关系。
- [Testing Guide](TESTING.md): 标准测试流程与本地验证。
- [Xcode Cloud Workflow](XCODE_CLOUD_WORKFLOW.md): Xcode Cloud 工作流创建与变量模板。
- [Architecture Refactoring Plan](ARCHITECTURE_REFACTORING_PLAN.md): UDF 架构迁移计划与现状。
- [Compliance Report](COMPLIANCE_REPORT.md): TS_008 合规审计与差距分析。
- [Plugin Development](PLUGIN_DEVELOPMENT.md): 插件开发指南。
- [Feature Roadmap](FEATURE_ROADMAP.md): 功能开发路线图。
