# 会话交接（HANDOFF）

新会话接手 CM311-1a 构建时先读本文件，再看 [PLAN.md](./PLAN.md)。

## 仓库

- 本地：`D:\各种盒子\CM311-1a\cm311-1a-immortalwrt`
- 远端：https://github.com/steven-ye/cm311-1a-immortalwrt（Public，main）
- 推送已配置 SSH（`steven-ye`），无需再配凭证

## 当前状态（截至 2026-10-30 晚）

- **镜像已产出**（run #5 / tag `v0.1.3` / `8027bb6`，全绿）：
  `firmware_25.12.2` Release 内 `openwrt_immortalwrt_amlogic_s905l3a-cm311_k6.6.160_2026.10.30.img.gz`（310.22 MB）
  https://github.com/steven-ye/cm311-1a-immortalwrt/releases/download/firmware_25.12.2/openwrt_immortalwrt_amlogic_s905l3a-cm311_k6.6.160_2026.10.30.img.gz
- `rootfs` job：成功（ImmortalWrt 25.12.2 apk 源里 `bluez-daemon`、`bluez-utils` 包名有效）
- `kernel` job：自编译 3 次失败后已放弃，改用 ophub 预编译内核
  - 失败根因：新版 kernel 动作产物变成**单一合并包** `<ver><sign>.tar.gz`（内部 `<ver><sign>/{boot,dtb-*,modules}-*.tar.gz`），
    旧门禁按顶层 `modules-*.tar.gz` 查找，必然报「未找到 modules 内核包」
  - 关键事实：仓库 `kernel-config/config-6.6` 与 `ophub/kernel` 的 `kernel-config/release/stable/config-6.6`
    **逐行完全一致**（均含 `CONFIG_BT=m`、`CONFIG_BT_HCIBTUSB=m`），故预编译包与本仓库自编译产物等价
  - 现策略：`image` job 用 `kernel_repo: ophub/kernel` + `kernel_usage: stable`（自动取 6.6.160）；
    `kernel` job 保留但默认跳过（仅 `workflow_dispatch` + `build_kernel=true` 时运行），门禁已改为解合并包查 `btusb.ko`
- `image` job：成功，出 `.img.gz`

## 关键决策

- 用户空间：ImmortalWrt 25.12.2 `armsr/armv8`，用 ophub `config/imagebuilder/imagebuilder.sh`，已移除 4 个 `kmod-*`
- 内核：直接用 `ophub/kernel` 的 `kernel_stable` 预编译包（6.6.160），不再自编译
- 打包：`openwrt_board: s905l3a-cm311`、`kernel_repo: ophub/kernel`、`kernel_usage: stable`、`auto_kernel: true`
- 蓝牙：`btusb` + 内置 `rtl8761bu_fw.bin` / `rtl8761bu_config.bin`（从 Debian firmware-realtek 提取），bluez 开机自启

## 蓝牙/DTS 备用文件（仅在出问题后使用）

用户在旧固件上验证过的一对替换文件，已存入仓库 `fallback/`，**默认不参与构建**：

| 文件 | 位置 | 用途 |
| --- | --- | --- |
| `meson-g12a-s905l3a-cm311.dtb` (79229 B) | `fallback/dtb/` | 首启异常（网口/存储/外设不对）时，替换镜像 `/boot/dtb/amlogic/meson-g12a-s905l3a-cm311.dtb` |
| `rtl8761b_config.bin` (81 B) | `fallback/firmware/` | `hci0` 出现但初始化失败时，放到目标机 `/lib/firmware/rtl_bt/`（当前镜像内置的是 6 B 的 `rtl8761bu_config.bin`） |

处理方式：出问题时把对应文件加进 `config/imagebuilder/files/...`（固件）或替换 dtb 后重打包，而不是手工改板上文件。

## 待验证（实测）

1. U 盘启动后网口/存储是否正常（异常则按上表替换 dtb）
2. `hci0` 是否 `UP RUNNING`、能否扫描/配对（异常则先换 81 B 的 rtl8761b_config.bin 重打包）
3. 蓝牙不通时再回到自编译内核路径（workflow_dispatch 勾 `build_kernel=true`）

## 常用命令

```bash
# 触发构建（推 tag 即可，勿用 -f）
git tag v0.1.x && git push origin v0.1.x

# 查运行状态（无需 token）
curl -s "https://api.github.com/repos/steven-ye/cm311-1a-immortalwrt/actions/runs?per_page=3" \
  | python -c "import json,sys;d=json.load(sys.stdin);[print(r['id'],r['status'],r['conclusion']) for r in d['workflow_runs']]"

# 查 job/step 结论
curl -s ".../actions/runs/<id>/jobs" | python -c "..."
```

注意：匿名访问拿不到日志正文（403），需要看具体日志时让用户在网页端复制，或用带 repo 权限的 token。

## 下一步

1. 下载 `firmware_25.12.2` 的 `.img.gz`，写 U 盘启动 CM311-1a 验证
2. 蓝牙验收：`bluetoothctl list` / `show` / `scan on`，看 `hci0` 是否 UP
3. 全绿后可选：在「系统 → 晶晨宝盒」安装到 eMMC（设备选 `CM311-1a-YST`）
