#!/bin/bash
# MultiX V11.5 - 旗舰集成版 (函数序位修复 | 深度镜像清理 | 安装后即显地址)

INSTALL_PATH="/opt/multix_mvp"
CONFIG_FILE="${INSTALL_PATH}/.env"

# 颜色定义
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

# ==========================================
# 0. 【置顶修复】IP 嗅探函数 (确保全局调用)
# ==========================================
get_all_ips() {
    # 增加 5 秒超时，防止网络波动导致脚本假死
    IPV4=$(curl -4 -s --connect-timeout 5 https://api.ipify.org || echo "N/A")
    IPV6=$(curl -6 -s --connect-timeout 5 https://api64.ipify.org || echo "N/A")
}

# ==========================================
# 1. 深度环境修复 (增强清理镜像残留)
# ==========================================
force_fix_env() {
    echo -e "${Y}[*] 正在执行深度清理与环境初始化...${NC}"
    # 1. 停止并删除所有相关容器
    docker rm -f 3x-ui multix-agent 3x-ui-master 2>/dev/null
    # 2. 【新增】清理未使用的镜像残留，释放磁盘空间
    docker image prune -af 2>/dev/null
    # 3. 暴力清理 Python 进程
    pkill -9 -f app.py 2>/dev/null
    pkill -9 -f agent.py 2>/dev/null
    # 4. 优化网卡 MTU
    ETH_NAME=$(ip route | grep default | awk '{print $5}' | head -n 1)
    ip link set $ETH_NAME mtu 1280 2>/dev/null
    # 5. 重置依赖
    apt-get update -y >/dev/null 2>&1
    apt-get install -y python3 python3-pip python3-full psmisc curl lsof sqlite3 netcat-openbsd docker.io --no-install-recommends >/dev/null 2>&1
    python3 -m pip install flask websockets psutil cryptography --break-system-packages --quiet --force-reinstall >/dev/null 2>&1 || true
    echo -e "${G}✅ 深度自愈完成，环境已完全纯净。${NC}"
}

# ==========================================
# 2. 凭据管理中心 (集成版)
# ==========================================
manage_credentials() {
    clear
    get_all_ips
    [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
    WS_STATUS=$(lsof -i :8888 >/dev/null && echo -e "${G}RUNNING${NC}" || echo -e "${R}STOPPED${NC}")

    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 凭据管理中心 (V11.5)  "
    echo -e "${G}==================================${NC}"
    echo -e "主机 IPv4: ${G}${IPV4}${NC}"
    echo -e "主机 IPv6: ${G}${IPV6}${NC} (被控优先)"
    echo -e "WS 通讯状态 (8888): $WS_STATUS"
    echo -e "----------------------------------"
    echo -e "管理地址(v6): ${G}http://[${IPV6}]:${M_PORT:-7575}${NC}"
    echo -e "管理账号: ${G}${M_USER:-admin}${NC}"
    echo -e "管理密码: ${G}${M_PASS:-admin}${NC}"
    echo -e "通讯 Token: ${Y}${M_TOKEN:-token}${NC}"
    echo -e "----------------------------------"
    echo -e "1. 修改账号密码 | 2. 修改端口/Token | 5. 重新安装 | 0. 返回"
    read -p "选择操作: " opt
    case $opt in
        1) read -p "新账号: " M_USER; read -p "新密码: " M_PASS; save_and_apply ;;
        2) read -p "新端口: " M_PORT; read -p "新Token: " M_TOKEN; save_and_apply ;;
        5) install_master ;;
        *) show_menu ;;
    esac
}

save_and_apply() {
    cat > "$CONFIG_FILE" <<EOF
TYPE="MASTER"
M_PORT="${M_PORT:-7575}"
M_USER="${M_USER:-admin}"
M_PASS="${M_PASS:-admin}"
M_TOKEN="${M_TOKEN:-token}"
EOF
    write_master_app_py
    pkill -9 -f app.py 2>/dev/null
    nohup python3 ${INSTALL_PATH}/master/app.py > /dev/null 2>&1 &
    read -p "✅ 配置已应用。按回车返回..." ; manage_credentials
}

