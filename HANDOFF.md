# 会话交接（HANDOFF）

新会话接手 CM311-1a 构建时先读本文件，再看 [PLAN.md](./PLAN.md)。

## 仓库

- 本地：`D:\各种盒子\CM311-1a\cm311-1a-immortalwrt`
- 远端：https://github.com/steven-ye/cm311-1a-immortalwrt（Public，main）
- 推送已配置 SSH（`steven-ye`），无需再配凭证

## 当前状态（截至 2026-10-30）

- `rootfs` job：**成功**（证明 ImmortalWrt 25.12.2 apk 源里 `bluez-daemon`、`bluez-utils` 包名有效）
- `kernel` job：失败 3 次，均已修复
  1. 首次：下载模板 URL 拼成 `config-6.6.y` → 404
  2. 修复方式：改为仓库内置 `kernel-config/config-6.6`（ophub stable 模板 + `bt.fragment` 合并，9650 行）
  3. 第二次：校验步骤仍用 `KERNEL_SERIES=6.6.y` 拼文件名 → 又 404，已改为 `${KERNEL_SERIES%.y}` 映射
- `image` job：因 kernel 失败一直 skipped，**从未验证过**

## 关键决策

- 用户空间：ImmortalWrt 25.12.2 `armsr/armv8`，用 ophub `config/imagebuilder/imagebuilder.sh`，已移除 4 个 `kmod-*`
- 内核：unifreq 6.6.y 自编译，跑在 `ubuntu-26.04-arm`；产物发布到本仓库 Release `kernel_stable`
- 打包：`openwrt_board: s905l3a-cm311`、`kernel_repo: 本仓库`、`kernel_usage: stable`
- 蓝牙：`btusb` + 内置 `rtl8761bu_fw.bin` / `rtl8761bu_config.bin`（从 Debian firmware-realtek 提取），bluez 开机自启

## 待验证（首个未知点）

1. 打包动作是否接受 `kernel_repo` 指向非 ophub 的仓库（读取本仓库 `kernel_stable` Release）
2. `kernel_sign: -cm311bt` 是否影响打包时按 `6.6.y` 匹配内核文件
3. 镜像首启后 `hci0` 是否 `UP RUNNING`、能否扫描/配对

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

1. 推送本次修复并打新 tag 触发构建
2. 盯 `kernel` 是否编出 `btusb.ko`、`kernel_stable` Release 是否生成
3. 盯 `image` 能否读到内核并出 `.img.gz`
4. 出包后按 PLAN 第 6 节 USB 启动验收蓝牙
