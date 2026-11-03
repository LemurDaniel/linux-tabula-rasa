# Starts the Tabula Rasa text menu on tty2, every other console (Alt+F3 ...) stays a plain root shell.
# When the menu exits, getty logs root in again and the menu restarts.
if [ "$(tty)" = "/dev/tty2" ]; then
    exec pwsh -NoLogo -NoProfile -Command "Import-Module /opt/tabula-rasa/TabulaRasa; Start-TabulaRasa"
fi
