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

## Live camera (Google Meet, WhatsApp video, selfies...)

The phone's camera can be the **live webcam of the device you open the page on**,
just like a real phone camera. One-time setup:

```bash
./setup-camera.sh     # on WSL this builds a driver once (20-60 min)
./phone.sh start
```

Recent WSL versions already include the camera driver (v4l2loopback). Then
`./phone.sh start` loads it by itself and you can skip `./setup-camera.sh`.

Then click **Camera: off** in the top bar so it turns red (**Camera: ON**) and allow
the webcam. Your live picture shows as a small preview, and every app in the phone
(Meet, WhatsApp, Camera...) now sees it as the phone's front and back camera.
When it's off, apps see a dark grey picture.

The browser only allows webcams on `http://localhost` or an `https://` address.

The phone container runs privileged so it can attach this camera itself.

If the camera doesn't work, run `./phone.sh doctor`. It checks each step and tells you the fix.

## Copy and paste

- **PC to phone:** copy on your PC, tap a text box in the phone, press **Ctrl+V**.
  The first time, the browser asks to allow clipboard access: click **Allow**.
- **Phone to PC:** copy text in the phone. It lands on your PC clipboard automatically.
- If Ctrl+V doesn't work, use the **Paste text** button.

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
| `./phone.sh camera-on` | Re-enable the camera device (after a PC/WSL restart) |
| `./phone.sh doctor` | Check the live camera setup step by step |
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

The live camera and clipboard only work over `https://` (or on `localhost`). To get an
https address, run `sudo tailscale serve --bg 6080` and open the `https://...ts.net`
address it prints.

### Run it on a cloud server

This works on any Linux VPS that exposes `/dev/kvm`: a bare-metal server or a VM with
nested virtualization enabled. Most cheap VPSes don't have KVM. Run the same
`./setup.sh` and `./phone.sh start` there.

## Speed

The phone runs without a graphics card (WSL and Docker can't share it), so the PC's
processor draws everything. To make it faster:

1. **Give WSL more power.** In Windows, edit `C:\Users\<you>\.wslconfig`:
   ```
   [wsl2]
   nestedVirtualization=true
   memory=10GB
   processors=8
   ```
   Use about 2/3 of your PC's RAM and cores. Then run `wsl --shutdown` in PowerShell.
2. **Match the phone to it.** In `.env`, set `PHONE_CORES` (e.g. 6) and `PHONE_RAM_MB=6144`.
3. **Lower the screen resolution.** This gives the biggest speed-up. In `.env`, set
   `PHONE_WIDTH=540`, `PHONE_HEIGHT=1200`, `PHONE_DENSITY=240`.
4. Run `./phone.sh reset` (this **erases the phone**), then `./phone.sh start`.

Animations inside the phone are switched off automatically, which also helps.
The first 10 minutes after a fresh phone are slow while Google Play updates itself.

## Troubleshooting

- **`/dev/kvm missing`**: turn on Intel VT-x / AMD SVM ("Virtualization") in BIOS and reboot.
  Check with `ls /dev/kvm`.
- **Black screen in browser**: Android is still booting. Wait and refresh, or check `./phone.sh logs`.
- **Slow or laggy**: see "Speed" below.
- **Some banking or game apps refuse to run**: some apps block all emulators. A real phone is
  the only fix for those.
