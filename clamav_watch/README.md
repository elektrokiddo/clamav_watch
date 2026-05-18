# clamav-watch
## Real-Time Virus Scanner in User Space
### Setup Guide for Fedora 43

---

## 1. Overview

clamav-watch is a real-time virus scanner running entirely in user space on Linux. It uses inotify for file system monitoring, clamd as the scan backend, and notify-send for desktop notifications. Infected files are automatically moved to a virus vault (quarantine).

| Component | Purpose |
|---|---|
| `clamd@scan` | ClamAV daemon, keeps virus database loaded in RAM |
| `freshclam` | Automatically updates the virus database |
| `clamdscan` | Scan client, communicates with clamd via Unix socket |
| `inotifywait` | Monitors directories for file changes (inotify-tools) |
| `notify-send` | Displays desktop notifications (libnotify) |
| `clamav-watch.sh` | Main script: ties all components together |
| `clamav-watch.service` | systemd user unit, starts the script at login |

---

## 2. Prerequisites

### 2.1 Install packages

```bash
sudo dnf install clamav clamd clamav-update inotify-tools libnotify jq
```

### 2.2 Prepare SELinux

On Fedora with active SELinux, two booleans need to be set:

```bash
sudo setsebool -P antivirus_can_scan_system 1
sudo setsebool -P clamd_use_jit 1
```

### 2.3 Configure clamd

In `/etc/clamd.d/scan.conf`, uncomment the following lines:

```
LocalSocket /run/clamd.scan/clamd.sock
LocalSocketGroup virusgroup
LocalSocketMode 660
```

> **Note:** The directory `/run/clamd.scan/` is created automatically by systemd at startup.

### 2.4 Add user to groups

The executing user must be a member of the `virusgroup` group to access the clamd socket:

```bash
sudo gpasswd -a [USERNAME] virusgroup
```

> **Warning:** After changing group membership, a full logout and re-login is required. Simply reopening a terminal is not sufficient.

### 2.5 Enable clamd

```bash
sudo systemctl enable --now clamd@scan
sudo systemctl status clamd@scan
```

> **Note:** clamd keeps the virus database permanently loaded in RAM (~1 GB). This is expected behavior.

---

## 3. Directory Structure

clamav-watch is installed entirely under `~/.local/clamav_watch/`:

| Path | Contents |
|---|---|
| `~/.local/clamav_watch/bin/` | Main script `clamav-watch.sh` |
| `~/.local/clamav_watch/etc/` | `config.json`, `clamav-watch.service` |
| `~/.local/clamav_watch/var/virus_vault/` | Quarantine directory for infected files |
| `~/.local/clamav_watch/log/` | Daily log files (`clamav-watch-YYYYMMDD.log`) |
| `~/.local/clamav_watch/usr/share/` | Icons for desktop notifications |

Create directories:

```bash
mkdir -p ~/.local/clamav_watch/{bin,etc,var/virus_vault,log,usr/share}
```

---

## 4. Configuration

### 4.1 config.json

All configuration lives in `~/.local/clamav_watch/etc/config.json`. All paths, scan directories, and notification settings are defined here:

```json
{
  "app": {
    "dir_app": "/home/[USERNAME]/.local/clamav_watch",
    "dir_etc": "/home/[USERNAME]/.local/clamav_watch/etc",
    "dir_var": "/home/[USERNAME]/.local/clamav_watch/var",
    "dir_usr": "/home/[USERNAME]/.local/clamav_watch/usr",
    "dir_log": "/home/[USERNAME]/.local/clamav_watch/log",
    "dir_vault": "/home/[USERNAME]/.local/clamav_watch/var/virus_vault",
    "dir_icons": "/home/[USERNAME]/.local/clamav_watch/usr/share"
  },
  "scan": {
    "dir_watch": "/home/[USERNAME]",
    "dirs_excluded": [
      "/home/[USERNAME]/.local/clamav_watch/var/virus_vault",
      "/home/[USERNAME]/.cache",
      "/home/[USERNAME]/.local/share/clamav"
    ]
  },
  "notifications": {
    "flag_show_notifications": true,
    "icon_virusalert": "virusalert.png",
    "notification_duration": 10000
  }
}
```

