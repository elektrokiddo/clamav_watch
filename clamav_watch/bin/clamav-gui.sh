#!/bin/bash
######
###### clamav-gui.sh
###### YAD-basierte GUI für clamav-watch
######

######
###### DEF
######
DIR_APP="$HOME/.local/clamav_watch"
CONFIG_FILE="${DIR_APP}/etc/config.json"
SERVICE="clamav-watch.service"

######
###### FUNC
######

# FUNC: check_deps
# Prüft ob alle benötigten Tools vorhanden sind
check_deps() {
  for CMD in yad jq systemctl notify-send; do
    if ! command -v "$CMD" &>/dev/null; then
      yad --error \
        --title="clamav-watch GUI" \
        --text="Abhängigkeit fehlt: <b>${CMD}</b>\nBitte installieren und erneut starten." \
        --button="OK:0"
      exit 1
    fi
  done
}

# FUNC: config_read
# Liest einen Wert aus der config.json
# Input: jq-Pfad z.B. '.scan.dir_watch'
config_read() {
  jq -r "$1" "$CONFIG_FILE" 2>/dev/null
}

# FUNC: config_write
# Schreibt die gesamte config.json neu
# Input: komplettes JSON als String
config_write() {
  echo "$1" > "$CONFIG_FILE"
}

# FUNC: service_status
# Gibt den aktuellen Dienststatus zurück
service_status() {
  if systemctl --user is-active --quiet "$SERVICE"; then
    echo "running"
  else
    echo "stopped"
  fi
}

# FUNC: service_status_label
# Gibt ein formatiertes Status-Label zurück
service_status_label() {
  if [ "$(service_status)" = "running" ]; then
    echo "● Dienst läuft"
  else
    echo "○ Dienst gestoppt"
  fi
}

# FUNC: tab_config
# Tab 1: Konfigurationseditor
tab_config() {
  # Aktuelle Werte lesen
  local DIR_WATCH
  local DIRS_EXCL
  local FLAG_NOTIF
  local ICON_ALERT
  local NOTIF_DUR

  DIR_WATCH=$(config_read '.scan.dir_watch')
  mapfile -t EXCL_ARRAY < <(config_read '.scan.dirs_excluded[]')
  FLAG_NOTIF=$(config_read '.notifications.flag_show_notifications')
  ICON_ALERT=$(config_read '.notifications.icon_virusalert')
  NOTIF_DUR=$(config_read '.notifications.notification_duration')

  # Excluded dirs als zeilengetrennten String
  DIRS_EXCL=$(printf '%s\n' "${EXCL_ARRAY[@]}")

  yad --plug="$$" --tabnum=1 \
    --form \
    --columns=1 \
    --text="<b>Scan-Konfiguration</b>" \
    --field="Überwachtes Verzeichnis":DIR \
    --field="Ausgeschlossene Verzeichnisse\n(eines pro Zeile)":TXT \
    --field="Desktop-Benachrichtigungen":CHK \
    --field="Icon-Dateiname":TEXT \
    --field="Benachrichtigungsdauer (ms)":NUM \
    "$DIR_WATCH" \
    "$DIRS_EXCL" \
    "$FLAG_NOTIF" \
    "$ICON_ALERT" \
    "$NOTIF_DUR!1000..30000!500!0" \
    > /tmp/clamav_gui_config_$$ &
}

# FUNC: tab_service
# Tab 2: Dienstverwaltung
tab_service() {
  local STATUS
  STATUS=$(service_status_label)

  yad --plug="$$" --tabnum=2 \
    --form \
    --columns=1 \
    --text="<b>Dienstverwaltung</b>\n\nclamav-watch läuft als systemd User-Unit." \
    --field="Status":RO \
    --field="Dienst starten!media-playback-start!Startet den Überwachungsdienst":FBTN \
    --field="Dienst stoppen!media-playback-stop!Stoppt den Überwachungsdienst":FBTN \
    --field="Dienst neu starten!view-refresh!Startet den Dienst neu":FBTN \
    --field="Status aktualisieren!view-refresh":FBTN \
    "$STATUS" \
    "bash -c 'systemctl --user start $SERVICE; notify-send \"clamav-watch\" \"Dienst gestartet.\"'" \
    "bash -c 'systemctl --user stop $SERVICE; notify-send \"clamav-watch\" \"Dienst gestoppt.\"'" \
    "bash -c 'systemctl --user restart $SERVICE; notify-send \"clamav-watch\" \"Dienst neu gestartet.\"'" \
    "bash -c '${0} &'" \
    > /tmp/clamav_gui_svc_$$ &
}

