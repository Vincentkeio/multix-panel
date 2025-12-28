#!/bin/bash

# ==============================================================================
# MultiX Pro Script V62.1 (Dependency Reset & Syntax Hard-Fix)
# Fix 1: Force uninstall incompatible Flask/Werkzeug versions.
# Fix 2: Re-install stable Flask 2.3.3 to prevent 500/503 errors.
# Fix 3: Remove all indentation in cat <<EOF to prevent Python SyntaxError.
# ==============================================================================

export M_ROOT="/opt/multix_mvp"
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
SH_VER="V62.1"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 0. 快捷命令 ] ---
install_shortcut() {
    rm -f /usr/bin/multix
    cp "$0" /usr/bin/multix && chmod +x /usr/bin/multix
    echo -e "${GREEN}[INFO]${PLAIN} multix 快捷命令已更新"
}
install_shortcut

# --- [ 1. 基础函数 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[ERROR]${PLAIN} Root required" && exit 1; }
check_sys() {
    if [[ -f /etc/redhat-release ]]; then RELEASE="centos";
    elif cat /etc/issue | grep -q -E -i "debian"; then RELEASE="debian";
    else RELEASE="ubuntu"; fi
}
get_public_ips() {
    IPV4=$(curl -s4m 2 api.ipify.org || echo "N/A"); IPV6=$(curl -s6m 2 api64.ipify.org || echo "N/A")
}
resolve_ip() {
    python3 -c "import socket; try: print(socket.getaddrinfo('$1', None, socket.$2)[0][4][0]); except: pass"
}
pause_back() { echo -e "\n${YELLOW}按任意键返回...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 2. 环境修复 (暴力重置依赖) ] ---
fix_dual_stack() {
    if grep -q "net.ipv6.bindv6only" /etc/sysctl.conf; then sed -i 's/net.ipv6.bindv6only.*/net.ipv6.bindv6only = 0/' /etc/sysctl.conf
    else echo "net.ipv6.bindv6only = 0" >> /etc/sysctl.conf; fi
    sysctl -p >/dev/null 2>&1
}

install_dependencies() {
    echo -e "${YELLOW}[INFO]${PLAIN} 正在清理旧环境..."
    check_sys
    if [[ "${RELEASE}" == "centos" ]]; then yum install -y epel-release python3 python3-devel python3-pip curl wget socat tar openssl git
    else apt-get update && apt-get install -y python3 python3-pip curl wget socat tar openssl git; fi
    
    # [V62.1 关键] 强制卸载可能冲突的高版本库
    pip3 uninstall -y flask werkzeug jinja2 itsdangerous click blinker websockets psutil >/dev/null 2>&1
    
    echo -e "${YELLOW}[INFO]${PLAIN} 安装稳定版依赖 (Flask 2.3.3)..."
    # 指定版本安装，防止 API 变动导致的 500/503
    pip3 install "Flask==2.3.3" "Werkzeug==2.3.7" "Jinja2==3.1.2" "websockets==11.0.3" "psutil" --break-system-packages >/dev/null 2>&1 || \
    pip3 install "Flask==2.3.3" "Werkzeug==2.3.7" "Jinja2==3.1.2" "websockets==11.0.3" "psutil" >/dev/null 2>&1
    
    if ! command -v docker &> /dev/null; then curl -fsSL https://get.docker.com | bash; systemctl start docker; fi
    fix_dual_stack
}

# --- [ 3. 深度清理 ] ---
deep_cleanup() {
    echo -e "${RED}⚠️  警告：此操作将删除所有 MultiX 组件！${PLAIN}"; read -p "确认? [y/N]: " confirm
    [[ "$confirm" != "y" ]] && return
    systemctl stop multix-master 2>/dev/null; rm -f /etc/systemd/system/multix-master.service
    systemctl daemon-reload
    docker stop multix-agent 2>/dev/null; docker rm -f multix-agent 2>/dev/null
    docker rmi $(docker images | grep "multix-agent" | awk '{print $3}') 2>/dev/null
    pkill -9 -f "master/app.py"; pkill -9 -f "agent/agent.py"
    echo -e "${GREEN}[INFO]${PLAIN} 清理完成"; pause_back
}

# --- [ 4. 服务管理 ] ---
service_manager() {
    while true; do
        clear; echo -e "${SKYBLUE}⚙️ 服务管理${PLAIN}"
        echo " 1. 启动主控  2. 停止主控  3. 重启主控  4. 主控日志 (排错用)"
        echo " 5. 重启被控  6. 被控日志  0. 返回"
        read -p "选择: " s
        case $s in
            1) systemctl start multix-master && echo "Done" ;; 2) systemctl stop multix-master && echo "Done" ;;
            3) systemctl restart multix-master && echo "Done" ;; 
            4) echo "--- 最后 50 行日志 ---"; journalctl -u multix-master -n 50 --no-pager ;;
            5) docker restart multix-agent && echo "Done" ;; 6) docker logs multix-agent --tail 20 ;; 0) break ;;
        esac; read -n 1 -s -r -p "继续..."
    done; main_menu
}

