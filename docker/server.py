"""Cloud Phone web server: phone screen (noVNC), uploads, clipboard sync and live camera."""
import asyncio
import base64
import hmac
import os
import re
import tempfile
import time

from aiohttp import WSMsgType, web

HERE = os.path.dirname(os.path.abspath(__file__))
NOVNC_DIR = "/usr/share/novnc"
VNC_ADDR = ("127.0.0.1", 5900)
PASSWORD = os.environ.get("VNC_PASSWORD", "")

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic", ".heif", ".bmp"}
VIDEO_EXT = {".mp4", ".mov", ".3gp", ".mkv", ".webm", ".avi", ".m4v"}
CAMERA_DEV = os.environ.get("CAMERA_DEV", "/dev/video0")
CAMERA_READY = "/tmp/camera-ready"
CAMERA_FPS = 15
CAMERA_SIZE = (640, 480)
MEDIA_DIR = "/sdcard/DCIM/Uploads"  # shows up in Gallery, Photos and photo pickers
OTHER_DIR = "/sdcard/Download"


@web.middleware
async def password_check(request, handler):
    """When VNC_PASSWORD is set, the whole page (and uploads) needs it too."""
    if PASSWORD:
        given = ""
        header = request.headers.get("Authorization", "")
        if header.startswith("Basic "):
            try:
                given = base64.b64decode(header[6:]).decode().partition(":")[2]
            except ValueError:
                pass
        if not hmac.compare_digest(given.encode(), PASSWORD.encode()):
            return web.Response(status=401, headers={"WWW-Authenticate": 'Basic realm="Cloud Phone"'})
    return await handler(request)


async def run(*cmd):
    proc = await asyncio.create_subprocess_exec(
        *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT
    )
    out, _ = await proc.communicate()
    return proc.returncode, out.decode(errors="replace").strip()


def safe_name(filename):
    base = os.path.basename(filename.replace("\\", "/"))
    base = re.sub(r"[^A-Za-z0-9._-]", "_", base).lstrip(".") or "file"
    stem, ext = os.path.splitext(base)
    return f"{stem[:80]}_{time.strftime('%Y%m%d_%H%M%S')}{ext.lower()}"


async def index(request):
    return web.FileResponse(os.path.join(HERE, "web", "index.html"))


async def vnc_proxy(request):
    """WebSocket <-> VNC bridge used by the noVNC viewer."""
    ws = web.WebSocketResponse(protocols=("binary",), max_msg_size=0)
    await ws.prepare(request)
    try:
        reader, writer = await asyncio.open_connection(*VNC_ADDR)
    except OSError:
        await ws.close()
        return ws

    async def vnc_to_browser():
        while data := await reader.read(65536):
            await ws.send_bytes(data)
        await ws.close()

    pump = asyncio.create_task(vnc_to_browser())
    try:
        async for msg in ws:
            if msg.type == WSMsgType.BINARY:
                writer.write(msg.data)
                await writer.drain()
            elif msg.type == WSMsgType.TEXT:
                writer.write(msg.data.encode("latin-1"))
                await writer.drain()
    finally:
        pump.cancel()
        writer.close()
    return ws


async def upload(request):
    code, state = await run("adb", "get-state")
    if code != 0 or state != "device":
        return web.json_response({"error": "The phone is still starting. Try again in a minute."}, status=503)

    saved = []
    reader = await request.multipart()
    async for part in reader:
        if part.name != "file" or not part.filename:
            continue
        name = safe_name(part.filename)
        ext = os.path.splitext(name)[1]
        is_media = ext in IMAGE_EXT or ext in VIDEO_EXT
        dest_dir = MEDIA_DIR if is_media else OTHER_DIR

        with tempfile.TemporaryDirectory() as tmp:
            local = os.path.join(tmp, name)
            with open(local, "wb") as f:
                while chunk := await part.read_chunk(1 << 20):
                    f.write(chunk)
            await run("adb", "shell", "mkdir", "-p", dest_dir)
            code, out = await run("adb", "push", local, f"{dest_dir}/{name}")
        if code != 0:
            return web.json_response({"error": f"Could not copy {name} to the phone: {out}"}, status=500)

        # Make it appear in Gallery / photo pickers right away.
        await run("adb", "shell", "am", "broadcast", "-a", "android.intent.action.MEDIA_SCANNER_SCAN_FILE",
                  "-d", f"file://{dest_dir}/{name}")
        saved.append({"name": name, "folder": dest_dir.replace("/sdcard/", "")})

    if not saved:
        return web.json_response({"error": "No file received."}, status=400)
    return web.json_response({"saved": saved})


# ---------------------------------------------------------------- clipboard
# The emulator syncs the X clipboard with Android's clipboard, so we only need
# to read and write the X clipboard here.

