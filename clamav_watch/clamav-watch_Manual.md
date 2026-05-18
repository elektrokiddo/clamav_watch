# clamav-watch
## Echtzeit-Virenscanner im Userspace
### Einrichtungshandbuch für Fedora 43

---

## 1. Übersicht

clamav-watch ist ein im Userspace laufender Echtzeit-Virenscanner für Linux. Er nutzt inotify zur Dateiüberwachung, clamd als Scan-Backend und notify-send für Desktop-Benachrichtigungen. Infizierte Dateien werden automatisch in einen Virus-Vault (Quarantäne) verschoben.

| Komponente | Aufgabe |
|---|---|
| `clamd@scan` | ClamAV-Daemon, hält Virendatenbank im RAM |
| `freshclam` | Aktualisiert die Virendatenbank automatisch |
| `clamdscan` | Scan-Client, kommuniziert mit clamd über Unix-Socket |
| `inotifywait` | Überwacht Verzeichnisse auf Dateiänderungen (inotify-tools) |
| `notify-send` | Zeigt Desktop-Benachrichtigungen (libnotify) |
| `clamav-watch.sh` | Hauptskript: verbindet alle Komponenten |
| `clamav-watch.service` | systemd User-Unit, startet das Skript beim Login |

---

## 2. Voraussetzungen

### 2.1 Pakete installieren

```bash
sudo dnf install clamav clamd clamav-update inotify-tools libnotify jq
```

### 2.2 SELinux vorbereiten

Auf Fedora mit aktivem SELinux müssen zwei Booleans gesetzt werden:

```bash
sudo setsebool -P antivirus_can_scan_system 1
sudo setsebool -P clamd_use_jit 1
```

### 2.3 clamd konfigurieren

In `/etc/clamd.d/scan.conf` folgende Zeilen einkommentieren:

```
LocalSocket /run/clamd.scan/clamd.sock
LocalSocketGroup virusgroup
LocalSocketMode 660
```

> **Hinweis:** Das Verzeichnis `/run/clamd.scan/` wird von systemd beim Start automatisch angelegt.

### 2.4 Benutzer zu Gruppen hinzufügen

Der ausführende Benutzer muss Mitglied der Gruppe `virusgroup` sein, um auf den clamd-Socket zugreifen zu können:

```bash
sudo gpasswd -a [USERNAME] virusgroup
```

> **Achtung:** Nach der Gruppenänderung ist eine vollständige Abmeldung und erneute Anmeldung erforderlich. Ein einfaches Neuöffnen des Terminals reicht nicht aus.

### 2.5 clamd aktivieren

```bash
sudo systemctl enable --now clamd@scan
sudo systemctl status clamd@scan
```

> **Hinweis:** clamd hält die Virendatenbank dauerhaft im RAM (~1 GB). Dies ist erwartetes Verhalten.

---

## 3. Verzeichnisstruktur

clamav-watch wird vollständig unter `~/.local/clamav_watch/` installiert:

| Pfad | Inhalt |
|---|---|
| `~/.local/clamav_watch/bin/` | Hauptskript `clamav-watch.sh` |
| `~/.local/clamav_watch/etc/` | `config.json`, `clamav-watch.service` |
| `~/.local/clamav_watch/var/virus_vault/` | Quarantäne-Verzeichnis für infizierte Dateien |
| `~/.local/clamav_watch/log/` | Tagesweise Logdateien (`clamav-watch-YYYYMMDD.log`) |
| `~/.local/clamav_watch/usr/share/` | Icons für Desktop-Benachrichtigungen |

Verzeichnisse anlegen:

```bash
mkdir -p ~/.local/clamav_watch/{bin,etc,var/virus_vault,log,usr/share}
```

---

## 4. Konfiguration

### 4.1 config.json

Die gesamte Konfiguration liegt in `~/.local/clamav_watch/etc/config.json`. Alle Pfade, Scan-Verzeichnisse und Benachrichtigungseinstellungen werden hier definiert:

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

> **Hinweis:** `[USERNAME]` durch den tatsächlichen Benutzernamen ersetzen (`echo $USER`).

### 4.2 Konfigurationsparameter