# --- [ 5. 凭据中心 ] ---
credential_center() {
    clear; echo -e "${SKYBLUE}🔐 凭据管理${PLAIN}"
    if [ -f $M_ROOT/.env ]; then
        M_PORT=$(grep "M_PORT" $M_ROOT/.env | cut -d'=' -f2 | tr -d "'\""); M_TOKEN=$(grep "M_TOKEN" $M_ROOT/.env | cut -d'=' -f2 | tr -d "'\"")
        M_USER=$(grep "M_USER" $M_ROOT/.env | cut -d'=' -f2 | tr -d "'\""); M_PASS=$(grep "M_PASS" $M_ROOT/.env | cut -d'=' -f2 | tr -d "'\"")
        get_public_ips
        echo -e "${YELLOW}[主控]${PLAIN} http://[${IPV6}]:${M_PORT}"
        echo -e "用户: ${GREEN}$M_USER${PLAIN} | 密码: ${GREEN}$M_PASS${PLAIN}"
        echo -e "Token: ${SKYBLUE}$M_TOKEN${PLAIN}"
    fi
    if [ -f "$M_ROOT/agent/agent.py" ]; then
        CUR_MASTER=$(grep 'MASTER =' $M_ROOT/agent/agent.py | cut -d'"' -f2)
        echo -e "${YELLOW}[被控]${PLAIN} 连至: $CUR_MASTER"
    fi
    echo "--------------------------------"
    echo " 1. 修改配置  2. 修改连接  0. 返回"; read -p "选择: " c
    if [[ "$c" == "1" ]]; then
        read -p "端口: " np; M_PORT=${np:-$M_PORT}; read -p "Token: " nt; M_TOKEN=${nt:-$M_TOKEN}
        echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'" > $M_ROOT/.env
        fix_dual_stack; systemctl restart multix-master; echo "已重启"
    fi
    if [[ "$c" == "2" ]]; then
        read -p "IP: " nip; sed -i "s/MASTER = \".*\"/MASTER = \"$nip\"/" $M_ROOT/agent/agent.py
        docker restart multix-agent; echo "已重连"
    fi
    main_menu
}

