# CM311-1a ImmortalWrt 25.12.2 构建方案

> 目标：通过 GitHub Actions 编译适配 CM311-1a（Amlogic S905L3A）的 ImmortalWrt 25.12.2 固件，且**蓝牙功能必须正常**。
> 状态：方案已定稿，待实现。

## 1. 已锁定决策

| 项目 | 决策 | 说明 |
| --- | --- | --- |
| 蓝牙芯片 | RTL8761B（USB 接口，`btusb` 驱动） | 对应 CM311-1a-YST 批次，固件为 `rtl8761bu_fw.bin` |
| 内核 | 自编译 S905L3A 内核（unifreq 源码 + ophub 编译动作） | 完全控制蓝牙相关 config，不依赖上游内核是否带 `btusb` |
| 首版刷机 | 先 USB 启动验证，通过后再写 eMMC | 避免直接写 eMMC 导致变砖 |
| 用户空间 | ImmortalWrt 25.12.2 `armsr/armv8` | 版本严格锁定 25.12.2 |

## 2. 关键约束

ImmortalWrt 25.12.2 官方 target 列表（`dl.wrt.moe/releases/25.12.2/targets/`）中**没有 amlogic/meson**，无法用官方源码直接产出 S905L3A 可刷镜像。因此采用三层拼装：

| 层 | 来源 | 产出 | 职责 |
| --- | --- | --- | --- |
| 用户空间 | ImmortalWrt 25.12.2 `armsr/armv8` ImageBuilder | `rootfs.tar.gz` | LuCI、bluez、dbus、自定义文件；包全部为 aarch64_cortex-a53 |
| 内核/启动 | `unifreq/linux-6.6.y` + `ophub/amlogic-s9xxx-armbian` 编译动作 | `boot/modules/dtb` 三个 tar | Amlogic DTS 与补丁，蓝牙 config 由本项目显式打开 |
| 打包 | `ophub/amlogic-s9xxx-openwrt` / flippy 打包动作 | `*.img.gz` | 生成可 USB 启动、可由晶晨宝盒写入 eMMC 的镜像 |

代价：内核不是 ImmortalWrt 官方内核，而是 unifreq 6.6.y；用户空间、软件包版本、LuCI 均为 25.12.2。

## 3. GitHub Actions 流水线

### 3.1 `build-kernel.yml`

调用 `ophub/amlogic-s9xxx-armbian@main`：

```yaml
- uses: ophub/amlogic-s9xxx-armbian@main
  with:
    build_target: kernel
    kernel_source: unifreq
    kernel_version: 6.6.y
    kernel_config: kernel-config      # 本项目仓库内的 config-6.6
    kernel_sign: -cm311bt
    kernel_package: all
```

产物：`boot-6.6.y-cm311bt.tar.gz`、`modules-*.tar.gz`、`dtb-*.tar.gz`，附 sha256；开启 ccache 缓存以缩短重复编译时间。

### 3.2 `build-rootfs.yml`

1. 下载 `immortalwrt-imagebuilder-25.12.2-armsr-armv8.Linux-x86_64.tar.zst`，校验 sha256，命中 Actions 缓存；
2. 执行：

```bash
make image PROFILE=generic \
  PACKAGES="luci luci-base bluez-daemon bluez-utils dbus" \
  FILES=files/
```

**不安装任何 `kmod-*` 包**，避免替换内核后 ABI 不匹配、白白占用空间。

### 3.3 `build-image.yml`

1. 拉取 3.1、3.2 的产物；
2. 调用打包动作：

```yaml
- uses: ophub/amlogic-s9xxx-openwrt@main
  with:
    openwrt_path: rootfs.tar.gz
    openwrt_board: s905l3a
    openwrt_kernel: 6.6.y-cm311bt
```

3. 执行强制门禁（见第 5 节），全部通过才上传 Artifact 与 Release。

产物命名：`immortalwrt_25.12.2_s905l3a_cm311-1a_bt_<YYYYMMDD>.img.gz` + `sha256.txt`。

触发方式：`workflow_dispatch`（输入内核版本、是否复用缓存）+ `push tag`。

## 4. 蓝牙链路设计

### 4.1 内核配置（显式写入 `kernel-config/config-6.6`）

```
CONFIG_BT=y
CONFIG_BT_HCIBTUSB=m        # RTL8761B 走 USB，决定成败
CONFIG_BT_HCIUART=m         # 备用
CONFIG_BT_HCIUART_RTL=y
CONFIG_BT_RFCOMM=m
CONFIG_BT_RFCOMM_TTY=y
CONFIG_BT_BNEP=m
CONFIG_BT_HIDP=m
CONFIG_BT_LE=y
CONFIG_RFKILL=y
```

