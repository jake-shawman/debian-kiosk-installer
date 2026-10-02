#!/bin/bash

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this script as root."
    echo "Example:"
    echo 'sudo bash kiosk-installer.sh "https://www.google.com"'
    exit 1
fi

KIOSK_URL="$1"

if [ -z "$KIOSK_URL" ]; then
    echo "A kiosk URL is required."
    echo "Example:"
    echo 'bash kiosk-installer.sh "https://www.google.com"'
    exit 1
fi

case "$KIOSK_URL" in
    http://*|https://*)
        ;;
    *)
        KIOSK_URL="https://${KIOSK_URL}"
        ;;
esac

echo "Installing kiosk components..."

apt-get update

apt-get install -y \
    xorg \
    chromium \
    openbox \
    lightdm \
    locales \
    x11-xserver-utils \
    wmctrl

# Remove keyring components to prevent unlock prompts.
apt-get purge -y \
    gnome-keyring \
    seahorse || true

apt-get autoremove -y

# Create the kiosk group.
groupadd -f kiosk

# Create the kiosk user if it does not already exist.
if ! id -u kiosk >/dev/null 2>&1; then
    useradd \
        --create-home \
        --gid kiosk \
        --shell /bin/bash \
        kiosk
fi

# Create configuration directories.
mkdir -p /home/kiosk/.config/openbox
mkdir -p /etc/chromium/policies/managed

# Remove the earlier custom Xorg configuration if it still exists.
rm -f /etc/X11/xorg.conf

# Configure LightDM to automatically start an X11 Openbox session.
cat > /etc/lightdm/lightdm.conf <<'EOF'
[Seat:*]
autologin-user=kiosk
autologin-user-timeout=0
user-session=openbox
xserver-command=X -nolisten tcp
EOF

# Disable password storage, browser sign-in, and synchronization.
cat > /etc/chromium/policies/managed/kiosk.json <<'EOF'
{
    "PasswordManagerEnabled": false,
    "BrowserSignin": 0,
    "SyncDisabled": true
}
EOF

# Configure Openbox window controls.
#
# L = window title
# M = maximize
# C = close
#
# Chromium currently draws its own title bar, so this does not remove
# Chromium's minimize button. The watchdog below restores Chromium if
# that button is used.
cat > /home/kiosk/.config/openbox/rc.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>

<openbox_config xmlns="http://openbox.org/3.4/rc">

    <theme>
        <name>Clearlooks</name>
        <titleLayout>LMC</titleLayout>
        <keepBorder>yes</keepBorder>
        <animateIconify>no</animateIconify>
    </theme>

    <focus>
        <focusNew>yes</focusNew>
        <followMouse>no</followMouse>
        <raiseOnFocus>yes</raiseOnFocus>
    </focus>

    <applications>
        <application class="Chromium-browser">
            <maximized>yes</maximized>
            <focus>yes</focus>
        </application>

        <application class="Chromium">
            <maximized>yes</maximized>
            <focus>yes</focus>
        </application>

        <application name="chromium">
            <maximized>yes</maximized>
            <focus>yes</focus>
        </application>
    </applications>

</openbox_config>
EOF

# Safely quote the supplied URL before inserting it into the generated script.
printf -v KIOSK_URL_QUOTED '%q' "$KIOSK_URL"

# Create the Openbox autostart script.
cat > /home/kiosk/.config/openbox/autostart <<EOF
#!/bin/bash

KIOSK_URL=$KIOSK_URL_QUOTED
PROFILE_DIR="/tmp/chromium-kiosk-profile"

# Disable screen blanking and display power management.
xset s off
xset s noblank
xset -dpms

# Configure connected displays.
xrandr --auto

# Watch Chromium windows continuously.
#
# If Chromium is minimized, remove its hidden state.
# If Chromium is behind another window, activate and raise it.
(
    while true; do
        WINDOW_ID=\$(wmctrl -lx 2>/dev/null |
            awk 'BEGIN { IGNORECASE=1 }
                 /chromium/ { id=\$1 }
                 END { print id }')

        if [ -n "\$WINDOW_ID" ]; then
            wmctrl -i -r "\$WINDOW_ID" -b remove,hidden 2>/dev/null || true
            wmctrl -i -r "\$WINDOW_ID" -b add,maximized_vert,maximized_horz \
                2>/dev/null || true
            wmctrl -i -a "\$WINDOW_ID" 2>/dev/null || true
        fi

        sleep 2
    done
) &

# Relaunch Chromium whenever it is closed.
while true; do
    # Use a fresh browser profile for every Chromium launch.
    rm -rf "\$PROFILE_DIR"
    mkdir -p "\$PROFILE_DIR"

    chromium \\
        --ozone-platform=x11 \\
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

    sleep 2
done
EOF

# Set ownership and permissions after creating all kiosk files.
chown -R kiosk:kiosk /home/kiosk

chmod 755 /home/kiosk
chmod 755 /home/kiosk/.config
chmod 755 /home/kiosk/.config/openbox
chmod 755 /home/kiosk/.config/openbox/autostart

chmod 644 /home/kiosk/.config/openbox/rc.xml
chmod 644 /etc/chromium/policies/managed/kiosk.json

# Enable the graphical login manager.
systemctl enable lightdm

echo
echo "Kiosk configuration complete."
echo "Configured URL: $KIOSK_URL"
echo "Window manager: Openbox on Xorg"
echo "Chromium will be restored if minimized."
echo "Chromium will be relaunched if closed."
echo
echo "Reboot the computer to apply the configuration."
