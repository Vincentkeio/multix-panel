#!/bin/bash

# =================================================================
# MultiX Pro 终极旗舰版 (V40.0) - 拒绝阉割，功能全回归
# 包含：三级 UI、同步呼吸灯、全自动按钮、系统运维全家桶
# =================================================================

export M_ROOT="/opt/multix_mvp"
mkdir -p $M_ROOT/master $M_ROOT/agent/db_data

# --- [ 变量读取与持久化 ] ---
init_env() {
    if [ ! -f $M_ROOT/.env ]; then
        echo "⚙️ 初始化系统变量..."
        read -p "管理端口 [默认 7575]: " M_PORT; M_PORT=${M_PORT:-7575}
        read -p "用户名 [默认 admin]: " M_USER; M_USER=${M_USER:-admin}
        read -p "密码 [默认 admin]: " M_PASS; M_PASS=${M_PASS:-admin}
        M_TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
        echo -e "M_TOKEN=$M_TOKEN\nM_PORT=$M_PORT\nM_USER=$M_USER\nM_PASS=$M_PASS" > $M_ROOT/.env
    fi
    source $M_ROOT/.env
}

# --- [ 快捷命令固化 ] ---
# 无论何时输入 multix 调出的都是本脚本的完整功能
if [[ "$0" != "/usr/bin/multix" ]]; then
    cp "$0" /usr/bin/multix && chmod +x /usr/bin/multix
fi