# --- [ 6. 主控安装 (格式硬修正) ] ---
install_master() {
    install_dependencies; mkdir -p $M_ROOT/master $M_ROOT/agent/db_data
    if [ -f $M_ROOT/.env ]; then source $M_ROOT/.env; fi
    
    echo -e "${SKYBLUE}>>> 主控初始化${PLAIN}"
    read -p "管理端口 [默认 7575]: " IN_PORT; M_PORT=${IN_PORT:-${M_PORT:-7575}}
    read -p "管理用户 [默认 admin]: " IN_USER; M_USER=${IN_USER:-${M_USER:-admin}}
    read -p "管理密码 [默认 admin]: " IN_PASS; M_PASS=${IN_PASS:-${M_PASS:-admin}}
    RAND=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    read -p "Token [默认随机]: " IN_TOKEN; M_TOKEN=${IN_TOKEN:-${M_TOKEN:-$RAND}}
    
    echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'" > $M_ROOT/.env
    
    echo -e "${YELLOW}🛰️ 部署主控 (V62.1 格式硬修正版)...${PLAIN}"
    
    # [V62.1] 使用单引号 'EOF' 防止变量展开
    # 并且所有 Python 代码顶格写，防止缩进错误
    cat > $M_ROOT/master/app.py <<'EOF'
import json, asyncio, psutil, os, socket, subprocess, base64, logging
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread

# 设置日志，方便排查 500 错误
logging.basicConfig(level=logging.DEBUG)

def load_conf():
    c = {}
    try:
        with open('/opt/multix_mvp/.env') as f:
            for l in f:
                if '=' in l: k,v = l.strip().split('=', 1); c[k] = v.strip("'\"")
    except: pass
    return c

CONF = load_conf()
M_PORT = int(CONF.get('M_PORT', 7575))
M_TOKEN = CONF.get('M_TOKEN', 'error')
M_USER = CONF.get('M_USER', 'admin')
M_PASS = CONF.get('M_PASS', 'admin')

app = Flask(__name__)
app.secret_key = M_TOKEN
AGENTS = {}; LOOP_GLOBAL = None

def get_sys_info():
    try: return {"cpu": psutil.cpu_percent(), "mem": psutil.virtual_memory().percent, "ipv4": os.popen("curl -4s api.ipify.org").read().strip(), "ipv6": os.popen("curl -6s api64.ipify.org").read().strip()}
    except: return {"cpu":0,"mem":0, "ipv4":"N/A", "ipv6":"N/A"}

@app.route('/api/gen_key', methods=['POST'])
def gen_key():
    t = request.json.get('type')
    try:
        if t == 'reality':
            out = subprocess.check_output("xray x25519 || echo 'Private key: x Public key: x'", shell=True).decode()
            return jsonify({"private": out.split("Private key:")[1].split()[0].strip(), "public": out.split("Public key:")[1].split()[0].strip()})
        elif t == 'ss-128': return jsonify({"key": base64.b64encode(os.urandom(16)).decode()})
        elif t == 'ss-256': return jsonify({"key": base64.b64encode(os.urandom(32)).decode()})
    except: return jsonify({"key": "", "private": "", "public": ""})

# HTML 模板变量
LOGIN_T = """
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8"><title>MultiX Login</title>
<style>
body { margin: 0; height: 100vh; background: #050505; display: flex; align-items: center; justify-content: center; font-family: sans-serif; color: #fff; }
.login-box { background: rgba(20, 20, 20, 0.8); border: 1px solid rgba(255,255,255,0.1); border-radius: 20px; padding: 40px; width: 320px; backdrop-filter: blur(10px); box-shadow: 0 20px 50px rgba(0,0,0,0.5); text-align: center; }
h1 { font-style: italic; margin-bottom: 30px; font-size: 28px; background: linear-gradient(45deg, #3b82f6, #8b5cf6); -webkit-background-clip: text; -webkit-text-fill-color: transparent; font-weight: 900; }
input { background: #111; border: 1px solid #333; width: 100%; padding: 12px 15px; border-radius: 8px; color: #fff; margin-bottom: 15px; outline: none; box-sizing: border-box; transition: 0.3s; }
input:focus { border-color: #3b82f6; box-shadow: 0 0 10px rgba(59,130,246,0.3); }
button { width: 100%; padding: 12px; border-radius: 8px; border: none; background: linear-gradient(90deg, #3b82f6, #2563eb); color: #fff; font-weight: bold; cursor: pointer; transition: 0.3s; margin-top: 10px; }
button:hover { filter: brightness(1.2); transform: scale(1.02); }
</style>
</head>
<body>
<div class="login-box">
<h1>MultiX Pro</h1>
<form method="post">
<input type="text" name="u" placeholder="Username" required autocomplete="off">
<input type="password" name="p" placeholder="Password" required>
<button type="submit">ENTER SYSTEM</button>
</form>
</div>
</body>
</html>
"""

HTML_T = """
<!DOCTYPE html>
<html class="dark">
<head>
<meta charset="UTF-8"><title>MultiX Console</title>
<link rel="stylesheet" href="https://unpkg.com/element-plus/dist/index.css" />
<link rel="stylesheet" href="https://unpkg.com/element-plus/theme-chalk/dark/css-vars.css">
<script src="https://unpkg.com/vue@3/dist/vue.global.js"></script>
<script src="https://unpkg.com/element-plus"></script>
<script src="https://cdn.tailwindcss.com"></script>
<style>
body { background: #020202; color: #cfd3dc; margin: 0; padding: 20px; font-family: sans-serif; }
.glass-card { background: #141414; border: 1px solid #2c2c2c; border-radius: 12px; }
:root { --el-bg-color: #141414; --el-text-color-primary: #E5EAF3; --el-border-color: #333; }
.el-input__wrapper { background-color: #0a0a0a !important; box-shadow: 0 0 0 1px #333 inset !important; }
</style>
</head>
<body>
<script>
window.SERVER_INFO = { token: "{{ token }}", ipv4: "{{ ipv4 }}", ipv6: "{{ ipv6 }}" };
</script>
<div id="app">
<div class="flex justify-between items-center mb-8 px-4">
<div><h1 class="text-3xl font-black italic text-blue-500">MultiX <span class="text-white">Pro</span></h1><div class="text-xs text-zinc-500 mt-1 font-mono">TOKEN: <span class="text-blue-400">[[ sys.token ]]</span> | IP: <span class="text-zinc-400">[[ sys.ipv4 ]]</span></div></div>
<div class="flex gap-4"><el-tag type="info" effect="dark">CPU: [[ masterStats.CPU ]]%</el-tag><el-tag type="info" effect="dark">MEM: [[ masterStats.MEM ]]%</el-tag></div>
</div>
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
<div v-for="agent in displayAgents" :key="agent.ip" class="glass-card p-6 relative">
<div class="flex justify-between items-start mb-4"><div><div class="text-lg font-bold text-white cursor-pointer hover:text-blue-400" @click="editAlias(agent)">[[ agent.alias || 'Node' ]] ✎</div><div class="text-xs text-zinc-500 font-mono mt-1">[[ agent.ip ]]</div></div><div :class="['h-2 w-2 rounded-full', agent.syncing ? 'bg-yellow-500 animate-pulse' : (agent.nodes ? 'bg-green-500' : 'bg-red-500')]"></div></div>
<div class="grid grid-cols-2 gap-4 mb-6"><div class="bg-black/30 p-3 rounded-lg text-center border border-white/5"><div class="text-[10px] text-zinc-500">CPU</div><div class="text-sm font-bold text-blue-400">[[ agent.stats.cpu ]]%</div></div><div class="bg-black/30 p-3 rounded-lg text-center border border-white/5"><div class="text-[10px] text-zinc-500">MEM</div><div class="text-sm font-bold text-purple-400">[[ agent.stats.mem ]]%</div></div></div>
<el-button type="primary" size="small" @click="openManage(agent)" class="w-full">Manage ([[ agent.nodes.length ]])</el-button>
</div>
</div>
<el-drawer v-model="drawerVisible" :title="activeAgent.alias + ' / Inbounds'" size="600px">
<div class="p-6 h-full flex flex-col">
<div v-if="!isEditing" class="flex-1 overflow-y-auto space-y-3">
<el-empty v-if="activeAgent.nodes.length === 0" description="No Data"></el-empty>
<div v-for="node in activeAgent.nodes" :key="node.id" class="bg-zinc-900 border border-white/5 p-4 rounded-lg flex justify-between items-center hover:border-blue-500/50 cursor-pointer" @click="editNode(node)">
<div><div class="flex items-center gap-2"><el-tag size="small" effect="dark">[[ node.protocol.toUpperCase() ]]</el-tag><span class="font-bold text-sm">[[ node.remark ]]</span><el-tag size="small" type="warning" effect="plain">[[ node.port ]]</el-tag></div></div><el-button type="primary" link>Edit</el-button>
</div>
</div>
<div v-else class="flex-1 overflow-y-auto pr-2">
<el-form :model="form" label-position="top" size="large">
<div class="grid grid-cols-2 gap-4"><el-form-item label="Remark"><el-input v-model="form.remark" /></el-form-item><el-form-item label="Port"><el-input v-model.number="form.port" type="number" /></el-form-item></div>
<div class="grid grid-cols-2 gap-4"><el-form-item label="Protocol"><el-select v-model="form.protocol"><el-option value="vless" label="VLESS"></el-option><el-option value="vmess" label="VMess"></el-option><el-option value="shadowsocks" label="Shadowsocks"></el-option></el-select></el-form-item><el-form-item label="UUID" v-if="['vless','vmess'].includes(form.protocol)"><el-input v-model="form.uuid"><template #append><el-button @click="genUUID">GEN</el-button></template></el-input></el-form-item><el-form-item label="Cipher" v-if="form.protocol === 'shadowsocks'"><el-select v-model="form.ssCipher"><el-option value="aes-256-gcm">aes-256-gcm</el-option><el-option value="2022-blake3-aes-128-gcm">2022-blake3-aes-128-gcm</el-option></el-select></el-form-item></div>
<el-form-item label="Password" v-if="form.protocol === 'shadowsocks'"><el-input v-model="form.ssPass"><template #append><el-button @click="genSSKey">GEN</el-button></template></el-input></el-form-item>
<el-form-item label="Flow" v-if="form.protocol === 'vless' && form.security === 'reality'"><el-select v-model="form.flow"><el-option value="xtls-rprx-vision">xtls-rprx-vision</el-option></el-select></el-form-item>
<div v-if="form.protocol !== 'shadowsocks'">
<el-divider content-position="left">Transport</el-divider>
<div class="grid grid-cols-2 gap-4"><el-form-item label="Network"><el-select v-model="form.network"><el-option value="tcp">TCP</el-option><el-option value="ws">WebSocket</el-option></el-select></el-form-item><el-form-item label="Security"><el-select v-model="form.security"><el-option value="none">None</el-option><el-option value="tls">TLS</el-option><el-option value="reality" v-if="form.protocol === 'vless'">Reality</el-option></el-select></el-form-item></div>
<div v-if="form.security === 'reality'" class="bg-blue-900/10 p-4 rounded-lg border border-blue-500/20 mb-4"><el-form-item label="Dest"><el-input v-model="form.dest" /></el-form-item><el-form-item label="SNI"><el-input v-model="form.serverNames" /></el-form-item><el-form-item label="Key"><el-input v-model="form.privKey"><template #append><el-button @click="genRealityPair">PAIR</el-button></template></el-input></el-form-item><el-form-item label="SID"><el-input v-model="form.shortIds" /></el-form-item></div>
<div v-if="form.network === 'ws'" class="bg-zinc-800/30 p-4 rounded-lg border border-zinc-700 mb-4"><el-form-item label="Path"><el-input v-model="form.wsPath" /></el-form-item><el-form-item label="Host"><el-input v-model="form.wsHost" /></el-form-item></div>
</div>
<el-divider content-position="left">Limits</el-divider>
<div class="grid grid-cols-2 gap-4"><el-form-item label="Traffic (GB)"><el-input v-model="form.totalGB" type="number" /></el-form-item><el-form-item label="Expiry"><el-date-picker v-model="form.expiryDate" type="date" style="width: 100%" /></el-form-item></div>
</el-form>
</div>
<div class="mt-4 pt-4 border-t border-zinc-800 flex gap-3"><el-button v-if="isEditing" @click="isEditing = false" class="flex-1">Back</el-button><el-button v-if="isEditing" type="primary" @click="saveNode" class="flex-1" :loading="activeAgent.syncing">Save</el-button><el-button v-else type="primary" @click="openAdd" class="w-full">Add</el-button></div>
</div>
</el-drawer>
</div>
<script>
const { createApp, ref, computed, onMounted, reactive } = Vue;
const App = {
setup() {
const sys = ref(window.SERVER_INFO || {});
const agents = ref({}); const masterStats = ref({ CPU:0, MEM:0 });
const drawerVisible = ref(false); const isEditing = ref(false);
const activeAgent = ref({ nodes: [] }); const form = reactive({});
const mockAgent = ref({ ip: 'MOCK-SERVER', alias: 'Demo', stats: {cpu:10,mem:20}, nodes: [], syncing: false });
const displayAgents = computed(() => { const list = [mockAgent.value]; for(let k in agents.value) { agents.value[k].ip=k; list.push(agents.value[k]); } return list; });
const update = async () => { try { const r = await fetch('/api/state'); const d = await r.json(); masterStats.value = d.master.stats; for(let ip in d.agents) { if(!agents.value[ip] || !agents.value[ip].syncing) agents.value[ip] = { ...agents.value[ip], ...d.agents[ip], syncing: false }; } } catch(e){} };
const openManage = (agent) => { activeAgent.value = agent; drawerVisible.value = true; isEditing.value = false; };
const openAdd = () => { resetForm(); isEditing.value = true; };
const editAlias = (agent) => { const n = prompt("Rename:", agent.alias); if(n) agent.alias = n; };
const resetForm = () => { Object.assign(form, { id: null, remark: 'New', port: Math.floor(Math.random()*10000)+10000, protocol: 'vless', uuid: crypto.randomUUID(), email: 'u@mx.com', flow: 'xtls-rprx-vision', ssCipher: '2022-blake3-aes-128-gcm', ssPass: '', network: 'tcp', security: 'reality', dest: 'www.microsoft.com:443', serverNames: 'www.microsoft.com', privKey: '', shortIds: '', wsPath: '/', totalGB: '', expiryDate: null }); genRealityPair(); };
const editNode = (node) => { const s = node.settings||{}; const ss = node.stream_settings||{}; const c = s.clients?s.clients[0]:{}; Object.assign(form, { id: node.id, remark: node.remark, port: node.port, protocol: node.protocol, uuid: c.id, email: c.email, flow: c.flow, ssCipher: s.method, ssPass: s.password, network: ss.network||'tcp', security: ss.security||'none', dest: ss.realitySettings?.dest, serverNames: (ss.realitySettings?.serverNames||[]).join(','), privKey: ss.realitySettings?.privateKey, shortIds: (ss.realitySettings?.shortIds||[]).join(','), wsPath: ss.wsSettings?.path, wsHost: ss.wsSettings?.headers?.Host, totalGB: node.total>0?(node.total/1073741824).toFixed(2):'', expiryDate: node.expiry_time>0?new Date(node.expiry_time):null }); isEditing.value = true; };
const saveNode = async () => { if(activeAgent.value.ip.includes('MOCK')) return; activeAgent.value.syncing = true; const clients = []; if(form.protocol!=='shadowsocks') clients.push({ id: form.uuid, email: form.email, flow: form.flow, alterId: 0 }); const stream = { network: form.network, security: form.security }; if(form.security==='reality') stream.realitySettings = { dest: form.dest, privateKey: form.privKey, shortIds: form.shortIds?form.shortIds.split(','):[], serverNames: form.serverNames?form.serverNames.split(','):[], fingerprint: 'chrome' }; if(form.network==='ws') stream.wsSettings = { path: form.wsPath, headers: { Host: form.wsHost } }; const settings = form.protocol==='shadowsocks' ? { method: form.ssCipher, password: form.ssPass, network: "tcp,udp" } : { clients, decryption: "none" }; const payload = { id: form.id, remark: form.remark, port: parseInt(form.port), protocol: form.protocol, total: form.totalGB>0?Math.floor(form.totalGB*1073741824):0, expiry_time: form.expiryDate?new Date(form.expiryDate).getTime():0, settings: JSON.stringify(settings), stream_settings: JSON.stringify(stream), sniffing: JSON.stringify({ enabled: true, destOverride: ["http","tls","quic"] }) }; try { await fetch('/api/sync', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({ ip: activeAgent.value.ip, config: payload }) }); setTimeout(() => { activeAgent.value.syncing = false; drawerVisible.value = false; }, 3000); } catch(e) { activeAgent.value.syncing = false; } };
const genUUID = () => form.uuid = crypto.randomUUID();
const genRealityPair = async () => { try { const r = await fetch('/api/gen_key', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({type:'reality'})}); const d=await r.json(); if(d.private){form.privKey=d.private;form.pubKey=d.public;} } catch(e){} };
const genSSKey = async () => { let t='ss-128'; if(form.ssCipher.includes('256')) t='ss-256'; try { const r = await fetch('/api/gen_key', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({type:t})}); const d=await r.json(); form.ssPass=d.key; } catch(e){} };
onMounted(() => { update(); setInterval(update, 3000); });
return { masterStats, sys, drawerVisible, isEditing, activeAgent, displayAgents, form, openManage, openAdd, editAlias, editNode, saveNode, genUUID, genRealityPair, genSSKey };
}
};
const app = createApp(App); app.use(ElementPlus); app.config.compilerOptions.delimiters = ['[[', ']]']; app.mount('#app');
</script>
</body></html>
"""

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    s = get_sys_info()
    return render_template_string(HTML_T, token=M_TOKEN, ipv4=s['ipv4'], ipv6=s['ipv6'])

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form['u'] == M_USER and request.form['p'] == M_PASS: session['logged'] = True; return redirect('/')
    return render_template_string(LOGIN_T)

async def ws_handler(ws):
    ip = ws.remote_address[0]
    try:
        auth = await asyncio.wait_for(ws.recv(), timeout=10)
        if json.loads(auth).get('token') == M_TOKEN:
            AGENTS[ip] = {"ws": ws, "stats": {}, "nodes": []}
            async for msg in ws:
                d = json.loads(msg)
                if d.get('type') == 'heartbeat':
                    AGENTS[ip]['stats'] = d.get('data', {})
                    AGENTS[ip]['nodes'] = d.get('nodes', [])
    except: pass
    finally:
        if ip in AGENTS: del AGENTS[ip]

def start_ws():
    global LOOP_GLOBAL; LOOP_GLOBAL = asyncio.new_event_loop(); asyncio.set_event_loop(LOOP_GLOBAL)
    async def m(): await websockets.serve(ws_handler, "::", 8888, family=socket.AF_INET6)
    LOOP_GLOBAL.run_until_complete(m())

if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    app.run(host='::', port=M_PORT)
EOF

    # Systemd Config
    cat > /etc/systemd/system/multix-master.service <<EOF
[Unit]
Description=MultiX Master
After=network.target
[Service]
ExecStart=/usr/bin/python3 $M_ROOT/master/app.py
Restart=always
User=root
WorkingDirectory=$M_ROOT/master
Environment=PYTHONUNBUFFERED=1
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable multix-master; systemctl restart multix-master
    get_public_ips
    echo -e "${GREEN}✅ 主控端部署成功！${PLAIN}"
    echo -e "   IPv4入口: http://${IPV4}:${M_PORT}"
    [[ "$IPV6" != "N/A" ]] && echo -e "   IPv6入口: http://[${IPV6}]:${M_PORT}"
    echo -e "   Token: ${YELLOW}$M_TOKEN${PLAIN}"
    pause_back
}

