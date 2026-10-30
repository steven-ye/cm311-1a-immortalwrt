# CM311-1a ImmortalWrt 25.12.2

通过 GitHub Actions 编译适配 CM311-1a（Amlogic S905L3A）的 ImmortalWrt 25.12.2 固件，蓝牙基于 RTL8761B，要求开机可用。

## 当前进度

- [x] 方案定稿（见 [PLAN.md](./PLAN.md)）
- [x] 搭建 Actions 流水线（`build.yml` 三阶段：内核 / rootfs / 打包）
- [x] 蓝牙内核 config 与固件内置
- [ ] 首次 Actions 运行与出包
- [ ] USB 启动验证 → eMMC 安装

## 构建入口

在 Actions 页面运行 **Build CM311-1a ImmortalWrt 25.12.2**（`workflow_dispatch`），或推送 `v*` 标签。
内核与固件分别发布到本仓库 `kernel_stable`、`firmware_25.12.2` 两个 Release。

## 方案要点

- ImmortalWrt 25.12.2 没有 amlogic target，采用「25.12.2 用户空间 + 自编译 S905L3A 内核 + ophub 打包」三层拼装。
- 内核用 unifreq 6.6.y 源码自编译，显式开启 `CONFIG_BT_HCIBTUSB` 等蓝牙选项。
- 内置 `rtl8761bu_fw.bin` / `rtl8761bu_config.bin`，用户态为 bluez + dbus。
- CI 内置门禁：缺 `btusb.ko`、固件或 bluez 即构建失败。

## 刷机

首版先写 U 盘启动验证（默认 IP `192.168.1.1`），蓝牙验收通过后再用晶晨宝盒写入 eMMC，设备选 `CM311-1a-YST`。

详细步骤、内核配置、门禁与风险预案见 [PLAN.md](./PLAN.md)。
