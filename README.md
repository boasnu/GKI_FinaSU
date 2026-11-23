# REDMI K90（annibale）GKI 内核 + FinaSU 云构建工程

用 GitHub Actions 在云端编译 **AOSP GKI `android15-6.6`**，把 **FinaSU 以 Built-In 方式编进内核**，产出可刷入红米 K90 的 AnyKernel3 包 / 内核镜像。

> 本工程只负责"编译 + 打包"。刷机前必须解锁 Bootloader、备份原厂镜像；构建成功 ≠ 一定能开机。

---

## 0. 先认清这台机器（最容易踩的坑）

| 项目 | 值 |
|---|---|
| 机型 / 代号 | REDMI K90 / **annibale**（2510DRK44C，POCO F8 Pro 同代号） |
| SoC | 骁龙 8 Elite，SM8750 |
| 出厂系统 | Android 16 / HyperOS 3 |
| 内核版本 | `6.6.77-android15-8-...-4k` ~ `6.6.118-android15-8-...-4k` |
| **KMI** | **`6.6-android15-8`**（家族 `android15-6.6`，KMI 代系 8） |
| 页大小 | **4 KiB**（`-4k`），不要刷 16K 页版本 |
| 启动分区 | `boot`（含内核）、`init_boot`、`vendor_boot`，A/B 双槽 |

**关键：系统显示 Android 16 / 17，但 KMI 仍然是 `android15-6.6`。**
千万不要因为"系统是 Android 16"就去选 `android16-6.12`；也不要选 6.1。选错 KMI 会直接卡第一屏。

刷前在手机上确认一次：

```sh
adb shell uname -r
# 期望：6.6.x-android15-8-gXXXX-...-4k
```

如果输出是 `6.6.77`，把工作流的 `kernel_tag` 改成对应 tag（如 `android15-6.6.77_r00`）；是 `6.6.118` 就用默认。

---

## 方案 A（推荐，成功率最高）：Fork 现成工程

已有维护良好的 GKI 自动化仓库原生支持 FinaSU 和 `android15-6.6`：

- <https://github.com/ysu344937/AnyKernel3> —— 工作流 `kernel-a15-6-6.yml`，`ksu_variant` 可选 **FinaSU**
- <https://github.com/AlexLiuDev233/GKI_KernelSU_SUSFS> —— 同类，支持 5.10 ~ 6.12

操作：

1. Fork 仓库 → **Actions** → `kernel-a15-6-6.yml` → **Run workflow**
2. 参数这样填：

| 参数 | 填什么 |
|---|---|
| `android_version` / `kernel_version` | `15` / `6.6` |
| `sub_level` | 与 `uname -r` 一致，如 `118`（或 `77`） |
| `ksu_variant` | **FinaSU** |
| `build_channel` | 选"正式 / Release"，管理器与内核版本对齐 |
| `enable_susfs` | 首次建议 **关**（少一个变量；要 SUSFS 再开） |
| `os_patch_level` | 按当前系统安全补丁级别，或用项目默认 `lts` |

3. 跑完在 **Artifacts** 下载：
   - `AnyKernel3.zip`（推荐，Recovery / KernelFlasher 刷）
   - `boot.img` / `boot-gz.img` / `boot-lz4.img`（按原厂压缩格式挑）

> 该方法用的就是"内核版本匹配即可刷"的通用 GKI 路线，不需要本机 Linux，也不需要自己维护工具链。

---

## 方案 B（本工程）：自包含、可定制

适合你想自己控制源码 tag、FinaSU 提交、内核 config 的场景。

### 启用步骤

1. 新建一个空 GitHub 仓库，把**本文件夹里的内容**（含隐藏的 `.github/workflows/`、`.gitignore` 不要漏）作为仓库**根目录**上传；不要把外面这层中文文件夹也套进去。
2. 仓库 → **Actions** → `REDMI K90 (annibale) GKI 6.6 + FinaSU` → **Run workflow**。
3. 三个输入：

| 输入 | 默认值 | 说明 |
|---|---|---|
| `kernel_tag` | `android15-6.6.118_r00` | AOSP `kernel/common` tag，对齐 `uname -r` |
| `manifest_branch` | `common-android15-6.6` | 决定 hermetic Clang 工具链 |
| `finasu_ref` | `master` | FinaSU 分支 / tag |

首次约 30~60 分钟（含 repo 同步与 ThinLTO 链接）。Runner 已自动清磁盘 + 开 10GB swap。

### 工作流做了什么

1. `repo init/sync` 拉 AOSP `kernel/manifest`（自带配套 Clang，保证 KMI 一致）。
2. `common/` 切到指定的 `android15-6.6.x_r00` tag。
3. `FinaSU/kernel/setup.sh --dir ...` 注入 `drivers/kernelsu` 链接、Makefile、Kconfig（GKI 树自动用 `common/drivers`）。
4. 在 `gki_defconfig` 上启用 `CONFIG_KSU` / `KPROBES` / `KALLSYMS_ALL` / `EXT4_FS` / `HEADERS_INSTALL`，先跑 `headers_install`。
5. `make ... KSU_REQUIRE_PREINIT=1 Image Image.gz Image.lz4` —— 这个变量**必须显式传**，否则 FinaSU 的 preinit 会静默关闭。
6. 用 AnyKernel3 模板分别打 `gz` / `lz4` / `raw` 三个包，并抓取配套 FinaSU Manager APK。

> 本工程**不含 SUSFS 内核补丁**（需要额外 patch，且和上游版本强耦合，首刷不建议叠）。FinaSU 管理器里 SUSFS 相关开关会显示为不可用，属正常。需要 SUSFS 请用方案 A 打开 `enable_susfs`。

