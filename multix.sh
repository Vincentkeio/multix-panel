#!/bin/bash
# MultiX V9.0 - 旗舰全功能集成版 (无省略 | 双栈自愈 | 数据库范式改写)

INSTALL_PATH="/opt/multix_mvp"
CONFIG_FILE="${INSTALL_PATH}/.env"

# 颜色定义
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

# ==========================================
# 1. 深度清理与环境自愈 (彻底清除残留)
# ==========================================
force_fix_env() {
    echo -e "${Y}[*] 正在执行深度清理与依赖同步...${NC}"
    # 暴力清理旧进程与容器
    docker rm -f 3x-ui multix-agent 3x-ui-master 2>/dev/null
    pkill -9 -f app.py 2>/dev/null
    pkill -9 -f agent.py 2>/dev/null
    
    # 清理 APT 锁并同步
    rm -f /var/lib/dpkg/lock* /var/lib/apt/lists/lock 2>/dev/null
    apt-get update -y >/dev/null 2>&1
    apt-get install -y python3 python3-pip python3-full psmisc curl lsof sqlite3 netcat-openbsd docker.io --no-install-recommends >/dev/null 2>&1
    systemctl start docker >/dev/null 2>&1
    
    # 强制注入 Python 环境
    python3 -m pip install flask websockets psutil cryptography --break-system-packages --quiet --force-reinstall >/dev/null 2>&1 || true
    echo -e "${G}✅ 环境深度清理完成。${NC}"
}

get_all_ips() {
    IPV4=$(curl -4 -s --connect-timeout 5 https://api.ipify.org || echo "N/A")
    IPV6=$(curl -6 -s --connect-timeout 5 https://api64.ipify.org || echo "N/A")
}

# ==========================================
# 2. 凭据管理中心 (支持双栈查看与动态修改)
# ==========================================
manage_credentials() {
    clear
    get_all_ips
    [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
    
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 凭据管理中心 (V9.0)   "
    echo -e "${G}==================================${NC}"
    echo -e "${Y}[ 1. 主机网络信息 ]${NC}"
    echo -e "本机 IPv4: ${G}${IPV4}${NC}"
    echo -e "本机 IPv6: ${G}${IPV6}${NC}"
    echo -e "----------------------------------"
    echo -e "${Y}[ 2. 登录与连接信息 ]${NC}"
    echo -e "面板地址(v4): ${G}http://${IPV4}:${M_PORT:-未设置}${NC}"
    echo -e "面板地址(v6): ${G}http://[${IPV6}]:${M_PORT:-未设置}${NC}"
    echo -e "管理账号: ${G}${M_USER:-未设置}${NC}"
    echo -e "管理密码: ${G}${M_PASS:-未设置}${NC}"
    echo -e "通讯 Token: ${G}${M_TOKEN:-未设置}${NC}"
    echo -e "----------------------------------"
    echo -e "3. 修改账号密码 | 4. 修改端口/Token | 5. 重新安装 | 0. 返回"
    read -p "选择操作: " opt
    case $opt in
        3) read -p "新账号: " M_USER; read -p "新密码: " M_PASS; save_and_apply ;;
        4) read -p "新端口: " M_PORT; read -p "新Token: " M_TOKEN; save_and_apply ;;
        5) install_master ;;
        0) show_menu ;;
        *) manage_credentials ;;
    esac
}

save_and_apply() {
    cat > "$CONFIG_FILE" <<EOF
TYPE="MASTER"
M_PORT="$M_PORT"
M_USER="$M_USER"
M_PASS="$M_PASS"
M_TOKEN="$M_TOKEN"
EOF
    write_master_app_py
    pkill -9 -f app.py 2>/dev/null
    nohup python3 ${INSTALL_PATH}/master/app.py > /dev/null 2>&1 &
    echo -e "${G}✅ 配置已更新并应用。${NC}"
    read -p "回车继续..." ; manage_credentials
}

