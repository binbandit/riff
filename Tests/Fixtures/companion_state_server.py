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
suggestion_requests = 0
button_triggers = []
audio_started = threading.Event()
audio_release = threading.Event()
hold_audio = False
suggestion_started = threading.Event()
suggestion_release = threading.Event()
lock = threading.Lock()
started = threading.Event()
release = threading.Event()
hold_next = False
fail_next = False
fail_next_deck_save = False
lose_deck_ack = False
conflict_deck_save = False
hold_deck_save = False
deck_save_started = threading.Event()
deck_save_release = threading.Event()
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
        global hold_next, fail_next, audio_requests, hold_audio, fail_next_deck_save
        if not self.authorized():
            return
        global lose_deck_ack, conflict_deck_save, hold_deck_save
        if self.path == "/test/lose-next-deck-ack":
            lose_deck_ack = True
            self.reply({"ok": True})
        elif self.path == "/test/conflict-next-deck-save":
            conflict_deck_save = True
            self.reply({"ok": True})
        elif self.path == "/test/hold-next-deck-save":
            hold_deck_save = True
            deck_save_started.clear()
            deck_save_release.clear()
            self.reply({"ok": True})
        elif self.path == "/test/deck-save-started":
            self.reply({"ok": deck_save_started.wait(5)})
        elif self.path == "/test/release-deck-save":
            deck_save_release.set()
            self.reply({"ok": True})
        elif self.path == "/test/fail-next-deck-save":
            fail_next_deck_save = True
            self.reply({"ok": True})
        elif self.path == "/test/suggestion-count":
            self.reply({"count": suggestion_requests})
        elif self.path == "/test/suggestion-started":
            self.reply({"ok": suggestion_started.wait(5)})
        elif self.path == "/test/release-suggestion":
            suggestion_release.set()
            self.reply({"ok": True})
        elif self.path == "/test/hold-next-audio":
            hold_audio = True
            audio_started.clear()
            audio_release.clear()
            self.reply({"ok": True})
        elif self.path == "/test/audio-started":
            self.reply({"ok": audio_started.wait(5)})
        elif self.path == "/test/release-audio":
            audio_release.set()
            self.reply({"ok": True})
        elif self.path == "/test/button-triggers":
            self.reply(button_triggers)
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
        global fail_next_deck_save, lose_deck_ack, conflict_deck_save, hold_deck_save
        if not self.authorized():
            return
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        if self.path == "/api/decks":
            if fail_next_deck_save:
                fail_next_deck_save = False
                self.reply({"error": "Temporary save failure."}, 503)
                return
            with lock:
                if conflict_deck_save:
                    conflict_deck_save = False
                    state["decks"][1]["name"] = "Changed on PC"
                    state["version"] += 1
                if body["version"] != state["version"]:
                    self.reply({"error": "Decks changed."}, 409)
                    return
                if any(p["kind"] == "sound" and p["value"] not in {c["id"] for c in state["clips"]} for d in body["decks"] for p in d["pads"]):
                    self.reply({"error": "Missing sound."}, 400)
                    return
                state["decks"] = body["decks"]
                state["version"] += 1
                response = copy.deepcopy(state)
            if hold_deck_save:
                hold_deck_save = False
                deck_save_started.set()
                deck_save_release.wait(8)
            if lose_deck_ack:
                lose_deck_ack = False
                self.reply({"error": "Save response lost."}, 503)
            else:
                self.reply(response)
            return
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

    def do_DELETE(self):
        if not self.authorized():
            return
        if not self.path.startswith("/api/clips/"):
            self.reply({"error": "Unknown path"}, 404)
            return
        clip_id = self.path.split("/")[-1]
        with lock:
            if any(p.get("kind") == "sound" and p.get("value") == clip_id or
                   any(step.get("kind") == "sound" and step.get("value") == clip_id
                       for step in p.get("steps", []) + (p.get("alternateSteps") or []))
                   for d in state["decks"] for p in d["pads"]):
                self.reply({"error": "Sound is used by a button."}, 400)
                return
            state["clips"] = [c for c in state["clips"] if c["id"] != clip_id]
            state["version"] += 1
            response = copy.deepcopy(state)
        self.reply(response)

    def do_POST(self):
        global pc_previews, suggestion_requests
        if not self.authorized():
            return
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path in ("/api/pad-suggestion", "/api/deck-suggestion", "/api/sound-suggestions"):
            suggestion_requests += 1
        if self.path == "/api/trigger":
            button_triggers.append(json.loads(body))
            self.reply({"ok": True})
        elif self.path == "/test/catalog":
            update = json.loads(body)
            with lock:
                for field in ("games", "apps", "outputs", "computerName"):
                    if field in update:
                        state[field] = update[field]
                response = copy.deepcopy(state)
            self.reply(response)
        elif self.path == "/api/deck-suggestion":
            catalog = json.loads((pathlib.Path(__file__).parents[2] / "Riff/Resources/sound-packs.json").read_text())
            pack = catalog[0]
            buttons = [{"pad": {"id": "suggested-" + sound["id"], "title": sound["name"], "icon": "waveform", "color": "orange", "kind": "sound", "value": "pack-" + sound["id"], "steps": []},
                        "reason": "A quick reaction.", "description": sound["name"], "packId": pack["id"], "soundId": sound["id"]} for sound in pack["sounds"][:2]]
            self.reply({"name": "Game night", "icon": "gamecontroller", "summary": "A mix of reactions.", "buttons": buttons})
        elif self.path == "/api/sound-suggestions":
            request = json.loads(body)
            if request.get("deckName") == "hold":
                suggestion_started.set()
                suggestion_release.wait(8)
            try:
                if request.get("deckName") == "failure":
                    self.reply({"error": "AI is unavailable."}, 503)
                else:
                    ids = request["clipIds"] if request.get("deckName") != "missing" else request["clipIds"][:-1]
                    self.reply({"buttons": [{"clipId": clip_id, "label": "Sound " + str(index + 1), "icon": "speaker.wave.2", "color": "orange"} for index, clip_id in reversed(list(enumerate(ids)))]})
            except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
                pass
        elif self.path == "/api/pad-suggestion":
            request = json.loads(body)
            if request.get("titleHint") == "hold":
                suggestion_started.set()
                suggestion_release.wait(8)
            try:
                if request.get("titleHint") == "failure":
                    self.reply({"error": "AI is unavailable."}, 503)
                else:
                    self.reply({"label": "Air Horn", "icon": "speaker.wave.2", "color": "orange"})
            except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
                pass
        elif self.path == "/api/preview":
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
