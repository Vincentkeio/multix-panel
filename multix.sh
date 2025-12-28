#!/bin/bash
# MultiX V3.95 - 终极加固版 (Host模式 + 智能修复 + 动态自愈)

INSTALL_PATH="/opt/multix_mvp"
MASTER_DOMAIN="multix.spacelite.top"

# 颜色定义
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 管理系统 V3.95       "
    echo -e "    Host模式自愈 | 智能一键修复    "
    echo -e "${G}==================================${NC}"
    echo "1. 🚀 安装/重装 主控端 (Master)"
    echo "2. 🗑️  卸载 主控端 (Master)"
    echo "----------------------------------"
    echo "3. 📡 安装/重装 被控端 (Agent + 3x-ui)"
    echo "4. 🗑️  卸载 被控端 (Agent)"
    echo "----------------------------------"
    echo "7. 🔧 智能一键修复 (不删数据，解决死机)"
    echo "----------------------------------"
    echo "5. 🚪 退出"
    echo -e "${G}==================================${NC}"
    read -p "请选择操作 [1-7]: " choice
}

# --- 核心功能：智能修复逻辑 ---
smart_repair() {
    echo -e "${Y}[*] 启动智能修复流程...${NC}"
    
    # 1. 端口冲突治理
    echo "[+] 检查 2053/2096 端口占用情况..."
    systemctl stop x-ui 2>/dev/null
    systemctl disable x-ui 2>/dev/null
    
    # 查找占用端口但不是 Docker 的进程
    for port in 2053 2096; do
        PID=$(lsof -t -i:$port)
        if [ ! -z "$PID" ]; then
            # 检查该 PID 是否属于 docker
            if ! ps -p $PID -o comm= | grep -qi "docker"; then
                echo -e "${R}[!] 发现非 Docker 进程 $PID 占用端口 $port，正在清理...${NC}"
                kill -9 $PID 2>/dev/null
            fi
        fi
    done

    # 2. 数据库解锁与配置修复
    DB_FILE="${INSTALL_PATH}/agent/db_data/x-ui.db"
    if [ -f "$DB_FILE" ]; then
        echo "[+] 正在执行数据库无损修复..."
        # 清除 SQLite 锁文件
        rm -f "${DB_FILE}-wal" "${DB_FILE}-shm"
        # 强制修正面板端口（从数据库内部修正）
        read -p "请输入您设定的面板端口 [回车跳过]: " FIX_PORT
        if [ ! -z "$FIX_PORT" ]; then
            sqlite3 "$DB_FILE" "UPDATE settings SET value = '$FIX_PORT' WHERE name = 'webPort';"
        fi
    fi

    # 3. 容器重启自愈
    echo "[+] 重启容器服务..."
    docker restart 3x-ui multix-agent 2>/dev/null
    
    echo -e "${G}✅ 修复尝试完成！请检查面板是否恢复。${NC}"
    sleep 2
}

