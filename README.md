<div align="center">

# HMAPLUS-Fixed

### Hide My Applist 增强版 · 黑名单残留清理 + UID 过滤（WebUI 重构）

[![STAR](https://img.shields.io/github/stars/Mr-Du12/HMAPLUS-Fixed?style=flat&logo=github)](https://github.com/Mr-Du12/HMAPLUS-Fixed/stargazers)
[![FORK](https://img.shields.io/github/forks/Mr-Du12/HMAPLUS-Fixed?style=flat&logo=greasyfork&color=%2394E61A)](https://github.com/Mr-Du12/HMAPLUS-Fixed/forks)
[![RELEASE](https://img.shields.io/github/v/release/Mr-Du12/HMAPLUS-Fixed?style=flat&logo=android&color=3399ff)](https://github.com/Mr-Du12/HMAPLUS-Fixed/releases/latest)
[![DOWNLOAD](https://img.shields.io/github/downloads/Mr-Du12/HMAPLUS-Fixed/total?style=flat&color=FF4500)](https://github.com/Mr-Du12/HMAPLUS-Fixed/releases/latest)

</div>

#####

一个更省心的 [Hide My Applist](https://github.com/Dr-TSNG/Hide-My-Applist)（HMA）配套 Root 模块：自动读取 HMA 黑名单配置，开机后清理黑名单应用残留在 `Android/data`、`Android/obb`、`Android/media` 下的目录，并实时监听后续产生的残留；同时内置 UID 过滤（seccomp），可按包过滤 `getpriority(PRIO_USER)`。自带图形化 WebUI 配置中心，支持 Magisk / KernelSU / APatch。

#####

这个项目的初衷是解决以下问题：

- HMA 只管“隐藏应用”，风险应用路径又可能被部分检测手段扫到；
- 旧版清理方式要手动跑脚本、翻日志，有没有清掉、清了多少全靠猜，对新手极不友好；
- 手动删除残留容易误删重要应用数据，缺少一个能和 HMA 黑名单联动、又带白名单保护的自动化清理工具；
- 后台轮询清理要么不实时、要么费电，缺少“目录一变就清理”的轻量方案；
- 部分检测会读取进程优先级信息，需要一种按 UID 生效、可随时开关的过滤手段。

## 本项目的主要内容(及计划)

- 读取 HMA `config.json` 中的黑名单（`isWhitelist:false` 分组），清理黑名单应用的 data / obb / media 残留目录；
- 图形化 WebUI 配置中心，双视图切换：「目录清理」与「UID 过滤」；
- inotifyd 实时监听目录变化，残留目录一产生立即清理，配合长间隔轻量巡检，兼顾实时性与功耗；
- 白名单保护机制，重要应用（默认保护 MT 管理器）免于清理；
- UID 过滤合并自 UID Filter 0.2.8 原生组件，默认关闭，可在 WebUI 手动开启；
- 配置热重载 + 单实例守护，改完名单自动生效，升级模块不多开冲突。

## 已实现：

### 目录清理

- [x] 内置图形化 WebUI 控制面板，首页实时显示进程 PID、黑名单数、白名单数、累计清理项数
- [x] 包名模糊搜索，全部 / 黑名单 / 白名单一键筛选
- [x] WebUI 内管理白名单，勾选后「保存并应用配置」即时生效，无需重启手机
- [x] 开机自动检测 HMA 配置，刷入时安装器直接打印黑名单数量与待清理包名示例
- [x] 黑名单应用 `Android/data`、`obb`、`media` 残留目录自动清理
- [x] 存储挂载完成后延后 90 秒启动服务，错开开机高峰，首次清理与实时监听同步延后
- [x] 支持 action.sh 手动一键执行清理，输出清理明细并写入系统日志（`log -t HMAPLUS`）
- [x] 累计清理数量持久化保存，重启不丢失
- [x] 白名单保护：命中白名单的应用跳过清理，默认内置保护 `bin.mt.plus`（MT 管理器）
- [x] inotifyd 实时监听 + 30 秒轻量巡检 + 10 分钟刷新统计，功耗优化
- [x] HMA 配置 / 白名单文件热重载，在 HMA 里改完名单保存后模块自动重新加载
- [x] 守护进程单实例保护，精确匹配并清理旧进程，不多开、不误伤其他模块

### UID 过滤

- [x] 合入 UID Filter 0.2.8 原生组件 `zygisk/arm64-v8a.so`，按包过滤 `getpriority(PRIO_USER)`
- [x] 启用开关，**默认关闭**，新安装不会自动生效
- [x] 生效应用列表管理：添加 / 移除包名、加入内置包名，启用时至少保留一个包名
- [x] 配置持久化到 `/data/adb/HMAPLUS`，并同步到模块目录与更新目录，供原生库读取
- [x] 保存后仅重启配置有变化的应用，不清除应用数据、不影响其他应用

### WebUI 与日志

- [x] 右上角「更多功能」菜单，顺序为：主题切换 / 运行日志 / 关于
- [x] 深色 / 浅色主题切换，视图与主题状态本地记忆
- [x] 运行日志展示清理明细与时间（蓝色）、运行错误（红色），上限 200 行自动截断
- [x] UID 过滤操作接入统一日志：启用 / 关闭、新增 / 移除应用、重启应用数量
- [x] 日志仅在事件发生时写入，无定时轮询，不额外增加耗电
- [x] 关于页保留酷安作者入口，并提供 GitHub 仓库入口

### 兼容性

- [x] 兼容 Magisk / KernelSU / APatch
- [x] 目录清理无特殊架构限制；UID 过滤原生组件仅支持 arm64 + Android 13 及以上

## 待实现：

- [ ] 收敛清理范围自定义（可选只清理 data / obb / media 中的部分目录）
- [ ] 残留目录扫描结果预览（先看后清，更稳妥）
- [ ] UID 过滤配置导入 / 导出
- 更多功能与细节优化……

#####

## ⬇️ 下载

👉 [前往 Releases 下载最新模块包](https://github.com/Mr-Du12/HMAPLUS-Fixed/releases/latest)

## 📲 安装与使用

1. 下载 Releases Assets 中的模块 ZIP 包；
2. 在 Magisk / KernelSU / APatch 管理器中刷入模块，重启后生效；
3. 确保已安装 [Hide My Applist](https://github.com/Dr-TSNG/Hide-My-Applist) 本体，并在 App 内保存过至少一次配置（模块靠读取 HMA 的 `config.json` 工作）；
4. 在支持 WebUI 的管理器（KernelSU / APatch 管理器，或 Magisk 搭配 [KsuWebUI](https://github.com/5ec1cff/KsuWebUI)）中打开模块详情页，点「打开 WebUI」即可进入配置中心；
5. 在 WebUI 中把重要应用加入白名单，其余黑名单应用的残留目录会被自动清理；
6. 如需 UID 过滤：在「UID 过滤」页添加包名并打开启用开关，保存后生效。该功能默认关闭，需要 arm64 架构、Android 13+，并在内核管理器中开启 Zygisk。

## ⚠️ 注意事项

- 本模块清理的是黑名单应用在**外部存储**（`Android/data`、`obb`、`media`）下的目录，不会卸载应用，也不碰 `/data/data` 应用私有数据；
- 清理动作不可恢复，重要应用请务必在 WebUI 白名单中勾选保护；
- UID 过滤默认关闭，只有手动开启并对指定包生效；关闭后不再干预任何进程；
- UID 过滤依赖 Zygisk，未开启或架构 / 系统版本不满足时仅该功能不可用，不影响目录清理；
- 本模块与 Hide My Applist 官方无直接关系，属于第三方增强清理辅助模块，使用中遇到问题请在本仓库 Issues 反馈。

<!-- 访客统计 -->
<div align="center">
  <img width="0" height="0" src="https://count.getloli.com/get/@:Mr-Du12" />
</div>
