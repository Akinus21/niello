FROM quay.io/fedora/fedora-bootc:44

# ── Container Registry Policy (secure by default) ──────────────
RUN printf '%s\n' \
  '{"default":[{"type":"reject"}],' \
  '"transports":{"docker":{"quay.io":[{"type":"insecureAcceptAnything"}],' \
  '"registry.fedoraproject.org":[{"type":"insecureAcceptAnything"}],' \
  '"download.rpmfusion.org":[{"type":"insecureAcceptAnything"}],' \
  '"mirrors.rpmfusion.org":[{"type":"insecureAcceptAnything"}],' \
  '"github.com":[{"type":"insecureAcceptAnything"}],' \
  '"raw.githubusercontent.com":[{"type":"insecureAcceptAnything"}],' \
  '"objects.githubusercontent.com":[{"type":"insecureAcceptAnything"}],' \
  '"pkg.osdn.net":[{"type":"insecureAcceptAnything"}],' \
  '"src.fedoraproject.org":[{"type":"insecureAcceptAnything"}]},' \
  '"containers-storage":{"docker":[{"type":"insecureAcceptAnything"}]}}}' \
  > /etc/containers/policy.json

# ── RPMFusion + Full Codec Stack (uBlue hardware enablement) ───
RUN dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm \
    && dnf install -y --skip-broken \
    mesa-va-drivers-freeworld \
    ffmpeg \
    pipewire-codec-aptx \
    && dnf clean all

# ── Metadata ────────────────────────────────────────────────
LABEL org.opencontainers.image.title="Niello"
LABEL org.opencontainers.image.description="Immutable Fedora Atomic — Niri + Noctalia + Rust toolchain"
LABEL org.opencontainers.image.source="https://github.com/Akinus21/niello"
LABEL org.opencontainers.image.vendor="akinus"

# ── OS Identity ──────────────────────────────────────────────
COPY usr/lib/os-release /usr/lib/os-release

# ── Terra repo + Noctalia Shell ─────────────────────────────
# Noctalia Shell — via Terra repo (Fyra Labs)
RUN dnf install -y --skip-broken --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release && \
    dnf install -y --skip-broken noctalia-shell || echo "Terra repo unavailable — install noctalia-shell at runtime"

# ── Desktop Stack ────────────────────────────────────────────
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
    network-manager-applet \
    zsh \
    git \
    just \
    waybar \
    fuzzel \
    xdg-user-dirs \
    xdg-utils

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
    uutils-coreutils

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

COPY config/systemd/bootc-nightly-reboot.service /etc/systemd/system/bootc-nightly-reboot.service
COPY config/systemd/bootc-nightly-reboot.timer   /etc/systemd/system/bootc-nightly-reboot.timer

RUN systemctl enable bootc-nightly-reboot.timer

# ── Homebrew Update Timer ─────────────────────────────────────
COPY config/systemd/brew-update.service /etc/systemd/system/brew-update.service
COPY config/systemd/brew-update.timer  /etc/systemd/system/brew-update.timer
RUN systemctl enable brew-update.timer

# ── Build deps: noctalia-greeter (meson + ninja) ───────────────────────────
RUN dnf install -y --skip-broken \
    meson \
    ninja-build \
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
    greetd \
    dbus-daemon \
    polkit \
    pkgconf-pkg-config \
    wayland-devel \
    wayland-protocols-devel \
    just

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

# ── niello-init bootstrap ─────────────────────────────────────
COPY config/niello-init/niello-init /tmp/niello-init
RUN mkdir -p /usr/local/bin && \
    install -m 755 /tmp/niello-init /usr/local/bin/niello-init && \
    rm -f /tmp/niello-init

RUN echo '[[ -x /usr/local/bin/niello-init ]] && /usr/local/bin/niello-init' >> /etc/zshenv
RUN echo '[[ -x /usr/local/bin/niello-init ]] && /usr/local/bin/niello-init' >> /etc/skel/.zshrc

RUN mkdir -p /etc/skel/.config/systemd/user /etc/skel/.local/bin
COPY config/systemd/niello-init.service /etc/skel/.config/systemd/user/niello-init.service
COPY config/systemd/ollama.service /etc/skel/.config/systemd/user/ollama.service
COPY config/systemd/user/niello-keyring.service /etc/skel/.config/systemd/user/niello-keyring.service
COPY config/cac/cac-setup /etc/skel/.local/bin/cac-setup
RUN chmod +x /etc/skel/.local/bin/cac-setup

COPY config/systemd/niello-init-boot.service /etc/systemd/system/niello-init-boot.service
RUN systemctl enable niello-init-boot 2>/dev/null || true

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
        dnf install -y --skip-broken wine winetricks || true; \
        dnf install -y --skip-broken lutris || true; \
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

# ── Cleanup ─────────────────────────────────────────────────
RUN dnf clean all && rm -rf /var/cache/dnf/*