同时保留 `CONFIG_FW_LOADER`、USB 控制器/存储相关配置。

### 4.2 固件内置

`files/lib/firmware/rtl_bt/` 内置：

- `rtl8761bu_fw.bin`
- `rtl8761bu_config.bin`

固件不依赖内核 ABI，从 linux-firmware 取用后直接打进 rootfs，是最安全的一环。

### 4.3 用户态

- 包：`bluez-daemon`、`bluez-utils`（含 `bluetoothctl`）、`dbus`；
- UCI 默认值：`bluetoothd` 开机自启；
- 校验 `/etc/init.d/bluetooth` 存在。

### 4.4 验收命令

```bash
dmesg | grep -iE "bluetooth|hci"
hciconfig -a
bluetoothctl
# 交互：power on → scan on → 配对
```

判定标准：`hci0` 出现且 `UP RUNNING`，能扫描到周边设备，能完成一次配对，重启后自动恢复。

## 5. CI 强制门禁

以下任一项不满足即构建失败，防止“刷完才发现没蓝牙”：

1. 内核 `modules` 包内存在 `kernel/drivers/bluetooth/btusb.ko`；
2. 镜像内存在 `rtl8761bu_fw.bin` 与 `rtl8761bu_config.bin`；
3. 镜像内存在 bluez init 脚本与 `bluetoothctl`；
4. 打包时 DTB 正确匹配 `CM311-1a-YST`（`s905l3a` 设备表）；
5. 镜像可解包且 rootfs 大小在预期范围（防止打包空洞）。

## 6. 刷机与验证流程

1. 用 Rufus/balenaEtcher 将 `*.img.gz` 写入 U 盘；
2. U 盘插入盒子通电，访问 `http://192.168.1.1`；
3. 完成第 4.4 节蓝牙验收；
4. 同时确认 100M 网口与 WiFi 状态，避免蓝牙正常但无线异常；
5. 全部通过后，使用晶晨宝盒（luci-app-amlogic）安装到 eMMC，设备选 `CM311-1a-YST`。

## 7. 风险与预案

| 风险 | 预案 |
| --- | --- |
| 6.6.y 内核与 25.12.2 用户态不匹配（概率低） | 保留 6.1.y 作为第二编译版本，出包时可选 |
| 自编译 DTB 与 YST 批次网口/存储不符 | 仅 USB 启动验证，不写 eMMC；必要时按 ophub 设备表换 DTB |
| 固件缺失或版本不匹配 | CI 门禁拦截；仍失败则回退旧版 `rtl8761b_fw.bin` |
| ImageBuilder 残留 armsr kmod 占空间 | 构建时不装 kmod 包，仅使用内核包自带模块 |
| 写 eMMC 变砖 | 保留线刷/短接恢复手段，首版不写 eMMC |

## 8. 仓库结构

```
cm311-1a-immortalwrt/
├── .github/workflows/
│   ├── build-kernel.yml
│   ├── build-rootfs.yml
│   └── build-image.yml
├── kernel-config/
│   └── config-6.6
├── config/
│   └── imagebuilder-packages.txt
├── files/
│   ├── lib/firmware/rtl_bt/rtl8761bu_fw.bin
│   ├── lib/firmware/rtl_bt/rtl8761bu_config.bin
│   └── etc/uci-defaults/
└── README.md
```

## 9. 版本锁定

| 组件 | 版本 |
| --- | --- |
| ImmortalWrt | 25.12.2（armsr/armv8 ImageBuilder） |
| 内核源码 | unifreq/linux-6.6.y（备选 6.1.y） |
| 打包工具 | ophub/amlogic-s9xxx-openwrt、flippy-openwrt-actions |
| 设备条目 | s905l3a / CM311-1a-YST |

## 10. 参考资料

- ImmortalWrt 下载站：https://dl.wrt.moe/
- 25.12.2 target 列表：https://dl.wrt.moe/releases/25.12.2/targets/
- 25.12.2 armsr/armv8 ImageBuilder：https://dl.wrt.moe/releases/25.12.2/targets/armsr/armv8/
- ophub/amlogic-s9xxx-openwrt：https://github.com/ophub/amlogic-s9xxx-openwrt
- ophub 内核编译指南：https://github.com/ophub/amlogic-s9xxx-armbian/blob/main/compile-kernel/README.cn.md
- ophub 设备表：https://github.com/ophub/amlogic-s9xxx-openwrt/blob/main/make-openwrt/openwrt-files/common-files/etc/model_database.conf
