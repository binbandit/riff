"""Loopback TLS companion fixture for import/poll races and local previews."""
import copy
import hashlib
import http.server
import json
import pathlib
import ssl
import subprocess
import sys
import tempfile
import threading

state = json.loads(pathlib.Path(sys.argv[1]).read_text())
audio_requests = 0
pc_previews = 0
audio_started = threading.Event()
audio_release = threading.Event()
hold_audio = False
lock = threading.Lock()
started = threading.Event()
release = threading.Event()
hold_next = False
fail_next = False
token = "a" * 64


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, value, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(value).encode())

    def authorized(self):
        if self.headers.get("Authorization") == "Bearer " + token:
            return True
        self.reply({"error": "Pairing expired."}, 401)
        return False

    def do_GET(self):
        global hold_next, fail_next, audio_requests, hold_audio
        if not self.authorized():
            return
        if self.path == "/test/hold-next-audio":
            hold_audio = True
            audio_started.clear()
            audio_release.clear()
            self.reply({"ok": True})
        elif self.path == "/test/audio-started":
            self.reply({"ok": audio_started.wait(5)})
        elif self.path == "/test/release-audio":
            audio_release.set()
            self.reply({"ok": True})
        elif self.path == "/test/preview-counts":
            self.reply({"audioRequests": audio_requests, "pcPreviews": pc_previews})
        elif self.path.startswith("/api/clips/") and self.path.endswith("/audio"):
            audio_requests += 1
            if hold_audio:
                hold_audio = False
                audio_started.set()
                audio_release.wait(8)
            data = (pathlib.Path(__file__).parents[2] / "Shared/Sounds/countdown.wav").read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
                pass  # Stopping a preview cancels its in-flight request.
        elif self.path == "/test/hold-next-state":
            with lock:
                hold_next = True
                started.clear()
                release.clear()
            self.reply({"ok": True})
        elif self.path == "/test/state-started":
            self.reply({"ok": started.wait(5)})
        elif self.path == "/test/fail-next-state":
            with lock:
                fail_next = True
            self.reply({"ok": True})
        elif self.path == "/test/release-state":
            release.set()
            self.reply({"ok": True})
        elif self.path == "/api/state":
            with lock:
                response = copy.deepcopy(state)
                hold = hold_next
                hold_next = False
                fail = fail_next
                fail_next = False
            if hold:
                started.set()
                release.wait(8)
            self.reply({"error": "Temporarily unavailable"} if fail else response, 503 if fail else 200)
        else:
            self.reply({"error": "Unknown path"}, 404)

    def do_PUT(self):
        if not self.authorized():
            return
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        if self.path != "/api/audio":
            self.reply({"error": "Unknown path"}, 404)
            return
        allowed = {"outputId", "volume"}
        if "audio-monitor-v1" in state.get("capabilities", []):
            allowed |= {"monitorEnabled", "monitorOutputId", "monitorVolume"}
        if set(body) - allowed:
            self.reply({"error": "Unknown audio setting"}, 400)
            return
        with lock:
            state.update(body)
            state["version"] += 1
            response = copy.deepcopy(state)
        self.reply(response)

    def do_POST(self):
        global pc_previews
        if not self.authorized():
            return
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path == "/api/preview":
            pc_previews += 1
            self.reply({"ok": True})
        elif self.path.startswith("/api/clips?"):
            with lock:
                state["version"] += 1
                clip = {"id": "upload-" + str(state["version"]), "name": "New sound", "duration": 1}
                state["clips"].append(clip)
            self.reply(clip)
        else:
            self.reply({"error": "Unknown path"}, 404)


with tempfile.TemporaryDirectory(prefix="riff-state-tls-") as folder:
    cert = pathlib.Path(folder) / "cert.pem"
    key = pathlib.Path(folder) / "key.pem"
    subprocess.run(["/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                    "-keyout", str(key), "-out", str(cert), "-days", "1", "-subj", "/CN=Riff state test"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(cert, key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    fingerprint = hashlib.sha256(ssl.PEM_cert_to_DER_cert(cert.read_text())).hexdigest()
    print(json.dumps({"host": "127.0.0.1", "port": server.server_port, "token": token, "fingerprint": fingerprint}), flush=True)
    server.serve_forever()
