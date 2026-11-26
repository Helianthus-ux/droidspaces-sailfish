# Droidspaces Kernel for Google Pixel 1 (sailfish)

为 **Pixel 1 / Pixel 1 XL（sailfish / marlin）+ crDroid 7.x（Android 11）** 编译的、
启用 [Droidspaces](https://github.com/AnandaAnugrahHandyanto/Droidspaces-OSS)
容器运行所需内核特性的内核。

本仓库是**构建配方**：通过 GitHub Actions 自动拉取内核源码、打补丁、合并配置、
用 GCC 4.9.4 编译，并产出可直接刷入的 AnyKernel3 zip。

---

## 为什么需要重编译内核

crDroid 7.x 自带的 3.18 内核默认关闭了 namespace、cgroup device controller、
devtmpfs、netfilter/NAT 等选项。Droidspaces 依赖这些特性来做进程隔离、网络隔离和
设备透传，stock 内核无法运行容器，所以必须重新编译。

---

## 关键事实（已针对你的设备核实）

| 项目 | 值 |
|---|---|
| 机型 | Pixel 1 = sailfish，Pixel 1 XL = marlin |
| ROM | crDroid 7.x（Android 11 / LineageOS 18.1 基础） |
| 内核源码 | `blckbearx/android_kernel_google_marlin` @ `lineage-18.1-upstream` |
| 内核版本 | 3.18.140（cgroup **v1**，非 GKI） |
| defconfig | `m1s1_defconfig`（crDroid device tree 的 `TARGET_KERNEL_CONFIG`） |
| 内核镜像 | `Image.lz4-dtb` |
| 编译器 | **Linaro GCC 4.9.4**（3.18 内核用 GCC 9/12 能编译但无法引导）。Linaro 官网下载已下线，脚本从 GitHub 镜像 clone，32 位端用 `arm-linux-gnueabihf-` 前缀 |
| boot 分区 | A/B 设备：`boot_a` / `boot_b`，路径 `/dev/block/bootdevice/by-name/boot` |

### 关于 Droidspaces 官方补丁的取舍

- **补丁 1（xt_qtaguid kernel panic）**：适用，已内置到 `scripts/build.sh`（用幂等的源码改写实现，比 patch 更稳）。
- **补丁 2（cgroup 文件前缀）**：官方原件针对 **cgroup v2** 的 `kernel/cgroup/cgroup.c`。
  你的 3.18 内核是 **cgroup v1**（只有 `kernel/cgroup.c`），v1 原生就是 `子系统.文件名`
  的命名方式，因此该补丁**不适用**，放在 `patches/not-applied/` 仅作存档。
- **额外修复**：3.18 源码里 `smp2p.c` 无条件调用 mock 测试函数，默认配置下会编译失败，
  build 脚本已用 `CONFIG_MSM_SMP2P_TEST` 守卫修复。

---

## 使用方法

### 方式 A：GitHub Actions 编译（推荐，无需本地环境）

1. 在 GitHub 新建一个仓库，例如 `droidspaces-sailfish`（可设为 Private）。
2. 把本目录 `droidspaces-sailfish/` 下的**全部内容**（包括隐藏的 `.github/` 目录）上传进去。
   - 用网页上传时，需先本地解压后逐个拖入；确保 `.github/workflows/build.yml` 存在。
   - 或用命令行：
     ```bash
     cd droidspaces-sailfish
     git init
     git add -A
     git commit -m "Droidspaces kernel build config for Pixel 1"
     git remote add origin https://github.com/<你的用户名>/droidspaces-sailfish.git
     git push -u origin main
     ```
3. 打开仓库的 **Actions** 标签页 → 左侧选 **Build Droidspaces Kernel (Pixel 1 / sailfish)**
   → 点 **Run workflow** → 选 `main` 分支 → 运行。
4. 等待约 15–40 分钟（视 GitHub runner 性能）。完成后在本次运行的 **Artifacts** 里下载：
   - `Droidspaces-Pixel1-sailfish-AnyKernel3` ← 刷这个
   - `Image.lz4-dtb` ← 裸内核镜像，备用
   - 失败时会额外上传 `build-log`，可据此排查。

> 提示：Actions 里 `ubuntu-22.04` runner 有 2 核 / 7GB 内存，编译 3.18 内核足够。
> 工具链约 220MB、源码约 1.5GB，会在每次运行时下载（无缓存）。
> 构建日志会作为 `build-log` artifact 上传（成功/失败都会上传），方便排查。

### 方式 B：本地 Linux 编译

需要 Ubuntu/Debian x86_64，约 15GB 磁盘：

```bash
sudo apt-get update
sudo apt-get install -y build-essential git bc bison flex libssl-dev libelf-dev \
  python3 lz4 liblz4-tool curl xz-utils cpio lib32stdc++6 lib32z1
cd droidspaces-sailfish
chmod +x scripts/build.sh
./scripts/build.sh
# 产物：out/arch/arm64/boot/Image.lz4-dtb
```

打包 AnyKernel3 zip：

```bash
git clone --depth=1 https://github.com/osm0sis/AnyKernel3.git anykernel3
cp anykernel/anykernel.sh anykernel3/anykernel.sh
cp out/arch/arm64/boot/Image.lz4-dtb anykernel3/Image.lz4-dtb
cd anykernel3 && zip -r9 ../Droidspaces-Pixel1-sailfish.zip . -x '*.git*' README.md
```

---

## 刷入

**前置条件：** bootloader 已解锁、已 root（Magisk / KernelSU / APatch）、已安装自定义 recovery
（TWRP / OrangeFox）或使用支持刷 zip 的 root 管理器。

AnyKernel3 会**保留你当前的 ramdisk**（即保留 root 和 crDroid 的 init），只替换 kernel，
因此不需要提供 boot.img，也不会丢失 root。

1. 把 `Droidspaces-Pixel1-sailfish.zip` 拷到手机。
2. 重启到 recovery（或 Magisk/KernelSU 的“从存储安装模块/刷入 zip”）。
3. 刷入该 zip。Pixel 1 是 A/B 设备，AnyKernel3 会自动检测并写入当前活动槽位
   （`IS_SLOT_DEVICE=1`）。
4. 重启。

> **重要：** 如果你通过 OTA 或 fastboot 更新了 ROM，ramdisk 会被替换，需要重新刷一次内核 zip。

备选（已解包 boot.img 的场合）：用 `mkbootimg` 把 `Image.lz4-dtb` 与原 ramdisk 重新打包，
参数见参考项目，然后 `fastboot flash boot_a` / `boot_b`。

---

## 验证

开机后：

```bash
adb shell uname -r
# 期望：3.18.140...-Droidspaces

adb shell su -c 'droidspaces check'
```

`droidspaces check` 应全部为绿色对勾。若某项为红叉，对照下表检查：

| 检查项 | 对应 CONFIG |
|---|---|
| PID namespace | `CONFIG_PID_NS=y` |
| MNT/UTS namespace | `CONFIG_NAMESPACES=y`, `CONFIG_UTS_NS=y` |
| IPC namespace | `CONFIG_IPC_NS=y` |
| cgroup device | `CONFIG_CGROUP_DEVICE=y` |
| devtmpfs | `CONFIG_DEVTMPFS=y` |
| OverlayFS（可选） | `CONFIG_OVERLAY_FS=y` |
| Network namespace（NAT/none） | `CONFIG_NET_NS=y` |
| VETH / Bridge（NAT） | `CONFIG_VETH=y`, `CONFIG_BRIDGE=y` |

然后按 Droidspaces 应用指引安装二进制、下载发行版 rootfs 并启动容器。

---

## 已知限制

- **3.18 是 Droidspaces 的最低支持内核**，官方标注为 "Legacy / basic namespace support"。
  现代发行版（较新的 systemd）在 3.18 上可能不稳定。推荐 **Alpine、Debian 稳定版、OpenWrt**
  等较轻量发行版。
- **NAT 模式**：3.18 使用旧式 `IP_NF_*` netfilter 命名，已尽量映射；若 NAT 不通，
  可改用 `--net=host` 或 `--net=none`，隔离特性仍可用。
- **嵌套容器（Docker/Podman 在容器内）**：3.18 缺少新内核的 BPF/cgroup v2 支持，
  嵌套容器大概率不可用；Droidspaces 容器本身不受影响。
- 本配方针对 **crDroid 7.x / LineageOS 18.1 树**。若你换用其他 ROM 内核分支，
  需相应调整 `KERNEL_REPO`、`KERNEL_BRANCH`、`DEFCONFIG`。

---

## 目录结构

```
droidspaces-sailfish/
├── .github/workflows/build.yml   # GitHub Actions 工作流
├── config/droidspaces.config     # 为 3.18 定制的内核配置 fragment
├── patches/
│   ├── 01.fix_kernel_panic_in_xt_qtaguid.patch
│   └── not-applied/
│       └── 02.fix_restore_cgroup_file_prefix_handling.patch  # cgroup v2 only
├── scripts/
│   ├── build.sh                  # 主构建脚本
│   └── verify_config.py          # 配置项强制校验
├── anykernel/anykernel.sh        # AnyKernel3 刷入脚本（A/B）
└── README.md
```

内核源码是 GPL v2；本仓库的构建脚本/配置按 MIT 使用。
