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
  *     KIOSK_URL="https://${KIOSK_URL}"
        ;;
esac

echo "Installi*g kiosk components..."

apt-get up*ate

apt-get install -y \
    xorg*\
    chromium \
    openbox \
   *lightdm \
    locales \
    x11-xs*rver-utils \
    wmctrl \
    kbd *
    sudo

# Remove keyring compon*nts to prevent unlock prompts.
apt*get purge -y \
    gnome-keyring \*    seahorse || true

apt-get auto*emove -y

# Create kiosk group.
gr*upadd -f kiosk

# Create kiosk use* if it does not already exist.
if * id -u kiosk >/dev/null 2>&1; then*    useradd \
        --create-hom* \
        --gid kiosk \
        -*shell /bin/bash \
        kiosk
fi*
# Create configuration directorie*.
mkdir -p /home/kiosk/.config/ope*box
mkdir -p /etc/chromium/policie*/managed

# Remove the earlier cus*om Xorg configuration if it still *xists.
rm -f /etc/X11/xorg.conf

#*Locate chvt after installing the k*d package.
CHVT_PATH="$(command -v*chvt)"

if [ -z "$CHVT_PATH" ]; th*n
    echo "Could not locate the c*vt command."
    exit 1
fi

# Allo* only the kiosk user to switch spe*ifically to TTY2 without a passwor*.
cat > /etc/sudoers.d/kiosk-chvt *<EOF
kiosk ALL=(root) NOPASSWD: $C*VT_PATH 2
EOF

chmod 440 /etc/sudo*rs.d/kiosk-chvt

# Validate the su*oers file before continuing.
visud* -cf /etc/sudoers.d/kiosk-chvt

# Ensure TTY2 is available for the emergency escape shortcut.
systemctl enable getty@tty2.service

# Configure LightDM to automatically start an X11 Openbox session.
cat > /etc/lightdm/lightdm.conf <<'EOF'
[Seat:*]
autologin-user=kiosk
autologin-user-timeout=0
user-session=openbox
xserver-command=X -nolisten tcp
EOF

# Disable password storage, synchronization, and browser sign-in.
cat > /etc/chromium/policies/managed/kiosk.json <<'EOF'
{
    "PasswordManagerEnabled": false,
    "BrowserSignin": 0,
    "SyncDisabled": true
}
EOF

# Create the local emergency escape command.
cat > /usr/local/bin/kiosk-emergency-exit <<EOF
#!/bin/bash

exec sudo "$CHVT_PATH" 2
EOF

chmod 755 /usr/local/bin/kiosk-emergency-exit

# Configure Openbox.
#
# Ctrl+Alt+Shift+K switches the physical console to TTY2.
#
# L = window title
# M = maximize
# C = close
#
# Chromium draws its own title bar, so the wmctrl watchdog below
# restores Chromium whenever it is minimized.
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

    <keyboard>
        <keybind key="C-A-S-k">
            <action name="Execute">
                <command>/usr/local/bin/kiosk-emergency-exit</command>
            </action>
        </keybind>
    </keyboard>

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

# Safely quote the supplied URL before writing it into autostart.
printf -v KIOSK_URL_QUOTED '%q' "$KIOSK_URL"

# Configure Openbox autostart.
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

# Restore, maximize, and raise Chromium whenever it is minimized
# or placed behind another window.
(
    while true; do
        WINDOW_ID=\$(wmctrl -lx 2>/dev/null |
            awk 'BEGIN { IGNORECASE=1 }
                 /chromium/ { id=\$1 }
                 END { print id }')

        if [ -n "\$WINDOW_ID" ]; then
            wmctrl -i -r "\$WINDOW_ID" \
                -b remove,hidden 2>/dev/null || true

            wmctrl -i -r "\$WINDOW_ID" \
                -b add,maximized_vert,maximized_horz \
                2>/dev/null || true

            wmctrl -i -a "\$WINDOW_ID" \
                2>/dev/null || true
        fi

        sleep 2
    done
) &

# Relaunch Chromium whenever it is closed.
while true; do
    # Start each Chromium launch with a clean browser profile.
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

# Set ownership only after all kiosk configuration files are created.
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
echo "Emergency local escape:"
echo "Ctrl+Alt+Shift+K switches to TTY2."
echo
echo "Return to the kiosk using Ctrl+Alt+F1 or Ctrl+Alt+F7,"
echo "depending on which TTY LightDM uses."
echo
echo "Reboot the computer to apply the configuration."
