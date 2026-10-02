#!/bin/bash

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root:"
    echo "sudo bash kiosk-install.sh"
    exit 1
fi

echo
read -p "Enter kiosk URL (example: https://dashboard.company.com): " KIOSK_URL
echo

if [ -z "$KIOSK_URL" ]; then
    echo "No URL entered."
    exit 1
fi

apt-get update

apt-get install -y \
    xorg \
    chromium \
    openbox \
    lightdm \
    locales \
    x11-xserver-utils

# Remove keyring components that cause unlock prompts
apt-get purge -y \
    gnome-keyring \
    seahorse || true

apt-get autoremove -y

# Create kiosk account if needed
groupadd -f kiosk

if ! id -u kiosk >/dev/null 2>&1; then
    useradd -m -g kiosk -s /bin/bash kiosk
fi

# Openbox config directory
mkdir -p /home/kiosk/.config/openbox

# LightDM autologin
cat > /etc/lightdm/lightdm.conf << 'EOF'
[Seat:*]
autologin-user=kiosk
autologin-user-timeout=0
user-session=openbox
EOF

# Chromium enterprise policy
mkdir -p /etc/chromium/policies/managed

cat > /etc/chromium/policies/managed/kiosk.json << 'EOF'
{
  "PasswordManagerEnabled": false,
  "BrowserSignin": 0,
  "SyncDisabled": true
}
EOF

# Openbox autostart
cat > /home/kiosk/.config/openbox/autostart << EOF
#!/bin/bash

KIOSK_URL="${KIOSK_URL}"

xset s off
xset s noblank
xset -dpms

xrandr --auto

while true
do
    PROFILE_DIR="/tmp/chrome-kiosk"

    rm -rf "\$PROFILE_DIR"
    mkdir -p "\$PROFILE_DIR"

    chromium \
        --noerrdialogs \
        --no-first-run \
        --disable-translate \
        --disable-infobars \
        --disable-session-crashed-bubble \
        --disable-sync \
        --password-store=basic \
        --disable-features=PasswordManagerOnboarding \
        --user-data-dir="\$PROFILE_DIR" \
        --start-maximized \
        "\$KIOSK_URL"

    sleep 2
done
EOF

# Permissions
chown -R kiosk:kiosk /home/kiosk
chmod 755 /home/kiosk/.config/openbox/autostart

# Enable LightDM
systemctl enable lightdm

echo
echo "Kiosk configuration complete."
echo "Configured URL: ${KIOSK_URL}"
echo
echo "Reboot to start kiosk mode."
