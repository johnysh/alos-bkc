# ALOS + Kernel BKC Build Guide

完整流程：**启动容器** → 下载源码 → 打 Patch → 编译 Kernel → 编译 ALOS → 生成 Android Image

> 所有脚本均为 **Linux bash 脚本**，需在 Linux 环境（或 Docker 容器）下运行。

---

## 获取脚本

```bash
git clone https://github.com/johnysh/alos-bkc.git
cd alos-bkc
chmod +x *.sh
```

---

## 环境说明

编译步骤默认在 **Docker 容器** 内运行，默认路径：

| 路径 | 说明 |
|------|------|
| `/root/alos` | Android 源码树 |
| `/root/kernel` | Android GKI kernel (6.18) |
| `/root/grub` | GRUB patches + kernel patches 仓库（alos-grub）|

如需使用自定义路径，通过脚本参数指定（见各步骤说明）。

---

## Step 0：启动 Docker 容器

在**宿主机（Linux）** 上运行：

```bash
./run_container.sh
```

脚本提供交互式菜单：

```
请选择功能:
1) 创建容器并初始化配置
2) 启动指定容器
3) 进入正在运行的容器
4) 退出
```

### 选项 1：创建容器

首次使用时选择 **1**，依次输入：

| 提示 | 默认值 | 说明 |
|------|--------|------|
| 镜像名 | `alos_build:latest` | Docker 镜像名称 |
| 容器名称 | `alos_yourname` | 建议填自己名字，如 `alos_zhangsan` |
| 宿主机映射端口 | `6000` | SSH 端口，映射到容器 22 |
| 宿主机 ALOS 源码目录 | （留空） | 填写后挂载为容器内 `/root/alos` |
| 宿主机 Kernel 源码目录 | （留空） | 填写后挂载为容器内 `/root/kernel` |
| 宿主机 alos-grub 目录 | （留空） | 填写后挂载为容器内 `/root/grub` |
| git user.name | | 设置容器内 git 用户名 |
| git user.email | | 设置容器内 git 邮箱 |

> **提示：** 如果宿主机已有 ALOS/Kernel/alos-grub 源码，填写目录后会挂载进容器，避免重复下载。

### 选项 2：启动已有容器

容器停止后重新启动：
```
输入选项: 2
请输入容器名称 [alos_yourname]: alos_zhangsan
```

### 选项 3：进入容器

```
输入选项: 3
请输入容器名称 [alos_yourname]: alos_zhangsan
```
进入容器后即可执行后续编译步骤。

### SSH 登录容器（可选）

创建容器后也可通过 SSH 连接（密码通常为 `root` 或镜像设定的密码）：
```bash
ssh root@<宿主机IP> -p <映射端口>
# 例如：
ssh root@10.67.116.199 -p 6000
```

---

## 完整 BKC 流程

### Step 1：下载 ALOS 源码

```bash
./sync_alos_ww13p.sh
```

运行后会提示输入 Artifactory 账号（Intel IDSID）和密码。

**自定义路径：**
```bash
./sync_alos_ww13p.sh --dir /data/alos
```

**参数说明：**
| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-d, --dir <path>` | `/root/alos` | ALOS 下载目录 |
| `-j, --jobs <num>` | `16` | 并行 sync 线程数 |

---

### Step 2：下载 Kernel 源码

```bash
./sync_kernel_ww13p.sh
```

**自定义路径：**
```bash
./sync_kernel_ww13p.sh --dir /data/kernel
```

**参数说明：**
| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-d, --dir <path>` | `/root/kernel` | Kernel 下载目录 |
| `-j, --jobs <num>` | `16` | 并行 sync 线程数 |
| `-b, --branch <name>` | `mirror/14-Mar-2025` | manifest repo 分支 |

---

### Step 3：打 Patch（ALOS + Kernel）

```bash
./deploy_patches.sh
```

脚本会依次询问：
1. `ALOS_GRUB_TOP` — alos-grub 目录（默认 `/root/grub`）
2. `ANDROID_BUILD_TOP` — ALOS 源码目录（默认 `/root/alos`）
3. `Kernel workspace` — Kernel 源码目录（默认 `/root/kernel`）
4. `Target device` — 目标设备（ocelot / firefly / fatcat）

**两类 patch 分别处理：**

- **ALOS patches**（GRUB/ESP 启动支持）：
  ```
  cd $ANDROID_BUILD_TOP
  $ALOS_GRUB_TOP/deploy.sh --target=<device>
  → 输出到 vendor/intel/utils/aosp_diff/<device>/
  → 输出到 vendor/intel/utils/grub_prebuilts/
  ```

- **Kernel patches**：
  ```
  cd $ALOS_GRUB_TOP/kernel
  ./patch-overlay -w <kernel_workspace> -p ./patches apply
  → 自动跳过已 apply 的 patch
  → 失败时报错退出
  ```

---

### Step 4：编译 Kernel

```bash
./build_kernel.sh
```

**自定义路径：**
```bash
./build_kernel.sh --dir /data/kernel
./build_kernel.sh -d /data/kernel -j 16
```

