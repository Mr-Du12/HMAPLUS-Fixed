<div align="center">

# HMAPLUS-Fixed

### Hide My Applist 增强版 · 黑名单残留自动清理模块（WebUI 重构）

[![STAR](https://img.shields.io/github/stars/Mr-Du12/HMAPLUS-Fixed?style=flat&logo=github)](https://github.com/Mr-Du12/HMAPLUS-Fixed/stargazers)
[![FORK](https://img.shields.io/github/forks/Mr-Du12/HMAPLUS-Fixed?style=flat&logo=greasyfork&color=%2394E61A)](https://github.com/Mr-Du12/HMAPLUS-Fixed/forks)
[![RELEASE](https://img.shields.io/github/v/release/Mr-Du12/HMAPLUS-Fixed?style=flat&logo=android&color=3399ff)](https://github.com/Mr-Du12/HMAPLUS-Fixed/releases/latest)
[![DOWNLOAD](https://img.shields.io/github/downloads/Mr-Du12/HMAPLUS-Fixed/total?style=flat&color=FF4500)](https://github.com/Mr-Du12/HMAPLUS-Fixed/releases/latest)

</div>

#####

一个更省心的 [Hide My Applist](https://github.com/Dr-TSNG/Hide-My-Applist)（HMA）配套 Root 模块：自动读取 HMA 黑名单配置，开机自动 + 实时监听清理黑名单应用残留在 `Android/data`、`Android/obb`、`Android/media` 下的垃圾目录，并自带全新图形化 WebUI 配置中心，支持 Magisk / KernelSU / APatch。

#####

这个项目的初衷是解决以下问题：

- HMA 只管“隐藏应用”，不管应用卸载/更新后残留在外部存储的空壳目录，这些目录既占空间，又可能被部分检测手段扫到；
- 旧版清理方式要手动跑脚本、翻日志，有没有清掉、清了多少全靠猜，对新手极不友好；
- 手动删除残留容易误删重要应用数据，缺少一个能和 HMA 黑名单联动、又带白名单保护的自动化清理工具；
- 后台轮询清理要么不实时、要么费电，缺少“目录一变就清理”的轻量方案。

## 本项目的主要内容(及计划)

- 开机自动读取 HMA `config.json` 中的黑名单（`isWhitelist:false` 分组），自动清理黑名单应用的 data / obb / media 残留目录；
- 全新重构图形化 WebUI 配置中心：实时统计进程 PID / 黑名单 / 白名单 / 累计清理数量，支持搜索、筛选、名单管理与深浅主题切换；
- inotifyd 实时监听目录变化，残留目录一产生立即清理，配合长间隔轻量巡检，兼顾实时性与功耗；
- 白名单保护机制，重要应用（默认保护 MT 管理器）免于清理；
- 配置热重载 + 单实例守护，改完名单自动生效，升级模块不多开冲突。

## 已实现：

- [x] 内置图形化 WebUI 控制面板，首页实时显示进程 PID、黑名单数、白名单数、累计清理项数
- [x] 包名模糊搜索，全部 / 黑名单 / 白名单一键筛选
- [x] WebUI 内管理白名单，勾选后「保存并应用配置」即时生效，无需重启手机
- [x] 深色 / 浅色双主题切换、手动刷新、关于页（自动读取模块名称、版本、作者信息）
- [x] 开机自动检测 HMA 配置，刷入时安装器直接打印黑名单数量与待清理包名示例
- [x] 黑名单应用 `Android/data`、`obb`、`media` 残留目录自动清理
- [x] 支持 action.sh 手动一键执行清理，每次清理写入系统日志（`log -t HMAPLUS`）
- [x] 累计清理数量持久化保存，重启不丢失
- [x] 白名单保护：命中白名单的应用跳过清理，默认内置保护 `bin.mt.plus`（MT 管理器）
- [x] inotifyd 实时监听 + 30 秒轻量巡检 + 10 分钟自动刷新统计，功耗优化
- [x] HMA 配置 / 白名单文件热重载，在 HMA 里改完名单保存后模块自动重新加载
- [x] 守护进程单实例保护，精确匹配并清理旧进程，不多开、不误伤其他模块
- [x] 兼容 Magisk / KernelSU / APatch（arm64 架构，Android 10 及以上体验最佳）

## 待实现：

- [ ] WebUI 清理记录明细页（按包名查看历史清理记录）
- [ ] 清理范围自定义（可选只清理 data / obb / media 中的部分目录）
- [ ] 残留目录扫描结果预览（先看后清，更稳妥）
- 更多功能与细节优化……

#####

## ⬇️ 下载

👉 [前往 Releases 下载最新模块包](https://github.com/Mr-Du12/HMAPLUS-Fixed/releases/latest)

## 📲 安装与使用

1. 下载 Releases Assets 中的模块 ZIP 包；
2. 在 Magisk / KernelSU / APatch 管理器中刷入模块，重启后生效；
3. 确保已安装 [Hide My Applist](https://github.com/Dr-TSNG/Hide-My-Applist) 本体，并在 App 内保存过至少一次配置（模块靠读取 HMA 的 `config.json` 工作）；
4. 在支持 WebUI 的管理器（KernelSU / APatch 管理器，或 Magisk 搭配 [KsuWebUI](https://github.com/5ec1cff/KsuWebUI)）中打开模块详情页，点「打开 WebUI」即可进入配置中心；
5. 在 WebUI 中把重要应用加入白名单，其余黑名单应用的残留目录会被自动清理。

## ⚠️ 注意事项

- 本模块只清理黑名单应用在**外部存储**（`Android/data`、`obb`、`media`）下的残留目录，不会卸载应用，也不碰 `/data/data` 应用私有数据；
- 清理动作不可恢复，重要应用请务必在 WebUI 白名单中勾选保护；
- 本模块与 Hide My Applist 官方无直接关系，属于第三方增强清理辅助模块，使用中遇到问题请在本仓库 Issues 反馈。

## 鸣谢

- Hide My Applist：[Dr-TSNG/Hide-My-Applist](https://github.com/Dr-TSNG/Hide-My-Applist)
- Magisk：[topjohnwu/Magisk](https://github.com/topjohnwu/Magisk)
- KernelSU：[tiann/KernelSU](https://github.com/tiann/KernelSU)
- APatch：[bmax121/APatch](https://github.com/bmax121/APatch)
- 独立 WebUI 运行环境 KsuWebUI：[5ec1cff/KsuWebUI](https://github.com/5ec1cff/KsuWebUI)

<!-- 访客统计 -->
<div align="center">
  <img width="0" height="0" src="https://count.getloli.com/get/@:Mr-Du12" />
</div>
