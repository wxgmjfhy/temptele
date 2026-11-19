"""Exercise OpenCode's non-interactive route against a deterministic local model stub."""

import base64
import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread


REPORT_DIR = Path("/out/harness")
COMMAND = (
    "blender --background --factory-startup --disable-autoexec --threads 4 "
    "--python-exit-code 1 --python /smoke/blender_asset.py -- /out/harness"
)


class ModelStub(BaseHTTPRequestHandler):
    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if self.path != "/v1/chat/completions":
            self.send_error(404)
            return

        if any(message["role"] == "tool" for message in request["messages"]):
            response = {"content": "Blender smoke command finished."}
            reason = "stop"
        elif not request.get("tools"):
            response = {"content": "Blender dependency smoke"}
            reason = "stop"
        else:
            tools = {tool["function"]["name"] for tool in request["tools"]}
            if "shell" not in tools:
                self.send_error(422, "Expected OpenCode to expose its shell tool")
                return
            images = [
                part["image_url"]["url"]
                for message in request["messages"]
                if isinstance(message.get("content"), list)
                for part in message["content"]
                if part.get("type") == "image_url"
            ]
            if not any(
                url.startswith("data:image/png;base64,")
                and base64.b64decode(url.split(",", 1)[1]).startswith(b"\x89PNG\r\n\x1a\n")
                for url in images
            ):
                self.send_error(422, "Expected the decoded PNG attachment")
                return
            arguments = {
                "command": COMMAND,
                "description": "Generate and verify a Blender test asset",
                "timeout": 90000,
            }
            response = {
                "tool_calls": [{
                    "index": 0,
                    "id": "call_blender_smoke",
                    "type": "function",
                    "function": {"name": "shell", "arguments": json.dumps(arguments)},
                }],
            }
            reason = "tool_calls"

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        self.chunk({"role": "assistant"})
        self.chunk(response)
        self.chunk({}, reason)
        self.wfile.write(b"data: [DONE]\n\n")

    def chunk(self, delta, reason=None):
        data = {
            "id": "chatcmpl-blender-smoke",
            "object": "chat.completion.chunk",
            "created": 1,
            "model": "fixture",
            "choices": [{"index": 0, "delta": delta, "finish_reason": reason}],
        }
        self.wfile.write(f"data: {json.dumps(data)}\n\n".encode())
        self.wfile.flush()


def find_session(events):
    for event in events:
        session = event.get("sessionID") or event.get("sessionId")
        if isinstance(session, str) and session.startswith("ses_"):
            return session
    raise AssertionError("OpenCode JSONL contained no session ID")


def main():
    REPORT_DIR.mkdir()
    project = Path("/tmp/opencode-project")
    project.mkdir()
    config_dir = Path(os.environ["XDG_CONFIG_HOME"]) / "opencode"
    config_dir.mkdir(parents=True, exist_ok=True)
    with ThreadingHTTPServer(("127.0.0.1", 0), ModelStub) as server:
        config = {
            "update": "disable",
            "model": "smoke/fixture",
            "providers": {
                "smoke": {
                    "name": "Smoke",
                    "package": "@opencode/ai/providers/openai-compatible",
                    "env": ["SMOKE_PROVIDER_KEY"],
                    "settings": {"baseURL": f"http://127.0.0.1:{server.server_port}/v1"},
                    "models": {
                        "fixture": {
                            "name": "Fixture",
                            "capabilities": {"tools": True, "input": ["text", "image"], "output": ["text"]},
                        },
                    },
                },
            },
        }
        (config_dir / "opencode.json").write_text(json.dumps(config))
        environment = {**os.environ, "SMOKE_PROVIDER_KEY": "local-fixture"}
        worker = Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            with (REPORT_DIR / "events.jsonl").open("w") as out, (
                REPORT_DIR / "opencode.stderr"
            ).open("w") as err:
                subprocess.run(
                    [
                        "opencode", "run", "--standalone", "--format", "json", "--auto",
                        "--model", "smoke/fixture", "Run the Blender smoke command.",
                        "--file", "/out/blender.png",
                    ],
                    env=environment,
                    cwd=project,
                    stdout=out,
                    stderr=err,
                    check=True,
                    timeout=105,
                )
        finally:
            server.shutdown()
            worker.join()

    events = [
        json.loads(line)
        for line in (REPORT_DIR / "events.jsonl").read_text().splitlines()
        if line.strip()
    ]
    assert any(
        event["type"] == "tool_use"
        and event["part"]["tool"] == "shell"
        and event["part"]["state"]["status"] == "completed"
        for event in events
    ), events
    session = find_session(events)
    with (REPORT_DIR / "session.json").open("w") as out:
        subprocess.run(
            ["opencode", "session", "export", session, "--standalone"],
            env=environment,
            cwd=project,
            stdout=out,
            check=True,
            timeout=20,
        )
    assert json.loads((REPORT_DIR / "session.json").read_text())
    assert (REPORT_DIR / "asset.glb").stat().st_size > 100
    assert (REPORT_DIR / "blender.png").read_bytes().startswith(b"\x89PNG\r\n\x1a\n")
    print("OPENCODE_OK PNG attachment, local provider, shell, Blender outputs, JSONL and session export")


if __name__ == "__main__":
    main()
