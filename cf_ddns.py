# -*- coding: utf-8 -*-
import requests
import time

# ================= 配置区域 =================
EMAIL     = "你的Cloudflare登录邮箱"   # ⚠️ 这里改成你登录 Cloudflare 的邮箱
GLOBAL_KEY = "4a2cbf42292cb56d6b3e3828a0c4c03fe3a48"  # 你的 Global API Key
ZONE_ID   = "5bcd4f03195a971cebd370e70161ed7d"        # Zone ID
DOMAIN    = "twisp.aack.eu.org"  # 要更新的域名
CHECK_INTERVAL = 5  # 每次检查间隔秒数
# ===========================================

def get_current_ip():
    """获取公网IP"""
    try:
        return requests.get("https://api.ipify.org").text.strip()
    except:
        return None

def get_record_id():
    """获取 Cloudflare 上该域名的 Record ID"""
    url = f"https://api.cloudflare.com/client/v4/zones/{ZONE_ID}/dns_records?type=A&name={DOMAIN}"
    headers = {
        "X-Auth-Email": EMAIL,
        "X-Auth-Key": GLOBAL_KEY
    }
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
    data = {
        "type": "A",
        "name": DOMAIN,
        "content": ip,
        "ttl": 120,     # 120秒缓存
        "proxied": False  # 是否启用CDN代理 (True = 开启橙色云)
    }
    resp = requests.put(url, headers=headers, json=data)
    return resp.json()

def main():
    record_id = get_record_id()
    if not record_id:
        print(f"[错误] 找不到 {DOMAIN} 的 A 记录，请先在 Cloudflare 添加一条 A 记录")
        return

    last_ip = None
    while True:
        current_ip = get_current_ip()
        if current_ip:
            if current_ip != last_ip:
                print(f"[检测到IP变化] {last_ip} -> {current_ip}")
                result = update_dns(current_ip, record_id)
                if result.get("success"):
                    print(f"[成功] 已更新 {DOMAIN} -> {current_ip}")
                    last_ip = current_ip
                else:
                    print("[失败] 更新失败", result)
            else:
                print(f"[无变化] 当前IP: {current_ip}")
        else:
            print("[错误] 获取公网IP失败")

        time.sleep(CHECK_INTERVAL)

if __name__ == "__main__":
    main()

