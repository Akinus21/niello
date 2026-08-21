FROM quay.io/fedora/fedora-bootc:44

# ── Container Registry Policy ─────────────────────────────────
COPY config/containers/policy.json /etc/containers/policy.json

# ── RPMFusion + Full Codec Stack (uBlue hardware enablement) ───
# Disable fedora-cisco-openh264 — its metalink is unreachable from CI runners
# and openh264 isn't needed for this image
RUN dnf config-manager --disable fedora-cisco-openh264 2>/dev/null || \
    dnf config-manager --set-disabled fedora-cisco-openh264 2>/dev/null || \
    true
RUN dnf install -y --setopt=retries=5 --setopt=timeout=120 --disablerepo=fedora-cisco-openh264 \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm \
    && dnf install -y --skip-broken --setopt=retries=5 --setopt=timeout=120 --disablerepo=fedora-cisco-openh264 \
    mesa-va-drivers-freeworld \
    ffmpeg \
    pipewire-codec-aptx \
    && dnf clean all

# ── Metadata ────────────────────────────────────────────────
LABEL org.opencontainers.image.title="Niello"

# Build-id stamp: lets niello-init detect that the underlying OS image
# changed (e.g. via `bootc switch`), since $HOME persists across
# deployments but this file lives in /usr and is fresh every build.
# Without this, niello-init's sync-interval skip would see a recent
# marker in $HOME from the PREVIOUS deployment and never run at all
# after switching images.
RUN mkdir -p /usr/share/niello && date -u +%Y%m%d%H%M%S%N > /usr/share/niello/build-id
LABEL org.opencontainers.image.description="Immutable Fedora Atomic — Niri + Noctalia + Rust toolchain"
LABEL org.opencontainers.image.source="https://github.com/Akinus21/niello"
LABEL org.opencontainers.image.vendor="akinus"

# ══════════════════════════════════════════════════════════════
# CORE SYSTEM ESSENTIALS — guaranteed present, not assumed from base image
# ══════════════════════════════════════════════════════════════

# Locale data — without this, LANG/LC_* being set to en_US.UTF-8 (or
# similar) with no matching locale actually generated produces
# "Cannot set LC_* to default locale" warnings from every locale-aware
# tool (Homebrew, git, etc.) on this minimal base image.
RUN dnf install -y glibc-langpack-en

# sudo — explicitly installed and wheel group granted, rather than trusting
# the base image already has this configured correctly.
RUN dnf install -y sudo && \
    mkdir -p /etc/sudoers.d && \
    printf '%%wheel ALL=(ALL) ALL\n' > /etc/sudoers.d/10-wheel && \
    chmod 0440 /etc/sudoers.d/10-wheel

# Root account: LOCKED, not blank-password. A blank password would let
# anyone log in as root with no credentials — locking disables password
# login entirely (root is still reachable via sudo from a wheel-group user).
RUN passwd -l root

# Hostname — default, user can change post-boot via hostnamectl.
RUN echo 'niello' > /etc/hostname

# SSH server — enabled for remote access/debugging.
RUN dnf install -y openssh-server && \
    systemctl enable sshd

# Time sync — required for TLS/HTTPS repo access and OIDC auth to work
# correctly; not assumed from the base image.
RUN dnf install -y chrony && \
    systemctl enable chronyd

# Firewall — explicitly installed and enabled rather than assumed.
RUN dnf install -y firewalld && \
    systemctl enable firewalld

# systemd-remount-fs.service — masked. On bootc/composefs roots, "/" is an
# overlay mount that doesn't support in-place remount (fsconfig() fails
# with "No changes allowed in reconfigure"). This unit tries to remount
# filesystems to match fstab options at boot and is a no-op/failure on
# this class of system — root mount state is managed by ostree/composefs,
# not classic fstab remounting. Masking avoids a permanently-failed unit
# cluttering `systemctl --failed` on every boot for something that was
# never going to succeed here.
RUN systemctl mask systemd-remount-fs.service

# ── OS Identity ──────────────────────────────────────────────
COPY usr/lib/os-release /usr/lib/os-release

