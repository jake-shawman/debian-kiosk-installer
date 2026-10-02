#!/bin/bash

set -e

# Must be run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Run this script as root or with sudo."
    exit 1
fi

# Update packages
apt-get update

# Install required software
apt-get install -y \
    xorg \
    chromium \
    openbox \
    lightdm \
    locales \
    x11-xserver-utils

# Create kiosk group and user
groupadd -f kiosk

if ! id kiosk >/dev/null 2>&1; then
    useradd -m -g kiosk -s /bin/bash kiosk
fi

# Create Openbox configuration directory
mkdir -p /home/kiosk/.config/openbox

# Disable virtual-terminal switching
if [ -e /etc/X11/xorg.conf ] &&
   [ ! -e /etc/X11/xorg.conf.backup ]; then
    mv /etc/X11/xorg.conf /etc/X11/xorg.conf.backup
fi

cat > /etc/X11/xorg.conf <<'EOF'
Section "ServerFlags"
    Option "DontVTSwitch" "true"
EndSection
EOF

# Configure LightDM autologin
if [ -e /etc/lightdm/lightdm.conf ] &&
   [ ! -e /etc/lightdm/lightdm.conf.backup ]; then
    cp /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.backup
fi

cat > /etc/lightdm/lightdm.conf <<'EOF'
[Seat:*]
xserver-command=X -nolisten tcp
autologin-user=kiosk
autologin-user-timeout=0
user-session=openbox
EOF

# Create Openbox autostart
cat > /home/kiosk/.config/openbox/autostart <<'EOF'
#!/bin/bash

KIOSK_URL="https://www.google.com/"

# Prevent screen blanking
xset s off
xset s noblank
xset -dpms

# Automatically configure connected displays
xrandr --auto

# Start Chromium and restart it if it exits
while true; do
    chromium \
        --noerrdialogs \
        --no-first-run \
        --start-maximized \
        --disable-translate \
        --disable-infobars \
        --disable-session-crashed-bubble \
        --incognito \
        --kiosk \
        "$KIOSK_URL"

    sleep 5
done
EOF

# Set ownership after creating all user files
chown -R kiosk:kiosk /home/kiosk/.config

# Although Openbox normally reads the file directly, executable permission
# is useful for manually testing it.
chmod 755 /home/kiosk/.config/openbox/autostart

# Ensure LightDM starts automatically
systemctl enable lightdm

echo "Kiosk configuration complete."
echo "Reboot with: reboot"
