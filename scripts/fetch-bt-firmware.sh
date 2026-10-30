#!/usr/bin/env bash
# 下载 RTL8761B 蓝牙固件到 ImageBuilder 的 files 覆盖层
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="${repo_root}/config/imagebuilder/files/lib/firmware/rtl_bt"
base="https://raw.githubusercontent.com/torvalds/linux-firmware/master/rtl_bt"

mkdir -p "${dest}"
for f in rtl8761bu_fw.bin rtl8761bu_config.bin; do
    curl -fsSL --retry 3 --retry-all-errors -o "${dest}/${f}" "${base}/${f}"
done

ls -l "${dest}"
