# Capture analysis: "Wireless Controller" fails to connect

Source: HCI capture of `bluetooth0` (pcapng, 551 frames) taken on Fedora with
kernel 7.2.10-200.fc44. Frames 1–201 are unrelated LE notifications from
another device and are ignored here. Times are seconds from the start of the
capture.

## What happens

| Frame | Time  | Direction | Event |
|------:|------:|-----------|-------|
| 202 | 5.980 | ctrl → host | HCI Connect Request (CoD 0x002508, gamepad) |
| 226 | 6.201 | ctrl → host | Connect Complete, handle 0x004a, **encryption disabled** |
| 244 | 6.262 | host → dev  | L2CAP Information Request (feature mask) |
| 252 | 6.301 | ctrl → host | **Link Key Request** (the controller starts authentication) |
| 253 | 6.301 | host → ctrl | Link Key Request Reply (stored key) |
| 256 | 6.311 | dev → host  | Information Response (not supported) |
| 258 | 6.329 | dev → host  | **L2CAP Connection Request, PSM 0x11 HID Control** |
| 259 | 6.329 | host → dev  | **Connection Response: Refused – security block** |
| 264 | 6.376 | ctrl → host | **Encryption Change: ON** (47 ms too late) |
| 267 | 6.378 | ctrl → host | Encryption key size 16 |
| 443 | 8.397 | host → dev  | bluetoothd opens HID Control itself → success |
| 452 | 8.476 | host → dev  | bluetoothd opens HID Interrupt (0x0041) |
| 453 | 8.479 | dev → host  | controller opens HID Interrupt too (0x0052), crossing the host's request |
| 455 | 8.479 | host → dev  | accepted as local CID 0x0042 |
| 468 | 8.517 | host → dev  | bluetoothd closes the controller's interrupt channel (it already has one) |
| 472–482 | 8.53–8.61 | dev → host | HID input reports `a1 01 80 80 80 80 08 …` arrive **only on 0x0042**, the channel that was just closed |
| 483 | 8.751 | ctrl → host | Disconnect Complete, reason 0x13 (remote user terminated) |

## Conclusion

The earlier analysis is right. The controller sends its HID Control
connection request 47 ms before encryption is on. The kernel refuses it with
"security block" in `l2cap_connect()` (`net/bluetooth/l2cap_core.c`):

```c
/* Check if the ACL is secure enough (if not SDP) */
if (psm != cpu_to_le16(L2CAP_PSM_SDP) &&
    (!hci_conn_check_link_mode(conn->hcon) || ...)) {
        result = L2CAP_CR_SEC_BLOCK;
```

`hci_conn_check_link_mode()` returns 0 for any SSP link without
`HCI_CONN_ENCRYPT`, so the request is refused outright instead of being held
until encryption finishes. This is in the kernel, not in BlueZ, so no
`input.conf` or `main.conf` setting (such as `ClassicBondedOnly`) changes it.

The controller never retries. bluetoothd then connects HID itself, but that
races with the controller's own HID Interrupt request. bluetoothd keeps its own
channel and closes the controller's, while the controller keeps sending input
on the closed one and drops the link about 230 ms later. That second failure is
a consequence of the first: once the controller's own HID Control request is
accepted, it opens HID Interrupt normally and bluetoothd has no reason to
connect on its own.

## The fix

`patches/0001-…patch` makes `l2cap_connect()` answer **"pending –
authentication pending"** instead of "security block" when the link is SSP and
simply not encrypted *yet*. That is the same path the kernel already uses for
channels that need a higher security level. The request is answered with
"success" from `l2cap_security_cfm()` once the Encryption Change event arrives.
The full link check (`hci_conn_check_link_mode()` plus the key size check) runs
again at that point, so a channel is never accepted on an unencrypted link, and
links that end up not meeting the requirements (Secure Connections Only, FIPS,
key size) are still refused.

Expected trace with the fix:

```
> L2CAP Connection Request  PSM 0x11
< L2CAP Connection Response Pending (authentication pending)
> HCI Encryption Change     ON
< L2CAP Connection Response Success
```
