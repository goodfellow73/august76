import asyncio
import base64
import io
import json
import os
import subprocess
from typing import Optional

import anthropic
from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

app = FastAPI(title="Phone Control")

# ---------------------------------------------------------------------------
# ADB helpers
# ---------------------------------------------------------------------------

def adb(*args: str, timeout: int = 10) -> str:
    result = subprocess.run(
        ["adb", *args],
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"adb error (code {result.returncode})")
    return result.stdout.strip()


def adb_bytes(*args: str, timeout: int = 10) -> bytes:
    result = subprocess.run(
        ["adb", *args],
        capture_output=True,
        timeout=timeout,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.decode().strip())
    return result.stdout


def screenshot_b64() -> str:
    raw = adb_bytes("exec-out", "screencap", "-p", timeout=15)
    return base64.b64encode(raw).decode()


def screen_size() -> tuple[int, int]:
    out = adb("shell", "wm", "size")
    # "Physical size: 1080x2400"
    parts = out.split(":")[-1].strip().split("x")
    return int(parts[0]), int(parts[1])


# ---------------------------------------------------------------------------
# REST models
# ---------------------------------------------------------------------------

class TapRequest(BaseModel):
    x: float
    y: float

class SwipeRequest(BaseModel):
    x1: float
    y1: float
    x2: float
    y2: float
    duration_ms: int = 300

class TypeRequest(BaseModel):
    text: str

class KeyRequest(BaseModel):
    keycode: str  # e.g. "KEYCODE_HOME", "KEYCODE_BACK"

class ShellRequest(BaseModel):
    command: str

class PushRequest(BaseModel):
    local_path: str
    remote_path: str = "/sdcard/Download/"

class AiRequest(BaseModel):
    instruction: str
    max_steps: int = 10

# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.get("/api/screenshot")
def get_screenshot():
    try:
        b64 = screenshot_b64()
        return {"image": b64}
    except Exception as e:
        raise HTTPException(500, str(e))


@app.get("/api/screen-size")
def get_screen_size():
    try:
        w, h = screen_size()
        return {"width": w, "height": h}
    except Exception as e:
        raise HTTPException(500, str(e))


@app.post("/api/tap")
def tap(req: TapRequest):
    try:
        adb("shell", "input", "tap", str(int(req.x)), str(int(req.y)))
        return {"ok": True}
    except Exception as e:
        raise HTTPException(500, str(e))


@app.post("/api/swipe")
def swipe(req: SwipeRequest):
    try:
        adb("shell", "input", "swipe",
            str(int(req.x1)), str(int(req.y1)),
            str(int(req.x2)), str(int(req.y2)),
            str(req.duration_ms))
        return {"ok": True}
    except Exception as e:
        raise HTTPException(500, str(e))


@app.post("/api/type")
def type_text(req: TypeRequest):
    try:
        # ADB input text doesn't handle spaces well — use sed trick
        escaped = req.text.replace(" ", "%s").replace("'", "\\'")
        adb("shell", "input", "text", escaped)
        return {"ok": True}
    except Exception as e:
        raise HTTPException(500, str(e))


@app.post("/api/key")
def press_key(req: KeyRequest):
    try:
        adb("shell", "input", "keyevent", req.keycode)
        return {"ok": True}
    except Exception as e:
        raise HTTPException(500, str(e))


@app.post("/api/shell")
def run_shell(req: ShellRequest):
    try:
        out = adb("shell", req.command, timeout=30)
        return {"output": out}
    except Exception as e:
        raise HTTPException(500, str(e))


@app.post("/api/push")
def push_file(req: PushRequest):
    try:
        out = adb("push", req.local_path, req.remote_path, timeout=60)
        return {"output": out}
    except Exception as e:
        raise HTTPException(500, str(e))


@app.get("/api/devices")
def list_devices():
    try:
        out = adb("devices")
        lines = [l for l in out.splitlines()[1:] if l.strip() and "device" in l]
        return {"devices": lines}
    except Exception as e:
        raise HTTPException(500, str(e))


# ---------------------------------------------------------------------------
# AI automation (Claude computer use)
# ---------------------------------------------------------------------------

SYSTEM_PROMPT = """You are controlling an Android phone via ADB.
You can see the phone screen. Use the provided tools to complete the user's instruction.
Always take a screenshot first to see the current state.
Be precise with coordinates — the screen dimensions are provided.
Complete the task efficiently and stop when done."""