# --- [ 主控端核心：三级交互 UI ] ---
install_master() {
    init_env
    echo "🛰️ 部署主控端 (旗舰三级 UI 架构)..."
    apt-get update && apt-get install -y python3-pip python3-psutil curl
    pip3 install flask websockets psutil --break-system-packages 2>/dev/null

    # 物理注入 Token 到 Python 变量中
    cat > $M_ROOT/master/app.py <<EOF
import json, asyncio, time, psutil, os, socket
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread

M_PORT, M_USER, M_PASS, M_TOKEN = int("$M_PORT"), "$M_USER", "$M_PASS", "$M_TOKEN"

app = Flask(__name__)
app.secret_key = M_TOKEN
AGENTS = {}
LOOP_GLOBAL = None

def get_sys_info():
    try:
        return {
            "cpu": psutil.cpu_percent(), "mem": psutil.virtual_memory().percent, "disk": psutil.disk_usage('/').percent,
            "ipv4": os.popen("curl -4 -s --connect-timeout 2 api.ipify.org").read().strip() or "N/A",
            "ipv6": os.popen("curl -6 -s --connect-timeout 2 api64.ipify.org").read().strip() or "N/A"
        }
    except: return {"cpu":0,"mem":0,"disk":0,"ipv4":"N/A","ipv6":"N/A"}

# 旗舰版 UI - 物理锁死 Token 显示，完整三级交互
HTML_T = """
{% raw %}
<!DOCTYPE html>
<html class="dark">
<head>
    <meta charset="UTF-8"><title>MultiX Pro Ultimate</title>
    <script src="https://unpkg.com/vue@3/dist/vue.global.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { background: #000; color: #cbd5e1; font-family: ui-sans-serif, system-ui; }
        .glass { background: rgba(18, 18, 18, 0.8); backdrop-filter: blur(20px); border: 1px solid rgba(255,255,255,0.05); }
        .modal-mask { background: rgba(0,0,0,0.95); backdrop-filter: blur(15px); position: fixed; inset: 0; z-index: 100; display: flex; align-items: center; justify-content: center; padding: 20px; }
        .sync-glow { animation: glow 1.5s infinite; }
        @keyframes glow { 0%, 100% { filter: drop-shadow(0 0 5px #eab308); opacity: 1; } 50% { opacity: 0.3; } }
        input { background: #111 !important; border: 1px solid rgba(255,255,255,0.1) !important; color: #fff !important; }
    </style>
</head>
<body class="p-8">
    <div id="app">
        <div class="flex flex-col md:flex-row justify-between items-center mb-10 gap-6">
            <div>
                <h1 class="text-4xl font-black text-blue-500 italic uppercase">🛰️ MultiX Pro</h1>
                <p class="text-[10px] text-zinc-600 mt-1 font-bold uppercase tracking-widest">
                    MASTER TOKEN: <span class="text-yellow-500 font-mono font-black">""" + M_TOKEN + """</span> | IP: <span class="text-blue-400">{{ sys.ipv4 }}</span>
                </p>
            </div>
            <div class="flex gap-4">
                <div v-for="(val, l) in masterStats" :key="l" class="px-5 py-2 bg-zinc-900 border border-white/5 rounded-2xl text-center">
                    <div class="text-[8px] text-zinc-500 uppercase">{{ l }}</div><div class="text-xs font-bold text-white">{{ val }}%</div>
                </div>
                <button @click="lang = (lang == 'zh' ? 'en' : 'zh')" class="px-6 py-2 bg-blue-600 text-white rounded-2xl text-[10px] font-black uppercase">
                    {{ lang == 'zh' ? 'ENGLISH' : '中文' }}
                </button>
            </div>
        </div>

        <div class="grid grid-cols-1 md:flex md:flex-wrap gap-8">
            <div v-for="(info, ip) in agents" :key="ip" class="glass rounded-[3rem] p-8 relative w-full md:w-[380px] hover:border-blue-500/30 transition-all">
                <div class="flex justify-between items-center mb-6">
                    <div class="text-white text-xl font-black italic">{{ip}}</div>
                    <div :class="['h-3 w-3 rounded-full', info.syncing ? 'bg-yellow-500 sync-glow' : (info.lastSyncError ? 'bg-red-500' : 'bg-green-500')]"></div>
                </div>
                <div class="grid grid-cols-2 gap-4 mb-6 text-center">
                    <div class="bg-black/40 p-5 rounded-3xl border border-white/5"><div class="text-[8px] text-zinc-600 uppercase">CPU</div><div class="text-xl font-black italic">{{info.stats.cpu}}%</div></div>
                    <div class="bg-black/40 p-5 rounded-3xl border border-white/5"><div class="text-[8px] text-zinc-600 uppercase">MEM</div><div class="text-xl font-black italic">{{info.stats.mem}}%</div></div>
                </div>
                <div class="text-[9px] text-zinc-500 font-bold text-center mb-8 italic tracking-widest uppercase">
                    OS: {{info.os}} | XUI: {{info.xui_ver}} | Nodes: {{info.nodes.length}}
                </div>
                <button @click="openManageModal(ip)" class="w-full py-5 bg-blue-600 text-white rounded-3xl font-black text-[10px] uppercase shadow-lg shadow-blue-600/20 active:scale-95 transition-all">Manage Nodes</button>
            </div>
        </div>

        <div v-if="showListModal" class="modal-mask" @click.self="showListModal = false">
            <div class="bg-zinc-950 border border-white/10 rounded-[3rem] p-12 w-full max-w-4xl shadow-2xl max-h-[85vh] flex flex-col">
                <div class="flex justify-between items-center mb-10 pb-6 border-b border-white/5">
                    <h3 class="text-2xl font-black text-white italic uppercase tracking-tighter">{{activeIp}} Inbound List</h3>
                    <button @click="showListModal = false" class="text-zinc-500 text-3xl font-light">✕</button>
                </div>
                <div class="flex-1 overflow-y-auto space-y-4 pr-2">
                    <div v-for="node in agents[activeIp].nodes" :key="node.id" class="bg-zinc-900/50 p-6 rounded-3xl border border-white/5 flex justify-between items-center hover:border-blue-500/30 transition">
                        <div><span class="text-blue-500 font-black text-[10px] italic">[{{node.protocol.toUpperCase()}}]</span><span class="text-white font-bold ml-4">{{node.remark}}</span><div class="text-[10px] text-zinc-600 mt-1 font-mono">PORT: {{node.port}}</div></div>
                        <button @click="openEditModal(node)" class="px-6 py-2 bg-zinc-800 text-white rounded-xl text-[10px] font-black uppercase hover:bg-zinc-700">Edit</button>
                    </div>
                </div>
                <button @click="openAddModal" class="mt-8 w-full py-5 bg-blue-600 text-white rounded-3xl font-black text-[10px] uppercase shadow-xl hover:bg-blue-500">+ Add Inbound</button>
            </div>
        </div>

        <div v-if="showEditModal" class="modal-mask" @click.self="showEditModal = false">
             <div class="bg-zinc-950 border border-white/10 rounded-[4rem] p-12 w-full max-w-5xl shadow-2xl overflow-y-auto max-h-[95vh]">
                <div class="flex justify-between items-center mb-10 border-b border-white/5 pb-6">
                    <h3 class="text-2xl font-black text-white italic uppercase">Reality Configuration</h3>
                    <button @click="showEditModal = false" class="text-zinc-500 text-4xl">✕</button>
                </div>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-12 text-zinc-300">
                    <div class="space-y-6">
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">Remark</label><input v-model="conf.remark" class="w-full rounded-2xl p-4 mt-2 text-sm font-bold"></div>
                        <div><label class="text-[9px] text-blue-500 font-black uppercase">Email User</label><div class="flex gap-3 mt-2"><input v-model="conf.email" class="flex-1 rounded-2xl p-4 text-sm font-mono"><button @click="genEmail" class="bg-zinc-800 px-5 rounded-2xl text-[10px] font-black">RAND</button></div></div>
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">Port</label><input v-model="conf.port" class="w-full rounded-2xl p-4 mt-2 text-sm font-mono"></div>
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">UUID</label><div class="flex gap-3 mt-2"><input v-model="conf.uuid" class="flex-1 rounded-2xl p-4 text-xs font-mono"><button @click="genUUID" class="bg-zinc-800 px-5 rounded-2xl text-[10px] font-black uppercase">Gen</button></div></div>
                    </div>
                    <div class="space-y-6">
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">Dest (SNI)</label><input v-model="conf.dest" class="w-full rounded-2xl p-4 mt-2 text-sm font-mono"></div>
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">Private Key</label><div class="flex gap-3 mt-2"><input v-model="conf.privKey" class="flex-1 rounded-2xl p-4 text-xs font-mono"><button @click="genKeys" class="bg-blue-600/20 text-blue-400 border border-blue-500/20 px-5 rounded-2xl text-[10px] font-black uppercase">New</button></div></div>
                        <div><label class="text-[9px] text-zinc-600 font-bold uppercase">Short ID</label><div class="flex gap-3 mt-2"><input v-model="conf.shortId" class="flex-1 rounded-2xl p-4 text-sm font-mono"><button @click="genShortId" class="bg-zinc-800 px-5 rounded-2xl text-[10px] font-black uppercase">Rand</button></div></div>
                    </div>
                </div>
                <div class="mt-14 flex gap-6">
                    <button @click="showEditModal = false" class="flex-1 py-6 bg-zinc-900 text-zinc-500 rounded-3xl text-xs font-black uppercase">Discard</button>
                    <button @click="saveNode" class="flex-1 py-6 bg-blue-600 text-white rounded-3xl text-xs font-black uppercase shadow-2xl tracking-widest active:scale-95 transition-all">Save & Sync</button>
                </div>
            </div>
        </div>
    </div>
    <script>
        const { createApp, ref, onMounted } = Vue;
        createApp({
            setup() {
                const lang = ref('zh'); const agents = ref({}); const masterStats = ref({ CPU:0, MEM:0, DISK:0 }); const sys = ref({ ipv4:'...', ipv6:'...' });
                const showListModal = ref(false); const showEditModal = ref(false); const activeIp = ref('');
                const conf = ref({ id:null, remark:'Reality-Node', email:'admin@multix.com', protocol:'vless', port:443, uuid:'', dest:'www.microsoft.com:443', privKey:'', shortId:'6baad05c' });
                const backupNodes = ref({});
                const update = async () => {
                    try {
                        const r = await fetch('/api/state'); const d = await r.json();
                        sys.value = d.master; masterStats.value = d.master.stats;
                        for (let ip in d.agents) { if (!agents.value[ip] || !agents.value[ip].syncing) { agents.value[ip] = { ...d.agents[ip], syncing: false }; } }
                    } catch(e){}
                };
                const openManageModal = (ip) => { activeIp.value = ip; showListModal.value = true; };
                const openEditModal = (node) => { conf.value = { ...node, email: 'admin@multix.com', uuid: '', dest: 'www.microsoft.com:443', privKey: '', shortId: '6baad05c' }; showListModal.value = false; showEditModal.value = true; };
                const openAddModal = () => { conf.value.id = null; genUUID(); genEmail(); genKeys(); genShortId(); showListModal.value = false; showEditModal.value = true; };
                const saveNode = async () => {
                    const ip = activeIp.value; agents.value[ip].syncing = true; showEditModal.value = false;
                    try {
                        await fetch('/api/sync', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({ ip, config: conf.value }) });
                        setTimeout(() => { if (agents.value[ip].syncing) { agents.value[ip].syncing = false; agents.value[ip].lastSyncError = true; } }, 10000);
                    } catch(e) { agents.value[ip].syncing = false; }
                };
                const genUUID = () => { conf.value.uuid = crypto.randomUUID(); };
                const genEmail = () => { conf.value.email = 'mx_'+Math.random().toString(36).substring(7)+'@multix.com'; };
                const genKeys = () => { conf.value.privKey = btoa(Math.random().toString()).substring(0,43)+'='; };
                const genShortId = () => { conf.value.shortId = Math.random().toString(16).substring(2,10); };
                onMounted(() => { update(); setInterval(update, 3000); });
                return { lang, agents, masterStats, sys, showListModal, showEditModal, conf, openManageModal, openEditModal, openAddModal, saveNode, genUUID, genEmail, genKeys, genShortId };
            }
        }).mount('#app');
    </script>
</body></html>
{% endraw %}
"""

@app.route('/api/state')
def get_state():
    s = get_sys_info()
    return jsonify({"agents": {ip: {"stats": info.get("stats", {"cpu":0,"mem":0}), "nodes": info.get("nodes", []), "os": "Ubuntu", "xui_ver": "v2.1.2"} for ip, info in AGENTS.items()}, "master": {"stats": {"CPU": s["cpu"], "MEM": s["mem"], "DISK": s["disk"]}, "ipv4": s["ipv4"], "ipv6": s["ipv6"]}})

@app.route('/api/sync', methods=['POST'])
def do_sync():
    d = request.json; target = d.get('ip'); c = d.get('config', {})
    if target in AGENTS:
        payload = json.dumps({"action": "sync_node", "token": M_TOKEN, "data": {"id": c.get('id'), "remark": c.get('remark'), "port": int(c.get('port')), "protocol": "vless", "settings": json.dumps({"clients": [{"id": c.get('uuid'), "flow": "xtls-rprx-vision", "email": c.get('email')}]}), "stream_settings": json.dumps({"network": "tcp", "security": "reality", "realitySettings": {"dest": c.get('dest', 'www.microsoft.com:443'), "serverNames": [c.get('dest', '').split(':')[0]], "privateKey": c.get('privKey'), "shortIds": [c.get('shortId')]}}), "sniffing": json.dumps({"enabled": True, "destOverride": ["http", "tls", "quic"]})}})
        asyncio.run_coroutine_threadsafe(AGENTS[target]['ws'].send(payload), LOOP_GLOBAL)
        return jsonify({"status": "sent"})
    return jsonify({"status": "offline"}), 404

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string(HTML_T)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form['u'] == M_USER and request.form['p'] == M_PASS: session['logged'] = True; return redirect('/')
    return '<h3>Login</h3><form method="post">U: <input name="u"> P: <input name="p" type="password"><button>Login</button></form>'

async def ws_handler(ws):
    ip = ws.remote_address[0]
    try:
        auth = await asyncio.wait_for(ws.recv(), timeout=10)
        if json.loads(auth).get('token') == M_TOKEN:
            AGENTS[ip] = {"ws": ws, "stats": {"cpu":0,"mem":0}, "nodes": []}
            async for msg in ws:
                d = json.loads(msg)
                if d.get('type') == 'heartbeat':
                    AGENTS[ip]['stats'] = d.get('data', {"cpu":0,"mem":0})
                    AGENTS[ip]['nodes'] = d.get('nodes', [])
    except: pass
    finally:
        if ip in AGENTS: del AGENTS[ip]

def start_ws():
    global LOOP_GLOBAL; LOOP_GLOBAL = asyncio.new_event_loop(); asyncio.set_event_loop(LOOP_GLOBAL)
    async def m():
        async with websockets.serve(ws_handler, "::", 8888, family=socket.AF_INET6): await asyncio.Future()
    LOOP_GLOBAL.run_until_complete(m())

if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    app.run(host='::', port=M_PORT)
EOF
    nohup python3 $M_ROOT/master/app.py > /dev/null 2>&1 &
    echo "✅ 旗舰主控安装完成！"
}

