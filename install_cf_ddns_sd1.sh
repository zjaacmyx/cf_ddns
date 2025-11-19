#!/bin/bash
set -e

# -----------------------------
# Cloudflare DDNS 一键安装脚本（手动输入域名版）
# -----------------------------
# 手动输入域名
echo "[1/6] 🧱 修复 apt 源 & 安装依赖..."
sudo dpkg --configure -a
sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
sudo sed -i '/bullseye-backports/s/^/#/' /etc/apt/sources.list
sudo apt update -y
sudo apt install -y python3 python3-pip curl wget ufw iproute2 iptables dos2unix

echo "[2/6] 🐍 安装 Python 依赖..."

apt update
apt install -y python3-venv python3-full

python3 -m venv venv

# 不一定要激活环境，直接用 venv 里的 pip 更稳
./venv/bin/pip install -r requirements.txt

echo
read -p "[3/6] 🌐 请输入要绑定的 Cloudflare 域名 (例如: az-hk-6oj.aack.eu.org): " INPUT_DOMAIN
if [[ -z "$INPUT_DOMAIN" ]]; then
    echo "[错误] 域名不能为空！"
    exit 1
fi

echo "[3/6] 📜 写入 Cloudflare DDNS 单次运行脚本..."
cat >/root/cf_ddns.py <<EOF
# -*- coding: utf-8 -*-
import requests
import time
from datetime import datetime

# =============== 配置区域 ===============
EMAIL = "zjaacg@gmail.com"
GLOBAL_KEY = "4a2cbf42292cb56d6b3e3828a0c4c03fe3a48"
ZONE_ID = "5bcd4f03195a971cebd370e70161ed7d"
DOMAIN = "${INPUT_DOMAIN}"
# ======================================

def get_current_ip():
    """获取公网IP"""
    try:
        return requests.get("https://api.ipify.org").text.strip()
    except:
        return None

def get_record_id():
    """获取 Cloudflare 上该域名的 Record ID"""
    url = f"https://api.cloudflare.com/client/v4/zones/{ZONE_ID}/dns_records?type=A&name={DOMAIN}"
    headers = {"X-Auth-Email": EMAIL, "X-Auth-Key": GLOBAL_KEY}
    resp = requests.get(url, headers=headers)
    data = resp.json()
    if data.get("success") and data["result"]:
        return data["result"][0]["id"]
    return None

def update_dns(ip, record_id):
    """更新 Cloudflare A 记录"""
    url = f"https://api.cloudflare.com/client/v4/zones/{ZONE_ID}/dns_records/{record_id}"
    headers = {
        "X-Auth-Email": EMAIL,
        "X-Auth-Key": GLOBAL_KEY,
        "Content-Type": "application/json",
    }
    data = {"type": "A", "name": DOMAIN, "content": ip, "ttl": 120, "proxied": False}
    resp = requests.put(url, headers=headers, json=data)
    return resp.json()

def main():
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"\\n========== Cloudflare DDNS 执行时间: {now} ==========")
    time.sleep(15)  # 延迟 15 秒，确保网络上线

    record_id = get_record_id()
    if not record_id:
        print(f"[错误] 找不到 {DOMAIN} 的 A 记录，请先在 Cloudflare 添加一条 A 记录")
        return

    current_ip = get_current_ip()
    if current_ip:
        print(f"[当前公网IP] {current_ip}")
        result = update_dns(current_ip, record_id)
        if result.get("success"):
            print(f"[成功] 已更新 {DOMAIN} -> {current_ip}")
        else:
            print("[失败] 更新失败", result)
    else:
        print("[错误] 无法获取公网IP")

if __name__ == "__main__":
    main()
EOF

echo "[4/6] ⚙️ 创建 systemd 服务..."
cat >/etc/systemd/system/cf-ddns-once.service <<'EOF'
[Unit]
Description=Run Cloudflare DDNS once on boot (with delay)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 15
ExecStart=/usr/bin/python3 /root/cf_ddns.py
StandardOutput=append:/root/cf_ddns.log
StandardError=append:/root/cf_ddns.log

[Install]
WantedBy=multi-user.target
EOF

echo "[5/6] 🔧 修正换行符并启用服务..."
dos2unix /root/cf_ddns.py /etc/systemd/system/cf-ddns-once.service /root/install_cf_ddns.sh >/dev/null 2>&1 || true
systemctl daemon-reload
systemctl enable cf-ddns-once.service

echo "[6/6] 🚀 立即执行一次 Cloudflare DDNS..."
python3 /root/cf_ddns.py | tee -a /root/cf_ddns.log

echo
echo "✅ 部署完成！Cloudflare DDNS 将在每次开机后延迟 15 秒自动运行一次。"
echo "📄 日志文件位置: /root/cf_ddns.log"
echo "🧩 如要修改域名或API信息，请编辑: /root/cf_ddns.py"