# FUNC: tab_logbrowser
# Tab 3: Logbrowser
tab_logbrowser() {
  local LOG_DIR
  LOG_DIR=$(config_read '.app.dir_log')

  # Verfügbare Logdateien ermitteln
  local LOG_FILES
  mapfile -t LOG_FILES < <(ls -1t "${LOG_DIR}"/clamav-watch-*.log 2>/dev/null)

  if [ ${#LOG_FILES[@]} -eq 0 ]; then
    yad --plug="$$" --tabnum=3 \
      --text="<b>Logbrowser</b>\n\nKeine Logdateien gefunden in:\n${LOG_DIR}" \
      --form \
      --field="":LBL "" \
      > /tmp/clamav_gui_log_$$ &
    return
  fi

  # Dropdown-Liste der Logdateien aufbauen
  local LOG_CHOICES
  LOG_CHOICES=$(printf '%s!' "${LOG_FILES[@]}" | sed 's/!$//')

  # Erste (neueste) Logdatei einlesen und einfärben
  local FIRST_LOG="${LOG_FILES[0]}"
  local LOG_CONTENT
  LOG_CONTENT=$(colorize_log "$FIRST_LOG")

  yad --plug="$$" --tabnum=3 \
    --form \
    --columns=1 \
    --text="<b>Logbrowser</b>" \
    --field="Logdatei":CBE \
    --field="Inhalt":TXT \
    --field="Aktualisieren!view-refresh":FBTN \
    --field="Nur WARN anzeigen!dialog-warning":FBTN \
    --field="Alle Einträge anzeigen!document-open":FBTN \
    "$LOG_CHOICES" \
    "$LOG_CONTENT" \
    "bash -c 'echo reload'" \
    "bash -c 'echo warn'" \
    "bash -c 'echo all'" \
    > /tmp/clamav_gui_log_$$ &
}

# FUNC: colorize_log
# Gibt Loginhalt mit Pango-Markup zurück
# Input: Pfad zur Logdatei
colorize_log() {
  local FILE="$1"
  local OUTPUT=""

  while IFS= read -r line; do
    if echo "$line" | grep -q '\[WARN\]'; then
      OUTPUT+="<span foreground='#cc0000'>${line}</span>\n"
    elif echo "$line" | grep -q '\[ERROR\]'; then
      OUTPUT+="<span foreground='#ff6600' weight='bold'>${line}</span>\n"
    else
      OUTPUT+="<span foreground='#333333'>${line}</span>\n"
    fi
  done < "$file"

  echo -e "$OUTPUT"
}

# FUNC: save_config
# Liest Tab-1-Ausgabe und schreibt config.json neu
save_config() {
  local RAW
  RAW=$(cat /tmp/clamav_gui_config_$$)

  # Felder parsen (yad --form gibt pipe-separiert aus)
  local DIR_WATCH FLAG_NOTIF ICON_ALERT NOTIF_DUR DIRS_EXCL_RAW
  DIR_WATCH=$(echo "$RAW" | cut -d'|' -f1)
  DIRS_EXCL_RAW=$(echo "$RAW" | cut -d'|' -f2)
  FLAG_NOTIF=$(echo "$RAW" | cut -d'|' -f3)
  ICON_ALERT=$(echo "$RAW" | cut -d'|' -f4)
  NOTIF_DUR=$(echo "$RAW" | cut -d'|' -f5 | tr -d '|')

  # Excluded dirs als JSON-Array aufbauen
  local EXCL_JSON
  EXCL_JSON=$(echo "$DIRS_EXCL_RAW" | grep -v '^\s*$' | jq -R . | jq -s .)

  # Boolean normalisieren
  [ "$FLAG_NOTIF" = "TRUE" ] && FLAG_NOTIF="true" || FLAG_NOTIF="false"

  # Bestehende config lesen und Scan+Notification-Felder überschreiben
  local NEW_JSON
  NEW_JSON=$(jq \
    --arg dw "$DIR_WATCH" \
    --argjson excl "$EXCL_JSON" \
    --argjson fn "$FLAG_NOTIF" \
    --arg ia "$ICON_ALERT" \
    --argjson nd "$NOTIF_DUR" \
    '.scan.dir_watch = $dw |
     .scan.dirs_excluded = $excl |
     .notifications.flag_show_notifications = $fn |
     .notifications.icon_virusalert = $ia |
     .notifications.notification_duration = $nd' \
    "$CONFIG_FILE")

  config_write "$NEW_JSON"
}

# FUNC: main
main() {
  check_deps

  # Tabs starten
  tab_config
  tab_service
  tab_logbrowser

  # Notebook-Fenster
  yad --notebook \
    --key="$$" \
    --title="clamav-watch GUI" \
    --width=720 --height=600 \
    --tab="  Konfiguration  " \
    --tab="  Dienst  " \
    --tab="  Logbrowser  " \
    --button="Speichern!document-save:0" \
    --button="Schließen!gtk-cancel:1"

  local RESULT=$?

  # Auf Tab-Prozesse warten
  wait

  if [ "$RESULT" -eq 0 ]; then
    save_config

    yad --question \
      --title="Gespeichert" \
      --text="Konfiguration gespeichert.\n\nDienst neu starten um Änderungen zu übernehmen?" \
      --button="Neu starten!view-refresh:0" \
      --button="Später!gtk-cancel:1"

    if [ $? -eq 0 ]; then
      systemctl --user restart "$SERVICE"
      notify-send "clamav-watch" "Konfiguration gespeichert, Dienst neu gestartet."
    fi
  fi

  # Aufräumen
  rm -f /tmp/clamav_gui_config_$$ \
        /tmp/clamav_gui_svc_$$ \
        /tmp/clamav_gui_log_$$
}

######
###### MAIN
######
main