### 产物（Artifacts）

| 文件 | 用途 |
|---|---|
| `AnyKernel3-...-gz.zip` | 原厂 kernel 为 gzip 时刷这个 |
| `AnyKernel3-...-lz4.zip` | 原厂 kernel 为 `lz4_legacy` 时刷这个（骁龙平台常见） |
| `AnyKernel3-...-raw.zip` | 原厂 kernel 未压缩时刷这个 |
| `Image` / `Image.gz` / `Image.lz4` | 裸内核，供本地 `magiskboot` 手工打包 |
| `FinaSU-Manager.apk` | 与内核配套的管理器（抓不到就自己去 Releases 下） |

---

## 刷之前必须做的 5 件事

1. **解锁 Bootloader**（会清空数据），全量备份照片 / 验证码 / 应用数据到电脑。
2. 下载与当前系统**完全一致**的原厂 Fastboot ROM，解出并留好：
   `boot.img`、`init_boot.img`、`vendor_boot.img`、`vbmeta.img`。
3. 记录 `adb shell uname -r`、当前槽位（`fastboot getvar current-slot`）、系统版本号。
4. 检测原厂 boot 的内核压缩格式（决定刷哪个包）：
   ```sh
   magiskboot unpack boot.img
   # 看输出里的 KERNEL_FMT：gz / lz4_legacy / raw
   ```
5. **清掉旧 Root**：装过 KernelSU / APatch / Magisk LKM 的，先卸载并刷回原厂 `boot.img`。
   FinaSU **Built-In 与 LKM 不能共存**；从 LKM 切过来必须先恢复原厂 boot。

---

## 刷入

### 方式 1：AnyKernel3（推荐）

把选中的 zip 放进手机，用自定义 Recovery（TWRP / OrangeFox）或 KernelFlasher 刷入**当前槽位**。
AK3 会读取当前 `boot` 分区、只替换其中的 kernel，保留 ramdisk / dtb / AVB 结构，不动 `init_boot` 与 `vendor_boot`。

### 方式 2：本地打 boot 镜像

```sh
magiskboot unpack boot.img          # 得到 kernel / ramdisk 等
cp Image.lz4 kernel                # 按 KERNEL_FMT 选 Image.gz / Image.lz4 / Image
magiskboot repack boot.img new-boot.img

# 先临时启动验证（能开机再永久刷）
fastboot boot new-boot.img

# 确认能进系统后
fastboot getvar current-slot
fastboot flash boot_a new-boot.img  # 按实际槽位 boot_a / boot_b
fastboot reboot
```

开机后安装 `FinaSU-Manager.apk`，首页应显示"工作中 / 内置（Built-In）"。

---

## 救砖与风险

- **卡第一屏 / 无限重启**：进 Fastboot，刷回原厂 `boot.img`；仍不行再补
  `fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img` 并刷回全部原厂启动镜像。
- **不要刷**：跨 KMI（6.1 / 6.12）、16K 页版本、比当前系统 SPL 更旧的镜像、把 `init_boot` 当内核分区刷。
- 改过 boot 后 OTA 可能被覆盖或失败；升级大版本前先恢复原厂 boot。
- 解锁与刷第三方内核可能影响保修；Root 会让银行 / 支付 / 流媒体 / 企业应用的完整性检测失败，没有"必过"的隐藏方案。
- 未解锁、没备份、没留原厂镜像，请不要动手。

---

## 构建失败怎么查

| 现象 | 处理 |
|---|---|
| `repo sync` 失败 / 找不到 `common/` | 换 `manifest_branch` 为 `common-android15-6.6-lts` 再跑 |
| 找不到 `kernel_tag` | 换 `android15-6.6.77_r00`，或留 tag 用分支 HEAD（脚本会给 warning） |
| `CONFIG_KSU 未生效` / `drivers/Kconfig 未被注入` | FinaSU 上游改了 `setup.sh` 参数，去官方"快速开始"核对后改 `scripts/build.sh` |
| `KSU_REQUIRE_PREINIT` 相关报错 | 确认 `headers_install` 成功、`$OUT/usr/include` 存在 |
| OOM / No space left on device | 工作流已含清盘 + 10G swap；仍不够就降低 `make -j` |
| 产物里 `Image` 没有 `android15-8` 版本串 | 停止刷入，人工核对 KMI |

---

## 参考来源

- FinaSU 官方：<https://github.com/LyraVoid/FinaSU> ｜ 文档 <https://fina.mysqil.com/guide/get-started> ｜ <https://fina.mysqil.com/guide/install>
- AOSP 构建内核 / KMI：<https://source.android.com/docs/setup/build/building-kernels> ｜ <https://source.android.com/docs/core/architecture/kernel/kmi>
- android15-6.6.118 tag：<https://android.googlesource.com/kernel/common/+/refs/tags/android15-6.6.118_r00>
- 小米内核开源（需要厂商树时）：<https://github.com/MiCode/Xiaomi_Kernel_OpenSource>（`annibale-w-oss` 分支）
- AnyKernel3 模板：<https://github.com/osm0sis/AnyKernel3>
- 现成云构建工程：<https://github.com/ysu344937/AnyKernel3> ｜ <https://github.com/AlexLiuDev233/GKI_KernelSU_SUSFS>

---

### 许可提示

Linux 内核为 GPL-2.0，FinaSU 的 `kernel/` 目录为 GPL-2.0-only、其余部分为 GPL-3.0。
自编译产物建议**仅供自己使用**；二次分发前请自行核对各组件许可与上游作者要求。
