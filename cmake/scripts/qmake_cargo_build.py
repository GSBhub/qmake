#!/usr/bin/env python3
"""Build a Cargo staticlib for QEMU's meson build (used by LANG CARGO modules).

Runs `cargo build`, copies lib<crate>.a to meson's declared output, and rewrites
cargo's dep-info into a depfile for that output so ninja rebuilds (and relinks
QEMU) exactly when a Rust source the crate depends on changes.
"""
import argparse
import os
import shutil
import subprocess
import sys


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cargo", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--crate", required=True, help="lib name (underscores)")
    ap.add_argument("--target-dir", required=True)
    ap.add_argument("--profile", default="release")
    ap.add_argument("--out", required=True)
    ap.add_argument("--depfile", required=True)
    ap.add_argument("--env", action="append", default=[], help="KEY=VALUE for build.rs")
    args = ap.parse_args()

    env = dict(os.environ)
    for kv in args.env:
        k, _, v = kv.partition("=")
        env[k] = v

    cmd = [args.cargo, "build", "--manifest-path", args.manifest,
           "--lib", "--profile", args.profile, "--target-dir", args.target_dir]
    rc = subprocess.call(cmd, env=env)
    if rc != 0:
        return rc

    profile_dir = "debug" if args.profile == "dev" else args.profile
    built = os.path.join(args.target_dir, profile_dir, f"lib{args.crate}.a")
    dep = os.path.join(args.target_dir, profile_dir, f"lib{args.crate}.d")
    if not os.path.exists(built):
        print(f"qmake_cargo_build: {built} not produced; is crate-type = [\"staticlib\"]?",
              file=sys.stderr)
        return 1
    shutil.copy2(built, args.out)

    # cargo dep-info: "<abs>/lib<crate>.a: src1 src2 ..." (spaces escaped as "\ ")
    deps = ""
    if os.path.exists(dep):
        with open(dep) as f:
            for line in f:
                head, sep, rest = line.partition(": ")
                if sep and head.endswith(f"lib{args.crate}.a"):
                    deps = rest.strip()
                    break
    with open(args.depfile, "w") as f:
        f.write(f"{args.out}: {deps}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