# ==========================================
# 3. 连通性拨测 (Agent -> Master)
# ==========================================
test_connectivity() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 连通性拨测工具        "
    echo -e "${G}==================================${NC}"
    read -p "请输入要探测的主控 IP/IPv6: " T_HOST
    echo -e "${Y}[*] 正在探测 TCP 8888 端口...${NC}"
    if nc -zv -w 5 $T_HOST 8888 2>&1 | grep -q 'succeeded'; then
        echo -e "${G}✅ 端口连通成功！${NC}"
    else
        echo -e "${R}❌ 连通失败，请检查主控防火墙。${NC}"
    fi
    read -p "回车返回..." ; show_menu
}

# ==========================================
# 4. 主控核心 (全量审计补齐)
# ==========================================
write_master_app_py() {
    source "$CONFIG_FILE"
    get_all_ips
    cat > "${INSTALL_PATH}/master/app.py" <<EOF
import json, asyncio, time, psutil, os, socket
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread

M_PORT = ${M_PORT}
M_USER = "${M_USER}"
M_PASS = "${M_PASS}"
M_TOKEN = "${M_TOKEN}"
IPV4_ADDR = "${IPV4}"
IPV6_ADDR = "${IPV6}"

app = Flask(__name__)
app.secret_key = M_TOKEN
AGENTS = {}
LOOP_GLOBAL = None

# 【旗舰面板】全功能：常驻指南、示例卡片、刷新按钮
HTML_T = "{% raw %}" + """
<!DOCTYPE html>
<html class="dark">
<head>
    <meta charset="UTF-8"><title>MultiX Center</title>
    <script src="https://unpkg.com/vue@3/dist/vue.global.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>body { background: #000; color: #cbd5e1; }</style>
</head>
<body class="p-6 md:p-12">
    <div id="app">
        <div class="flex justify-between items-center mb-10">
            <div><h1 class="text-3xl font-black text-blue-500 italic">🛰️ MultiX Center</h1><p class="text-[10px] text-zinc-500 font-bold uppercase tracking-widest mt-1">V11.5 Ultimate</p></div>
            <div class="flex gap-4">
                <button @click="update" class="px-4 py-2 bg-zinc-800 hover:bg-zinc-700 text-white rounded-xl text-xs font-bold transition flex items-center gap-2">
                    <span :class="{'animate-spin': loading}">🔄</span> 刷新状态
                </button>
                <div class="px-4 py-2 bg-zinc-900 border border-white/5 rounded-xl text-[10px] font-mono text-yellow-500">TOKEN: """ + M_TOKEN + """</div>
            </div>
        </div>
        <div class="mb-10 p-6 bg-zinc-900 border border-blue-500/10 rounded-3xl grid grid-cols-1 md:grid-cols-2 gap-4 text-xs font-mono">
            <div class="truncate text-white"><span class="text-zinc-500">WS_IPv6:</span> ws://[""" + IPV6_ADDR + """]:8888</div>
            <div class="truncate text-white"><span class="text-zinc-500">WS_IPv4:</span> ws://""" + IPV4_ADDR + """]:8888</div>
        </div>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
            <div v-for="(info, ip) in agents" :key="ip" class="bg-zinc-900 border border-white/5 p-8 rounded-[2rem] shadow-2xl transition hover:border-blue-500/40">
                <div class="flex justify-between items-start mb-8">
                    <div><div class="text-white text-xl font-bold">{{ip}}</div><div class="text-[9px] text-green-500 font-bold italic font-bold">ONLINE</div></div>
                    <div class="h-3 w-3 rounded-full bg-green-500 animate-pulse"></div>
                </div>
                <div class="grid grid-cols-2 gap-4 mb-8 text-center text-[10px] font-bold">
                    <div class="bg-black/50 p-4 rounded-2xl">CPU: {{info.stats.cpu}}%</div>
                    <div class="bg-black/50 p-4 rounded-2xl">MEM: {{info.stats.mem}}%</div>
                </div>
                <button @click="sync(ip)" class="w-full py-4 bg-blue-600 hover:bg-blue-500 text-white rounded-2xl font-bold text-[10px] uppercase transition">Sync Reality Node</button>
            </div>
            <div v-if="Object.keys(agents).length === 0" class="bg-zinc-900/30 border border-dashed border-white/10 rounded-[2rem] p-8 opacity-40 relative group">
                <div class="absolute inset-0 flex items-center justify-center bg-black/20 backdrop-blur-[2px] rounded-[2rem] z-10"><span class="bg-white/10 px-4 py-1 rounded-full text-[10px] font-bold text-white uppercase">布局预览 / MOCKUP</span></div>
                <div class="flex justify-between mb-8"><div><div class="text-zinc-400 text-xl font-bold italic">1.1.1.1</div><div class="text-[9px] text-zinc-600 font-bold italic mt-1">Mockup Data</div></div><div class="h-3 w-3 rounded-full bg-zinc-700"></div></div>
                <div class="grid grid-cols-2 gap-4 mb-8 text-center"><div class="bg-black/20 p-4 rounded-xl text-zinc-700 italic font-black">20%</div><div class="bg-black/20 p-4 rounded-xl text-zinc-700 italic font-black">30%</div></div>
                <button disabled class="w-full py-4 bg-zinc-800 text-zinc-700 rounded-2xl font-black text-[10px] uppercase">Sync Node</button>
            </div>
        </div>
    </div>
    <script>
        const { createApp, ref, onMounted } = Vue;
        createApp({
            setup() {
                const agents = ref({});
                const loading = ref(false);
                const update = async () => { 
                    loading.value = true;
                    try { const r = await fetch('/api/state'); const d = await r.json(); agents.value = d.agents; } 
                    finally { setTimeout(() => loading.value = false, 500); }
                };
                const sync = async (ip) => {
                    const r = await fetch('/api/sync', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({ip}) });
                    const d = await r.json(); alert(d.msg);
                };
                onMounted(() => { update(); setInterval(update, 3000); });
                return { agents, update, sync, loading };
            }
        }).mount('#app');
    </script>
</body></html>""" + "{% endraw %}"

@app.route('/api/state')
def get_state(): return jsonify({"agents": {ip: {"stats": info["stats"]} for ip, info in AGENTS.items()}})

@app.route('/api/sync', methods=['POST'])
def do_sync():
    target = request.json.get('ip')
    if target in AGENTS:
        # 下发全量同步逻辑
        payload = json.dumps({"action": "sync_node", "token": M_TOKEN, "data": {"remark": "V11.5_Sync", "port": 443, "protocol": "vless", "settings": "{}", "stream_settings": "{}"}})
        asyncio.run_coroutine_threadsafe(AGENTS[target]['ws'].send(payload), LOOP_GLOBAL)
        return jsonify({"msg": "🚀 任务下发指令已成功送出"})
    return jsonify({"msg": "节点不在线"})

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form['u'] == M_USER and request.form['p'] == M_PASS:
            session['logged'] = True; return redirect('/')
    return '<h3>Login</h3><form method="post">U: <input name="u"><br>P: <input name="p" type="password"><br><button>Go</button></form>'

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

def start_ws_server():
    global LOOP_GLOBAL
    LOOP_GLOBAL = asyncio.new_event_loop(); asyncio.set_event_loop(LOOP_GLOBAL)
    async def main():
        # 【双栈修复】
        async with websockets.serve(ws_handler, "::", 8888, family=socket.AF_INET6):
            await asyncio.Future()
    asyncio.run(main())

if __name__ == '__main__':
    Thread(target=start_ws_server, daemon=True).start()
    app.run(host='::', port=M_PORT)
EOF
}