# --- [ 7. 被控安装 (保持不变) ] ---
install_agent() {
    install_dependencies; mkdir -p $M_ROOT/agent
    
    if [ ! -d "/etc/x-ui" ]; then
        echo -e "${RED}未检测到 3X-UI 面板！${PLAIN}"
        read -p "是否自动安装 3X-UI (MHSanaei)? [Y/n]: " i
        if [[ "$i" != "n" ]]; then
            bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
            ufw allow 2053/tcp 2>/dev/null; firewall-cmd --zone=public --add-port=2053/tcp --permanent 2>/dev/null
        else
            echo "已取消"; exit 1
        fi
    fi

    echo -e "${SKYBLUE}>>> 被控端配置${PLAIN}"
    read -p "主控域名/IP: " IN_HOST; read -p "Token: " IN_TOKEN
    echo -e "${YELLOW}协议:${PLAIN} 1.自动  2.IPv4  3.IPv6"; read -p "选择: " NET_OPT
    TARGET_HOST="$IN_HOST"
    if [[ "$NET_OPT" == "3" ]]; then V6=$(resolve_ip "$IN_HOST" "AF_INET6"); [[ -n "$V6" ]] && TARGET_HOST="[$V6]"; fi
    if [[ "$NET_OPT" == "2" ]]; then V4=$(resolve_ip "$IN_HOST" "AF_INET"); [[ -n "$V4" ]] && TARGET_HOST="$V4"; fi
    
    cat > $M_ROOT/agent/Dockerfile <<EOF
FROM python:3.11-slim
RUN pip install websockets psutil --break-system-packages
WORKDIR /app
CMD ["python", "agent.py"]
EOF
    cat > $M_ROOT/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, socket, platform
MASTER = "$TARGET_HOST"; TOKEN = "$IN_TOKEN"; DB_PATH = "/app/db_share/x-ui.db"
def sync_db(data):
    try:
        conn = sqlite3.connect(DB_PATH, timeout=10); cursor = conn.cursor(); nid = data.get('id')
        vals = (data['remark'], data['port'], data['settings'], data['stream_settings'], data['sniffing'], data['total'], data['expiry_time'])
        if nid: cursor.execute("UPDATE inbounds SET remark=?, port=?, settings=?, stream_settings=?, sniffing=?, total=?, expiry_time=?, enable=1 WHERE id=?", vals + (nid,))
        else: cursor.execute("INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing) VALUES (1, 0, 0, ?, ?, 1, ?, '', ?, ?, ?, ?, 'multix', ?)", (data['total'], data['remark'], data['expiry_time'], data['port'], data['protocol'], data['settings'], data['stream_settings'], data['sniffing']))
        conn.commit(); conn.close(); return True
    except Exception as e: print(f"DB Error: {e}"); return False
async def run():
    target = MASTER
    if ":" in target and not target.startswith("["): target = f"[{target}]"
    uri = f"ws://{target}:8888"
    while True:
        try:
            async with websockets.connect(uri) as ws:
                await ws.send(json.dumps({"token": TOKEN}))
                while True:
                    conn = sqlite3.connect(DB_PATH); cur = conn.cursor()
                    cur.execute("SELECT id, remark, port, protocol, settings, stream_settings, sniffing, total, expiry_time FROM inbounds")
                    nodes = []
                    for r in cur.fetchall():
                        try:
                            s = json.loads(r[4]); ss = json.loads(r[5])
                            nodes.append({"id": r[0], "remark": r[1], "port": r[2], "protocol": r[3], "settings": s, "stream_settings": ss, "total": r[7], "expiry_time": r[8]})
                        except: pass
                    conn.close()
                    stats = { "cpu": int(psutil.cpu_percent()), "mem": int(psutil.virtual_memory().percent), "os": platform.system() }
                    await ws.send(json.dumps({"type": "heartbeat", "data": stats, "nodes": nodes}))
                    try:
                        msg = await asyncio.wait_for(ws.recv(), timeout=5); task = json.loads(msg)
                        if task.get('action') == 'sync_node': os.system("docker restart 3x-ui"); sync_db(task['data']); os.system("docker restart 3x-ui")
                    except: continue
        except: await asyncio.sleep(5)
asyncio.run(run())
EOF
    cd $M_ROOT/agent; docker build -t multix-agent-v62 .
    docker rm -f multix-agent 2>/dev/null
    docker run -d --name multix-agent --restart always --network host -v /var/run/docker.sock:/var/run/docker.sock -v /etc/x-ui:/app/db_share -v $M_ROOT/agent:/app multix-agent-v62
    echo -e "${GREEN}✅ 被控已启动${PLAIN}"; pause_back
}

