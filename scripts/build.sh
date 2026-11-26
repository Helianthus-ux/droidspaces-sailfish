#!/bin/bash
# =============================================================================
# build.sh — Build a Droidspaces-enabled kernel for Pixel 1 (sailfish/marlin)
# Target: crDroid 7.x (Android 11) / msm-3.18 / cgroup v1
# Compiler: Linaro GCC 4.9.4 (ONLY version that boots on msm-3.18)
# Output: out/arch/arm64/boot/Image.lz4-dtb
# =============================================================================
set -euo pipefail

KERNEL_REPO="${KERNEL_REPO:-https://github.com/blckbearx/android_kernel_google_marlin}"
KERNEL_BRANCH="${KERNEL_BRANCH:-lineage-18.1-upstream}"
ARCH="arm64"
DEFCONFIG="m1s1_defconfig"
JOBS="${JOBS:-$(nproc)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KERNEL_DIR="$ROOT_DIR/kernel"
OUT_DIR="$ROOT_DIR/out"
TC_DIR="$ROOT_DIR/toolchains"
AARCH64_TC="$TC_DIR/aarch64-linux-gnu"
ARM32_TC="$TC_DIR/arm-linux-gnueabi"
# Linaro's releases.linaro.org binaries were retired (URL now 301s to a
# contact page), so use verified GitHub mirrors of the exact same 4.9.4
# toolchains. These repos contain real ELF binaries, not Git LFS pointers.
AARCH64_URL="${AARCH64_URL:-https://github.com/KeanuSilverhand/gcc-linaro-4.9.4-2017.01-x86_64_aarch64-linux-gnu}"
AARCH64_BRANCH="${AARCH64_BRANCH:-master}"
AARCH64_FALLBACK="https://github.com/Backup-Gits/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-4.9.4"
AARCH64_FALLBACK_BRANCH="9.0"
ARM32_URL="${ARM32_URL:-https://github.com/chenxiaoqun/gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf}"
ARM32_BRANCH="${ARM32_BRANCH:-master}"
CROSS_COMPILE="${CROSS_COMPILE:-$AARCH64_TC/bin/aarch64-linux-gnu-}"
CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32:-$ARM32_TC/bin/arm-linux-gnueabihf-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[Droidspaces]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Helpers: idempotent config edit + source patch
# ---------------------------------------------------------------------------
set_config() {
    local file="$1" key="$2" val="$3"
    if grep -q "^${key}=" "$file"; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$file"
    elif grep -q "^# ${key} is not set" "$file"; then
        sed -i "s|^# ${key} is not set|${key}=${val}|" "$file"
    else
        echo "${key}=${val}" >> "$file"
    fi
}

