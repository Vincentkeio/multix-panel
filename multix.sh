#!/bin/bash
# MultiX V6.8 - 旗舰全能版 (全功能档案库 + 实时日志诊断)

INSTALL_PATH="/opt/multix_mvp"
ENV_FILE="$INSTALL_PATH/.env"
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

# --- 身份感知 ---
IS_MASTER=false
IS_AGENT=false
[ -f "$INSTALL_PATH/master/app.py" ] && IS_MASTER=true
[ -f "$INSTALL_PATH/agent/agent.py" ] && IS_AGENT=true

# --- 核心函数：服务修复 ---
service_fix() {
    echo -e "${Y}[*] 正在执行系统自愈...${NC}"
    pkill -9 -f app.py
    fuser -k 7575/tcp 8888/tcp 2>/dev/null
    docker restart multix-engine multix-agent 3x-ui 2>/dev/null
    [ -f "$INSTALL_PATH/master/app.py" ] && nohup python3 $INSTALL_PATH/master/app.py > /dev/null 2>&1 &
    echo -e "${G}✅ 修复动作已执行。${NC}"
    sleep 2
}

# --- 核心函数：实时诊断 ---
run_diagnose() {
    clear
    echo -e "${G}=== MultiX 深度诊断系统 ===${NC}"
    if [ "$IS_MASTER" = true ]; then
        echo -e "${Y}[主控模式自检]${NC}"
        echo -n "  Web 面板 (7575): "
        nc -zt 127.0.0.1 7575 &>/dev/null && echo -e "${G}RUNNING${NC}" || echo -e "${R}DOWN${NC}"
        echo -n "  通信端口 (8888): "
        nc -zt 127.0.0.1 8888 &>/dev/null && echo -e "${G}RUNNING${NC}" || echo -e "${R}DOWN${NC}"
        echo -n "  Reality 引擎: "
        docker ps | grep -q "multix-engine" && echo -e "${G}ONLINE${NC}" || echo -e "${R}OFFLINE${NC}"
    fi
    if [ "$IS_AGENT" = true ]; then
        echo -e "\n${Y}[被控模式链路拨测]${NC}"
        A_WS=$(grep "MASTER_WS =" "$INSTALL_PATH/agent/agent.py" | cut -d'"' -f2)
        A_IP=$(echo $A_WS | cut -d'/' -f3 | cut -d':' -f1)
        echo -n "  主控链路拨测 ($A_IP): "
        nc -ztw 3 $A_IP 8888 &>/dev/null && echo -e "${G}通畅${NC}" || echo -e "${R}阻塞${NC}"
        echo -e "${Y}>>> 正在拉取实时握手日志 (按 Ctrl+C 停止诊断并返回) <<<${NC}"
        docker logs -f --tail 20 multix-agent
    fi
    read -p "诊断结束，按回车返回..."
}

# --- 核心函数：档案库与修改 ---
manage_config() {
    clear
    echo -e "${G}=== MultiX 凭据档案管理 ===${NC}"
    if [ -f "$ENV_FILE" ]; then
        echo -e "${Y}[当前配置信息]${NC}"
        cat "$ENV_FILE" | sed 's/=/ : /g'
    else
        echo -e "${R}未找到 .env 配置文件。${NC}"
    fi
    
    echo -e "\n----------------------------------"
    echo "1. 修改通信 Token (主被控需一致)"
    echo "2. [主控] 修改管理账号/密码"
    echo "3. [被控] 修改主控 IP 地址"
    echo "0. 返回菜单"
    read -p "请选择修改项: " cf_choice
    
    case $cf_choice in
        1) read -p "输入新 Token: " nt
           [ ! -z "$nt" ] && sed -i "s/TOKEN=.*/TOKEN=$nt/" $ENV_FILE && sed -i "s/AUTH_TOKEN = .*/AUTH_TOKEN = \"$nt\"/" $INSTALL_PATH/master/app.py 2>/dev/null && sed -i "s/TOKEN = .*/TOKEN = \"$nt\"/" $INSTALL_PATH/agent/agent.py 2>/dev/null ;;
        2) read -p "新账号: " nu; read -p "新密码: " np
           [ ! -z "$nu" ] && sed -i "s/USER=.*/USER=$nu/" $ENV_FILE && sed -i "s/request.form\['u'\] == .*/request.form\['u'\] == \"$nu\"/" $INSTALL_PATH/master/app.py
           [ ! -z "$np" ] && sed -i "s/PASS=.*/PASS=$np/" $ENV_FILE && sed -i "s/request.form\['p'\] == .*/request.form\['p'\] == \"$np\"/" $INSTALL_PATH/master/app.py ;;
        3) read -p "新主控 IP: " ni
           [ ! -z "$ni" ] && sed -i "s/MASTER_IP=.*/MASTER_IP=$ni/" $ENV_FILE && sed -i "s/MASTER_WS = .*/MASTER_WS = \"ws:\/\/$ni:8888\"/" $INSTALL_PATH/agent/agent.py ;;
    esac
    service_fix
}