| Parameter | Beschreibung |
|---|---|
| `scan.dir_watch` | Wurzelverzeichnis das überwacht wird (rekursiv) |
| `scan.dirs_excluded` | Liste von Verzeichnissen die nicht gescannt werden |
| `notifications.flag_show_notifications` | `true`/`false` – Desktop-Benachrichtigungen ein/aus |
| `notifications.icon_virusalert` | Icon-Datei für Virus-Benachrichtigung (in `dir_icons`) |
| `notifications.notification_duration` | Anzeigedauer der Benachrichtigung in Millisekunden |

---

## 5. Installation

### 5.1 Skript installieren

```bash
cp clamav-watch.sh ~/.local/clamav_watch/bin/
chmod +x ~/.local/clamav_watch/bin/clamav-watch.sh
```

### 5.2 Icon installieren

Eine PNG-Datei für die Virus-Benachrichtigung nach `usr/share/` kopieren:

```bash
cp virusalert.png ~/.local/clamav_watch/usr/share/
```

### 5.3 systemd User-Unit installieren

Datei: `~/.local/clamav_watch/etc/clamav-watch.service`

```ini
[Unit]
Description=ClamAV Echtzeit-Ueberwachung (inotify)
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

Unit aktivieren:

```bash
mkdir -p ~/.config/systemd/user
cp ~/.local/clamav_watch/etc/clamav-watch.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now clamav-watch.service
```

---

## 6. Betrieb

### 6.1 Dienst verwalten

| Aktion | Befehl |
|---|---|
| Status prüfen | `systemctl --user status clamav-watch.service` |
| Starten | `systemctl --user start clamav-watch.service` |
| Stoppen | `systemctl --user stop clamav-watch.service` |
| Neu starten | `systemctl --user restart clamav-watch.service` |
| Autostart deaktivieren | `systemctl --user disable clamav-watch.service` |

### 6.2 Logs

```bash
# Heutiges Log live verfolgen
tail -f ~/.local/clamav_watch/log/clamav-watch-$(date +%Y%m%d).log

# Nur Virusfunde anzeigen
grep '\[WARN\]' ~/.local/clamav_watch/log/clamav-watch-*.log

# systemd Journal
journalctl --user -u clamav-watch.service -f
```

### 6.3 Quarantäne

Infizierte Dateien werden mit vorangestelltem Zeitstempel in den Virus-Vault verschoben:

```bash
ls ~/.local/clamav_watch/var/virus_vault/
# Beispiel: 2026-05-18_12-45-04_infizierte_datei.exe
```

> **Achtung:** Dateien im Virus-Vault sind inaktiv aber nicht gelöscht. Regelmäßig prüfen und bei Bedarf manuell entfernen.

---

## 7. Funktionstest mit EICAR-Testdatei

Die EICAR-Testdatei ist ein harmloser, standardisierter String der von allen gängigen Virenscannern erkannt wird. Er enthält keinen ausführbaren Code.

### 7.1 Testdatei erstellen

```bash
echo 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*' > ~/testfile_eicar
```

### 7.2 Erwartetes Ergebnis

Im Log sollte folgende Sequenz erscheinen:

```
[INFO] Scanne: /home/[USERNAME]/testfile_eicar
[WARN] VIRUS GEFUNDEN: /home/[USERNAME]/testfile_eicar
[INFO] Verschiebe nach: [...]/virus_vault/2026-..._testfile_eicar
[INFO] Datei erfolgreich in Quarantäne verschoben
```

Zusätzlich erscheint eine Desktop-Benachrichtigung mit dem Virus-Alert-Icon.

---

## 8. Fehlerbehebung

| Fehler | Lösung |
|---|---|
| `Permission denied` auf `clamd.sock` | Benutzer zur Gruppe `virusgroup` hinzufügen, neu anmelden |
| clamd startet nicht | `LocalSocket` in `/etc/clamd.d/scan.conf` einkommentieren |
| `no reply from clamd` | `clamd@scan.service` prüfen: `systemctl status clamd@scan` |
| Benachrichtigung erscheint nicht | `DISPLAY`-Variable prüfen, `libnotify` installiert? |
| `inotify: too many watches` | `echo fs.inotify.max_user_watches=524288 \| sudo tee /etc/sysctl.d/99-inotify.conf` |