apply_source_fixes() {
    log "Applying Droidspaces source fixes (idempotent)..."
    cd "$KERNEL_DIR"

    # Fix 1/3: xt_qtaguid kernel panic on inactive interfaces (from Droidspaces-OSS)
    # Applied via python for whitespace robustness instead of a fragile patch.
    if grep -q "DS_QTAGUID_FIX" net/netfilter/xt_qtaguid.c 2>/dev/null; then
        warn "xt_qtaguid fix already applied, skipping"
    else
        python3 - <<'PYEOF'
import sys
p = "net/netfilter/xt_qtaguid.c"
s = open(p, encoding="utf-8", errors="surrogateescape").read()
old_decl = "struct rtnl_link_stats64 dev_stats, *stats;"
new_decl = "struct rtnl_link_stats64 *stats; /* DS_QTAGUID_FIX */"
old_block = """\tif (iface_entry->active) {
\t\tstats = dev_get_stats(iface_entry->net_dev,
\t\t\t\t      &dev_stats);
\t} else {
\t\tstats = &no_dev_stats;
\t}"""
new_block = "\tstats = &no_dev_stats; /* DS_QTAGUID_FIX: avoid panic on inactive iface */"
if old_decl not in s:
    print("WARNING: xt_qtaguid decl not found (kernel variant?)", file=sys.stderr)
else:
    s = s.replace(old_decl, new_decl, 1)
if old_block not in s:
    print("WARNING: xt_qtaguid block not found (kernel variant?)", file=sys.stderr)
else:
    s = s.replace(old_block, new_block, 1)
open(p, "w", encoding="utf-8", errors="surrogateescape").write(s)
print("  xt_qtaguid: unsafe dev_get_stats removed")
PYEOF
    fi

    # Fix 2/3: SMP2P mock functions compiled unconditionally — upstream build bug
    # on msm-3.18. Guard them behind CONFIG_MSM_SMP2P_TEST.
    if grep -q "SMP2P_BUILD_FIX" drivers/soc/qcom/smp2p.c 2>/dev/null; then
        warn "SMP2P build fix already applied, skipping"
    else
        python3 - <<'PYEOF'
p = "drivers/soc/qcom/smp2p.c"
s = open(p, encoding="utf-8", errors="surrogateescape").read()
s = s.replace(
    "\tsmp2p_remote_mock_rx_interrupt();",
    "#ifdef CONFIG_MSM_SMP2P_TEST /* SMP2P_BUILD_FIX */\n\tsmp2p_remote_mock_rx_interrupt();\n#endif"
)
s = s.replace(
    "\t\titem_ptr = msm_smp2p_get_remote_mock_smem_item(&size);",
    "#ifdef CONFIG_MSM_SMP2P_TEST /* SMP2P_BUILD_FIX */\n\t\titem_ptr = msm_smp2p_get_remote_mock_smem_item(&size);\n#else\n\t\titem_ptr = NULL;\n#endif"
)
open(p, "w", encoding="utf-8", errors="surrogateescape").write(s)
print("  smp2p: mock calls guarded")
PYEOF
    fi

    # Fix 3/3: cgroup file prefix (Droidspaces patch 2) is for cgroup v2 only.
    # This kernel is cgroup v1 (kernel/cgroup.c), where the "subsys.file" naming
    # is native, so that patch is intentionally NOT applied.
    warn "cgroup prefix patch (cgroup v2) intentionally skipped — this kernel is cgroup v1"
}

clone_toolchain() {
    # clone_toolchain <url> <branch> <dest> <binary-name> <label> [fallback-url] [fallback-branch]
    local url="$1" branch="$2" dest="$3" bin="$4" label="$5"
    local fb_url="${6:-}" fb_branch="${7:-}"
    if [ -x "$dest/bin/$bin" ]; then
        log "$label toolchain already installed"
        return 0
    fi
    mkdir -p "$TC_DIR"
    log "Fetching $label GCC 4.9.4 from $url ..."
    if ! git clone --quiet --depth 1 --single-branch -b "$branch" "$url" "$dest"; then
        if [ -n "$fb_url" ]; then
            warn "primary mirror failed, trying fallback..."
            rm -rf "$dest"
            git clone --quiet --depth 1 --single-branch -b "$fb_branch" "$fb_url" "$dest" \
                || die "failed to fetch $label toolchain (both mirrors)"
        else
            die "failed to fetch $label toolchain"
        fi
    fi
    [ -x "$dest/bin/$bin" ] || die "$label toolchain missing bin/$bin"
    "$dest/bin/$bin" --version 2>/dev/null | head -1 || true
}