**参数说明：**
| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-d, --dir <path>` | `/root/kernel` | Kernel 源码目录 |
| `-j, --jobs <num>` | bazel 默认 | 并行编译线程数 |

**编译产物：**
```
/root/kernel/out/kernel_x86_64/dist/bzImage
/root/kernel/out/kernel_x86_64/dist/System.map
/root/kernel/out/kernel_x86_64/dist/*.ko   (system_dlkm)
/root/kernel/out/ocelot/dist/*.ko           (vendor_dlkm)
```

---

### Step 5：编译 ALOS + 打包 Image

```bash
./build_alos.sh
```

**自定义路径：**
```bash
./build_alos.sh --alos-dir /data/alos --kernel-dir /data/kernel
./build_alos.sh -a /data/alos -k /data/kernel -j 16
```

**参数说明：**
| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-a, --alos-dir <path>` | `/root/alos` | ALOS 源码目录 |
| `-k, --kernel-dir <path>` | `/root/kernel` | Kernel 产物目录 |
| `-j, --jobs <num>` | `40` | 并行编译线程数 |

**内部流程：**
```
[1/5] source build/envsetup.sh
[2/5] arsp-apks-prebuilt-recipe.sh
[3/5] lunch ocelot-cl3b-userdebug
[4/5] m droid              ← 编译 Android
[4.5] 替换 kernel 二进制   ← 从 kernel-dir 拷贝 bzImage/ko
[5/5] m pack-image         ← 打包成 Android Image
```

**输出 Image：**
```
/root/alos/out/target/product/ocelot/
├── system.img
├── vendor.img
├── boot.img
├── vendor_boot.img
├── super.img
└── ocelot-img-*.zip   ← 完整刷机包
```

---

## 快速一键执行（默认路径）

```bash
# 1. 下载源码（需要 Artifactory 账号）
./sync_alos_ww13p.sh
./sync_kernel_ww13p.sh

# 2. 打 patch（交互式输入路径和 target）
./deploy_patches.sh

# 3. 编译 kernel
./build_kernel.sh

# 4. 编译 ALOS + 打包
./build_alos.sh
```

---

## 自定义路径示例（非 Docker 默认）

```bash
ALOS=/data/alos
KERNEL=/data/kernel

./sync_alos_ww13p.sh   -d ${ALOS}
./sync_kernel_ww13p.sh -d ${KERNEL}
./deploy_patches.sh    # 按提示输入 ${ALOS} 和 ${KERNEL}
./build_kernel.sh      -d ${KERNEL}
./build_alos.sh        -a ${ALOS} -k ${KERNEL}
```

---

## 脚本列表

| 脚本 | 功能 |
|------|------|
| `run_container.sh` | 创建/启动/进入 Docker 编译容器（**宿主机运行**） |
| `sync_alos_ww13p.sh` | 下载 ALOS WW13_P 源码（repo sync） |
| `sync_kernel_ww13p.sh` | 下载 Kernel WW13_P 源码（repo sync） |
| `deploy_patches.sh` | 打 ALOS GRUB patches + Kernel patches |
| `build_kernel.sh` | 编译 GKI kernel + ocelot vendor modules |
| `build_alos.sh` | 编译 ALOS droid，替换 kernel，打包 image |
| `scripts/ecg-1/fix_usbrelay.sh` | 修复 USB Relay udev 权限规则（ECG-1 主机运行） |
| `scripts/ecg-1/switch_usb.sh` | 通过 USB Relay 切换 USB 供电（触发设备重启） |
| `scripts/ecg-1/flash_image.sh` | 将 Android Image 写入 SanDisk U 盘（ECG-1 主机运行） |
| `scripts/ecg-1/run_cts.sh` | 启动 CTS 测试（自动连接 ADB 设备） |

---

## ECG-1 测试机工具脚本

ECG-1 测试机（`alos-ecg-1@10.239.58.154`）上的辅助脚本，位于 `scripts/ecg-1/`。

### fix_usbrelay.sh — 修复 USB Relay 权限

首次使用 USB Relay 前运行，添加 udev 规则使普通用户可访问：

```bash
bash scripts/ecg-1/fix_usbrelay.sh
```

### switch_usb.sh — USB 电源切换

通过 USB Relay 断电再上电，用于重启连接的 USB 设备（如 U 盘）：

```bash
bash scripts/ecg-1/switch_usb.sh
```

### flash_image.sh — 刷写 Android Image

将 `.bin.gz` 格式的 Android Image 写入 SanDisk Extreme Pro U 盘（VID:0781 PID:5588）：

```bash
# 使用默认 image 文件名 android-desktop_image.bin.gz
bash scripts/ecg-1/flash_image.sh

# 或指定 image 文件
bash scripts/ecg-1/flash_image.sh /path/to/your_image.bin.gz
```

> 脚本会自动识别 SanDisk U 盘，提示确认后开始写入，写入前自动卸载已挂载分区。

### run_cts.sh — 启动 CTS 测试

自动连接 ADB 设备（`10.239.58.115:5555`）并启动 cts-tradefed：

```bash
# 进入交互模式
bash scripts/ecg-1/run_cts.sh

# 直接运行指定 plan
bash scripts/ecg-1/run_cts.sh run cts -m CtsDisplayTestCases
```

> 前提：CTS 工具包已解压到 `~/sjh/android-cts/`，参考 CTS 环境搭建步骤。
