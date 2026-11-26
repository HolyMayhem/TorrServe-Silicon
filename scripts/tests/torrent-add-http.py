import base64
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

KEY = "fixture-jackett-key"
AUTH = "Basic " + base64.b64encode(b"fixture-user:fixture-password").decode()
MAGNET = "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"
TORRENT = (
    b"d4:infod6:lengthi1e4:name1:x12:piece lengthi16384e6:pieces20:"
    + bytes(range(240, 256)) + bytes(range(4)) + b"ee"
)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def send(self, status=200, body=b"", **headers):
        self.send_response(status)
        for name, value in headers.items():
            self.send_header(name.replace("_", "-"), value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def redirect(self, target, status=302, **headers):
        self.send(status, Location=target, **headers)

    def do_GET(self):
        url = urlsplit(self.path)
        query = parse_qs(url.query)
        if self.server is external:
            if (url.path != "/public" or query != {"token": ["tracker-token"]}
                    or any(self.headers.get(h) for h in ("Authorization", "Cookie", "Referer"))):
                self.send(403)
            else:
                self.send(body=TORRENT)
            return

        if url.path == "/proxy/api/v2.0/indexers/all/results/torznab/api":
            if query.get("apikey") != [KEY] or self.headers.get("Authorization") != AUTH:
                self.send(401)
            elif query.get("t") == ["caps"]:
                self.send(body=b"<caps/>")
            elif query.get("q") == ["cross-origin"]:
                self.redirect(f"http://127.0.0.1:{external.server_port}/public?token=tracker-token")
            elif query.get("q") == ["film + title"]:
                def item(name, link):
                    return (
                        f'<item><title>{name}</title><guid>{name}</guid><enclosure url="{link}"/>'
                        '<comments>https://tracker.example/details</comments>'
                        '<torznab:attr name="seeders" value="7"/></item>'
                    )

                alias = f"http://localhost:9117/dl/example?jackett_apikey={KEY}"
                xml = '<rss xmlns:torznab="http://torznab.com"><channel>'
                xml += item("Alias", alias) + item("Relative", f"dl/example?jackett_apikey={KEY}")
                xml += item("Magnet", MAGNET) + "<item><title>No link</title></item></channel></rss>"
                self.send(body=xml.encode())
            else:
                self.send(400)
        elif url.path == "/proxy/dl/example":
            if query.get("jackett_apikey") != [KEY] or self.headers.get("Authorization") != AUTH:
                self.send(401)
            else:
                self.redirect(MAGNET)
        elif url.path == "/torrent":
            self.send(body=TORRENT, Content_Type="text/plain")
        elif url.path == "/magnet":
            self.send(body=("  " + MAGNET + "\n").encode())
        elif url.path == "/chain":
            self.redirect("/hop", 307)
        elif url.path == "/hop":
            self.redirect("magnet-redirect", 308)
        elif url.path == "/magnet-redirect":
            self.redirect(MAGNET)
        elif url.path == "/chain-torrent":
            self.redirect("/torrent", 301)
        elif url.path == "/loop":
            self.redirect("/loop")
        elif url.path == "/cross":
            self.redirect(
                f"http://127.0.0.1:{external.server_port}/public?token=tracker-token",
                Set_Cookie="session=fixture-cookie; Path=/",
            )
        elif url.path == "/cross-key":
            self.redirect(f"http://127.0.0.1:{external.server_port}/public?token={KEY}")
        elif url.path == "/cross-chain":
            self.redirect("/cross-token")
        elif url.path == "/cross-token":
            self.redirect(f"http://127.0.0.1:{external.server_port}/public?other=session-secret")
        elif url.path == "/cross-userinfo":
            self.redirect(f"http://user:secret@127.0.0.1:{external.server_port}/public")
        elif url.path == "/unsafe":
            self.redirect("file:///tmp/example")
        elif url.path == "/missing-location":
            self.send(302)
        elif url.path == "/login":
            self.redirect("/html", 303)
        elif url.path == "/html":
            self.send(body=b"<!doctype html><html><title>Login</title></html>",
                      Content_Type="application/x-bittorrent")
        elif url.path == "/json":
            self.send(body=b'{"message":"authentication required"}')
        elif url.path == "/xml":
            self.send(body=b'<error code="100" description="authentication required"/>')
        elif url.path == "/invalid":
            self.send(body=b"d4:infod4:name5:short", Content_Type="application/x-bittorrent")
        elif url.path == "/missing-info":
            self.send(body=b"d8:announce1:xe")
        elif url.path == "/empty":
            self.send()
        else:
            self.send(404)

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        parts = self.path.split("/", 2)
        if len(parts) != 3:
            self.send(400)
            return
        _, mode, endpoint = parts
        status = b'{"hash":"fixture-hash","title":"Lowercase"}'
        legacy = b'{"Hash":"fixture-hash","Title":"Legacy"}'
        if endpoint == "torrent/upload":
            if TORRENT not in body or b'name="file"' not in body or b'name="save"' not in body:
                self.send(400)
                return
        elif endpoint == "torrents":
            message = json.loads(body)
            if message.get("action") == "get" and message.get("hash") == "fixture-hash":
                self.send(body=status)
                return
            if message.get("action") == "list":
                self.send(body=b"[" + status + b"]")
                return
            if message.get("link") != MAGNET or message.get("save_to_db") is not True:
                self.send(400)
                return
        else:
            self.send(404)
            return

        replies = {
            "current": status,
            "legacy": b"[" + legacy + b"]",
            "invalid": b'{"hash":"fixture-hash","stat":"not-an-integer"}',
            "invalid-array": b"[" + status + b',{"hash":null}]',
            "unrelated": b'{"error":"unexpected shape"}',
            "html": b"<html>Unexpected</html>",
            "empty": b"",
            "empty-array": b"[]",
            "null": b"null",
        }
        if mode == "rejection":
            self.send(403, b"fixture-private-response")
        else:
            self.send(body=replies[mode])


external = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
jackett = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=external.serve_forever, daemon=True).start()
Path(sys.argv[1]).write_text(f"{jackett.server_port}\n{external.server_port}\n")
jackett.serve_forever()
