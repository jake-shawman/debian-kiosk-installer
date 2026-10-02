#!/bin/bash

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root:"
    echo "sudo bash kiosk-install.sh"
    exit 1
fi

echo
read -r -p "Enter kiosk URL (example: https://www.google.com): " KIOSK_URL
echo

if [ -z "$KIOSK_URL" ]; then
    echo "No URL entered."
    exit 1
fi

case "$KIOSK_URL" in
    http://*|https://*)
        ;;
    *)
        KIOSK_URL="https://${KIOSK_URL}"
        ;;
esac

apt-get update

apt-get install -y \
    xorg \
    chromium \
    openbox \
    lightdm \
    locales \
    x11-xserver-utils

# Remove keyring components to prevent unlock prompts.
apt-get purge -y \
    gnome-keyring \
    seahorse || true

apt-get autoremove -y

# Create kiosk group and user if needed.
groupadd -f kiosk

if ! id -u kiosk >/dev/null 2>&1; then
    useradd -m -g kiosk -s /bin/bash kiosk
fi

mkdir -p /home/kiosk/.config/openbox
mkdir -p /etc/chromium/policies/managed

# Configure LightDM autologin.
cat > /etc/lightdm/lightdm.conf <<'EOF'
[Seat:*]
autologin-user=kiosk
autologin-user-timeout=0
user-session=openbox
EOF

# Disable password saving, browser sign-in, and synchronization.
cat > /etc/chromium/policies/managed/kiosk.json <<'EOF'
{
  "PasswordManagerEnabled": false,
  "BrowserSignin": 0,
  "SyncDisabled": true
}
EOF

# Configure Openbox window decorations.
#
# L = window icon
# M = maximize button
# C = close button
#
# There is intentionally no I, so the minimize button is hidden.
cat > /home/kiosk/.config/openbox/rc.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>

<openbox_config xmlns="http://openbox.org/3.4/rc">
  <theme>
    <name>Clearlooks</name>
    <titleLayout>LMC</titleLayout>
  </theme>

  <applications>
    <application class="Chromium-browser">
      <maximized>yes</maximized>
    </application>

    <application class="Chromium">
      <maximized>yes</maximized>
    </application>

    <application name="chromium">
      <maximized>yes</maximized>
    </application>
  </applications>
</openbox_config>
EOF

# Safely quote the URL before writing it into the autostart script.
printf -v KIOSK_URL_QUOTED '%q' "$KIOSK_URL"

# Configure Openbox autostart.
cat > /home/kiosk/.config/openbox/autostart <<EOF
#!/bin/bash

KIOSK_URL=$KIOSK_URL_QUOTED
PROFILE_DIR="/tmp/chromium-kiosk-profile"

xset s off
xset s noblank
xset -dpms
xrandr --auto

while true; do
    # Remove all browser data from the previous launch.
    rm -rf "\$PROFILE_DIR"
    mkdir -p "\$PROFILE_DIR"

    chromium \\
        --noerrdialogs \\
        --no-first-run \\
        --disable-translate \\
        --disable-infobars \\
        --disable-session-crashed-bubble \\
        --disable-sync \\
        --disable-features=PasswordManagerOnboarding \\
        --password-store=basic \\
        --user-data-dir="\$PROFILE_DIR" \\
        --start-maximized \\
        "\$KIOSK_URL"

    # Relaunch Chromium if it is closed.
    sleep 2
done
EOF

# Ensure the kiosk session can read its configuration.
chown -R kiosk:kiosk /home/kiosk
chmod 755 /home/kiosk/.config/openbox/autostart
chmod 644 /home/kiosk/.config/openbox/rc.xml
chmod 644 /etc/chromium/policies/managed/kiosk.json

systemctl enable lightdm

echo
echo "Kiosk configuration complete."
echo "Configured URL: $KIOSK_URL"
echo "The minimize button has been removed."
echo "Reboot the system to start the kiosk."
