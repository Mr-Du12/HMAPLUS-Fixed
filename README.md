<div align="center">

# HMAPLUS-Fixed

[![最新版本](https://img.shields.io/github/v/release/Mr-Du12/HMAPLUS-Fixed?label=最新版本&style=for-the-badge)](https://github.com/Mr-Du12/HMAPLUS-Fixed/releases/latest)
[![下载量](https://img.shields.io/github/downloads/Mr-Du12/HMAPLUS-Fixed/total?style=for-the-badge)](https://github.com/Mr-Du12/HMAPLUS-Fixed/releases/latest)

基于 HMA 的 Magisk/KernelSU 模块，开机自动清理黑名单应用的 data/obb/media 目录

</div>

---

## ⬇️ 下载

> **⚠️ 重要：请下载 Assets 中的「模块包」，不要下载 Source code！**

| ✅ 正确下载 | ❌ 错误下载 |
|-----------|-----------|
| `0_HMAPLUS-Fixed-xxx-模块包.zip` | Source code (zip / tar.gz) |
| 可直接刷入 | 是源代码，无法刷入 |

👉 [前往 Releases 下载](https://github.com/Mr-Du12/HMAPLUS-Fixed/releases/latest)

---

## ✨ 功能特性

- 🔍 自动读取 HMA 黑名单配置
- 🧹 开机自动清理黑名单应用的 data/obb/media 目录
- 🌐 WebUI 管理界面，支持黑白名单配置
- 🌙 深色/浅色主题切换
- 🛡️ 单实例保护，防止重复进程
- ⚡ inotify 实时监听目录变化

---

## 📲 安装

1. 下载模块 ZIP 包（Assets 中的 `0_HMAPLUS-Fixed-xxx-模块包.zip`）
2. 在 Magisk / KernelSU / SukiSU 管理器中刷入
3. 重启设备
4. 在管理器 WebUI 中打开 HMAPLUS 配置页面

---

## ⚙️ 使用

- 模块会在开机后自动启动守护进程
- 通过 WebUI 可以管理白名单（白名单应用不会被清理）
- 默认已加入 `bin.mt.plus`（MT 管理器）到白名单

---

## 📝 说明

本模块基于 Hide My Applist 增强版修改，WebUI 重构，新增单实例保护等功能。

原作者：酷安 [@小石不会搞机](https://www.coolapk.com/u/3888187)
