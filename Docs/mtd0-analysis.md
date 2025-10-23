# MT7628 Ralink U‑Boot (mtd0.bin) — HTTP Update Findings

Summary: Vendor U‑Boot (1.1.3) embeds a tiny HTTP server ("JBC_Router/0.9") that serves update pages for U‑Boot, firmware, and ART. Uploads use multipart/form‑data with Content‑Length; files < 10 KB are rejected. After upload, it erases SPI NOR and reboots on success.

Useful bits:
- Forms: name="uboot" (U‑Boot), name="firmware", name="art"
- Pages: index.html, style.css, progress, 404
- Status: "HTTP server is starting for update…", "HTTP server is ready!", "HTTP upload is done! Upgrading…"
- Errors: missing Content‑Length, too‑small uploads, generic upgrade failure
- Env defaults present: bootcmd=tftp, baudrate=57600, ipaddr=192.168.188.1, serverip=192.168.188.103

See extracted strings (with hex offsets):
- mtd0-http-strings.txt
- mtd0-env-strings.txt
- mtd0-error-strings.txt
- mtd0-strings.txt (full dump)

Caveats:
- The HTTP U‑Boot updater likely expects a vendor‑formatted NOR image; do not upload RAM‑boot images.
- Prefer RAM boot via TFTP (`tftpboot 0x80200000 u-boot-raw.bin; go 0x80200000`) when testing.
