// Empty City Runner 云端静态服务器（HTTPS，pm2 托管）。
// 证书由本地 CA 签发（tools/certs/），iPhone 装过 ca.pem 就零拦截。
// 部署布局：本文件 + cert.pem/key.pem + web/（Godot 导出产物）放同一目录。
// 用法：pm2 start serve-game.js --name empty-city
const https = require("https");
const fs = require("fs");
const path = require("path");

const PORT = 3001;
const ROOT = path.join(__dirname, "web");
const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript",
  ".wasm": "application/wasm", // 必须正确，否则 Godot 加载失败
  ".pck": "application/octet-stream",
  ".png": "image/png",
};

const options = {
  key: fs.readFileSync(path.join(__dirname, "key.pem")),
  cert: fs.readFileSync(path.join(__dirname, "cert.pem")),
};

https
  .createServer(options, (req, res) => {
    let p = decodeURIComponent(new URL(req.url, "https://x").pathname);
    if (p === "/") p = "/index.html";
    const file = path.normalize(path.join(ROOT, p));
    if (!file.startsWith(ROOT)) {
      res.writeHead(403);
      return res.end();
    }
    fs.readFile(file, (err, data) => {
      if (err) {
        res.writeHead(404);
        return res.end("not found");
      }
      res.writeHead(200, {
        "Content-Type": MIME[path.extname(file)] || "application/octet-stream",
        // 关缓存：重新部署后手机刷新即生效（pck 才 18M，局外加载无所谓）
        "Cache-Control": "no-store",
        // 多线程构建需要的隔离头；当前单线程构建加了也无害
        "Cross-Origin-Opener-Policy": "same-origin",
        "Cross-Origin-Embedder-Policy": "require-corp",
      });
      res.end(data);
    });
  })
  .listen(PORT, () => console.log(`empty-city https server on :${PORT}`));
