# mtd0.bin Flash Write Routine Map

This note ties the HTTP upgrader’s strings in `mtd0.bin` to the control flow in the bootloader. Addresses below use the U-Boot link base (`0xBFC00000`).

## Top-Level HTTP Upgrade Driver (`0xBFC011A4`)
- Prints the progress banner `*     U-BOOT UPGRADING     *` (string at file offset `0x1A557`) via the `addiu a0,a0,-28464` sequence at `0xBFC011E4`.
- Disables/retargets the MT7628 switch before touching flash by twiddling `0xB0000034`/`0xB0000030` (see `0xBFC01290` onwards where it masks in `0x00200000`).
- Clears staging buffers and copies the uploaded image into stack work areas using the GOT slots for `memset` (`gp+0x1DC`) and `memcpy` (`gp+0x410`) across the block starting at `0xBFC0174C`.
- Dispatches to upgrade-specific handlers depending on the parsed form field (`Upgrade type: firmware|U-Boot|ART`, strings at offsets `0x1A8CC`–`0x1A8FC`).

## Multipart Parser & Staging (`0xBFC0174C`)
- Allocates ~704 bytes of stack scratch, zeros four 0x80-byte chunks, and captures both filename and payload buffers (see repeated `memset` calls at `0xBFC017A0`/`0xBFC017C0`).
- Compares the POSTed buffer with the expected boundary + filename (the tight loops at `0xBFC018E0` and `0xBFC019B0` backstop strings like `boundary=` and `Upload file size: %d bytes`).
- Counts CRC mismatches through the `gp+0x1A8` counter when bytes differ, matching the “## Error: request for upload < 10 KB data!” guard at string offset `0x1A8E0`.

## Image Sanity & Header Checks (`0xBFC01DA4` family)
- Builds two 0x40-byte working buffers (stack offset `0x18`) and calls the NOR driver through GOT slot `gp+0x490` to read SPI flash IDs (strings `flash manufacture id` / vendor tables around file offset `0x1B708`).
- Validates the uploaded image against the U-Boot header magic `0x27151967` (`0xBFC01E6C` and `0xBFC01EDC`) before allowing erase/write, printing either success (`HTTP upload is done! Upgrading…`, offset `0x1A6B8`) or failure (`## Error: HTTP ugrade failed!`, offset `0x1A700`).
- Reuses the same path twice: once for the main payload (`s2` flag) and once for an optional second chunk (`s3` flag) so both U-Boot and firmware uploads share the logic.

## Flash Erase & Copy Core (`0xBFC0232C` – `0xBFC02470`)
- Formats status messages drawn from CLI strings: `Copy uboot[%d byte] to SPI Flash[0x%08X]....` (offset `0x1B5AD`), `Erase u-boot block !!` (`0x1B62D`), and linux equivalents (`0x1B460` onwards). Each arises from consecutive `addiu a0,a0,-0x6Axx` immediates feeding the `puts`/`printf` stub at GOT `gp+0x4C0`.
- Size guard at `0xBFC02368` compares staged length (`s1 + 0x40`) against `0x007B0000`; exceeding this triggers the `Abort: image size larger than %d!` string (`0x1B43C`).
- Calls the low-level SPI driver:
  - `gp+0x34` / `gp+0x214` paths map to the `erase` routine (`erase offs 0x%x, len 0x%x`, string offset `0x1B790`) executed before flashing.
  - `gp+0x34` with `a0=1` or `a0=2` chooses between U-Boot (`cp.uboot`, CLI text at `0x1B52C`) and firmware (`cp.linux`, `0x1B4B4`).
  - Final write uses GOT slot `gp+0x4A8` with buffer size 0x80 (loop at `0xBFC01B60`) matching the `write offs 0x%x, len 0x%x` log (`0x1B7D4`).

## Observed Control Flow
1. `0xBFC011A4` (HTTP entry) → prints banner, clears buffers.
2. `0xBFC0174C` parses multipart upload, fills staging buffers, enforces Content-Length (>10 KB).
3. `0xBFC01DA4` checks headers, ID fields, and existing flash contents. Depending on type, it sets `s2/s3` and branches:
   - U-Boot → `erase uboot` (`0xBFC0238C` path) → `cp.uboot` writer (`0xBFC02398`/`0xBFC02404`).
   - Firmware → analogous linux block using strings at offsets `0x1B4B4` and `0x1B460`.
4. SPI transactions occur via registers under `0x80C0xxxx` (controller base) and `0x4400xxxx` (DMA window) as seen in the packed pixel operations at `0xBFC02084` and `0xBFC02178`.
5. On success, control returns to `0xBFC011A4` which prints `HTTP ugrade is done! Rebooting…` (`0x1A6DC`); failures fall back to `## Error: HTTP ugrade failed!` / `Update failed` page (`0x1872E`).

## Useful String Offsets (from `mtd0-http-update-strings.txt`)
- Banner / warnings: offsets `0x1A557`, `0x1A5B0`, `0x1A604`.
- Progress logs: `0x1A6A0` (`HTTP server is ready!`), `0x1A6B8`, `0x1A6DC`, `0x1A700`.
- Validation errors: `0x1A8A8` (Content-Length), `0x1A8E0` (<10 KB), `0x1A960` (wrong size), `0x1A98C` (boundary).
- SPI ops: `0x1B097` (`erase uboot`), `0x1B2D2` (`Erase linux kernel block`), `0x1B5AD` (`Copy uboot[...]`).

Cross-check the above with `mipsel-objdump` slices starting at the cited addresses; immediates in the `addiu a0,a0,-XXXX` instructions line up with the decimal offsets exported in `mtd0-http-update-strings.txt`.

## Upstream Comparison (mainline U-Boot mt7628)
- **Command surface**: mainline relies on the generic SPI flash CLI (`work-uboot/u-boot/cmd/sf.c:1`) with `spi_flash_update_block()` managing erase/program cycles, whereas our ROM exposes bespoke `cp.uboot` / `erase uboot` verbs baked into the HTTP workflow (`Router/mtd0-http-update-strings.txt:48`).
- **Controller access**: the vendor routine bangs controller registers directly via KSEG1 addresses around `0xBFC020A0`, but mainline expects transfers to be funneled through the DM SPI driver which stages DMA pointers in `mtk_spim_setup_dma_xfer()` (`work-uboot/u-boot/drivers/spi/mtk_spim.c:392`) and gates execution via `mtk_spim_exec_op()` (`work-uboot/u-boot/drivers/spi/mtk_spim.c:447`).
- **Chunk sizing**: our HTTP path writes fixed 0x80-byte bursts (loop at `0xBFC01B60`), while mainline lets the controller handle packet sizing up to 64 KB and only loops when necessary (`work-uboot/u-boot/drivers/spi/mtk_spim.c:382`).
- **Validation model**: the HTTP uploader enforces multipart framing and a minimum payload (`Router/uboot_http_update_notes.md:10`), but upstream defers to flash geometry checks in `sf_parse_len_arg()` (`work-uboot/u-boot/cmd/sf.c:46`) and offers no built-in HTTP surfacing.
- **Porting hint**: to forward-port the vendor upgrader, the hand-rolled erase/program steps we mapped at `0xBFC0232C` would need to be rewritten as `spi_mem` ops so they ride the same execution path as modern SPI drivers, mirroring the queueing that `mtk_spim_exec_op()` performs today.
