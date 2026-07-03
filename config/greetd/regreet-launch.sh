#!/usr/bin/env bash
# greetd regreet launcher for niello
# Starts weston DRM backend with NVIDIA GPU, then runs regreet
# VERSION: debug-enabled for testing

# ULTRA-EARLY DEBUG: echo to both log AND stdout/TTY
exec >/var/lib/greeter/greeter.log 2>&1
set -x
echo "=========================================="
echo "=== regreet-launch.sh BOOT $(date) ==="
echo "=========================================="
echo "UID: $(id -u greeter)"
echo "USER: $(whoami)"
echo "PWD: $(pwd)"
echo "XDG_RUNTIME_DIR: ${XDG_RUNTIME_DIR:-not set}"
echo "WAYLAND_DISPLAY: ${WAYLAND_DISPLAY:-not set}"
echo "DISPLAY: ${DISPLAY:-not set}"
echo "NVIDIA ICD check: $([ -f /etc/vulkan/icd.d/nvidia_icd.x86_64.json ] && echo 'EXISTS' || echo 'MISSING')"
echo "=========================================="

export XDG_RUNTIME_DIR=/run/user/$(id -u greeter)
mkdir -p "$XDG_RUNTIME_DIR"
echo "Created XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"

# Show all environment variables for debugging
echo "=== FULL ENV ==="
env | sort
echo "=== END ENV ==="

# NVIDIA environment — needed because niello starts from minimal fedora-bootc
# without the ublue hardware enablement layer
if [ -f /etc/vulkan/icd.d/nvidia_icd.x86_64.json ]; then
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.x86_64.json
    echo "NVIDIA ICD FOUND - enabled NVIDIA environment"
else
    echo "NVIDIA ICD MISSING - skipping NVIDIA env vars"
fi

# Intel/AMD Vulkan fallback (for igpu)
if [ -f /usr/share/vulkan/icd.d/intel_icd.x86_64.json ]; then
    export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-}:/usr/share/vulkan/icd.d/intel_icd.x86_64.json"
    echo "Intel ICD found and added"
fi

# Show Vulkan ICD files present
echo "=== Vulkan ICD files ==="
ls -la /etc/vulkan/icd.d/ 2>/dev/null || echo "No /etc/vulkan/icd.d/"
ls -la /usr/share/vulkan/icd.d/ 2>/dev/null | head -20 || echo "No /usr/share/vulkan/icd.d/"
echo "VK_ICD_FILENAMES=${VK_ICD_FILENAMES:-not set}"

# Ensure libGLdispatch uses hardware
export LIBGL_ALWAYS_SOFTWARE=0

# List DRM devices
echo "=== DRM devices ==="
ls -la /dev/dri/
echo "--- card* devices ---"
ls -la /dev/dri/card* 2>/dev/null || echo "No card* devices"
echo "--- render* devices ---"
ls -la /dev/dri/render* 2>/dev/null || echo "No render* devices"
echo "--- card0 status ---"
cat /sys/class/drm/card0/status 2>/dev/null || echo "No card0/status"
cat /sys/class/drm/card0/modes 2>/dev/null || echo "No card0/modes"

# List nvidia devices if present
echo "=== NVIDIA devices ==="
ls -la /dev/nvidia* 2>/dev/null || echo "No nvidia devices found"

# Weston version
echo "=== weston version ==="
weston --version 2>&1 || echo "weston not found"

# Start weston with DRM backend in kiosk mode
echo "=== Starting weston ==="
weston --backend=drm --shell=kiosk \
    --log=/var/lib/greeter/weston.log \
    &

WESTON_PID=$!
echo "weston started with PID $WESTON_PID"
sleep 3

# Check if weston is still running
if ! kill -0 $WESTON_PID 2>/dev/null; then
    echo "ERROR: weston exited early!"
    echo "=== weston log ==="
    cat /var/lib/greeter/weston.log 2>/dev/null || echo "No weston log"
    echo "=== dmesg | tail 20 ==="
    dmesg | tail -20
    exit 1
fi

echo "weston is running (PID $WESTON_PID)"
echo "=== current weston log ==="
cat /var/lib/greeter/weston.log 2>/dev/null || echo "No weston log"

# Run regreet
echo "=== Starting regreet ==="
echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}, using wayland-1"
WAYLAND_DISPLAY=wayland-1 regreet -c /etc/greetd/regreet.toml 2>&1
REGREET_EXIT=$?

echo "regreet exited with code $REGREET_EXIT"
kill $WESTON_PID 2>/dev/null || true
echo "=== greeter script complete ==="
exit $REGREET_EXIT