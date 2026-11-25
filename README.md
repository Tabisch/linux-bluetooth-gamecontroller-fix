# linux-bluetooth-gamecontroller-fix

A small kernel patch, packaged with DKMS for Fedora, for Bluetooth game
controllers that pair fine but disconnect again right after connecting.

## The problem

Some controllers (this was found with one that shows up as
"Wireless Controller") open their HID connection a few milliseconds
**before** the link is encrypted. The Linux kernel answers that request with
*"Refused – security block"*. The controller does not retry, and it drops the
connection shortly after.

You can check whether you have this problem by running `sudo btmon` while the
controller connects, and looking for:

```
L2CAP: Connection Request  ... PSM: 17 (HID Control)
L2CAP: Connection Response ... Result: Connection refused - security block
HCI Event: Encryption Change ... Encryption: Enabled
```

The details are in [docs/capture-analysis.md](docs/capture-analysis.md).

## The fix

[`patches/0001-…patch`](patches/) changes `net/bluetooth/l2cap_core.c` so that
such a request is answered with *"pending"* and accepted as soon as encryption
is on, instead of being refused. Security is not lowered. The channel is only
accepted once the link is encrypted and passes the same checks as before.

Only `bluetooth.ko` is rebuilt. Everything else stays the stock Fedora kernel.

## Install (Fedora)

```bash
git clone https://github.com/Tabisch/linux-bluetooth-gamecontroller-fix.git
cd linux-bluetooth-gamecontroller-fix
sudo ./install.sh --reload
```

`install.sh`:

1. installs `dkms`, `kernel-devel` for the running kernel, `git`, `patch`, etc. with `dnf`,
2. downloads the Bluetooth source of the matching upstream kernel
   (e.g. `v7.2.10` for `7.2.10-200.fc44`), once per kernel version, from
   git.kernel.org (with GitHub and cdn.kernel.org as fallbacks),
3. applies the patch, builds `bluetooth.ko`, and checks that its exported symbol
   CRCs match the stock module (so `btusb`, `hidp`, … keep working),
4. installs it with DKMS, so it is **rebuilt automatically for every new
   kernel** that `dnf` installs,
5. with `--reload`, swaps the module in without a reboot. Without it, just reboot.

Check the state any time:

```bash
./install.sh --status
```

### Secure Boot

With Secure Boot on, DKMS signs the module with its own key. On the first
install, `install.sh` runs `mokutil --import` and asks you for a one-time
password. Reboot, choose **Enroll MOK → Continue → Yes** on the blue screen,
and enter that password. This is needed only once.

### Uninstall

```bash
sudo ./uninstall.sh   # then reboot
```

## Notes

- The source comes from the upstream stable tag that matches your kernel
  version. Fedora normally carries no Bluetooth patches, and the build refuses to
  install if the exported symbols don't match the running kernel.
- A new kernel needs network access once while `dnf` installs it, to download
  its source. If that fails, the stock module is used until you run
  `sudo dkms autoinstall`.
- To build from a local kernel tree instead of downloading, set
  `BT_FIX_KERNEL_SRC=/path/to/linux`.