# --- 安装主控端 (含鉴权) ---
install_master() {
    echo -e "${G}[+] 启动主控安装向导...${NC}"
    read -p "设置管理 Web 端口 [默认 7575]: " M_PORT
    M_PORT=${M_PORT:-7575}
    read -p "设置管理员账号 [默认 admin]: " M_USER
    M_USER=${M_USER:-admin}
    read -p "设置管理员密码 [默认 admin123]: " M_PASS
    M_PASS=${M_PASS:-admin123}
    DEF_TOKEN=$(openssl rand -hex 8)
    read -p "设置通信 Token [默认 $DEF_TOKEN]: " M_TOKEN
    M_TOKEN=${M_TOKEN:-$DEF_TOKEN}

    mkdir -p ${INSTALL_PATH}/master
    apt update && apt install -y python3 python3-pip psmisc curl lsof
    pip3 install flask websockets psutil --break-system-packages --quiet || pip3 install flask websockets psutil --quiet

    cat > ${INSTALL_PATH}/master/app.py <<EOF
import json, asyncio, time, psutil, secrets, os
from flask import Flask, render_template_string, request, session, redirect
import websockets
from threading import Thread

app = Flask(__name__)
app.secret_key = "$M_TOKEN"
AGENTS = {} 
LOOP = None
AUTH_TOKEN = "$M_TOKEN"

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form['u'] == "$M_USER" and request.form['p'] == "$M_PASS":
            session['logged'] = True
            return redirect('/')
    return '<h2>MultiX Login</h2><form method="post">User: <input name="u"><br>Pass: <input name="p" type="password"><br><button>Login</button></form>'

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string("""
    <h2>🛰️ MultiX V3.95 管理台</h2>
    <div style="background:#222;color:#eee;padding:15px;border-radius:10px">
        <p>在线节点: {{ agents_count }} | Token: <code>$M_TOKEN</code></p>
        {% for ip, info in agents.items() %}
        <div>🌐 {{ ip }} | CPU: {{ info.stats.cpu }}% | MEM: {{ info.stats.mem }}%</div>
        {% endfor %}
    </div>
    <form action="/send" method="post" style="margin-top:20px">
        备注: <input name="remark" value="V395_STABLE"> 端口: <input name="port" value="12345"> 
        <button type="submit">🚀 全集群同步</button>
    </form>
    """, agents_count=len(AGENTS), agents=AGENTS)

@app.route('/send', methods=['POST'])
def send_cmd():
    if not session.get('logged'): return "Unauthorized"
    node_data = {
        "remark": f"MX-{request.form['remark']}", "port": int(request.form['port']), "protocol": "vless",
        "settings": json.dumps({"clients": [{"id": secrets.token_hex(16), "flow": "xtls-rprx-vision"}], "decryption": "none"}),
        "stream_settings": json.dumps({"network": "tcp", "security": "reality", "realitySettings": {"show": False, "dest": "www.microsoft.com:443", "serverNames": ["www.microsoft.com"], "privateKey": "YOUR_KEY", "shortIds": ["abcdef123456"]}}),
        "sniffing": json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic"]})
    }
    payload = json.dumps({"action": "sync_node", "data": node_data, "token": AUTH_TOKEN})
    if LOOP:
        for ip in list(AGENTS.keys()): LOOP.call_soon_threadsafe(asyncio.create_task, AGENTS[ip]['ws'].send(payload))
    return "✅ 已同步下发！"

async def ws_server(websocket):
    ip = websocket.remote_address[0]
    try:
        auth_msg = await asyncio.wait_for(websocket.recv(), timeout=10)
        if json.loads(auth_msg).get('token') != AUTH_TOKEN: return
        AGENTS[ip] = {"ws": websocket, "stats": {"cpu":0, "mem":0}}
        async for msg in websocket:
            data = json.loads(msg)
            if data.get('type') == 'heartbeat': AGENTS[ip]['stats'] = data['data']
    finally:
        if ip in AGENTS: del AGENTS[ip]

async def start_ws():
    global LOOP
    LOOP = asyncio.get_running_loop()
    async with websockets.serve(ws_server, "::", 8888): await asyncio.Future()

if __name__ == '__main__':
    Thread(target=lambda: asyncio.run(start_ws()), daemon=True).start()
    app.run(host='0.0.0.0', port=$M_PORT)
EOF
    pkill -9 -f app.py 2>/dev/null
    nohup python3 ${INSTALL_PATH}/master/app.py > ${INSTALL_PATH}/master/master.log 2>&1 &
    
    IPV4=$(curl -s4 https://api64.ipify.org || echo "None")
    echo -e "${G}==========================================${NC}"
    echo -e "🎉 主控部署成功！访问: http://${IPV4}:${M_PORT}"
    echo -e "🔑 鉴权 Token: ${Y}${M_TOKEN}${NC}"
    echo -e "${G}==========================================${NC}"
    read -p "按回车返回"
}

# --- 安装被控端 (含智能避让与Host模式) ---
install_agent() {
    echo -e "${G}--- 被控端安装 (Host自愈版) ---${NC}"
    read -p "请输入主控 Token: " A_TOKEN
    read -p "自定义面板端口 [默认 2053]: " P_WEB
    P_WEB=${P_WEB:-2053}

    # 前置清理：不仅停服务，还要强杀非Docker占用
    systemctl stop x-ui 2>/dev/null
    systemctl disable x-ui 2>/dev/null
    fuser -k ${P_WEB}/tcp 2096/tcp 2>/dev/null

    apt update && apt install -y sqlite3 docker.io psmisc lsof
    mkdir -p ${INSTALL_PATH}/agent/db_data

    docker rm -f 3x-ui multix-agent 2>/dev/null
    
    # 强制环境变量覆盖面板端口
    docker run -d --name 3x-ui --restart always --network host \
      -e XUI_PORT=${P_WEB} \
      -v ${INSTALL_PATH}/agent/db_data:/etc/x-ui ghcr.io/mhsanaei/3x-ui:latest

    cat > ${INSTALL_PATH}/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, docker, time
MASTER_WS = "ws://${MASTER_DOMAIN}:8888"
TOKEN = "$A_TOKEN"
DB_PATH = "/app/db_share/x-ui.db"

def get_db_columns():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(inbounds)")
    cols = [i[1] for i in cursor.fetchall()]
    conn.close(); return cols

async def handle_task(data):
    try:
        client = docker.from_env(); xui = client.containers.get("3x-ui")
        cols = get_db_columns()
        xui.stop(); time.sleep(2)
        conn = sqlite3.connect(DB_PATH); cursor = conn.cursor()
        mapping = {
            "remark": data['remark'], "port": int(data['port']), "protocol": data['protocol'],
            "settings": data['settings'], "stream_settings": data['stream_settings'],
            "sniffing": data['sniffing'], "enable": 1, "tag": f"inbound-{data['port']}",
            "up": 0, "down": 0, "total": 0, "expiry_time": 0, "user_id": 1
        }
        final_fields = [f for f in cols if f in mapping or f == "id"]
        placeholders = ",".join(["?" if f != "id" else "NULL" for f in final_fields])
        sql = f"INSERT OR REPLACE INTO inbounds ({','.join(final_fields)}) VALUES ({placeholders})"
        cursor.execute(sql, [mapping[f] for f in final_fields if f != "id"])
        conn.commit(); conn.close(); xui.start()
        print(f"[+] 动态同步成功")
    except Exception as e: print(f"Error: {e}")

async def run_agent():
    while True:
        try:
            async with websockets.connect(MASTER_WS) as ws:
                await ws.send(json.dumps({"token": TOKEN}))
                while True:
                    stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent)}
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats}))
                    msg = await asyncio.wait_for(ws.recv(), timeout=25)
                    task = json.loads(msg)
                    if task.get('token') == TOKEN: await handle_task(task['data'])
        except: await asyncio.sleep(5)

if __name__ == '__main__': asyncio.run(run_agent())
EOF

    cd ${INSTALL_PATH}/agent
    cat > Dockerfile <<EOF
FROM python:3.11-slim
RUN pip install --no-cache-dir websockets psutil docker -i https://pypi.tuna.tsinghua.edu.cn/simple
WORKDIR /app
CMD ["python", "-u", "agent.py"]
EOF
    docker build -t multix-agent-image .
    docker run -d --name multix-agent --restart always --network host \
      -v /var/run/docker.sock:/var/run/docker.sock -v ${INSTALL_PATH}/agent:/app \
      -v ${INSTALL_PATH}/agent/db_data:/app/db_share multix-agent-image

    echo -e "${G}✅ 部署完成！面板地址: http://小鸡IP:${P_WEB}${NC}"
    read -p "按回车返回"
}

while true; do show_menu; case $choice in 1) install_master ;; 3) install_agent ;; 7) smart_repair ;; 5) exit 0 ;; esac; done
