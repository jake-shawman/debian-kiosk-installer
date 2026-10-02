#!/bin/bash

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root:"
    echo "sudo bash kiosk-installer.sh https://example.com"
    exit 1
fi

KIOSK_URL="$1"

if [ -z "$KIOSK_URL" ]; then
    echo "Usage:"
    echo "bash kiosk-installer.sh https://example.com"
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

apt-get purge -y \
    gnome-keyring \
    seahorse || true

apt-get autoremove -y

groupadd -f kiosk

if ! id -u kiosk >/dev/null 2>&1; then
    useradd -m -g kiosk -s /bin/bash kiosk
fi

mkdir -p /home/kiosk/.config/openbox
mkdir -p /etc/chromium/policies/managed

cat > /etc/lightdm/lightdm.conf <<'EOF'
[Seat:*]
autologin-user=kiosk
autologin-user-timeout=0
user-session=openbox
EOF

cat > /etc/chromium/policies/managed/kiosk.json <<'EOF'
{
  "PasswordManagerEnabled": false,
  "BrowserSignin": 0,
  "SyncDisabled": true
}
EOF

cat > /home/kiosk/.config/openbox/rc.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>

<openbox_config xmlns="http://openbox.org/3.4/rc">

  <theme>
    <name>Clearlooks</name>

    <!--
    L = icon
    M = maximize
    C = close

    No I = no minimize button
    -->

    <titleLayout>LMC</titleLayout>
  </theme>

</openbox_config>
EOF

printf -v KIOSK_URL_Q '%q' "$KIOSK_URL"

cat > /home/kiosk/.config/openbox/autostart <<EOF
#!/bin/bash

KIOSK_URL=$KIOSK_URL_Q
PROFILE_DIR=/tmp/chromium-kiosk-profile

xset s off
xset s noblank
xset -dpms

xrandr --auto

while true
do
    rm -rf "\$PROFILE_DIR"
    mkdir -p "\$PROFILE_DIR"

    chromium \
        --noerrdialogs \
        --no-first-run \
        --disable-translate \
        --disable-infobars \
        --disable-session-crashed-bubble \
        --disable-sync \
        --disable-features=PasswordManagerOnboarding \
        --password-store=basic \
        --user-data-dir="\$PROFILE_DIR" \
        --start-maximized \
        "\$KIOSK_URL"

    sleep 2
done
EOF

chown -R kiosk:kiosk /home/kiosk

chmod 755 /home/kiosk/.config/openbox/autostart
chmod 644 /home/kiosk/.config/openbox/rc.xml
chmod 644 /etc/chromium/policies/managed/kiosk.json

systemctl enable lightdm

echo
echo "Kiosk configuration complete."
echo "Configured URL: $KIOSK_URL"
echo "Run: reboot"
echo
