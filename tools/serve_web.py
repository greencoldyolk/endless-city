"""在局域网起一个静态服务器给 iPhone Safari 玩网页版。

用法：.venv/bin/python tools/serve_web.py   （或系统 python3 也行）
然后 iPhone 连同一个 Wi-Fi，Safari 打开脚本打印的地址。

- 自带 .wasm 的正确 MIME（老 Python 缺这个会导致加载失败）
- 加 COOP/COEP 头（多线程构建需要；单线程构建加了也无害）
- 关缓存，改完重导出刷新即生效
"""
import http.server
import socket
import socketserver
import ssl
import subprocess
from pathlib import Path

PORT = 8060
ROOT = Path(__file__).resolve().parent.parent / "build" / "web"
CERT_DIR = Path(__file__).resolve().parent / "certs"


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
    }

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)


def lan_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    finally:
        s.close()


if __name__ == "__main__":
    # 多线程必须：Safari 会并发开多条连接，单线程服务器在 TLS 下会互相卡死
    with http.server.ThreadingHTTPServer(("", PORT), Handler) as httpd:
        # Godot 4 网页版要求"安全上下文"（音频 Worklet 等），localhost 天然安全，
        # 但手机走局域网 IP 必须 HTTPS——自签名证书，手机上首次访问需手动信任
        # 证书由 tools/make_certs.sh 生成（本地 CA 签发；iPhone 装一次 ca.pem
        # 并开完全信任后不再有任何拦截）。IP 变了重跑 make_certs.sh 即可
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(CERT_DIR / "cert.pem", CERT_DIR / "key.pem")
        httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
        name = subprocess.run(["scutil", "--get", "LocalHostName"],
                              capture_output=True, text=True).stdout.strip()
        print(f"iPhone 上打开: https://{name}.local:{PORT}  （推荐，换 IP 不受影响）")
        print(f"      或 IP 版: https://{lan_ip()}:{PORT}")
        httpd.serve_forever()
