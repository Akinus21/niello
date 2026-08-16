#!/bin/bash
# =============================================================================
# niello-firstboot.sh — prompts to create an admin user if none exists yet.
# Runs once, before greetd starts. Safe to re-run: exits immediately if a
# real (non-system) user already exists, or if it already completed once.
# =============================================================================
set -uo pipefail

MARKER=/etc/niello-firstboot-done

if [ -f "$MARKER" ]; then
    exit 0
fi

# Skip if a real (UID >= 1000, non-system) user already exists.
if awk -F: '$3>=1000 && $3<60000 {found=1} END{exit !found}' /etc/passwd; then
    touch "$MARKER"
    exit 0
fi

exec < /dev/tty1 > /dev/tty1 2>&1

whiptail --title "Niello First Boot Setup" \
    --msgbox "Welcome to Niello.\n\nLet's create your first user account. This account will have admin (sudo) access." \
    12 60

while true; do
    USERNAME=$(whiptail --title "Create User" --inputbox "Enter a username:" 10 60 3>&1 1>&2 2>&3)
    STATUS=$?
    [ $STATUS -ne 0 ] && continue
    if [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]] && ! id "$USERNAME" &>/dev/null; then
        break
    fi
    whiptail --msgbox "Invalid or already-taken username. Use lowercase letters, numbers, - or _, starting with a letter." 10 60
done

while true; do
    PASS1=$(whiptail --title "Set Password" --passwordbox "Enter password for $USERNAME:" 10 60 3>&1 1>&2 2>&3)
    PASS2=$(whiptail --title "Confirm Password" --passwordbox "Confirm password:" 10 60 3>&1 1>&2 2>&3)
    if [ -n "$PASS1" ] && [ "$PASS1" = "$PASS2" ]; then
        break
    fi
    whiptail --msgbox "Passwords did not match, or were empty. Try again." 10 60
done

useradd -m -G wheel -s /bin/zsh "$USERNAME"
echo "$USERNAME:$PASS1" | chpasswd
unset PASS1 PASS2

touch "$MARKER"
whiptail --msgbox "Account '$USERNAME' created with admin access.\n\nYou can now log in." 10 60
