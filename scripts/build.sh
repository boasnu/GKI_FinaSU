#!/usr/bin/env bash
# AOSP GKI android15-6.6 -> 集成 FinaSU (Built-In) -> 产出 Image / Image.gz / Image.lz4
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/config.env"

KERNEL_TAG="${KERNEL_TAG:-$DEFAULT_KERNEL_TAG}"
MANIFEST_BRANCH="${MANIFEST_BRANCH:-$DEFAULT_MANIFEST_BRANCH}"
FINASU_REF="${FINASU_REF:-$DEFAULT_FINASU_REF}"

WORK="$ROOT/work"
OUT="$ROOT/out"
REL="$ROOT/release"
mkdir -p "$WORK" "$OUT" "$REL"

echo "=========================================================="
echo " REDMI K90 ($DEVICE / $MODEL) GKI + FinaSU"
echo " KMI         : $KMI  ($KERNEL_FAMILY, $PAGE_SIZE pages)"
echo " kernel tag  : $KERNEL_TAG"
echo " manifest    : $MANIFEST_BRANCH"
echo " FinaSU      : $FINASU_REPO @ $FINASU_REF"
echo "=========================================================="

# ---------------------------------------------------------------- 1. AOSP 源码
cd "$WORK"
if [ ! -d .repo ]; then
  echo "==> repo init ($MANIFEST_BRANCH)"
  repo init --depth=1 -u https://android.googlesource.com/kernel/manifest -b "$MANIFEST_BRANCH"
fi
echo "==> repo sync"
if ! repo sync -c --no-tags --no-clone-bundle -j"$(nproc --all)" > "$ROOT/repo-sync.log" 2>&1; then
  echo "!! repo sync 失败，日志末尾："
  tail -30 "$ROOT/repo-sync.log"
  exit 1
fi

[ -d "$WORK/common" ] || { echo "!! 未找到 common/ 内核树，检查 manifest 分支是否存在"; exit 1; }

# 锁定到与设备 6.6.x 一致的 GKI tag（tag 不存在时沿用分支 HEAD 并给警告）
cd "$WORK/common"
if git fetch --depth=1 origin "refs/tags/$KERNEL_TAG:refs/tags/$KERNEL_TAG" >/dev/null 2>&1; then
  git checkout -f "$KERNEL_TAG"
  echo "==> 已锁定 $KERNEL_TAG ($(git rev-parse --short HEAD))"
else
  echo "::warning::未找到 tag $KERNEL_TAG，沿用 $MANIFEST_BRANCH 当前 HEAD，请自行核对 uname -r"
fi

# ---------------------------------------------------------------- 2. 工具链（manifest 自带，hermetic）
CLANG_BIN="$(find "$WORK/prebuilts/clang/host/linux-x86" -type f -path '*/bin/clang' 2>/dev/null | head -1 || true)"
if [ -z "$CLANG_BIN" ]; then
  echo "!! 未在 prebuilts/clang 找到 clang；确认 repo sync 完整"
  exit 1
fi
export PATH="$(dirname "$CLANG_BIN"):$PATH"
echo "==> clang: $(clang --version | head -1)"

# ---------------------------------------------------------------- 3. 集成 FinaSU 驱动
if [ ! -d "$WORK/FinaSU/.git" ]; then
  echo "==> clone FinaSU ($FINASU_REF)"
  git clone --depth=1 -b "$FINASU_REF" "$FINASU_REPO" "$WORK/FinaSU"
fi

echo "==> FinaSU kernel/setup.sh --dir"
cd "$WORK/common"
bash "$WORK/FinaSU/kernel/setup.sh" --dir "$WORK/FinaSU"
# setup.sh 会创建 common/drivers/kernelsu 链接并注入 Makefile/Kconfig
if [ ! -e drivers/kernelsu ] || ! grep -q 'kernelsu' drivers/Makefile; then
  echo "!! FinaSU 驱动未注入 drivers/，检查 setup.sh 参数是否变更（官方写法：setup.sh --dir /path/to/FinaSU）"
  exit 1
fi

# FinaSU preinit 运行器需要 UAPI 头文件，先装好并把路径暴露给源码树
mkdir -p "$WORK/common/usr"
ln -sfn "$OUT/usr/include" "$WORK/common/usr/include"

# ---------------------------------------------------------------- 4. 配置
MAKEVARS=(
  "O=$OUT"
  "ARCH=arm64"
  "LLVM=1"
  "LLVM_IAS=1"
  "CLANG_TRIPLE=aarch64-linux-gnu-"
  "CROSS_COMPILE=aarch64-linux-gnu-"
  "-j$(nproc --all)"
)

echo "==> gki_defconfig"
make "${MAKEVARS[@]}" gki_defconfig > "$ROOT/build.log" 2>&1

echo "==> 启用 FinaSU 所需 CONFIG"
scripts/config --file "$OUT/.config" \
  --enable KSU \
  --enable KPROBES \
  --enable KALLSYMS_ALL \
  --enable EXT4_FS \
  --enable HEADERS_INSTALL

make "${MAKEVARS[@]}" olddefconfig >> "$ROOT/build.log" 2>&1
make "${MAKEVARS[@]}" headers_install >> "$ROOT/build.log" 2>&1

# 确认关键项真的写进去了
grep -q '^CONFIG_KSU=y' "$OUT/.config" || { echo "!! CONFIG_KSU 未生效（FinaSU Kconfig 可能改名）"; exit 1; }
echo "    CONFIG_KSU=y  OK"

# ---------------------------------------------------------------- 5. 编译
# KSU_REQUIRE_PREINIT=1 必须显式传入：缺 UAPI 头文件时直接失败，而不是静默关掉 preinit
echo "==> make KSU_REQUIRE_PREINIT=1 Image Image.gz Image.lz4"
if ! make "${MAKEVARS[@]}" KSU_REQUIRE_PREINIT=1 Image Image.gz Image.lz4 >> "$ROOT/build.log" 2>&1; then
  echo "!! 编译失败，日志末尾："
  tail -80 "$ROOT/build.log"
  exit 1
fi

IMG="$OUT/arch/arm64/boot/Image"
[ -s "$IMG" ] || { echo "!! 未生成 Image"; exit 1; }

echo "==> 产物校验"
if strings "$IMG" | grep -qE '6\.6\.[0-9]+-android15-8'; then
  strings "$IMG" | grep -m1 -E 'Linux version 6\.6\.[0-9]+-android15-8' || true
  echo "    KMI  android15-8  OK"
else
  echo "::warning::Image 中未检出 android15-8 版本串，请人工核对 KMI 后再刷入"
fi

cp "$IMG"                       "$REL/Image"
cp "$OUT/arch/arm64/boot/Image.gz"  "$REL/Image.gz"
cp "$OUT/arch/arm64/boot/Image.lz4" "$REL/Image.lz4"
ls -lh "$REL"
echo "==> build.sh 完成"