# --- [ 8. 运维菜单 ] ---
sys_tools() {
    while true; do
        clear; echo -e "${SKYBLUE}🧰 运维工具箱${PLAIN}"
        echo "1. BBR加速"; echo "2. 安装 3X-UI"; echo "3. 申请 SSL"; echo "4. 重置 3X-UI"; echo "5. 清空流量"; echo "6. 开放端口"; echo "0. 返回"
        read -p "选择: " t; case $t in
            1) bash <(curl -L -s https://github.com/chiakge/Linux-NetSpeed/raw/master/tcp.sh) ;;
            2) bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) ;;
            3) curl https://get.acme.sh | sh ;;
            4) docker exec -it 3x-ui x-ui setting ;;
            5) sqlite3 $M_ROOT/agent/db_data/x-ui.db "UPDATE client_traffics SET up=0, down=0;" && echo "已清空" ;;
            6) read -p "端口: " p; ufw allow $p/tcp 2>/dev/null; firewall-cmd --zone=public --add-port=$p/tcp --permanent 2>/dev/null; echo "Done" ;;
            0) break ;;
        esac; read -n 1 -s -r -p "继续..."
    done; main_menu
}

main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ MultiX Pro (V62.1 依赖修复版)${PLAIN}"
    echo " 1. 安装 主控端 | 2. 安装 被控端"
    echo " 3. 连通测试   | 4. 被控重启"
    echo " 5. 深度清理   | 6. 环境修复"
    echo " 7. 凭据管理   | 8. 实时日志"
    echo " 9. 运维工具   | 10. 服务管理"
    echo " 0. 退出"; read -p "选择: " c
    case $c in
        1) install_master ;; 2) install_agent ;;
        3) read -p "IP: " t; nc -zv -w 5 $t 8888; pause_back ;;
        4) docker restart multix-agent; pause_back ;;
        5) deep_cleanup ;;
        6) install_dependencies; pause_back ;;
        7) credential_center ;;
        8) journalctl -u multix-master -f || docker logs -f multix-agent --tail 50; pause_back ;;
        9) sys_tools ;; 10) service_manager ;; 0) exit 0 ;; *) main_menu ;;
    esac
}
main_menu