def _build_tools(width: int, height: int) -> list:
    return [
        {
            "type": "computer_20250124",
            "name": "computer",
            "display_width_px": width,
            "display_height_px": height,
        }
    ]


def _execute_computer_action(action: dict) -> str:
    action_type = action.get("action") or action.get("type")

    if action_type == "screenshot":
        return screenshot_b64()

    elif action_type in ("left_click", "click"):
        coord = action.get("coordinate", [0, 0])
        adb("shell", "input", "tap", str(int(coord[0])), str(int(coord[1])))
        return "tapped"

    elif action_type == "double_click":
        coord = action.get("coordinate", [0, 0])
        adb("shell", "input", "tap", str(int(coord[0])), str(int(coord[1])))
        adb("shell", "input", "tap", str(int(coord[0])), str(int(coord[1])))
        return "double-tapped"

    elif action_type == "type":
        text = action.get("text", "")
        escaped = text.replace(" ", "%s").replace("'", "\\'")
        adb("shell", "input", "text", escaped)
        return "typed"

    elif action_type == "key":
        key = action.get("key", "")
        keymap = {"Return": "KEYCODE_ENTER", "BackSpace": "KEYCODE_DEL",
                  "Escape": "KEYCODE_BACK", "super": "KEYCODE_HOME"}
        adb("shell", "input", "keyevent", keymap.get(key, key))
        return "key pressed"

    elif action_type == "scroll":
        coord = action.get("coordinate", [0, 0])
        direction = action.get("direction", "down")
        delta = action.get("scroll_direction") or direction
        x, y = int(coord[0]), int(coord[1])
        if delta == "down":
            adb("shell", "input", "swipe", str(x), str(y), str(x), str(y - 500), "300")
        elif delta == "up":
            adb("shell", "input", "swipe", str(x), str(y), str(x), str(y + 500), "300")
        return "scrolled"

    return f"unknown action: {action_type}"


async def run_ai_task(instruction: str, max_steps: int):
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        yield json.dumps({"error": "ANTHROPIC_API_KEY not set"}) + "\n"
        return

    client = anthropic.Anthropic(api_key=api_key)

    try:
        w, h = screen_size()
    except Exception as e:
        yield json.dumps({"error": f"Could not get screen size: {e}"}) + "\n"
        return

    tools = _build_tools(w, h)
    messages = [{"role": "user", "content": instruction}]

    for step in range(max_steps):
        yield json.dumps({"step": step + 1, "status": "thinking"}) + "\n"

        response = client.messages.create(
            model="claude-opus-4-8",
            max_tokens=1024,
            system=SYSTEM_PROMPT,
            tools=tools,
            messages=messages,
        )

        # Collect assistant message
        assistant_content = []
        tool_uses = []

        for block in response.content:
            assistant_content.append(block)
            if block.type == "text":
                yield json.dumps({"step": step + 1, "text": block.text}) + "\n"
            elif block.type == "tool_use":
                tool_uses.append(block)

        messages.append({"role": "assistant", "content": assistant_content})

        if response.stop_reason == "end_turn" or not tool_uses:
            yield json.dumps({"done": True, "status": "completed"}) + "\n"
            return

        # Execute tool uses
        tool_results = []
        for tool_use in tool_uses:
            action = tool_use.input
            yield json.dumps({"step": step + 1, "action": action.get("action", "unknown")}) + "\n"

            try:
                result = _execute_computer_action(action)
            except Exception as e:
                result = f"error: {e}"

            if action.get("action") == "screenshot" and isinstance(result, str) and len(result) > 100:
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": tool_use.id,
                    "content": [{"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": result}}],
                })
            else:
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": tool_use.id,
                    "content": str(result),
                })

        messages.append({"role": "user", "content": tool_results})

    yield json.dumps({"done": True, "status": "max_steps_reached"}) + "\n"


@app.post("/api/ai")
async def ai_task(req: AiRequest):
    async def generate():
        async for chunk in run_ai_task(req.instruction, req.max_steps):
            yield chunk

    return StreamingResponse(generate(), media_type="application/x-ndjson")


# ---------------------------------------------------------------------------
# Serve the web UI
# ---------------------------------------------------------------------------

@app.get("/", response_class=HTMLResponse)
def index():
    html_path = os.path.join(os.path.dirname(__file__), "static", "index.html")
    with open(html_path) as f:
        return f.read()


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8765, reload=False)
