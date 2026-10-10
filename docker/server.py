"""Cloud Phone web server: phone screen (noVNC) plus photo/video upload into the phone."""
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


def main():
    app = web.Application(middlewares=[password_check], client_max_size=4 * 1024**3)
    app.router.add_get("/", index)
    app.router.add_get("/websockify", vnc_proxy)
    app.router.add_post("/upload", upload)
    app.router.add_static("/novnc/", NOVNC_DIR)
    web.run_app(app, host="0.0.0.0", port=6080, access_log=None)


if __name__ == "__main__":
    main()
