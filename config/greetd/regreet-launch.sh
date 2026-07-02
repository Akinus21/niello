#!/usr/bin/env bash
# greetd regreet launcher for niello
# Starts weston DRM backend with NVIDIA GPU, then runs regreet

set -e

export XDG_RUNTIME_DIR=/run/user/$(id -u greeter)
mkdir -p "$XDG_RUNTIME_DIR"

# NVIDIA environment — needed because niello starts from minimal fedora-bootc
# without the ublue hardware enablement layer
if [ -f /etc/vulkan/icd.d/nvidia_icd.x86_64.json ]; then
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.x86_64.json
fi

# Intel/AMD Vulkan fallback (for igpu)
if [ -f /usr/share/vulkan/icd.d/intel_icd.x86_64.json ]; then
    export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-}:/usr/share/vulkan/icd.d/intel_icd.x86_64.json"
fi

# Ensure libGLdispatch uses NVIDIA
export LIBGL_ALWAYS_SOFTWARE=0

# Log both stdout and stderr to greeter log
exec >/var/lib/greeter/greeter.log 2>&1

echo "=== regreet-launch.sh started at $(date) ==="
echo "NVIDIA ICD: ${VK_ICD_FILENAMES:-not set}"
echo "GLX vendor: ${__GLX_VENDOR_LIBRARY_NAME:-not set}"

# Find the render node - prefer NVIDIA
RENDER_NODE=$(ls -la /dev/dri/render* 2>/dev/null | head -5)
echo "Available render nodes: $RENDER_NODE"

# Start weston with DRM backend in kiosk mode
# --shell=kiosk: fullscreen single-app mode (regreet)
# --backend=drm: direct hardware access
weston --backend=drm --shell=kiosk \
    --log=/var/lib/greeter/weston.log \
    -- modules=shared_egl_vendor \
    &

WESTON_PID=$!

echo "weston started with PID $WESTON_PID"
sleep 2

# Check if weston is still running
if ! kill -0 $WESTON_PID 2>/dev/null; then
    echo "ERROR: weston exited early. Check weston.log:"
    cat /var/lib/greeter/weston.log
    exit 1
fi

# Run regreet
echo "Starting regreet with WAYLAND_DISPLAY=wayland-1"
WAYLAND_DISPLAY=wayland-1 regreet -c /etc/greetd/regreet.css
REGREET_EXIT=$?

echo "regreet exited with code $REGREET_EXIT"
kill $WESTON_PID 2>/dev/null || true
exit $REGREET_EXIT