# --- 安装引导 (主控) ---
install_master() {
    clear
    echo -e "${G}>>> 主控端安装引导${NC}"
    read -p "设置登录账号 [admin]: " M_USER; M_USER=${M_USER:-admin}
    read -p "设置登录密码 [admin]: " M_PASS; M_PASS=${M_PASS:-admin}
    read -p "通信 Token [随机]: " M_TOKEN; M_TOKEN=${M_TOKEN:-$(openssl rand -hex 8)}
    
    mkdir -p $INSTALL_PATH/master
    echo "TYPE=MASTER" > $ENV_FILE
    echo "USER=$M_USER" >> $ENV_FILE
    echo "PASS=$M_PASS" >> $ENV_FILE
    echo "TOKEN=$M_TOKEN" >> $ENV_FILE
    
    docker pull ghcr.io/mhsanaei/3x-ui:latest &>/dev/null
    docker run -d --name multix-engine -p 2053:2053 --restart always ghcr.io/mhsanaei/3x-ui:latest &>/dev/null

    # 写入主控代码逻辑
    cat > $INSTALL_PATH/master/app.py <<EOF
import json, asyncio, time, psutil, os, base64, subprocess
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread

app = Flask(__name__)
app.secret_key = "$M_TOKEN"
AGENTS = {} 
LOOP = None
AUTH_TOKEN = "$M_TOKEN"

def get_engine_keys():
    try:
        out = subprocess.check_output("docker exec multix-engine xray x25519", shell=True).decode()
        lines = [l for l in out.split('\\n') if l.strip()]
        return lines[0].split(': ')[1].strip(), lines[1].split(': ')[1].strip()
    except: return "Error", "Error"

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><script src="https://cdn.tailwindcss.com"></script></head>
<body class="bg-black text-gray-300 font-sans">
    <div class="flex h-screen">
        <div class="w-64 bg-zinc-950 border-r border-white/5 p-6">
            <h1 class="text-xl font-bold text-white italic">🛰️ MultiX V6.8</h1>
            <p class="text-[10px] text-zinc-500 mt-2 font-mono">User: $M_USER</p>
            <button onclick="location.reload()" class="w-full mt-10 p-3 bg-blue-600 rounded-xl font-bold">刷新集群</button>
        </div>
        <div class="flex-1 p-10 overflow-y-auto">
            <h2 class="text-3xl font-bold text-white mb-10">在线小鸡 ({{ agents_count }})</h2>
            <div class="grid grid-cols-3 gap-6">
                {% for ip, info in agents.items() %}
                <div class="bg-zinc-900 border border-white/5 p-6 rounded-3xl">
                    <div class="flex justify-between items-center mb-4"><span>{{ ip }}</span><span class="w-2 h-2 bg-green-500 rounded-full animate-pulse"></span></div>
                    <button onclick="openEdit('{{ ip }}')" class="w-full py-2 bg-zinc-800 hover:bg-blue-600 rounded-xl text-sm transition">配置管理</button>
                </div>
                {% endfor %}
            </div>
        </div>
    </div>
    <div id="modal" class="fixed inset-0 bg-black/90 hidden items-center justify-center">
        <div class="bg-zinc-900 w-[450px] p-8 rounded-[32px] border border-white/10 shadow-2xl">
            <h3 class="text-white mb-6 font-bold text-lg">下发配置: <span id="tip" class="text-blue-500"></span></h3>
            <div class="space-y-4">
                <input id="uuid" placeholder="UUID" class="w-full bg-black border border-white/5 p-3 rounded-xl text-sm outline-none">
                <div class="flex gap-2"><input id="priv" placeholder="Reality 私钥" class="flex-1 bg-black border border-white/5 p-3 rounded-xl text-sm outline-none"><button onclick="gk()" class="bg-green-600/20 text-green-500 px-4 rounded-xl text-xs font-bold border border-green-500/20">生成</button></div>
                <input id="pub" readonly placeholder="公钥 (自动同步显示)" class="w-full bg-zinc-800/30 p-3 rounded-xl text-[10px] text-zinc-500 outline-none">
                <div class="flex gap-4 pt-4"><button onclick="closeM()" class="flex-1 py-3 bg-zinc-800 rounded-xl">取消</button><button onclick="ss()" class="flex-1 py-3 bg-blue-600 text-white font-bold rounded-xl shadow-lg">🚀 同步下发</button></div>
            </div>
        </div>
    </div>
    <script>
        let cur = "";
        function openEdit(ip) { cur = ip; document.getElementById('tip').innerText = ip; document.getElementById('modal').style.display = 'flex'; }
        function closeM() { document.getElementById('modal').style.display = 'none'; }
        async function gk() { const r = await fetch('/gen_keys'); const d = await r.json(); document.getElementById('priv').value = d.priv; document.getElementById('pub').value = d.pub; }
        async function ss() {
            const data = { ip: cur, uuid: document.getElementById('uuid').value, priv: document.getElementById('priv').value };
            const r = await fetch('/send', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(data) });
            const res = await r.json(); alert(res.msg); closeM();
        }
    </script>
