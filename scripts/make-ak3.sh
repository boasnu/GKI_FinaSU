#!/usr/bin/env bash
# 把编译产物打成 3 份 AnyKernel3 包（按原厂 boot 的 kernel 压缩格式挑一份刷）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/out"
REL="$ROOT/release"
AK3="$ROOT/work/AK3"

[ -s "$OUT/arch/arm64/boot/Image" ] || { echo "!! 先跑 build.sh"; exit 1; }

echo "==> 拉取 AnyKernel3 模板（含 META-INF / tools / magiskboot / ak3-core.sh）"
if [ ! -d "$AK3/.git" ]; then
  git clone --depth=1 https://github.com/osm0sis/AnyKernel3.git "$AK3"
fi
rm -f "$AK3/anykernel.sh" "$AK3/Image" "$AK3/Image.gz" "$AK3/Image.lz4" "$AK3/Image.gz-dtb" "$AK3/Image.lz4-dtb"
cp "$ROOT/anykernel.sh" "$AK3/anykernel.sh"

# 裸内核文件（供本地 magiskboot 手工打包）
cp "$OUT/arch/arm64/boot/Image"     "$REL/Image"
cp "$OUT/arch/arm64/boot/Image.gz"  "$REL/Image.gz"
cp "$OUT/arch/arm64/boot/Image.lz4" "$REL/Image.lz4"

for fmt in gz lz4 raw; do
  name="AnyKernel3-REDMI-K90-annibale-FinaSU-${fmt}"
  tmp="$ROOT/work/ak3-$fmt"
  rm -rf "$tmp"
  cp -a "$AK3" "$tmp"
  case "$fmt" in
    gz)  cp "$OUT/arch/arm64/boot/Image.gz"  "$tmp/Image.gz"  ;;
    lz4) cp "$OUT/arch/arm64/boot/Image.lz4" "$tmp/Image.lz4" ;;
    raw) cp "$OUT/arch/arm64/boot/Image"     "$tmp/Image"     ;;
  esac
  (cd "$tmp" && zip -r9 -q "$REL/$name.zip" . -x '*.git*' -x '*README*' -x '*.md')
  echo "    $name.zip"
done

# 顺带把配套 FinaSU Manager 抓下来（版本与内核对齐更省心）
echo "==> 获取 FinaSU Manager APK"
APK_URL="$(curl -sSL --max-time 30 \
  https://api.github.com/repos/LyraVoid/FinaSU/releases/latest \
  | jq -r '.assets[] | select(.name | test("\\.apk$"; "i")) | .browser_download_url' \
  | head -1 || true)"
if [ -n "$APK_URL" ] && [ "$APK_URL" != "null" ]; then
  curl -sSL --max-time 120 -o "$REL/FinaSU-Manager.apk" "$APK_URL" && \
    echo "    FinaSU-Manager.apk" || echo "::warning::Manager 下载失败，自行去 FinaSU Releases 取"
else
  echo "::warning::未解析到 Manager APK，自行去 https://github.com/LyraVoid/FinaSU/releases 取"
fi

echo "==> 产物清单"
ls -lh "$REL"