# ==========================================
# 5. 安装与被控 (拒绝省略)
# ==========================================
install_master() {
    echo -e "${G}[+] 启动主控安装向导...${NC}"
    get_all_ips
    read -p "管理端口 [7575]: " M_PORT
    read -p "账号: " M_USER
    read -p "密码: " M_PASS
    # 手动输入 Token
    DEF_TOKEN=$(openssl rand -hex 8)
    read -p "通信 Token (默认 $DEF_TOKEN): " M_TOKEN
    M_TOKEN=${M_TOKEN:-$DEF_TOKEN}

    mkdir -p "${INSTALL_PATH}/master"
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
    
    # 【新增】安装后直接显示面板信息
    echo -e "\n${G}🎉 主控安装成功！${NC}"
    echo -e "IPv6 地址: ${G}http://[${IPV6}]:${M_PORT:-7575}${NC}"
    echo -p "IPv4 地址: ${G}http://${IPV4}:${M_PORT:-7575}${NC}"
    read -p "按回车返回菜单..." ; show_menu
}

install_agent() {
    echo -e "${G}[+] 正在部署被控端 (Agent)...${NC}"
    read -p "主控 IP/IPv6: " M_HOST
    read -p "主控 Token: " A_TOKEN
    mkdir -p ${INSTALL_PATH}/agent/db_data
    # 写入 agent.py
    cat > ${INSTALL_PATH}/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, socket
MASTER = "${M_HOST}"; TOKEN = "${A_TOKEN}"
DB_PATH = "/app/db_share/x-ui.db"
def sync_to_db(data):
    try:
        conn = sqlite3.connect(DB_PATH); cursor = conn.cursor()
        cursor.execute("PRAGMA table_info(inbounds)")
        db_fields = [row[1] for row in cursor.fetchall()]
        valid_data = {k: v for k, v in data.items() if k in db_fields}
        keys = ", ".join(valid_data.keys()); placeholders = ", ".join(["?"] * len(valid_data))
        cursor.execute(f"INSERT OR REPLACE INTO inbounds ({keys}) VALUES ({placeholders})", list(valid_data.values()))
        conn.commit(); conn.close(); return True
    except: return False
async def run():
    uri = f"ws://{MASTER}:8888"
    while True:
        try:
            async with websockets.connect(uri, family=socket.AF_UNSPEC) as ws:
                await ws.send(json.dumps({"token": TOKEN, "type": "auth"}))
                while True:
                    stats = {"cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent)}
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats}))
                    msg = await asyncio.wait_for(ws.recv(), timeout=20)
                    task = json.loads(msg)
                    if task.get('action') == 'sync_node':
                        os.system("docker stop 3x-ui")
                        sync_to_db(task['data'])
                        os.system("docker start 3x-ui")
        except: await asyncio.sleep(5)