</body>
</html>
"""

@app.route('/gen_keys')
def g_keys():
    priv, pub = get_engine_keys()
    return jsonify({"priv": priv, "pub": pub})

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form['u'] == "$M_USER" and request.form['p'] == "$M_PASS":
            session['logged'] = True
            return redirect('/')
    return '<h3>Auth</h3><form method="post"><input name="u"><input name="p" type="password"><button>Go</button></form>'

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(HTML_TEMPLATE, agents_count=len(AGENTS), agents=AGENTS, auth_token=AUTH_TOKEN)

@app.route('/send', methods=['POST'])
def send():
    req = request.json
    node_data = {"remark": "V68_SYNC", "port": 443, "protocol": "vless", "settings": json.dumps({"clients": [{"id": req['uuid'], "flow": "xtls-rprx-vision"}]}), "stream_settings": json.dumps({"network": "tcp", "security": "reality", "realitySettings": {"privateKey": req['priv'], "dest": "www.microsoft.com:443", "serverNames": ["www.microsoft.com"]}}), "sniffing": json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic"]})}
    payload = json.dumps({"action": "sync_node", "data": node_data, "token": AUTH_TOKEN})
    if req['ip'] in AGENTS:
        asyncio.run_coroutine_threadsafe(AGENTS[req['ip']]['ws'].send(payload), LOOP)
        return jsonify({"msg": "✅ 已下发"})
    return jsonify({"msg": "❌ 离线"})

async def ws_server(websocket):
    ip = websocket.remote_address[0]
    try:
        auth = await asyncio.wait_for(websocket.recv(), timeout=10)
        if json.loads(auth).get('token') != AUTH_TOKEN: return
        AGENTS[ip] = {"ws": websocket, "stats": {"cpu":0}}
        async for msg in websocket: pass
    finally:
        if ip in AGENTS: del AGENTS[ip]

def run_loop():
    global LOOP
    LOOP = asyncio.new_event_loop(); asyncio.set_event_loop(LOOP)
    LOOP.run_until_complete(websockets.serve(ws_server, "0.0.0.0", 8888))
    LOOP.run_forever()

if __name__ == '__main__':
    Thread(target=run_loop, daemon=True).start()
    app.run(host='0.0.0.0', port=7575)
EOF

    service_fix
    echo -e "${G}🎉 安装摘要: 账号 $M_USER | 密码 $M_PASS | Token $M_TOKEN${NC}"
    read -p "凭据已存入档案库，按回车返回菜单..."
}

# --- 安装引导 (被控) ---
install_agent() {
    clear
    echo -e "${G}>>> 被控端安装引导${NC}"
    read -p "主控端公网 IP: " M_IP
    read -p "通信 Token: " A_TOKEN
    
    mkdir -p $INSTALL_PATH/agent
    echo "TYPE=AGENT" > $ENV_FILE
    echo "MASTER_IP=$M_IP" >> $ENV_FILE
    echo "TOKEN=$A_TOKEN" >> $ENV_FILE
    
    # 安装 Docker 依赖并启动容器逻辑保持原样
    apt update && apt install -y sqlite3 docker.io psmisc lsof curl
    mkdir -p ${INSTALL_PATH}/agent/db_data
    docker rm -f 3x-ui multix-agent 2>/dev/null
    docker run -d --name 3x-ui --restart always --network host -e XUI_PORT=2053 -v ${INSTALL_PATH}/agent/db_data:/etc/x-ui ghcr.io/mhsanaei/3x-ui:latest

    cat > ${INSTALL_PATH}/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, docker, time
MASTER_WS = "ws://${M_IP}:8888"
TOKEN = "$A_TOKEN"
DB_PATH = "/app/db_share/x-ui.db"

async def handle_task(data):
    try:
        client = docker.from_env(); xui = client.containers.get("3x-ui")
        xui.stop(); time.sleep(2)
        conn = sqlite3.connect(DB_PATH); cursor = conn.cursor()
        cursor.execute("INSERT OR REPLACE INTO inbounds (remark, port, protocol, settings, stream_settings, sniffing, enable, tag, up, down, total, expiry_time) VALUES (?, ?, ?, ?, ?, ?, 1, ?, 0, 0, 0, 0)", 
                       (data['remark'], data['port'], data['protocol'], data['settings'], data['stream_settings'], data['sniffing'], f"inbound-{data['port']}"))
        conn.commit(); conn.close(); xui.start()
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
RUN pip install --no-cache-dir websockets psutil docker
WORKDIR /app
CMD ["python", "-u", "agent.py"]
EOF
    docker build -t multix-agent-image .
    docker run -d --name multix-agent --restart always --network host -v /var/run/docker.sock:/var/run/docker.sock -v ${INSTALL_PATH}/agent:/app -v ${INSTALL_PATH}/agent/db_data:/app/db_share multix-agent-image

    service_fix
    echo -e "${G}✅ 被控端已完成凭据设置并启动自愈修复！${NC}"
    read -p "请前往选项 4 观察连接日志，按回车返回菜单。"
}

# --- 菜单界面 ---
show_menu() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 管理系统 V6.8        "
    echo -e "   [ 主控: $IS_MASTER | 被控: $IS_AGENT ] "
    echo -e "${G}==================================${NC}"
    echo "1. 🚀 安装/重装 主控端 (Master)"
    echo "2. 📡 安装/重装 被控端 (Agent)"
    echo "----------------------------------"
    echo "3. ⚙️  档案库 (查看与一键修改凭据)"
    echo "4. 📊 深度诊断 (实时日志追踪)"
    echo "----------------------------------"
    echo "7. 🔧 智能一键自愈 (解决各种死锁)"
    echo "9. 🗑️  完全卸载"
    echo "0. 🚪 退出"
    echo -e "${G}==================================${NC}"
}

# --- 主循环 ---
while true; do
    show_menu
    read -p "选择操作: " choice
    case $choice in
        1) install_master ;;
        2) install_agent ;;
        3) manage_config ;;
        4) run_diagnose ;;
        7) service_fix ;;
        9) docker rm -f multix-engine multix-agent 3x-ui 2>/dev/null; rm -rf $INSTALL_PATH; exit 0 ;;
        0) exit 0 ;;
    esac
done