# ==========================================
# 3. 主控端逻辑 (Master - 全量代码)
# ==========================================
write_master_app_py() {
    source "$CONFIG_FILE"
    cat > "${INSTALL_PATH}/master/app.py" <<EOF
import json, asyncio, time, psutil, os, subprocess
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread

# 强注入变量
M_PORT = ${M_PORT}
M_USER = "${M_USER}"
M_PASS = "${M_PASS}"
M_TOKEN = "${M_TOKEN}"

app = Flask(__name__)
app.secret_key = M_TOKEN
AGENTS = {}
LOOP = None

# Vue 仪表盘全量代码
HTML_T = """
<!DOCTYPE html>
<html class="dark">
<head><meta charset="UTF-8"><script src="https://unpkg.com/vue@3/dist/vue.global.js"></script><script src="https://cdn.tailwindcss.com"></script></head>
<body class="bg-black text-gray-200 p-8">
    <div id="app">
        <div class="flex justify-between items-center mb-8">
            <h1 class="text-2xl font-bold text-blue-500">MultiX Control Center</h1>
            <div class="text-xs bg-zinc-900 p-2 rounded border border-white/10">TOKEN: {{token}}</div>
        </div>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <div v-for="(info, ip) in agents" class="bg-zinc-900 border border-white/5 p-5 rounded-2xl">
                <div class="flex justify-between font-bold mb-4"><span>{{ip}}</span><span class="text-green-500 underline text-xs">ONLINE</span></div>
                <div class="text-xs space-y-2 mb-4">
                    <div class="flex justify-between"><span>CPU</span><span>{{info.stats.cpu}}%</span></div>
                    <div class="flex justify-between"><span>MEM</span><span>{{info.stats.mem}}%</span></div>
                </div>
                <button @click="sync(ip)" class="w-full py-2 bg-blue-600 rounded-lg text-xs font-bold hover:bg-blue-700 transition">下发 Reality 节点</button>
            </div>
        </div>
    </div>
    <script>
        const { createApp, ref, onMounted } = Vue;
        createApp({
            setup() {
                const agents = ref({});
                const token = ref('$M_TOKEN');
                const update = async () => { const r = await fetch('/api/state'); const d = await r.json(); agents.value = d.agents; };
                const sync = async (ip) => {
                    const r = await fetch('/api/sync', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({ip}) });
                    const d = await r.json(); alert(d.msg);
                };
                onMounted(() => { update(); setInterval(update, 3000); });
                return { agents, token, sync };
            }
        }).mount('#app');
    </script>
</body></html>"""

@app.route('/api/state')
def get_state(): return jsonify({"agents": {ip: {"stats": info["stats"]} for ip, info in AGENTS.items()}})

@app.route('/api/sync', methods=['POST'])
def do_sync():
    target = request.json.get('ip')
    if target in AGENTS:
        # 下发完整的 Reality 配置字典
        payload = json.dumps({
            "action": "sync_node",
            "data": {
                "remark": "MX-Reality-443", "port": 443, "protocol": "vless",
                "settings": '{"clients": [{"id": "893d2564-968b-4b2a-89a0-6f29633c5e88", "flow": "xtls-rprx-vision"}], "decryption": "none"}',
                "stream_settings": '{"network": "tcp", "security": "reality", "realitySettings": {"show": false, "dest": "www.microsoft.com:443", "serverNames": ["www.microsoft.com"], "privateKey": "PRIVATE_KEY_HERE", "shortIds": ["6a7b8c9d0e1f"]}}',
                "sniffing": '{"enabled": true, "destOverride": ["http", "tls", "quic"]}'
            }
        })
        asyncio.run_coroutine_threadsafe(AGENTS[target]['ws'].send(payload), LOOP)
        return jsonify({"msg": "已向被控端推送数据包"})
    return jsonify({"msg": "节点不在线"}), 404

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form['u'] == M_USER and request.form['p'] == M_PASS:
            session['logged'] = True; return redirect('/')
    return '<h3>Login</h3><form method="post"><input name="u"><input name="p" type="password"><button>Go</button></form>'

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(HTML_T)

async def ws_handler(ws):
    ip = ws.remote_address[0]
    try:
        auth = await asyncio.wait_for(ws.recv(), timeout=10)
        if json.loads(auth).get('token') == M_TOKEN:
            AGENTS[ip] = {"ws": ws, "stats": {"cpu":0, "mem":0}}
            async for msg in ws:
                d = json.loads(msg)
                if d.get('type') == 'heartbeat': AGENTS[ip]['stats'] = d['data']
    finally:
        if ip in AGENTS: del AGENTS[ip]

def start_ws():
    global LOOP
    LOOP = asyncio.new_event_loop(); asyncio.set_event_loop(LOOP)
    srv = websockets.serve(ws_handler, "0.0.0.0", 8888)
    LOOP.run_until_complete(srv); LOOP.run_forever()

if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    app.run(host='0.0.0.0', port=M_PORT)
EOF
}

install_master() {
    echo -e "${G}[+] 正在全量安装主控端...${NC}"
    get_all_ips
    read -p "管理端口 [7575]: " M_PORT
    read -p "管理账号 [admin]: " M_USER
    read -p "管理密码 [admin]: " M_PASS
    M_TOKEN=$(openssl rand -hex 8)
    mkdir -p "${INSTALL_PATH}/master/db_data"
    cat > "$CONFIG_FILE" <<EOF
TYPE="MASTER"
M_PORT="${M_PORT:-7575}"
M_USER="${M_USER:-admin}"
M_PASS="${M_PASS:-admin}"
M_TOKEN="$M_TOKEN"
EOF
    write_master_app_py
    pkill -9 -f app.py 2>/dev/null
    nohup python3 ${INSTALL_PATH}/master/app.py > /dev/null 2>&1 &
    echo -e "${G}🎉 安装成功！请进入凭据中心查看登录地址。${NC}"
    read -p "回车返回..." ; show_menu
}