# ── Terra repo + Noctalia Shell ─────────────────────────────
# Noctalia Shell — via Terra repo (Fyra Labs). Terra's metadata has shown
# checksum-mismatch flakiness during builds — if the install fails here,
# don't just print a comment nobody will see; leave a marker so niello-init
# retries and warns the user at first login rather than silently booting
# into a blank/broken desktop.
RUN dnf install -y --skip-broken --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release && \
    dnf install -y --skip-broken noctalia-shell || \
    (echo "WARNING: noctalia-shell install failed at build time (Terra repo unavailable)" && \
     touch /etc/niello-noctalia-missing)

# ── Desktop Stack ────────────────────────────────────────────
# gtk2 — provides libgdk-x11-2.0.so.0 (GTK2 GDK X11 backend)
RUN dnf install -y \
    niri \
    alacritty \
    swaybg \
    earlyoom \
    okular \
    android-tools \
    gnome-keyring \
    pipewire \
    wireplumber \
    polkit \
    zsh \
    git \
    just \
    fuzzel \
    xdg-user-dirs \
    xdg-utils \
    newt \
    gtk2

# earlyoom — userspace OOM mitigator, kills the worst offender before the
# kernel OOM-killer has to step in under memory/swap pressure. Installed
# above; explicitly enabled here rather than relying on the package's
# default post-install state, since that's not guaranteed across Fedora
# packaging changes.
RUN systemctl enable earlyoom