install_toolchain() {
    clone_toolchain "$AARCH64_URL" "$AARCH64_BRANCH" "$AARCH64_TC" \
        "aarch64-linux-gnu-gcc" "aarch64" \
        "$AARCH64_FALLBACK" "$AARCH64_FALLBACK_BRANCH"
    clone_toolchain "$ARM32_URL" "$ARM32_BRANCH" "$ARM32_TC" \
        "arm-linux-gnueabihf-gcc" "arm32"
    log "Toolchains ready"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log "Root: $ROOT_DIR"
command -v curl >/dev/null || die "curl not found"
command -v python3 >/dev/null || die "python3 not found"

# 1. Get kernel source
if [ -d "$KERNEL_DIR/.git" ]; then
    log "Kernel source exists, skipping clone"
else
    log "Cloning kernel source ($KERNEL_BRANCH)..."
    git clone --depth=1 --single-branch -b "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_DIR" \
        || die "kernel clone failed"
fi

# 2. Toolchain
install_toolchain

# 3. Source fixes
apply_source_fixes

# 4. Configure — merge device defconfig with the Droidspaces fragment.
#    Kbuild merges multiple config targets passed to a single make invocation.
cd "$KERNEL_DIR"
mkdir -p "$OUT_DIR"
cp "$ROOT_DIR/config/droidspaces.config" "arch/$ARCH/configs/droidspaces.config"

log "Generating base config ($DEFCONFIG)..."
make O="$OUT_DIR" ARCH="$ARCH" \
    CROSS_COMPILE="$CROSS_COMPILE" CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32" \
    "$DEFCONFIG"

# Merge the Droidspaces fragment into .config with an idempotent Python routine.
# Doing it directly (rather than relying on multi-target `make ... frag.config`,
# whose merge behavior varies across Kbuild versions) is deterministic on 3.18.
log "Merging droidspaces.config fragment..."
python3 - "$ROOT_DIR/config/droidspaces.config" "$OUT_DIR/.config" <<'PYEOF'
import sys
frag, cfg = sys.argv[1], sys.argv[2]
lines = open(cfg, encoding="utf-8", errors="surrogateescape").read().splitlines()
index = {}
for i, line in enumerate(lines):
    if line.startswith("CONFIG_") and "=" in line:
        index[line.split("=", 1)[0]] = i
    elif line.startswith("# CONFIG_") and line.endswith(" is not set"):
        index[line.split()[1]] = i

with open(frag, encoding="utf-8") as f:
    for raw in f:
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#"):
            # turn "# CONFIG_X is not set" into an explicit n assignment
            if " is not set" in line and line.startswith("# CONFIG_"):
                key = line.split()[1]
                newline = "# %s is not set" % key
                if key in index:
                    lines[index[key]] = newline
                else:
                    index[key] = len(lines); lines.append(newline)
            continue
        if "=" not in line or not line.startswith("CONFIG_"):
            continue
        key = line.split("=", 1)[0]
        if key in index:
            lines[index[key]] = line
        else:
            index[key] = len(lines); lines.append(line)

open(cfg, "w", encoding="utf-8", errors="surrogateescape").write("\n".join(lines) + "\n")
print("  fragment merged")
PYEOF

log "Running olddefconfig to resolve dependencies..."
make O="$OUT_DIR" ARCH="$ARCH" olddefconfig

log "Verifying required Droidspaces options..."
python3 "$SCRIPT_DIR/verify_config.py" "$OUT_DIR/.config"

# 5. Build
log "Building with $JOBS jobs (GCC 4.9)..."
make -C "$KERNEL_DIR" O="$OUT_DIR" \
    ARCH="$ARCH" \
    CROSS_COMPILE="$CROSS_COMPILE" \
    CROSS_COMPILE_ARM32="$CROSS_COMPILE_ARM32" \
    KCFLAGS="-Wno-error=unused-variable -Wno-error=unused-but-set-variable" \
    -j"$JOBS"

IMAGE="$OUT_DIR/arch/$ARCH/boot/Image.lz4-dtb"
if [ -f "$IMAGE" ]; then
    log "BUILD SUCCESS — $IMAGE ($(du -h "$IMAGE" | cut -f1))"
    strings "$OUT_DIR/vmlinux" | grep "Linux version" | head -1 || true
else
    die "Build finished but Image.lz4-dtb not found"
fi
