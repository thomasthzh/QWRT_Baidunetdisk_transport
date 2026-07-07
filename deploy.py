#!/usr/bin/env python3
"""Deploy optimized Alist LuCI files to the router via OpenSSH/SCP.

Run with the router password in the environment:
    ROUTER_PASS='your-password' python deploy.py
"""
import os
import sys
import datetime
import stat
import shutil
import subprocess
import tempfile

HOST = os.environ.get("ROUTER_HOST", "192.168.1.1")
USER = os.environ.get("ROUTER_USER", "root")
PASS = os.environ.get("ROUTER_PASS", "")
LOCAL_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "files")

FILES = [
    ("usr/lib/lua/luci/alistapi.lua", "/usr/lib/lua/luci/alistapi.lua"),
    ("usr/lib/lua/luci/controller/alist.lua", "/usr/lib/lua/luci/controller/alist.lua"),
    ("usr/lib/lua/luci/model/cbi/alist.lua", "/usr/lib/lua/luci/model/cbi/alist.lua"),
    ("usr/lib/lua/luci/view/alist_admin.htm", "/usr/lib/lua/luci/view/alist_admin.htm"),
    ("usr/lib/lua/luci/view/alist_shares.htm", "/usr/lib/lua/luci/view/alist_shares.htm"),
    ("etc/init.d/alist", "/etc/init.d/alist"),
    ("mnt/usbdata/alist/tc_apply.sh", "/mnt/usbdata/alist/tc_apply.sh"),
    # memory / swap management
    ("etc/sysctl.d/99-memory.conf", "/etc/sysctl.d/99-memory.conf"),
    ("etc/init.d/usb_swap", "/etc/init.d/usb_swap"),
    ("etc/init.d/usb_swap_run", "/etc/init.d/usb_swap_run"),
    ("etc/init.d/cgroup_mem_limits", "/etc/init.d/cgroup_mem_limits"),
    ("usr/bin/cgroup-mem-limit.sh", "/usr/bin/cgroup-mem-limit.sh"),
    ("usr/bin/router-optimize.sh", "/usr/bin/router-optimize.sh"),
    ("usr/bin/router-optimize-revert.sh", "/usr/bin/router-optimize-revert.sh"),
    ("etc/netdata/netdata.conf", "/etc/netdata/netdata.conf"),
]

SSH_OPTS = [
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-o", "HostKeyAlgorithms=+ssh-rsa",
    "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa",
    "-o", "BatchMode=no",
]


def make_askpass(password):
    fd, path = tempfile.mkstemp(prefix="askpass_", suffix=".sh")
    os.write(fd, (f'#!/bin/sh\necho "{password}"\n').encode())
    os.close(fd)
    os.chmod(path, stat.S_IRUSR | stat.S_IXUSR)
    return path


def ssh_env(askpass_path):
    env = os.environ.copy()
    env["DISPLAY"] = ":0"
    env["SSH_ASKPASS"] = askpass_path
    return env


def run_ssh(askpass_path, cmd, desc=""):
    print(f"[ssh] {desc or cmd}")
    argv = ["ssh"] + SSH_OPTS + [f"{USER}@{HOST}", cmd]
    p = subprocess.run(
        argv,
        env=ssh_env(askpass_path),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    out = p.stdout.decode("utf-8", "replace").strip()
    err = p.stderr.decode("utf-8", "replace").strip()
    if out:
        print(out)
    if err:
        # OpenSSH prints warnings to stderr; keep only the last few lines
        for line in err.splitlines()[-3:]:
            if "WARNING" not in line and "Permanently" not in line:
                print(f"[stderr] {line}")
    if p.returncode != 0:
        print(f"[warn] ssh exit {p.returncode}")
    return p.returncode, out, err


def run_scp(askpass_path, local, remote):
    print(f"[scp] {local} -> {remote}")
    argv = ["scp", "-O"] + SSH_OPTS + [local, f"{USER}@{HOST}:{remote}"]
    p = subprocess.run(
        argv,
        env=ssh_env(askpass_path),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    out = p.stdout.decode("utf-8", "replace").strip()
    err = p.stderr.decode("utf-8", "replace").strip()
    if out:
        print(out)
    if err:
        for line in err.splitlines()[-3:]:
            if "WARNING" not in line and "Permanently" not in line:
                print(f"[stderr] {line}")
    if p.returncode != 0:
        print(f"[warn] scp exit {p.returncode}")
    return p.returncode


def main():
    if not PASS:
        print("Set ROUTER_PASS environment variable.")
        sys.exit(1)
    if not shutil.which("ssh") or not shutil.which("scp"):
        print("OpenSSH (ssh/scp) is required.")
        sys.exit(1)

    askpass = make_askpass(PASS)
    try:
        print(f"Deploying to {USER}@{HOST} ...")

        ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        backup_dir = f"/tmp/alist_backup_{ts}"
        run_ssh(askpass, f"mkdir -p {backup_dir}", "create backup dir")

        for rel, remote in FILES:
            local = os.path.join(LOCAL_ROOT, rel.replace("/", os.sep))
            if not os.path.isfile(local):
                print(f"[skip] not found: {local}")
                continue
            run_ssh(askpass, f"[ -f {remote} ] && cp {remote} {backup_dir}/ || true", f"backup {remote}")
            run_scp(askpass, local, remote)

        run_ssh(askpass,
                "chmod +x /etc/init.d/alist /etc/init.d/usb_swap /etc/init.d/usb_swap_run "
                "/etc/init.d/cgroup_mem_limits /usr/bin/cgroup-mem-limit.sh "
                "/usr/bin/router-optimize.sh /usr/bin/router-optimize-revert.sh "
                "/mnt/usbdata/alist/tc_apply.sh",
                "set permissions")
        run_ssh(askpass, "rm -f /tmp/luci-indexcache /tmp/luci-modulecache/*", "clear LuCI cache")
        run_ssh(askpass, "/etc/init.d/usb_swap enable && /etc/init.d/cgroup_mem_limits enable", "enable services")
        run_ssh(askpass, "/etc/init.d/alist restart", "restart alist")
        run_ssh(askpass, "sleep 2 && pidof alist && echo 'alist is running' || echo 'alist NOT running'", "check alist process")
        run_ssh(askpass, "sysctl -p /etc/sysctl.d/99-memory.conf", "apply sysctl")
        run_ssh(askpass, f"echo 'Backed up to {backup_dir}'", "backup summary")

        print("\nDeploy complete.")
    finally:
        try:
            os.remove(askpass)
        except OSError:
            pass


if __name__ == "__main__":
    main()
