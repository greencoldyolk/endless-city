#!/bin/bash
# 本地 HTTPS 证书链：本地 CA + 由它签发的服务器证书。
#
# 为什么需要 CA：裸自签名证书 iOS 只能每次临时豁免，加到主屏幕的
# standalone app 每次冷启动都会重新拦截；只有"系统信任的 CA 签发的证书"
# 才能一次性放行。CA 只需要在 iPhone 上安装一次：
#   1. 把 tools/certs/ca.pem 隔空投送到 iPhone，打开
#   2. 设置 → 通用 → VPN与设备管理 → 安装描述文件
#   3. 设置 → 通用 → 关于本机 → 证书信任设置 → 对 EmptyCity Local CA 开完全信任
#
# 服务器证书同时签了局域网 IP 和 Mac 的 .local 域名（Bonjour），
# 建议手机上用 https://<名字>.local:8060 访问——路由器换 IP 也不受影响。
# IP 变了只需重跑本脚本重新签发（CA 不变，手机不用动）。
set -euo pipefail
cd "$(dirname "$0")/certs"

IP=$(ipconfig getifaddr en0)
NAME="$(scutil --get LocalHostName).local"

# CA 只生成一次（重新生成就得重新在手机上装一遍，所以尽量别删）
if [ ! -f ca-key.pem ]; then
	openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
		-keyout ca-key.pem -out ca.pem \
		-subj "/CN=EmptyCity Local CA" \
		-addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
		-addext "keyUsage=critical,keyCertSign,cRLSign"
	echo "== 新建了本地 CA：需要在 iPhone 上安装并信任 tools/certs/ca.pem =="
fi

# 服务器证书：825 天以内（苹果对 TLS 证书有效期的硬性要求），
# 必须带 SAN 和 serverAuth，否则 iOS 拒绝
openssl req -newkey rsa:2048 -sha256 -nodes \
	-keyout key.pem -out server.csr -subj "/CN=EmptyCityRunner"
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca-key.pem \
	-CAcreateserial -out cert.pem -days 820 -sha256 \
	-extfile <(printf "subjectAltName=DNS:localhost,DNS:%s,IP:%s\nextendedKeyUsage=serverAuth\nkeyUsage=critical,digitalSignature,keyEncipherment\nbasicConstraints=CA:FALSE\n" "$NAME" "$IP")
rm -f server.csr

echo "服务器证书已签发：https://$NAME:8060  /  https://$IP:8060"