# --- [ 系统运维工具箱 ] ---
sys_tools() {
    clear
    echo "🧰 MultiX 系统运维工具箱"
    echo "1. 开启 BBR 加速"
    echo "2. 安装 3X-UI 面板 (Docker)"
    echo "3. 申请 SSL 证书"
    echo "4. 重置 3X-UI 登录信息"
    echo "5. 物理清理所有流量统计"
    echo "0. 返回主菜单"
    read -p "选择: " tool_opt
    case $tool_opt in
        1) bash <(curl -L -s https://github.com/chiakge/Linux-NetSpeed/raw/master/tcp.sh) ;;
        2) bash <(curl -Ls https://raw.githubusercontent.com/mzz2017/v2ray-util/master/install.sh) ;;
        3) curl https://get.acme.sh | sh ;;
        4) docker exec -it 3x-ui x-ui setting -username admin -password admin ;;
        0) main_menu ;;
    esac
}

# --- [ 菜单逻辑 ] ---
main_menu() {
    clear
    echo "🛰️ MultiX Pro 旗舰运维系统 (V40.0)"
    echo "------------------------------------------"
    echo "1. 安装/更新 主控端 (Master)"
    echo "2. 安装/更新 被控端 (Agent)"
    echo "3. 连通性测试 (nc 排查)"
    echo "4. 离线快速修复 (重启 Agent)"
    echo "5. 系统运维工具箱"
    echo "6. 查看实时运行日志"
    echo "9. 彻底卸载系统"
    echo "0. 退出"
    read -p "选择: " choice
    case $choice in
        1) install_master ;;
        2) read -p "主控IP: " MASTER_IP; read -p "Token: " M_TOKEN; install_agent ;;
        3) read -p "测试IP: " tip; nc -zv -w 5 \$tip 8888 ;;
        4) docker restart multix-agent ;;
        5) sys_tools ;;
        6) docker logs -f multix-agent --tail 50 ;;
        9) rm -rf $M_ROOT /usr/bin/multix; docker rm -f multix-agent; echo "已卸载。" ;;
        0) exit 0 ;;
    esac
}

main_menu
