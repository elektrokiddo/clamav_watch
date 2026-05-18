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
config_read() {
  jq -r "$1" "$CONFIG_FILE" 2>/dev/null
}

# FUNC: config_write
config_write() {
  echo "$1" > "$CONFIG_FILE"
}

# FUNC: service_status_label
service_status_label() {
  if systemctl --user is-active --quiet "$SERVICE"; then
    echo "● Dienst läuft"
  else
    echo "○ Dienst gestoppt"
  fi
}

# FUNC: tab_watch
# Tab 1: Watch-Verzeichnisse
tab_watch() {
  local WATCH_ARRAY
  mapfile -t WATCH_ARRAY < <(config_read '.scan.dirs_watch[]')

  yad --plug="$$" --tabnum=1 \
    --list \
    --text="<b>Zu überwachende Verzeichnisse</b>\n\nVerzeichnisse die rekursiv auf neue und geänderte Dateien überwacht werden." \
    --column="Verzeichnis":TEXT \
    --editable \
    --print-all \
    "${WATCH_ARRAY[@]}" \
    > /tmp/clamav_gui_watch_$$ &
}

# FUNC: tab_excludes
# Tab 2: Exclude-Verzeichnisse
tab_excludes() {
  local EXCL_ARRAY
  mapfile -t EXCL_ARRAY < <(config_read '.scan.dirs_excluded[]')

  yad --plug="$$" --tabnum=2 \
    --list \
    --text="<b>Ausgeschlossene Verzeichnisse</b>\n\nDateien in diesen Verzeichnissen werden nicht gescannt." \
    --column="Verzeichnis":TEXT \
    --editable \
    --print-all \
    "${EXCL_ARRAY[@]}" \
    > /tmp/clamav_gui_excl_$$ &
}

# FUNC: tab_service
# Tab 3: Dienstverwaltung
tab_service() {
  local STATUS
  STATUS=$(service_status_label)

  yad --plug="$$" --tabnum=3 \
    --form \
    --columns=1 \
    --text="<b>Dienstverwaltung</b>\n\nclamav-watch läuft als systemd User-Unit.\nÄnderungen an der Konfiguration erfordern einen Neustart des Dienstes." \
    --field="Status":RO \
    --field="Dienst starten!media-playback-start!Startet den Überwachungsdienst":FBTN \
    --field="Dienst stoppen!media-playback-stop!Stoppt den Überwachungsdienst":FBTN \
    --field="Dienst neu starten!view-refresh!Startet den Dienst neu":FBTN \
    "$STATUS" \
    "bash -c 'systemctl --user start $SERVICE; notify-send \"clamav-watch\" \"Dienst gestartet.\"'" \
    "bash -c 'systemctl --user stop $SERVICE; notify-send \"clamav-watch\" \"Dienst gestoppt.\"'" \
    "bash -c 'systemctl --user restart $SERVICE; notify-send \"clamav-watch\" \"Dienst neu gestartet.\"'" \
    > /tmp/clamav_gui_svc_$$ &
}

# FUNC: save_config
save_config() {
  local WATCH_JSON
  WATCH_JSON=$(grep -v '^\s*$' /tmp/clamav_gui_watch_$$ \
    | sed 's/|$//' \
    | jq -R . \
    | jq -s .)

  local EXCL_JSON
  EXCL_JSON=$(grep -v '^\s*$' /tmp/clamav_gui_excl_$$ \
    | sed 's/|$//' \
    | jq -R . \
    | jq -s .)

  local NEW_JSON
  NEW_JSON=$(jq \
    --argjson watch "$WATCH_JSON" \
    --argjson excl "$EXCL_JSON" \
    '.scan.dirs_watch = $watch |
     .scan.dirs_excluded = $excl' \
    "$CONFIG_FILE")

  config_write "$NEW_JSON"
}

# FUNC: main
main() {
  check_deps

  tab_watch
  tab_excludes
  tab_service

  yad --notebook \
    --key="$$" \
    --title="clamav-watch GUI" \
    --width=720 --height=480 \
    --tab="  Watch-Verzeichnisse  " \
    --tab="  Excludes  " \
    --tab="  Dienst  " \
    --button="Speichern!document-save:0" \
    --button="Schließen!gtk-cancel:1"

  local RESULT=$?

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

  rm -f /tmp/clamav_gui_watch_$$ \
        /tmp/clamav_gui_excl_$$ \
        /tmp/clamav_gui_svc_$$
}

######
###### MAIN
######
main
