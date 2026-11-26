#!/usr/bin/env python3
"""Verify that the generated .config actually contains everything Droidspaces needs.

Fatal items: containers cannot start at all without them.
Optional items: only needed for NAT mode / extra features — warn, don't fail.
"""
import sys

FATAL = [
    "CONFIG_NAMESPACES",
    "CONFIG_PID_NS",
    "CONFIG_UTS_NS",
    "CONFIG_IPC_NS",
    "CONFIG_CGROUP_DEVICE",
    "CONFIG_DEVTMPFS",
    "CONFIG_SYSVIPC",
    "CONFIG_SECCOMP",
]
OPTIONAL = [
    "CONFIG_NET_NS",          # NAT / none network modes
    "CONFIG_VETH",            # NAT mode
    "CONFIG_BRIDGE",          # NAT mode
    "CONFIG_NETFILTER",       # NAT mode
    "CONFIG_NF_CONNTRACK",    # NAT mode
    "CONFIG_IP_NF_NAT",       # NAT mode
    "CONFIG_IP_NF_TARGET_MASQUERADE",  # NAT mode
    "CONFIG_OVERLAY_FS",      # volatile mode
    "CONFIG_MEMCG",           # resource limits
    "CONFIG_CGROUP_FREEZER",
    "CONFIG_FAIR_GROUP_SCHED",
    "CONFIG_POSIX_MQUEUE",
]


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify_config.py <path-to-.config>", file=sys.stderr)
        return 2
    enabled = set()
    with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if line.startswith("CONFIG_") and "=" in line:
                key, val = line.split("=", 1)
                if val not in ("n", "m", '""'):
                    enabled.add(key)

    missing = [k for k in FATAL if k not in enabled]
    warn = [k for k in OPTIONAL if k not in enabled]

    for k in enabled:
        if k in FATAL:
            print(f"  [OK]   {k}")
    for k in warn:
        print(f"  [WARN] {k} not enabled — related Droidspaces feature may be unavailable")

    if missing:
        print("\nFATAL: required Droidspaces options are missing:", file=sys.stderr)
        for k in missing:
            print(f"  - {k}", file=sys.stderr)
        print("\nThese options were dropped by Kconfig on this kernel tree.", file=sys.stderr)
        print("Check that m1s1_defconfig enables CONFIG_NAMESPACES and its dependencies.", file=sys.stderr)
        return 1

    print("\nAll required Droidspaces options present.")
    if warn:
        print("Containers will start; NAT mode may be unavailable if network options are missing.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