async def clipboard_get(request):
    try:
        proc = await asyncio.create_subprocess_exec(
            "xclip", "-selection", "clipboard", "-o",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
        out, _ = await asyncio.wait_for(proc.communicate(), 2)
    except (OSError, asyncio.TimeoutError):
        out = b""
    return web.json_response({"text": out.decode(errors="replace")})


async def clipboard_set(request):
    data = await request.json()
    text = str(data.get("text", ""))
    # xclip stays in the background to serve the clipboard, so don't wait on its output.
    proc = await asyncio.create_subprocess_exec(
        "xclip", "-selection", "clipboard", "-i",
        stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
    proc.stdin.write(text.encode())
    proc.stdin.close()
    await proc.wait()
    if data.get("paste"):
        await asyncio.sleep(0.4)  # let the emulator copy it into Android first
        await run("adb", "shell", "input", "keyevent", "KEYCODE_PASTE")
    return web.json_response({"ok": True})


# ------------------------------------------------------------------- camera
# The phone's camera is a virtual webcam (v4l2loopback). We keep it fed with
# frames all the time: live frames from the browser's webcam while it's on,
# otherwise a plain "camera off" frame.

class Camera:
    def __init__(self):
        self.available = os.path.exists(CAMERA_DEV)
        self.latest = None        # last JPEG frame from a browser
        self.latest_at = 0.0
        self.placeholder = None
        self.error = ""           # last camera feed error, shown on the page

    async def start(self, app):
        if self.available:
            app["camera_task"] = asyncio.create_task(self.feed_forever())

    async def make_placeholder(self):
        w, h = CAMERA_SIZE
        path = "/tmp/camera-off.jpg"
        await run("ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", f"color=c=0x202124:s={w}x{h}",
                  "-frames:v", "1", path)
        with open(path, "rb") as f:
            self.placeholder = f.read()

    async def feed_forever(self):
        await self.make_placeholder()
        w, h = CAMERA_SIZE
        while True:
            proc = await asyncio.create_subprocess_exec(
                # No probing/buffering: frames must reach the phone immediately.
                "ffmpeg", "-loglevel", "error", "-probesize", "32", "-analyzeduration", "0",
                "-fflags", "nobuffer", "-flags", "low_delay", "-f", "image2pipe", "-c:v", "mjpeg",
                "-framerate", str(CAMERA_FPS), "-i", "pipe:0",
                "-vf", f"scale={w}:{h}", "-pix_fmt", "yuyv422", "-f", "v4l2", CAMERA_DEV,
                stdin=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
            sent = 0
            next_at = time.monotonic()
            try:
                while proc.returncode is None:
                    live = self.latest and time.monotonic() - self.latest_at < 2
                    proc.stdin.write(self.latest if live else self.placeholder)
                    await proc.stdin.drain()
                    sent += 1
                    if sent == CAMERA_FPS:
                        open(CAMERA_READY, "w").close()  # the emulator waits for this
                    next_at += 1 / CAMERA_FPS
                    await asyncio.sleep(max(0, next_at - time.monotonic()))
            except (BrokenPipeError, ConnectionResetError):
                pass
            err = (await proc.stderr.read()).decode(errors="replace").strip()
            await proc.wait()
            self.error = err[-300:] or f"ffmpeg exited with code {proc.returncode}"
            print(f"camera feed stopped ({self.error}), restarting", flush=True)
            await asyncio.sleep(1)

    async def websocket(self, request):
        """Receives JPEG frames from the browser's webcam."""
        ws = web.WebSocketResponse(max_msg_size=4 * 1024 * 1024)
        await ws.prepare(request)
        async for msg in ws:
            if msg.type == WSMsgType.BINARY and msg.data[:2] == b"\xff\xd8":
                self.latest = msg.data
                self.latest_at = time.monotonic()
        self.latest = None
        return ws


async def status(request):
    cam = request.app["camera"]
    if not cam.available:
        problem = ("The phone has no camera device. On the PC run ./phone.sh doctor to see which "
                   "step is missing (usually: ./setup-camera.sh, then ./phone.sh start).")
    elif not os.path.exists(CAMERA_READY):
        problem = "The camera feed is not running: " + (cam.error or "still starting, wait a few seconds.")
    else:
        problem = ""
    return web.json_response({"camera": cam.available and not problem, "problem": problem})


def main():
    app = web.Application(middlewares=[password_check], client_max_size=4 * 1024**3)
    camera = Camera()
    app["camera"] = camera
    app.on_startup.append(camera.start)
    app.router.add_get("/", index)
    app.router.add_get("/status", status)
    app.router.add_get("/clipboard", clipboard_get)
    app.router.add_post("/clipboard", clipboard_set)
    app.router.add_get("/camera", camera.websocket)
    app.router.add_get("/websockify", vnc_proxy)
    app.router.add_post("/upload", upload)
    app.router.add_static("/novnc/", NOVNC_DIR)
    web.run_app(app, host="0.0.0.0", port=6080, access_log=None)


if __name__ == "__main__":
    main()
