# linux-bluetooth-gamecontroller-fix

> [!WARNING]
> This patch was made with the help of AI. I am not an expert in C, Bluetooth
> or Linux kernel development. It works for my controller, but it has not been
> reviewed by kernel developers, and it replaces the Bluetooth module in your
> kernel. Use it at your own risk.
>
> If you'd rather not install a modified kernel module, see
> [Alternative without the patch](#alternative-without-the-patch-turn-off-secure-simple-pairing)
> at the bottom of this page.

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

## Alternative without the patch: turn off Secure Simple Pairing

If you'd rather not install a kernel module, you can work around the problem by
switching off Secure Simple Pairing (SSP) on the adapter:

```bash
sudo btmgmt power off
sudo btmgmt ssp off
sudo btmgmt power on
```

The kernel only refuses an early connection on SSP links. With SSP off, the
link uses legacy pairing and the controller's early request is accepted.

Trade-offs:

- **Weaker security for every Bluetooth device on this adapter**, not just
  the controller. Legacy (PIN) pairing is much easier to attack than SSP, and
  Secure Connections is turned off too, because it depends on SSP.
- Devices that require SSP (many headsets, phones, newer keyboards) may fail to
  pair, or need to be paired again.
- You may have to remove and pair the controller again, because its existing
  link key was created with SSP.
- **It does not persist.** The setting resets after a reboot, a suspend/resume
  that resets the adapter, or a restart of `bluetooth.service`, so you have to
  run the commands again each time.

The patch keeps SSP on and only waits for encryption before accepting the
connection, so it is the better long-term fix.

## Notes

- The source comes from the upstream stable tag that matches your kernel
  version. Fedora normally carries no Bluetooth patches, and the build refuses to
  install if the exported symbols don't match the running kernel.
- A new kernel needs network access once while `dnf` installs it, to download
  its source. If that fails, the stock module is used until you run
  `sudo dkms autoinstall`.
- To build from a local kernel tree instead of downloading, set
  `BT_FIX_KERNEL_SRC=/path/to/linux`.
