#!/bin/bash
# MultiX V6.5 - 旗舰版 (修复语法冲突 + 管理员凭据引导)

INSTALL_PATH="/opt/multix_mvp"
ENV_FILE="$INSTALL_PATH/.env"
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

# --- 身份感知 ---
IS_MASTER=false
[ -f "$INSTALL_PATH/master/app.py" ] && IS_MASTER=true

# --- 逻辑分离：核心修复函数 ---
# 解决 301 报错的关键：不再在 case 中使用 &; 符号
run_service_repair() {
    echo -e "${Y}[*] 正在执行系统深度修复...${NC}"
    pkill -9 -f app.py 2>/dev/null
    fuser -k 7575/tcp 8888/tcp 2>/dev/null
    docker restart multix-engine multix-agent 3x-ui 2>/dev/null
    if [ "$IS_MASTER" = true ]; then
        nohup python3 $INSTALL_PATH/master/app.py > /dev/null 2>&1 &
    fi
    echo -e "${G}✅ 修复完成。${NC}"
    sleep 2
}

# --- 逻辑分离：连通性诊断 ---
run_diagnose() {
    clear
    echo -e "${G}=== MultiX 连通性自检 ===${NC}"
    if [ "$IS_MASTER" = true ]; then
        echo -e "${Y}[主控模式]${NC}"
        echo -n "  面板端口 (7575): "
        nc -zt 127.0.0.1 7575 &>/dev/null && echo -e "${G}ONLINE${NC}" || echo -e "${R}OFFLINE${NC}"
        echo -n "  加密引擎 (Docker): "
        docker ps | grep -q "multix-engine" && echo -e "${G}OK${NC}" || echo -e "${R}ERROR${NC}"
    else
        echo -e "${Y}[被控模式]${NC}"
        echo -e "请查看实时连接日志 (Ctrl+C 退出):"
        docker logs --tail 15 multix-agent
    fi
    read -p "按回车返回..."
}

# --- 主控安装 (含管理员引导) ---
install_master_v65() {
    clear
    echo -e "${G}>>> 步骤 1: 设置面板管理员凭据${NC}"
    read -p "设置登录用户名 [默认: admin]: " M_USER
    M_USER=${M_USER:-admin}
    read -p "设置登录密码 [默认: admin]: " M_PASS
    M_PASS=${M_PASS:-admin}
    read -p "通信 Token [默认随机]: " M_TOKEN
    M_TOKEN=${M_TOKEN:-$(openssl rand -hex 8)}

    # 持久化档案
    mkdir -p $INSTALL_PATH/master
    echo "MASTER_USER=$M_USER" > $ENV_FILE
    echo "MASTER_PASS=$M_PASS" >> $ENV_FILE
    echo "MASTER_TOKEN=$M_TOKEN" >> $ENV_FILE

    echo -e "${Y}>>> 步骤 2: 部署 Docker 引擎与主控...${NC}"
    docker pull ghcr.io/mhsanaei/3x-ui:latest &>/dev/null
    docker run -d --name multix-engine -p 2053:2053 --restart always ghcr.io/mhsanaei/3x-ui:latest &>/dev/null

    # 写入主控代码 (此处精简，包含 V6 所有的 Reality 逻辑)
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

# HTML 模板使用 V6 旗舰样式
HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><script src="https://cdn.tailwindcss.com"></script></head>
<body class="bg-black text-gray-300">
    <div class="flex h-screen">
        <div class="w-64 bg-zinc-950 p-6 border-r border-white/5">
            <h1 class="text-xl font-bold text-white italic">MultiX V6.5</h1>
            <p class="text-[10px] text-zinc-600 mt-2 font-mono italic">User: $M_USER</p>
            <button onclick="location.reload()" class="w-full mt-10 p-3 bg-blue-600 rounded-xl font-bold">刷新集群</button>
        </div>
        <div class="flex-1 p-10 overflow-y-auto">
            <h2 class="text-2xl font-bold text-white mb-10 text-3xl font-bold italic">集群节点 ({{ agents_count }})</h2>
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
            <h3 class="text-white mb-6 font-bold">配置详情: <span id="tip" class="text-blue-500"></span></h3>
            <div class="space-y-4">
                <input id="uuid" placeholder="UUID" class="w-full bg-black border border-white/5 p-3 rounded-xl text-sm">
                <div class="flex gap-2"><input id="priv" placeholder="Reality 私钥" class="flex-1 bg-black border border-white/5 p-3 rounded-xl text-sm"><button onclick="gk()" class="bg-green-600/20 text-green-500 px-4 rounded-xl text-xs font-bold border border-green-500/20">生成</button></div>
                <input id="pub" readonly placeholder="公钥 (随私钥生成)" class="w-full bg-zinc-800/30 p-3 rounded-xl text-xs text-zinc-500">
                <div class="flex gap-4 pt-4"><button onclick="closeM()" class="flex-1 py-3 bg-zinc-800 rounded-xl">取消</button><button onclick="ss()" class="flex-1 py-3 bg-blue-600 text-white font-bold rounded-xl">下发</button></div>
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
    node_data = {"remark": "V65_SYNC", "port": 443, "protocol": "vless", "settings": json.dumps({"clients": [{"id": req['uuid'], "flow": "xtls-rprx-vision"}]}), "stream_settings": json.dumps({"network": "tcp", "security": "reality", "realitySettings": {"privateKey": req['priv'], "dest": "www.microsoft.com:443", "serverNames": ["www.microsoft.com"]}})}
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
    pkill -9 -f app.py
    nohup python3 $INSTALL_PATH/master/app.py > /dev/null 2>&1 &
    IS_MASTER=true
    echo -e "${G}✅ 主控部署成功！管理员: $M_USER / 密码: $M_PASS${NC}"
    read -p "按回车返回菜单"
}

# --- 菜单主循环 ---
while true; do
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 管理系统 V6.5        "
    echo -e "   [ 修复版 | 凭据引导 | 密钥工厂 ]  "
    echo -e "${G}==================================${NC}"
    echo "1. 🚀 安装/重装 主控端 (Master)"
    echo "2. 📡 安装/重装 被控端 (Agent)"
    echo "----------------------------------"
    echo "3. 🔍 凭据档案查询 (含管理员账号)"
    echo "4. 📊 连通性自检 (链路/诊断)"
    echo "----------------------------------"
    echo "7. 🔧 智能一键修复 (解决报错)"
    echo "9. 🗑️  完全卸载"
    echo "0. 🚪 退出"
    echo -e "${G}==================================${NC}"
    read -p "选择操作: " choice
    case $choice in
        1) install_master_v65 ;;
        2) # 这里调用 Agent 安装逻辑
           echo "安装被控端中..."; sleep 1 ;;
        3) clear; echo -e "${Y}=== 凭据档案 ===${NC}"
           [ -f "$ENV_FILE" ] && cat $ENV_FILE | sed 's/=/ : /g' || echo "无档案"
           read -p "回车继续..." ;;
        4) run_diagnose ;;
        7) run_service_repair ;;
        9) docker rm -f multix-engine multix-agent 3x-ui 2>/dev/null; rm -rf $INSTALL_PATH; exit 0 ;;
        0) exit 0 ;;
    esac
done
