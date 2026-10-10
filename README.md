# Cloud Phone

A real Android 14 phone running on your Ubuntu PC, shown in your web browser.
It uses Google's official **Google Play** emulator image (the one Android Studio uses),
so you can sign in with your Google account and install apps from the Play Store,
such as Chrome, WhatsApp and TikTok. Apps, accounts and files are kept between restarts.

```
 Browser  ──►  web server + noVNC (port 6080)  ──►  VNC  ──►  Android emulator (KVM)  [Docker container]
```

## Requirements

- Ubuntu 20.04 / 22.04 / 24.04, 64-bit Intel or AMD CPU
- Virtualization (Intel VT-x / AMD-V) **enabled in BIOS**
- 8 GB RAM or more (the phone uses 4 GB), about 15 GB free disk space

## Install and run

```bash
git clone <this repo> cloudphone && cd cloudphone
./setup.sh          # checks KVM, installs Docker (log out/in if it asks)
./phone.sh start    # first run downloads ~2 GB, takes a while
```

Wait 1–3 minutes for Android to boot (`./phone.sh logs` shows `Phone booted`), then open:

**http://localhost:6080**

## Install apps from the Play Store

1. In the phone, open **Play Store** and sign in with your Google account.
2. Search for **Chrome** (or any app) and tap **Install**.

Use the mouse to tap and swipe, and your PC keyboard to type.
On-screen Back/Home/Recents buttons are at the bottom of the phone.
The emulator's side toolbar has volume, rotate and power buttons.

You can also install an APK file directly: `./phone.sh install myapp.apk`

## Send photos and videos to the phone

The bar above the phone has **Upload photo / video** and **Upload file** buttons
(you can also drag files onto the bar). Photos and videos go to the phone's gallery
(`DCIM/Uploads`), and other files go to `Download`.

Then, when an app or website asks for a picture or video:

- Choose **Gallery**, **Photos**, **Files** or **Browse** (not **Camera**) and pick your file.
- In Chrome, an upload button usually shows a menu. Pick **Files** or **Photos**.

### About the camera

The phone has no real camera. Its camera shows a built-in test picture (a virtual room).
Live-camera features such as Google Meet video will use that test picture.
Use Meet's **Present** or **Share screen** button to show your content instead.

## Commands

| Command | What it does |
|---|---|
| `./phone.sh start` | Build and start the phone |
| `./phone.sh stop` | Stop it (apps and data are kept) |
| `./phone.sh restart` | Reboot the phone |
| `./phone.sh status` | Show whether Android has booted |
| `./phone.sh logs` | Show live logs |
| `./phone.sh install app.apk` | Install an APK |
| `./phone.sh upload photo.jpg` | Send a photo/video/file to the phone |
| `./phone.sh home` / `back` / `rotate` | Press buttons |
| `./phone.sh crashlog` | Show why an app crashed |
| `./phone.sh shell` | Open an adb shell |
| `./phone.sh reset` | **Erase everything** and start fresh |

## Settings

Edit `.env` (created from `.env.example`) and run `./phone.sh start` again.

- `PHONE_RAM_MB`, `PHONE_CORES`, `PHONE_STORAGE`, `PHONE_WIDTH/HEIGHT/DENSITY` set the phone's hardware.
  They apply when the phone is created, so run `./phone.sh reset` after changing them.
- `VNC_PASSWORD` sets the password the browser page asks for.

### Open it from your laptop or phone (same Wi-Fi)

In `.env` set `LISTEN_ADDR=0.0.0.0` and a `VNC_PASSWORD`, run `./phone.sh start`,
then open `http://<your-PC-IP>:6080` (find the IP with `hostname -I`).

### Open it from anywhere on the internet

Don't open port 6080 on your router. Use [Tailscale](https://tailscale.com/download/linux)
on the PC and on your other device, then open `http://<pc-tailscale-ip>:6080`.

### Run it on a cloud server

This works on any Linux VPS that exposes `/dev/kvm`: a bare-metal server or a VM with
nested virtualization enabled. Most cheap VPSes don't have KVM. Run the same
`./setup.sh` and `./phone.sh start` there.

## Troubleshooting

- **`/dev/kvm missing`**: turn on Intel VT-x / AMD SVM ("Virtualization") in BIOS and reboot.
  Check with `ls /dev/kvm`.
- **Black screen in browser**: Android is still booting. Wait and refresh, or check `./phone.sh logs`.
- **Slow or laggy**: give more cores/RAM in `.env`, close other heavy programs, or lower
  `PHONE_WIDTH/HEIGHT` (e.g. 540x1200, density 240) and run `./phone.sh reset`.
- **Some banking or game apps refuse to run**: some apps block all emulators. A real phone is
  the only fix for those.
