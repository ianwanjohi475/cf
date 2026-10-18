#!/bin/bash
# Gives the cloud phone a live camera.
#
# Loads a virtual webcam named CloudPhoneCam into the kernel. The phone uses it as its camera, and
# the picture comes from the webcam of whatever device you open the phone page on.
#
# Native Ubuntu: installs the v4l2loopback driver from apt.
# Ubuntu on WSL: builds v4l2loopback against the exact WSL kernel you run
# (one-time, about 20-60 minutes). Your Windows/WSL settings are not changed.
set -e
cd "$(dirname "$0")"

MOD_OPTS=(devices=1 video_nr=42 card_label=CloudPhoneCam exclusive_caps=1)
DATA_DIR="${HOME}/.local/share/cloudphone"
WSL_DIR="${DATA_DIR}/$(uname -r)"

if ls /sys/class/video4linux/*/max_openers > /dev/null 2>&1; then
    echo "Camera device is ready. Run: ./phone.sh start"
    exit 0
fi

if modinfo v4l2loopback > /dev/null 2>&1; then
    echo "Your system already includes the camera driver - no build needed."
    exec ./phone.sh camera-on
fi

if ! grep -qi microsoft /proc/version; then
    # ---- Native Ubuntu ----
    if ! modinfo v4l2loopback > /dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y v4l2loopback-dkms "linux-headers-$(uname -r)"
    fi
    sudo modprobe v4l2loopback "${MOD_OPTS[@]}"
    echo "Camera device is ready. Run: ./phone.sh start"
    exit 0
fi

# ---- Ubuntu on WSL ----
if [ ! -f "${WSL_DIR}/v4l2loopback.ko" ]; then
    KREL="$(uname -r)"            # e.g. 6.6.87.2-microsoft-standard-WSL2
    TAG="linux-msft-wsl-${KREL%%-*}"
    BUILD="${HOME}/.cache/cloudphone-kernel"
    echo "Building the virtual camera driver for WSL kernel ${KREL}."
    echo "This is a one-time build and takes 20-60 minutes. Leave this window open."
    sleep 3

    sudo apt-get update
    sudo apt-get install -y build-essential flex bison libssl-dev libelf-dev bc dwarves \
        python3 cpio git kmod

    mkdir -p "${BUILD}"
    if [ ! -d "${BUILD}/linux/.git" ]; then
        rm -rf "${BUILD}/linux"
        git clone --depth 1 --branch "${TAG}" https://github.com/microsoft/WSL2-Linux-Kernel.git "${BUILD}/linux" || {
            echo "Could not download kernel source tag ${TAG}."
            echo "Update WSL (in PowerShell: wsl --update), then run this again."
            exit 1
        }
    fi
    if [ ! -d "${BUILD}/v4l2loopback/.git" ]; then
        git clone --depth 1 https://github.com/umlaeute/v4l2loopback.git "${BUILD}/v4l2loopback"
    fi

    cd "${BUILD}/linux"
    # Same configuration as the running kernel, so the driver matches it exactly.
    if [ -r /proc/config.gz ]; then
        zcat /proc/config.gz > .config
    else
        cp arch/x86/configs/config-wsl .config
    fi
    scripts/config --module MEDIA_SUPPORT --enable MEDIA_CAMERA_SUPPORT --module VIDEO_DEV
    # The driver only loads if its version matches the running kernel exactly.
    # Builds from this source add "+" to the version unless LOCALVERSION= is
    # given; some WSL kernels have the "+" and some don't, so match whichever runs.
    if [[ "${KREL}" == *+ ]]; then LV=(); else LV=(LOCALVERSION=); fi
    make "${LV[@]}" olddefconfig > /dev/null
    if [ "$(make -s "${LV[@]}" kernelrelease)" != "${KREL}" ]; then
        echo "Kernel source version $(make -s "${LV[@]}" kernelrelease) does not match running ${KREL}."
        exit 1
    fi
    make "${LV[@]}" -j"$(nproc)"
    make -C "${BUILD}/v4l2loopback" KERNELRELEASE="${KREL}" KERNEL_DIR="${BUILD}/linux"

    mkdir -p "${WSL_DIR}"
    cp "${BUILD}/v4l2loopback/v4l2loopback.ko" "${WSL_DIR}/"
    # Keep the media modules too, in case this WSL install doesn't ship them.
    cp drivers/leds/led-class.ko drivers/media/mc/mc.ko drivers/media/v4l2-core/videodev.ko "${WSL_DIR}/"
    cd - > /dev/null
    rm -rf "${BUILD}"
fi

./phone.sh camera-on
