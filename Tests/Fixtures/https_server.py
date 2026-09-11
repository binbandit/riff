"""Loopback-only TLS fixture. Generates a throwaway certificate; never executes PC actions."""
import hashlib
import http.server
import json
import pathlib
import ssl
import subprocess
import tempfile

with tempfile.TemporaryDirectory(prefix='riff-tls-test-') as folder:
    cert = pathlib.Path(folder) / 'cert.pem'
    key = pathlib.Path(folder) / 'key.pem'
    subprocess.run(['/usr/bin/openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(key), '-out', str(cert), '-days', '1', '-subj', '/CN=Riff test'], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    token = 'a' * 64

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            if self.headers.get('Authorization') != 'Bearer ' + token:
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b'{"error":"Pairing expired."}')
            elif self.path == '/redirect':
                self.send_response(302)
                self.send_header('Location', '/ack')
                self.end_headers()
            else:
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"ok":true}')

    server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(cert, key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    fingerprint = hashlib.sha256(ssl.PEM_cert_to_DER_cert(cert.read_text())).hexdigest()
    print(json.dumps({'host': '127.0.0.1', 'port': server.server_port, 'token': token, 'fingerprint': fingerprint}), flush=True)
    server.serve_forever()