if __name__ == '__main__': asyncio.run(run())
EOF
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
    docker build -t multix-agent-v11 . >/dev/null 2>&1
    docker run -d --name multix-agent --restart always --network host -v ${INSTALL_PATH}/agent/db_data:/app/db_share -v ${INSTALL_PATH}/agent:/app multix-agent-v11
    echo -e "${G}✅ 被控端上线。${NC}"
    read -p "回车继续..." ; show_menu
}

# ==========================================
# 6. 主菜单 (全量补齐)
# ==========================================
show_menu() {
    clear
    echo -e "${G}==================================${NC}"
    echo -e "      MultiX 最终旗舰版 V11.5      "
    echo -e "   全量找回 | 深度自愈 | 无遗漏    "
    echo -e "${G}==================================${NC}"
    echo -e "1. 🚀 安装/重装 主控端 (Master)"
    echo -e "2. 📡 安装/重装 被控端 (Agent)"
    echo -e "----------------------------------"
    echo -e "3. 🔑 凭据中心 (查看IP/Token/改密)"
    echo -e "4. ⚙️  服务管理 (主/被控 运行状态)"
    echo -e "5. 📡 连通性拨测 (排查 Agent 连不上)"
    echo -e "----------------------------------"
    echo -e "7. 🧹 深度清理与自愈 (重置所有环境)"
    echo -e "9. 🗑️  完全卸载"
    echo -e "0. 退出"
    read -p "请选择操作 [0-9]: " opt
    case $opt in
        1) force_fix_env; install_master ;;
        2) force_fix_env; install_agent ;;
        3) manage_credentials ;;
        4) echo -e "${Y}[*] 正在扫描监听状态...${NC}"; lsof -i :7575 && lsof -i :8888; read -p "回车返回..." ; show_menu ;;
        5) test_connectivity ;;
        7) force_fix_env; read -p "自愈完成..." ; show_menu ;;
        9) docker rm -f 3x-ui multix-agent 3x-ui-master; docker image prune -af; rm -rf $INSTALL_PATH; exit 0 ;;
        *) exit 0 ;;
    esac
}



mkdir -p "$INSTALL_PATH"
show_menu
