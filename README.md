# LincStation N1 – Linux LED & RGB Control Center

**Unofficial community project. Not affiliated with LincPlus.**

**Language / Sprache:** **English** | [Deutsch](docs/de/README.de.md)

When running an operating system other than the supplied Unraid installation, the **LincStation N1** may show blinking status LEDs. On the unit investigated for this project, drive and network LEDs were controlled through software communicating with an I²C controller, rather than automatically by BIOS. Behavior may vary by firmware and OS.

This project controls **seven drive/network LEDs and the RGB strip** under Linux. Developed and tested with **OpenMediaVault on Debian**. Ubuntu and other distributions have not been tested; the installer supports Debian/Ubuntu systems with `apt` only.

## Features

- Status LEDs: **white** = detected/OK; **red** = fault; **off** = absent; **unknown** = no state change.
- SMART monitoring for **two explicitly mapped NVMe drives**, at PCI paths `0000:05:00.0` and `0000:04:00.0` (verify on your device).
- Other NVMe/SATA bays are **not guessed**: without a verified mapping, their status stays `UNKNOWN`.
- Network carrier detection at PCI path `0000:01:00.0`.
- RGB effects: off, solid, breathing, two-color chasing; brightness and persistent settings.
- SMART warning: yellow breathing; critical NVMe condition: red breathing. Unreadable SMART data is treated as a warning.
- Web UI on port **8088**; optional password protection and password changes through the UI.
- systemd timer approximately every **30 seconds**; `/run/lincstation-led/` caches previous state to avoid redundant I²C writes.

## Read before installing — hardware safety

**I²C access is hardware-specific. Incorrect bus, address or register writes may disrupt or damage hardware. This is not a universal plug-and-play utility.** Use it only on an identified LincStation N1 with a verified controller mapping.

Read [hardware verification](docs/HARDWARE-VERIFICATION.md), [bus safety](docs/I2C-SAFETY-AND-BUS.md), [register map](docs/I2C-REGISTERS.md), and [Python/web architecture](docs/PYTHON-WEB-AND-ARCHITECTURE.md).

The tested machine used **I²C bus 0**, device address **`0x26`**. Addresses `0x08` and `0x44` were also visible. The presence of `0x26` alone does **not** identify an LED controller.

## Installation — new systems

1. Download this repository as a ZIP and extract it, or clone it using Git.
2. Open a terminal in the repository directory and run:

   ```bash
   sudo bash install.sh
   ```

   The script runs `apt-get update` and installs `i2c-tools`, `smartmontools`, `jq`, `python3`, `python3-flask`, `python3-werkzeug`, `util-linux` and `pciutils`. It installs `/opt/lincstation-led-web/`, `/usr/local/sbin/lincstation-led-control.sh`, systemd units, and a restricted web account. **Only the web UI is enabled initially; no I²C writes are performed.**

3. Open `http://Lincstation:8088` (or use the device IP address). Initial credentials are stored in `/root/lincstation-led-web-password.txt` (root-only). Change the password in the UI.
4. **Only after independently verifying the I²C bus and controller**, run:

   ```bash
   sudo bash enable-leds.sh
   ```

   This script lists adapters with `i2cdetect -l`, asks for the verified bus number, checks the sysfs/PCI host controller (`0000:00:15.0`, ID `8086:4de8`), and requires explicit confirmation. It saves the approved bus and adapter information to `/etc/lincstation-led.conf` before enabling the LED timer.

5. Check status:

   ```bash
   systemctl status lincstation-led-web.service
   systemctl status lincstation-led-control.timer
   journalctl -u lincstation-led-control.service -n 50 --no-pager
   ```

**Existing installations:** `install.sh` intentionally aborts when it detects an existing web or controller installation. There is no automatic migration or overwrite. Back up and migrate configuration deliberately.

## Persistent and temporary data

| Location | Contents |
|---|---|
| `/opt/lincstation-led-web/data/rgb.json` | Persistent RGB mode, colors, brightness |
| `/opt/lincstation-led-web/data/security.json` | Persistent authentication setting and password hash, not plaintext |
| `/etc/lincstation-led.conf` | Approved I²C bus and adapter information |
| `/run/lincstation-led/` | Temporary LED/RGB comparison cache, cleared on reboot |

