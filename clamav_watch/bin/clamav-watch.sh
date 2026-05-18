#!/bin/bash

######
###### PREACTIONS
######

# SELINUX
# sudo setsebool -P antivirus_can_scan_system 1
# sudo setsebool -P clamd_use_jit 1

# CLAMAV: /etc/clamd.d/clamd.conf
# Uncomment #LocalSocket /run/clamd.scan/clamd.sock
# Uncomment #LocalSocketGroup virusgroup
# Uncomment #LocalSocketMode 660
# systemctl enable --now clamd@scan
# systemctl restart clamd@scan

# Groups
# Add particular user to group 'virusgroup'
# e.g. gpasswd -a [USER] virusgroup

######
###### DEF
######
DIR_APP="/home/hhepting/.local/clamav_watch"
CONFIG_FILE="${1:-${DIR_APP}/etc/config.json}"

# Config einlesen
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "FEHLER: Konfigurationsdatei nicht gefunden: $CONFIG_FILE"
  exit 1
fi

if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
  echo "FEHLER: Ungültiges JSON in $CONFIG_FILE"
  exit 1
fi

# App-Verzeichnisse
DIR_ETC=$(jq -r '.app.dir_etc' "$CONFIG_FILE")
DIR_VAR=$(jq -r '.app.dir_var' "$CONFIG_FILE")
DIR_USR=$(jq -r '.app.dir_usr' "$CONFIG_FILE")
DIR_LOG=$(jq -r '.app.dir_log' "$CONFIG_FILE")
DIR_VAULT=$(jq -r '.app.dir_vault' "$CONFIG_FILE")
DIR_ICONS=$(jq -r '.app.dir_icons' "$CONFIG_FILE")

# Scan-Konfiguration
mapfile -t DIRS_WATCH < <(jq -r '.scan.dirs_watch[]' "$CONFIG_FILE")
mapfile -t DIRS_EXCLUDED < <(jq -r '.scan.dirs_excluded[]' "$CONFIG_FILE")

# Notifications
FLAG_SHOW_NOTIFICATIONS=$(jq -r '.notifications.flag_show_notifications' "$CONFIG_FILE")
ICON_VIRUSALERT=$(jq -r '.notifications.icon_virusalert' "$CONFIG_FILE")
NOTIFICATION_DURATION=$(jq -r '.notifications.notification_duration' "$CONFIG_FILE")

# Logdatei – tagesweise
LOG_FILE="${DIR_LOG}/clamav-watch-$(date +%Y%m%d).log"

######
###### FUNC
######
# FUNC: log
# Writes a timestamped log entry to logfile and stdout
# Input: Log level (INFO|WARN|ERROR), message
# Returns: none
log()
{
  local LEVEL
  local MSG
  LEVEL=$1
  shift
  MSG="$*"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${LEVEL}] ${MSG}" | tee -a "$LOG_FILE"
}

# FUNC: test_if_excluded_dir
# Check if a file finds itself in an excluded directory
# Input: filepath
# Returns:
#   0 : File not in excluded dir
#   1 : File in excluded dir
test_if_excluded_dir()
{
  local FILE_2_TEST
  local RETVAL
  RETVAL=0
  FILE_2_TEST=$1
  for D in "${DIRS_EXCLUDED[@]}";
  do
    if [[ "$FILE_2_TEST" == "$D"/* ]]; then
      RETVAL=1
      echo $RETVAL
      exit
    fi
  done
  echo $RETVAL
}

# FUNC: tray_notification
# Shows a tray notification if flag is permissive
# Input: Notification titel, text and icon
# Returns: none
tray_notification()
{
  if [ "${FLAG_SHOW_NOTIFICATIONS}" == "true" ]; then
    local NOT_TITLE
    local NOT_TEXT
    local NOT_ICON
    NOT_TITLE=$1
    NOT_TEXT=$2
    NOT_ICON=$3

    notify-send \
      --expire-time ${NOTIFICATION_DURATION} \
      --icon "${DIR_ICONS}/${NOT_ICON}" \
      "${NOT_TITLE}" \
      "DETECTED: ${NOT_TEXT}\nMOVED TO: $DIR_VAULT"
  fi
}

# FUNC: main
# Mainloop: Eyes on directory
main()
{
  log "INFO" "ClamAV Watch gestartet"
  log "INFO" "Überwache Verzeichnis: $DIR_WATCH"
  log "INFO" "Ausgeschlossene Verzeichnisse: ${DIRS_EXCLUDED[*]}"
  log "INFO" "Virus-Vault: $DIR_VAULT"

  inotifywait -m -r -e CLOSE_WRITE --format '%w%f' "${DIRS_WATCH[@]}" | while read FILE
  do
    # Continue only when file locates not in excluded dir
    if [[ ! "$(dirname ${FILE})" == "${DIR_LOG}"  ]]; then
      if [[ "$(test_if_excluded_dir $FILE)" == "0" ]]; then
        # Ensure it's a file, not a directory
        if [ -f "$FILE" ]; then
          log "INFO" "Scanne: $FILE"
          # Run clamdscan against the new file
          if clamdscan --fdpass "$FILE" | grep -q "FOUND"; then
            TS_FILE=$(date +%Y-%m-%d_%H-%M-%S)
            log "WARN" "VIRUS GEFUNDEN: $FILE"
            log "INFO" "Verschiebe nach: ${DIR_VAULT}/${TS_FILE}_$(basename $FILE)"
            tray_notification "VIRUS ALERT" "${FILE}" "$ICON_VIRUSALERT"
            mv "$FILE" "${DIR_VAULT}/${TS_FILE}_$(basename $FILE)"
            log "INFO" "Datei erfolgreich in Quarantäne verschoben"
          else
            log "INFO" "Kein Fund: $FILE"
          fi
        fi
      else
        log "INFO" "Übersprungen (excluded): $FILE"
      fi
    fi
  done
}

######
###### PRE
######
# Create dirs if not existing
for D in ${DIR_VAULT} ${DIR_LOG};
do
  [[ ! -d ${D} ]] && mkdir -p ${D}
done

######
###### MAIN
######
main