# ==========================================
# 4. 被控端逻辑 (Agent - 数据库改写核心)
# ==========================================
install_agent() {
    echo -e "${G}[+] 正在安装被控端 (IPv6 优先模式)...${NC}"
    read -p "主控 IPv6 或 IP: " M_HOST
    read -p "主控 Token: " A_TOKEN
    
    mkdir -p ${INSTALL_PATH}/agent/db_data
    # 核心 Agent 代码：包含动态 SQL 字段对齐
    cat > ${INSTALL_PATH}/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, socket

MASTER = "${M_HOST}"; TOKEN = "${A_TOKEN}"
DB_PATH = "/app/db_share/x-ui.db"

def sync_to_db(data):
    try:
        conn = sqlite3.connect(DB_PATH); cursor = conn.cursor()
        # 1. 嗅探本地 3X-UI 数据库字段
        cursor.execute("PRAGMA table_info(inbounds)")
        db_fields = [row[1] for row in cursor.fetchall()]
        # 2. 过滤掉本地数据库不存在的字段，防止 SQL 报错
        valid_data = {k: v for k, v in data.items() if k in db_fields}
        # 3. 写入或替换
        keys = ", ".join(valid_data.keys())
        placeholders = ", ".join(["?"] * len(valid_data))
        cursor.execute(f"INSERT OR REPLACE INTO inbounds ({keys}) VALUES ({placeholders})", list(valid_data.values()))
        conn.commit(); conn.close()
        return True
    except Exception as e:
        print(f"DB Error: {e}"); return False

async def run():
    # 使用 AF_UNSPEC 自动实现 IPv6 优先
    uri = f"ws://{MASTER}:8888"
    while True:
        try:
            async with websockets.connect(uri, family=socket.AF_UNSPEC) as ws:
                await ws.send(json.dumps({"token": TOKEN, "type": "auth"}))
                while True:
                    # 心跳汇报
                    stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent)}
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats}))
                    # 等待下发任务
                    msg = await asyncio.wait_for(ws.recv(), timeout=20)
                    task = json.loads(msg)
                    if task.get('action') == 'sync_node':
                        os.system("docker stop 3x-ui")
                        if sync_to_db(task['data']):
                            print("[*] 数据库改写成功")
                        os.system("docker start 3x-ui")
        except: await asyncio.sleep(5)

if __name__ == '__main__': asyncio.run(run())
EOF

    # 部署 Docker 容器
    docker pull ghcr.io/mhsanaei/3x-ui:latest >/dev/null 2>&1
    docker rm -f 3x-ui multix-agent 2>/dev/null
    docker run -d --name 3x-ui --restart always --network host -v ${INSTALL_PATH}/agent/db_data:/etc/x-ui ghcr.io/mhsanaei/3x-ui:latest
    
    cd ${INSTALL_PATH}/agent
    cat > Dockerfile <<'EOF'
FROM python:3.11-slim
RUN pip install --no-cache-dir websockets psutil
WORKDIR /app
CMD ["python", "agent.py"]
EOF
    docker build -t multix-agent-v9 . >/dev/null 2>&1
    docker run -d --name multix-agent --restart always --network host \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v ${INSTALL_PATH}/agent/db_data:/app/db_share \
      -v ${INSTALL_PATH}/agent:/app multix-agent-v9
    echo -e "${G}✅ 被控端部署完成！${NC}"
    read -p "回车返回..." ; show_menu
}

# ==========================================
# 5. 主菜单入口
# ==========================================
show_menu() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 旗舰全功能 V9.0      "
    echo -e "   IPv6优先 | 范式写入 | 深度自愈  "
    echo -e "${G}==================================${NC}"
    echo -e "1. 🚀 安装/重装 主控端"
    echo -e "2. 📡 安装/重装 被控端"
    echo -e "----------------------------------"
    echo -e "3. 🔑 凭据管理中心 (双栈/改密/查看)"
    echo -e "7. 🧹 深度环境清理 (解决一切报错)"
    echo -e "9. 🗑️  完全卸载系统"
    echo -e "0. 退出"
    read -p "操作: " opt
    case $opt in
        1) force_fix_env; install_master ;;
        2) force_fix_env; install_agent ;;
        3) manage_credentials ;;
        7) force_fix_env; read -p "清理完成..." ; show_menu ;;
        9) docker rm -f 3x-ui multix-agent 3x-ui-master; rm -rf $INSTALL_PATH; exit 0 ;;
        *) exit 0 ;;
    esac
}

mkdir -p "$INSTALL_PATH"
show_menu