# ananicy-cpp — auto-renices/ionices known CPU-hog processes (browsers,
# Electron apps, compilers, etc.) using rule sets, so a single runaway
# process doesn't peg a core and starve the rest of the (already
# CPU-constrained) Surface Laptop. Packaged via Terra (Fyra Labs), same
# repo already added above for noctalia-shell. Rules are NOT a separate
# RPM (there is no "ananicy-cpp-rules" package) — they're distributed
# upstream as a plain directory of .rules files, pulled from CachyOS's
# maintained rule set here.
RUN dnf install -y --skip-broken ananicy-cpp && \
    systemctl enable ananicy-cpp && \
    git clone --depth=1 https://github.com/CachyOS/ananicy-rules.git /tmp/ananicy-rules && \
    mkdir -p /etc/ananicy.d && \
    cp /tmp/ananicy-rules/*.rules /etc/ananicy.d/ && \
    rm -rf /tmp/ananicy-rules

# xremap — key remapping tool for Linux (https://github.com/xremap/xremap).
# Not packaged for Fedora — it's a Rust project distributed via cargo or
# prebuilt GitHub release binaries only. Installed here via cargo since a
# Rust toolchain is expected on this image; swap for a curl'd release
# binary if that's not baked in yet at this point in the build.
RUN dnf install -y cargo && \
    cargo install xremap --locked --root /usr/local && \
    dnf remove -y cargo || true

# ══════════════════════════════════════════════════════════════
# NETWORKING + BLUETOOTH — Noctalia is UI-only, needs real daemons
# ══════════════════════════════════════════════════════════════
RUN dnf install -y \
    NetworkManager \
    bluez \
    linux-firmware \
    microcode_ctl \
    thermald \
    qemu-guest-agent \
    irqbalance

# ── Direct firmware fetch for iwlwifi-so-a0-gf-a0 (Intel Wi-Fi 7 BE200)
# linux-firmware package does not ship this chip family at all (confirmed
# empty on live system) — files are in intel/iwlwifi/ subdirectory. Fetched
# from upstream as plain/uncompressed; Fedora's actual packaged firmware
# ships everything .xz-compressed (confirmed on a working Bluefin install
# with the same chip) — compress here to match exactly what a real,
# working Fedora firmware package produces.
# ══════════════════════════════════════════════════════════════
# WIRELESS/WWAN FIRMWARE — Fedora splits these OUT of the base
# linux-firmware package into separate sub-packages. The iwlwifi ucode
# files (including this exact chip's iwlwifi-so-a0-gf-a0-* family) live
# in iwlwifi-mvm-firmware/iwlwifi-mld-firmware, not linux-firmware itself
# — confirmed by diffing package lists against a known-working Bluefin
# install on identical hardware. wireless-regdb (regulatory.db) is
# likewise a separate package. Installing all of them rather than
# guessing exactly one, since they're small and this eliminates the
# ambiguity around which generation (mvm vs mld) this chip needs.
# ══════════════════════════════════════════════════════════════
RUN dnf install -y --skip-broken \
    iwlwifi-dvm-firmware \
    iwlwifi-mvm-firmware \
    iwlwifi-mld-firmware \
    iwlegacy-firmware \
    wireless-regdb

# Ensure network kernel modules are loaded at boot
RUN echo 'iwlwifi' >> /etc/modules-load.d/niello-networking.conf && \
    echo 'iwlmvm' >> /etc/modules-load.d/niello-networking.conf && \
    echo 'btusb' >> /etc/modules-load.d/niello-networking.conf

# ══════════════════════════════════════════════════════════════
# HARDWARE / NETWORK / MEDIA ENABLEMENT — found missing via direct
# package-list diff against a working Bluefin install on the same
# hardware. Curated: excludes anything GNOME/KDE-specific (Bluefin's own
# desktop-shell dependency tree) and systemd-networkd (would conflict
# with NetworkManager, which Niello already uses exclusively).
# ══════════════════════════════════════════════════════════════
RUN dnf install -y --skip-broken \
    zenity \
    plymouth \
    ModemManager \
    NetworkManager-bluetooth \
    NetworkManager-wifi \
    NetworkManager-wwan \
    NetworkManager-openvpn \
    NetworkManager-openconnect \
    NetworkManager-ssh \
    NetworkManager-vpnc \
    alsa-utils \
    alsa-ucm \
    avahi-tools \
    bluez-obexd \
    bolt \
    cups \
    cups-filters \
    cups-browsed \
    pciutils \
    geoclue2-libs \
    switcheroo-control \
    pipewire-utils \
    pipewire-gstreamer \
    ImageMagick \
    LibRaw \
    SDL3_image \
    SDL3_ttf \
    ffmpegthumbnailer \
    gstreamer1-plugins-good \
    gstreamer1-plugins-bad-free \
    gstreamer1-plugins-ugly-free \
    gstreamer1-plugin-libav \
    gstreamer1-plugin-dav1d \
    autoconf \
    automake \
    bison \
    flex \
    libtool

# ══════════════════════════════════════════════════════════════
# XDG DESKTOP PORTAL — required for Flatpak sandboxing, screen share
# ══════════════════════════════════════════════════════════════
RUN dnf install -y \
    xdg-desktop-portal \
    xdg-desktop-portal-wlr

# ══════════════════════════════════════════════════════════════
# FLATPAK — runtime + Flathub remote
# ══════════════════════════════════════════════════════════════
RUN dnf install -y flatpak

COPY config/systemd/niello-flatpak-setup.service /etc/systemd/system/niello-flatpak-setup.service
RUN systemctl enable niello-flatpak-setup 2>/dev/null || true

COPY config/systemd/niello-networking.service /etc/systemd/system/niello-networking.service
RUN systemctl enable niello-networking 2>/dev/null || true

# ══════════════════════════════════════════════════════════════
# FILE MANAGER — keyboard-driven, Rust, fits ecosystem until
# Corten's frontend (Corten Patina) exists
# yazi is not packaged in Fedora/RPMFusion/Terra — install prebuilt
# binary directly from upstream GitHub releases instead.
# ══════════════════════════════════════════════════════════════
RUN curl -fsSL -o /tmp/yazi.zip \
    "https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-gnu.zip" && \
    unzip -o /tmp/yazi.zip -d /tmp/yazi-extract && \
    install -m 755 /tmp/yazi-extract/*/yazi /usr/local/bin/yazi && \
    install -m 755 /tmp/yazi-extract/*/ya /usr/local/bin/ya && \
    rm -rf /tmp/yazi.zip /tmp/yazi-extract

# ══════════════════════════════════════════════════════════════
# GUI FILE MANAGER — SpaceFM (https://github.com/IgnorantGuru/spacefm),
# trying alongside yazi. NOTE: upstream has been unmaintained since ~2016
# — --skip-broken so the build doesn't hard-fail if Fedora 44 has dropped
# the package. Confirm after build whether this actually installed
# (`rpm -q spacefm`) rather than assuming --skip-broken silently worked.
# ══════════════════════════════════════════════════════════════
RUN dnf install -y --skip-broken spacefm

# ══════════════════════════════════════════════════════════════
# WEBKITGTK 6.0 — required by Iron (GTK4-native browser, built
# against the webkit6 crate / webkitgtk-6.0 API). This is a
# SEPARATE Fedora package from webkit2gtk4.1 (the GTK3-era API,
# already pulled in transitively by other packages) — Iron will
# fail at launch with "libwebkitgtk-6.0.so.4: cannot open shared
# object file" if only the 4.1 package is present.
# Baked into the base image here rather than left to rpm-ostree
# layering on the live system: layered packages require a reboot
# to take effect and are easy to forget/lose track of on an
# atomic system. Deliberately NOT --skip-broken — this is a hard
# requirement for Iron, not an optional extra, so the build
# should fail loudly if Fedora 44 ever renames/drops the package
# rather than silently shipping an image where Iron can't run.
# ══════════════════════════════════════════════════════════════
RUN dnf install -y webkitgtk6.0

# ══════════════════════════════════════════════════════════════
# BACKUP BROWSER — until Iron is complete
# ══════════════════════════════════════════════════════════════
RUN dnf install -y qutebrowser
# qutebrowser: vim-keybind, QtWebEngine-based. Alternative: Nyxt (Lisp/keyboard-driven,
# already configured with Noctalia theming + Linkding + 1Password CLI per prior work)

# ══════════════════════════════════════════════════════════════
# SCREENSHOT / CLIPBOARD / IDLE / LOCK
# ══════════════════════════════════════════════════════════════
RUN dnf install -y \
    grim \
    slurp \
    cliphist \
    swayidle \
    swaylock

# ══════════════════════════════════════════════════════════════
# USB AUTOMOUNT / IMAGE VIEWER
# ══════════════════════════════════════════════════════════════
RUN dnf install -y \
    udiskie \
    imv

# ══════════════════════════════════════════════════════════════
# FONTS — Nerd Font for Noctalia/Waybar icon glyphs
# ══════════════════════════════════════════════════════════════
RUN dnf install -y --skip-broken \
    google-noto-fonts-common \
    google-noto-sans-fonts

RUN mkdir -p /usr/share/fonts/nerd-fonts && \
    curl -fsSL -o /tmp/jbm.zip \
    https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip && \
    unzip -o /tmp/jbm.zip -d /usr/share/fonts/nerd-fonts && \
    rm /tmp/jbm.zip && \
    fc-cache -f

# ── CAC Smart Card Support ───────────────────────────────────
RUN dnf install -y --skip-broken \
    pcsc-lite \
    pcsc-lite-ccid \
    pcsc-tools \
    opensc \
    nss-tools \
    p11-kit \
    p11-kit-server \
    gnutls-utils \
    openssl \
    unzip && \
    mkdir -p /etc/pkcs11/modules && \
    printf 'module: /usr/lib64/pkcs11/opensc-pkcs11.so\ncritical: no\n' \
        > /etc/pkcs11/modules/opensc.module

RUN mkdir -p /etc/opensc && \
    printf 'app default {\n    card_drivers = cac;\n    force_card_driver = cac;\n}\n' \
    > /etc/opensc/opensc.conf.new && \
    if [ -f /etc/opensc/opensc.conf ]; then \
        grep -q "force_card_driver" /etc/opensc/opensc.conf || \
        cat /etc/opensc/opensc.conf >> /etc/opensc/opensc.conf.new; \
    fi && \
    mv /etc/opensc/opensc.conf.new /etc/opensc/opensc.conf

RUN mkdir -p /etc/udev/rules.d && \
    printf '# CAC/PCSC smart card readers\n' \
    'SUBSYSTEM=="usb", ATTR{idVendor}=="04e6", ATTR{idProduct}=="e003", MODE="0660", GROUP="pcscd"\n' \
    'SUBSYSTEM=="usb", ATTR{idVendor}=="04e6", ATTR{idProduct}=="e004", MODE="0660", GROUP="pcscd"\n' \
    'SUBSYSTEM=="usb", ATTR{idVendor}=="04e6", ATTR{idProduct}*="*scr*", MODE="0660", GROUP="pcscd"\n' \
    'SUBSYSTEM=="usb", ATTR{idVendor}=="0dc3", MODE="0660", GROUP="pcscd"\n' \
    'SUBSYSTEM=="usb", ATTR{idVendor}=="0b97", ATTR{idProduct}=="7762", MODE="0660", GROUP="pcscd"\n' \
    'SUBSYSTEM=="usb", ATTR{idVendor}=="0b97", ATTR{idProduct}=="7761", MODE="0660", GROUP="pcscd"\n' \
    'SUBSYSTEM=="usb", ATTR{idVendor}=="1a34", MODE="0660", GROUP="pcscd"\n' \
    'SUBSYSTEM=="usb", ATTR{idVendor}=="0a5c", MODE="0660", GROUP="pcscd"\n' \
    'KERNEL=="pcsc*", SUBSYSTEM=="usbmisc", MODE="0660", GROUP="pcscd"\n' \
    > /etc/udev/rules.d/92-cac-reader.rules && \
    printf 'SUBSYSTEM=="usb", ENV{ID_SMARTCARD}=="1", MODE="0660", GROUP="pcscd"\n' \
    >> /etc/udev/rules.d/92-cac-reader.rules

RUN systemctl enable pcscd.service && \
    systemctl enable pcscd.socket 2>/dev/null || true

RUN mkdir -p /etc/pki/nssdb && \
    if [ ! -f /etc/pki/nssdb/cert9.db ]; then \
        certutil -d sql:/etc/pki/nssdb -N --empty-password; \
    fi && \
    chmod 644 /etc/pki/nssdb/* && \
    if ! modutil -dbdir sql:/etc/pki/nssdb -list 2>/dev/null | grep -q "OpenSC"; then \
        modutil -dbdir sql:/etc/pki/nssdb -add "OpenSC" \
            -libfile /usr/lib64/opensc-pkcs11.so \
            -mechanisms FRIENDLY 2>/dev/null || true; \
    fi && \
    chown -R root:root /etc/pki/nssdb

RUN printf 'export NSS_USE_SHARED_DB=1\nexport PKCS11_MODULE=/usr/lib64/opensc-pkcs11.so\n' \
    > /etc/profile.d/niello-cac.sh && \
    chmod +x /etc/profile.d/niello-cac.sh

# ── Shell Tooling + Python ───────────────────────────────────
RUN dnf install -y \
    fzf \
    eza \
    bat \
    zoxide \
    btop \
    fd-find \
    ripgrep \
    python3 \
    python3-pip \
    python3-virtualenv \
    tesseract \
    tesseract-langpack-eng \
    poppler-utils \
    odt2txt \
    npm \
    dust \
    procs \
    starship \
    uutils-coreutils \
    vim-common

RUN sed -i 's|^SHELL=.*|SHELL=/bin/zsh|' /etc/default/useradd 2>/dev/null || \
    echo 'SHELL=/bin/zsh' >> /etc/default/useradd

# ── Oh-My-Zsh + Powerlevel10k + Plugins ────────────────────
RUN git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /etc/skel/.oh-my-zsh

RUN git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
    /etc/skel/.oh-my-zsh/custom/themes/powerlevel10k

RUN git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git \
        /etc/skel/.oh-my-zsh/custom/plugins/zsh-autosuggestions && \
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git \
        /etc/skel/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting && \
    git clone --depth=1 https://github.com/zsh-users/zsh-completions.git \
        /etc/skel/.oh-my-zsh/custom/plugins/zsh-completions

COPY config/zsh/p10k.zsh /etc/skel/.p10k.zsh
COPY config/zsh/zshrc    /etc/skel/.zshrc

# ── just recipes ─────────────────────────────────────────────
COPY config/just/justfile /etc/skel/justfile

# ── bootc Update Config ──────────────────────────────────────
RUN mkdir -p /etc/systemd/system/bootc-fetch-apply-updates.service.d && \
    printf '[Service]\nExecStart=\nExecStart=/usr/bin/bootc upgrade --quiet\n' \
    > /etc/systemd/system/bootc-fetch-apply-updates.service.d/stage-only.conf

# ══════════════════════════════════════════════════════════════
# BOOT-TIME bootc UPGRADE CHECK — replaces nightly timer
# ══════════════════════════════════════════════════════════════
COPY config/systemd/niello-boot-upgrade.service /etc/systemd/system/niello-boot-upgrade.service
COPY config/systemd/niello-boot-upgrade.sh /usr/local/bin/niello-boot-upgrade.sh
RUN chmod +x /usr/local/bin/niello-boot-upgrade.sh && \
    systemctl enable niello-boot-upgrade.service

# Force greetd to wait on our upgrade check via drop-in override
RUN mkdir -p /etc/systemd/system/greetd.service.d && \
    printf '[Unit]\nAfter=niello-boot-upgrade.service\nWants=niello-boot-upgrade.service\n' \
    > /etc/systemd/system/greetd.service.d/10-niello-upgrade.conf

# ── Homebrew Update Timer ─────────────────────────────────────
COPY config/systemd/brew-update.service /etc/systemd/system/brew-update.service
COPY config/systemd/brew-update.timer  /etc/systemd/system/brew-update.timer
RUN systemctl enable brew-update.timer

# ── Build deps: noctalia-greeter (meson + ninja) ───────────────────────────
RUN dnf install -y --skip-broken \
    meson \
    ninja-build \
    cmake \
    gcc-c++ \
    wlroots-devel \
    libinput-devel \
    libEGL-devel \
    mesa-libGLES-devel \
    freetype-devel \
    fontconfig-devel \
    cairo-devel \
    pango-devel \
    harfbuzz-devel \
    libxkbcommon-devel \
    glib2-devel \
    libwebp-devel \
    librsvg2-devel \
    tomlplusplus-devel \
    json-devel \
    greetd \
    dbus-daemon \
    polkit \
    pkgconf-pkg-config \
    wayland-devel \
    wayland-protocols-devel \
    just

# ── Vendor stb headers (no distro package exists — stb is intentionally
# header-only, drop-in code, never packaged with pkg-config) ──────────────
RUN mkdir -p /usr/include/stb && \
    curl -fsSL -o /usr/include/stb/stb_image_resize2.h \
    https://raw.githubusercontent.com/nothings/stb/master/stb_image_resize2.h

# ── Clone + build noctalia-greeter (Eldritch theme) ────────────────────────
RUN git clone --depth=1 \
    https://github.com/noctalia-dev/noctalia-greeter.git \
    /tmp/noctalia-greeter && \
    cd /tmp/noctalia-greeter && \
    meson setup build --prefix=/usr && \
    ninja -C build && \
    ninja -C build install && \
    rm -rf /tmp/noctalia-greeter

# ── Runtime deps: noctalia-greeter ────────────────────────────────────────
RUN dnf install -y --skip-broken \
    mesa-libGLES \
    libxkbcommon \
    cairo \
    pango \
    harfbuzz \
    libwebp \
    librsvg2 \
    greetd || true

# ── Noctalia config ──────────────────────────────────────────
RUN mkdir -p /etc/skel/.config/noctalia /etc/skel/.cache/noctalia
COPY config/noctalia/ /etc/skel/.config/noctalia/

# ── greetd + noctalia-greeter setup ──────────────────────────────────────
RUN dnf install -y --skip-broken greetd || true && \
    mkdir -p /etc/greetd

# Create greeter user dirs
RUN printf 'u greeter - "Greeter" /var/lib/greeter /usr/bin/nologin\nm greeter video\nm greeter input\nm greeter render\n' \
        > /usr/lib/sysusers.d/greeter.conf && \
    printf 'd /var/lib/greeter 0750 greeter greeter\n' \
        > /usr/lib/tmpfiles.d/greeter.conf

# Create /var/lib/greeter/noctalia-greeter/ (owned by greeter user)
RUN mkdir -p /var/lib/greeter/noctalia-greeter && \
    chown 955:955 /var/lib/greeter/noctalia-greeter && \
    chmod 0755 /var/lib/greeter/noctalia-greeter

# greeter.toml with Eldritch + HiDPI (in greeter user's dir)
RUN printf '[appearance]\n\n[output]\nscale = 1.5\n' > /var/lib/greeter/noctalia-greeter/greeter.toml

# PAM for greetd
RUN printf 'session required pam_systemd.so\n' >> /etc/pam.d/greetd

# greetd config: use noctalia-greeter-session wrapper with correct state dir
RUN printf '[terminal]\nvt = 1\n\n[default_session]\ncommand = "/bin/bash /etc/greetd/noctalia-greeter-launch.sh"\nuser = "greeter"\n' > /etc/greetd/config.toml

COPY config/greetd/noctalia-greeter-launch.sh /etc/greetd/noctalia-greeter-launch.sh
RUN chmod +x /etc/greetd/noctalia-greeter-launch.sh

RUN systemctl disable gdm 2>/dev/null || true
RUN systemctl enable greetd 2>/dev/null || true

# ── nirinit ──────────────────────────────────────────────────
RUN curl -fsSL \
    https://github.com/amaanq/nirinit/releases/download/v0.2.2/nirinit-x86_64-linux.tar.gz \
    -o /tmp/nirinit.tar.gz && \
    mkdir -p /tmp/nirinit-extract && \
    tar xzf /tmp/nirinit.tar.gz -C /tmp/nirinit-extract && \
    NIRINIT_PATH=$(find /tmp/nirinit-extract -type f -name nirinit 2>/dev/null | head -1) && \
    if [[ -n "$NIRINIT_PATH" ]]; then \
        mv "$NIRINIT_PATH" /usr/local/bin/nirinit && \
        chmod +x /usr/local/bin/nirinit; \
    fi && \
    rm -rf /tmp/nirinit*

# ══════════════════════════════════════════════════════════════
# FIRST-BOOT USER CREATION WIZARD
# Root is locked (no password login). On first boot, if no real user
# exists yet, prompt to create one with sudo/wheel access before greetd
# starts. Safe to re-run — no-ops once a user exists or it has completed.
# Users can be created afterward as normal via `useradd`/`sudo useradd`.
# ══════════════════════════════════════════════════════════════
COPY config/niello-init/niello-firstboot.sh /usr/local/bin/niello-firstboot.sh
RUN chmod +x /usr/local/bin/niello-firstboot.sh

COPY config/systemd/niello-firstboot.service /etc/systemd/system/niello-firstboot.service
RUN systemctl enable niello-firstboot.service 2>/dev/null || true

# ── niello-init bootstrap ─────────────────────────────────────
COPY config/niello-init/niello-init /tmp/niello-init
RUN mkdir -p /usr/local/bin && \
    install -m 755 /tmp/niello-init /usr/local/bin/niello-init && \
    rm -f /tmp/niello-init

# niello-init is triggered via niello-init.service (login) and
# niello-init.timer (midnight nightly) — see below. Previously also
# triggered from /etc/zshenv and .zshrc, but zshenv fires on EVERY zsh
# invocation (every subshell, command substitution, prompt-theme helper —
# not just interactive logins), which caused many overlapping concurrent
# runs racing on a non-atomic lock check and at least one observed
# "Argument list too long" crash. Removed in favor of the systemd triggers
# only, which fire at controlled, predictable points.

COPY config/profile.d/PS1-fix.sh /etc/profile.d/PS1-fix.sh
RUN chmod +x /etc/profile.d/PS1-fix.sh

COPY config/niello-init/set-defaults.sh /etc/profile.d/niello-defaults.sh
RUN chmod +x /etc/profile.d/niello-defaults.sh

RUN mkdir -p /etc/skel/.config/systemd/user /etc/skel/.local/bin
COPY config/systemd/niello-init.service /etc/skel/.config/systemd/user/niello-init.service
COPY config/systemd/user/niello-init.timer /etc/skel/.config/systemd/user/niello-init.timer

# Bake the enablement directly into skel — this is what `systemctl --user
# enable` actually does under the hood (create these symlinks). Without
# this, nothing starts niello-init.service on its own on a fresh account,
# since the self-enable logic lives inside the script itself, which
# nothing then triggers in the first place (chicken-and-egg).
RUN mkdir -p /etc/skel/.config/systemd/user/default.target.wants \
             /etc/skel/.config/systemd/user/timers.target.wants && \
    ln -sf ../niello-init.service \
        /etc/skel/.config/systemd/user/default.target.wants/niello-init.service && \
    ln -sf ../niello-init.timer \
        /etc/skel/.config/systemd/user/timers.target.wants/niello-init.timer
COPY config/systemd/ollama.service /etc/skel/.config/systemd/user/ollama.service
COPY config/systemd/user/niello-keyring.service /etc/skel/.config/systemd/user/niello-keyring.service
COPY config/cac/cac-setup /etc/skel/.local/bin/cac-setup
RUN chmod +x /etc/skel/.local/bin/cac-setup

# niello-init-boot.service deliberately removed — it ran niello-init as
# root, before display-manager.service (before any graphical session or
# XDG_RUNTIME_DIR setup), via fragile nested bash -c string interpolation,
# as a third uncoordinated trigger alongside niello-init.service and
# niello-init.timer. Fully redundant with those two, and the likely
# source of an observed "Argument list too long" crash.

# ── niri session + wayland sessions ──────────────────────────
RUN mkdir -p /usr/share/wayland-sessions
COPY config/wayland-sessions/niri.desktop /usr/share/wayland-sessions/niri.desktop
COPY config/niri/ /etc/skel/.config/niri/

# ── GTK theming (Eldritch) ────────────────────────────────────
RUN mkdir -p /etc/skel/.config/gtk-3.0 /etc/skel/.config/gtk-4.0
COPY config/gtk-3.0/settings.ini /etc/skel/.config/gtk-3.0/settings.ini
COPY config/gtk-4.0/settings.ini /etc/skel/.config/gtk-4.0/settings.ini

# ── Gaming (conditional) ─────────────────────────────────────
ARG GAMING=false
RUN if [ "$GAMING" = "true" ]; then \
        echo "GAMING=true — installing gaming packages..."; \
        dnf install -y --skip-broken \
            gamemode gamescope mangohud goverlay \
            vulkan-tools vulkan-loader mesa-vulkan-drivers \
            mesa-dri-drivers libva libva-utils mesa-va-drivers \
            steam-devices \
            mesa-vdpau-drivers-freeworld || true; \
        # wine and lutris removed — lutris ships its own Wine; install lutris as Flatpak instead
        dnf install -y --skip-broken akmod-nvidia xorg-x11-drv-nvidia-cuda || true; \
        printf '# Gaming tweaks\nvm.max_map_count=2147483642\nkernel.split_lock_mitigate=0\n' > /etc/sysctl.d/99-gaming.conf; \
        groupadd -f gamemode; \
        touch /etc/niello-gaming; \
        printf '#!/bin/sh\nexport __NV_PRIME_RENDER_OFFLOAD=1\nexport __GLX_VENDOR_LIBRARY_NAME=nvidia\nexport VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.x86_64.json:/usr/share/vulkan/icd.d/nvidia_icd.i686.json\n' > /etc/profile.d/niello-nvidia-gaming.sh; \
        if [ -f /usr/lib64/libnvidia-vulkan.so.* ]; then \
            NVIDIA_VULKAN_LIB=$(ls /usr/lib64/libnvidia-vulkan.so.* 2>/dev/null | head -1); \
            NVIDIA_VULKAN_VERSION=$(echo "$NVIDIA_VULKAN_LIB" | sed 's/.*libnvidia-vulkan.so.\(.*\)/\1/'); \
            mkdir -p /etc/vulkan/icd.d /usr/share/vulkan/icd.d; \
            printf '{\n    "file_format_version": "1.0.0",\n    "ICD": {\n        "library_path": "/usr/lib64/libnvidia-vulkan.so.%s",\n        "api_version": "1.3.293",\n        "is_portability_driver": false\n    }\n}\n' "$NVIDIA_VULKAN_VERSION" > /etc/vulkan/icd.d/nvidia_icd.x86_64.json; \
            cp /etc/vulkan/icd.d/nvidia_icd.x86_64.json /usr/share/vulkan/icd.d/; \
            echo "Created NVIDIA Vulkan ICD for libnvidia-vulkan.so.${NVIDIA_VULKAN_VERSION}"; \
        fi; \
    fi

# Corten is installed at first login via niello-init (brew_ensure "corten"),
# not baked into the image — Homebrew categorically refuses to run as root,
# and building it here duplicates what niello-init already does as the
# real logged-in user with a real $HOME. See niello-init's Homebrew section.

# ── Copy udiskie user service ──────────────────────────────────────
COPY config/systemd/user/niello-udiskie.service /etc/systemd/user/

# ══════════════════════════════════════════════════════════════
# SELINUX RELABEL — files placed via curl/install (firmware, yazi, ya,
# nirinit) don't get correct SELinux contexts the way dnf-installed files
# do. Relabel explicitly so they aren't silently denied under enforcing.
# ══════════════════════════════════════════════════════════════
# Manually-placed binaries (yazi, etc.) still need a relabel pass — RPM-
# installed files (including the firmware packages above) get correct
# SELinux contexts automatically and don't need this.
RUN restorecon -Rv /usr/local/bin 2>/dev/null || true

# ── Cleanup ─────────────────────────────────────────────────
RUN dnf clean all && rm -rf /var/cache/dnf/*
