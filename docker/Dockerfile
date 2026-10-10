# Cloud Phone: real Android emulator (Google Play image) streamed to the browser.
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG CMDLINE_TOOLS_VERSION=11076708
ARG ANDROID_API=34
ARG SYSTEM_IMAGE="system-images;android-${ANDROID_API};google_apis_playstore;x86_64"

ENV ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_AVD_HOME=/data/avd \
    SYSTEM_IMAGE=${SYSTEM_IMAGE} \
    DISPLAY=:0 \
    LANG=C.UTF-8
ENV PATH=${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/emulator:${ANDROID_SDK_ROOT}/platform-tools:${PATH}

# Java for sdkmanager, X server + VNC + noVNC for the browser view,
# and the shared libraries the Android emulator needs.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip openjdk-17-jre-headless \
        supervisor xvfb x11vnc novnc websockify procps \
        libgl1 libgl1-mesa-dri libegl1 libpulse0 libnss3 libasound2 \
        libxcomposite1 libxcursor1 libxi6 libxtst6 libxkbfile1 libxdamage1 \
        libxrandr2 libdbus-1-3 libxkbcommon-x11-0 libx11-xcb1 libfontconfig1 \
        libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 \
        libxcb-render-util0 libxcb-shape0 libxcb-xinerama0 libxcb-xfixes0 \
        libxcb-xkb1 libxcb-cursor0 \
    && rm -rf /var/lib/apt/lists/*

# Android SDK: command-line tools, emulator, platform-tools and the Play Store image.
RUN mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools \
    && curl -fsSL -o /tmp/cmdline-tools.zip \
        "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip" \
    && unzip -q /tmp/cmdline-tools.zip -d ${ANDROID_SDK_ROOT}/cmdline-tools \
    && mv ${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools ${ANDROID_SDK_ROOT}/cmdline-tools/latest \
    && rm /tmp/cmdline-tools.zip \
    && yes | sdkmanager --licenses > /dev/null \
    && sdkmanager --install "platform-tools" "emulator" "${SYSTEM_IMAGE}" \
    && rm -rf /root/.android/cache

COPY supervisord.conf /etc/supervisor/conf.d/cloudphone.conf
COPY start-emulator.sh /usr/local/bin/start-emulator.sh
COPY start-vnc.sh /usr/local/bin/start-vnc.sh
COPY index.html /usr/share/novnc/index.html
RUN chmod +x /usr/local/bin/start-emulator.sh /usr/local/bin/start-vnc.sh

VOLUME ["/data"]
EXPOSE 6080

HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=3 \
    CMD [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]

CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