> **Note:** Replace `[USERNAME]` with the actual username (`echo $USER`).

### 4.2 Configuration parameters

| Parameter | Description |
|---|---|
| `scan.dir_watch` | Root directory to monitor (recursive) |
| `scan.dirs_excluded` | List of directories excluded from scanning |
| `notifications.flag_show_notifications` | `true`/`false` – enable/disable desktop notifications |
| `notifications.icon_virusalert` | Icon file for virus notification (located in `dir_icons`) |
| `notifications.notification_duration` | Notification display duration in milliseconds |

---

## 5. Installation

### 5.1 Install the script

```bash
cp clamav-watch.sh ~/.local/clamav_watch/bin/
chmod +x ~/.local/clamav_watch/bin/clamav-watch.sh
```

### 5.2 Install the icon

Copy a PNG file for the virus notification to `usr/share/`:

```bash
cp virusalert.png ~/.local/clamav_watch/usr/share/
```

### 5.3 Install the systemd user unit

File: `~/.local/clamav_watch/etc/clamav-watch.service`

```ini
[Unit]
Description=ClamAV Real-Time Monitoring (inotify)
Documentation=file:/home/[USERNAME]/.local/clamav_watch/etc/config.json
After=default.target

[Service]
Type=simple
ExecStart=/bin/bash /home/[USERNAME]/.local/clamav_watch/bin/clamav-watch.sh
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
```

Activate the unit:

```bash
mkdir -p ~/.config/systemd/user
cp ~/.local/clamav_watch/etc/clamav-watch.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now clamav-watch.service
```

---

## 6. Operation

### 6.1 Managing the service

| Action | Command |
|---|---|
| Check status | `systemctl --user status clamav-watch.service` |
| Start | `systemctl --user start clamav-watch.service` |
| Stop | `systemctl --user stop clamav-watch.service` |
| Restart | `systemctl --user restart clamav-watch.service` |
| Disable autostart | `systemctl --user disable clamav-watch.service` |

### 6.2 Logs

```bash
# Follow today's log live
tail -f ~/.local/clamav_watch/log/clamav-watch-$(date +%Y%m%d).log

# Show virus detections only
grep '\[WARN\]' ~/.local/clamav_watch/log/clamav-watch-*.log

# systemd journal
journalctl --user -u clamav-watch.service -f
```

### 6.3 Quarantine

Infected files are moved to the virus vault with a prepended timestamp:

```bash
ls ~/.local/clamav_watch/var/virus_vault/
# Example: 2026-05-18_12-45-04_infected_file.exe
```

> **Warning:** Files in the virus vault are inactive but not deleted. Check regularly and remove manually as needed.

---

## 7. Functional Test with EICAR Test File

The EICAR test file is a harmless, standardized string recognized by all common virus scanners. It contains no executable code.

### 7.1 Create the test file

```bash
echo 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > ~/testfile_eicar
```

### 7.2 Expected result

The log should show the following sequence:

```
[INFO] Scanning: /home/[USERNAME]/testfile_eicar
[WARN] VIRUS FOUND: /home/[USERNAME]/testfile_eicar
[INFO] Moving to: [...]/virus_vault/2026-..._testfile_eicar
[INFO] File successfully moved to quarantine
```

A desktop notification with the virus alert icon will also appear.

---

## 8. Troubleshooting

| Error | Solution |
|---|---|
| `Permission denied` on `clamd.sock` | Add user to `virusgroup`, log out and back in |
| clamd does not start | Uncomment `LocalSocket` in `/etc/clamd.d/scan.conf` |
| `no reply from clamd` | Check `clamd@scan.service`: `systemctl status clamd@scan` |
| No desktop notification | Check `DISPLAY` variable, is `libnotify` installed? |
| `inotify: too many watches` | `echo fs.inotify.max_user_watches=524288 \| sudo tee /etc/sysctl.d/99-inotify.conf` |
