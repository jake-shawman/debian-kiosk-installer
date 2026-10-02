#!/bin/bash

apt-get update

apt-get install -y \
    xorg \
    chromium \
    openbox \
    lightdm \
    locales

# Remove keyring components that cause unlock prompts
apt-get purge -y \
    gnome-keyring \
    seahorse

apt-get autoremove -y

groupadd -f kiosk

id -u kiosk >/dev/null 2>&1 || useradd -m -g kiosk -s /bin/bash kiosk

mkdir -p /home/kiosk/.config/openbox

cat > /etc/lightdm/lightdm.conf << 'EOF'
[Seat:*]
autologin-user=kiosk
autologin-user-timeout=0
user-session=openbox
EOF

cat > /home/kiosk/.config/openbox/autostart << 'EOF'
#!/bin/bash

KIOSK_URL="https://www.google.com/"

xset s off
xset s noblank
xset -dpms

xrandr --auto

while true
do
    chromium \
        --noerrdialogs \
        --no-first-run \
        --disable-translate \
        --disable-infobars \
        --disable-session-crashed-bubble \
        --start-maximized \
        --user-data-dir=/home/kiosk/chrome-kiosk \
        --kiosk \
        "$KIOSK_URL"

    sleep 5
done
EOF

chown -R kiosk:kiosk /home/kiosk
chmod 755 /home/kiosk/.config/openbox/autostart

systemctl enable lightdm

echo "Kiosk configuration complete."
echo "Reboot the system."