The LED hardware may retain its previous state. After reboot, the first successful timer run reapplies the saved settings.

## Limitations and portability

- **Debian/OMV:** developed and tested; version differences may matter.
- **Ubuntu:** tools are generally available, but an Ubuntu N1 has not been tested.
- **Other Linux distributions:** manual installation; controller needs Bash, `smartctl`, `jq`, `i2c-tools`, `lsblk`, `flock` and systemd.
- **NVMe slot mapping:** only two PCI paths are explicitly implemented. Verify and adjust other layouts.
- **SATA LEDs:** no automatic SATA slot mapping unless hardware association is verified.
- **Web security:** Flask development server intended for a trusted LAN, **not direct internet exposure**. Without password protection, reachable clients can modify RGB settings. Restrict network access using a firewall.
- **I²C safety:** PCI path and PCI ID help identify the host adapter but do **not** prove the identity of the slave at `0x26`.

## Uninstall

```bash
sudo bash uninstall.sh
```

Stops and disables the services installed by this project and removes their unit files. Personal settings and application files are deliberately retained.

## Repository structure

```text
controller/lincstation-led-control.sh
web/app.py
web/templates/index.html
systemd/lincstation-led-control.service
systemd/lincstation-led-control.timer
systemd/lincstation-led-web.service
docs/HARDWARE-VERIFICATION.md
docs/I2C-REGISTERS.md
docs/I2C-SAFETY-AND-BUS.md
docs/PYTHON-WEB-AND-ARCHITECTURE.md
docs/SOURCE-CODE-REFERENCE.md
docs/de/README.de.md
docs/de/I2C-REGISTER.md\ndocs/de/SICHERHEIT-UND-BUS.md\ndocs/de/HARDWARE-VERIFIKATION.md\ndocs/de/PYTHON-WEB-UND-ARCHITEKTUR.md\ndocs/de/VOLLSTAENDIGER-QUELLCODE.md
install.sh
enable-leds.sh
uninstall.sh
LICENSE
```

## Technical identification of the I²C host

The investigated N1 used Intel PCI host controller `0000:00:15.0` (`8086:4de8`, `intel-lpss`) and sysfs path `/sys/devices/pci0000:00/0000:00:15.0/i2c_designware.0/i2c-0/i2c-dev/i2c-0`. This explains why Linux exposed the adapter as `i2c-0` on that machine. Mapping address `0x26` to LED functions also relied on vendor software and practical tests; see [hardware verification](docs/HARDWARE-VERIFICATION.md).

## Python, HTML and automatic installation

The complete Python application is in [`web/app.py`](web/app.py), and the HTML/CSS/JavaScript interface is in [`web/templates/index.html`](web/templates/index.html). The installer `install.sh` copies both into `/opt/lincstation-led-web/`. Python dependencies are installed through `apt`; no separate `pip` installation is needed. For details, see [Python/web architecture](docs/PYTHON-WEB-AND-ARCHITECTURE.md).

## Complete source code

The executable source files are available directly in the repository: [`web/app.py`](web/app.py), [`web/templates/index.html`](web/templates/index.html), [`controller/lincstation-led-control.sh`](controller/lincstation-led-control.sh), and the root-level installation and management scripts.

For an English overview with direct links to the source files, see the [source code reference](docs/SOURCE-CODE-REFERENCE.md). The [complete annotated source code catalog](docs/de/VOLLSTAENDIGER-QUELLCODE.md) reproduces the source files in full, but its commentary is currently in German. This catalog is documentation; edit the actual source files, not the reproduced listings.

## Related project

[LincStation S1 LCD & LED Control](https://github.com/AndiBcool/lincstation-s1-lcd-led-control) — a separate project for the **S1**. Do not interchange S1 and N1 programs or hardware instructions.

## License

This repository includes a `LICENSE` file containing **GNU GPL version 3**. See that file for the license text. The original German README contained an outdated statement that no license had been chosen; this should be reconciled by the repository owner before release.

## Documentation in German

The original German guide is preserved at [docs/de/README.de.md](docs/de/README.de.md); original German technical documents are in [docs/de/](docs/de/).
