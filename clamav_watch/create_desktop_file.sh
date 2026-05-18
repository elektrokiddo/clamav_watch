#!/bin/bash

cat > ~/.local/share/applications/clamav-watch-gui.desktop << 'EOF'
[Desktop Entry]
Name=clamav-watch GUI
Comment=Konfiguration und Überwachung für clamav-watch
Exec=/home/[USERNAME]/.local/clamav_watch/bin/clamav-gui.sh
Icon=preferences-system-privacy
Terminal=false
Type=Application
Categories=Settings;Security;
EOF
