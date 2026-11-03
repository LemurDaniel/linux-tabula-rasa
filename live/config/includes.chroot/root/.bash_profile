# Starts the Tabula Rasa menu on tty1, every other console (Alt+F2 ...) stays a plain root shell.
# When the menu exits, getty logs root in again and the menu restarts.
if [ "$(tty)" = "/dev/tty1" ]; then
    exec pwsh -NoLogo -NoProfile -Command "Import-Module /opt/tabula-rasa/TabulaRasa; Start-TabulaRasa"
fi
