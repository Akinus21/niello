# Add xdg-desktop-portal (at /usr/libexec) to PATH
# Without this, the portal binary is not found by shell users and
# xdg-desktop-portal --help fails with "command not found",
# breaking file pickers in browsers/Electron apps and Flatpak sandboxing.
case ":$PATH:" in
    *:/usr/libexec:*) ;;
    *) export PATH="${PATH}:/usr/libexec" ;;
esac
