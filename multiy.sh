#!/bin/bash
# Multiy Pro V78.0 - 链路诊断 + 智能自愈版

export M_ROOT="/opt/multiy_mvp"
SH_VER="V78.0"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 基础功能 ] ---
install_shortcut() { [ ! -f /usr/bin/multiy ] && cp "$0" /usr/bin/multiy && chmod +x /usr/bin/multiy; }
install_shortcut
get_env_val() { [ -f "$M_ROOT/.env" ] && grep "^$1=" "$M_ROOT/.env" | cut -d"'" -f2 || echo ""; }
pause_back() { echo -e "\n${YELLOW}按任意键返回菜单...${PLAIN}"; read -n 1 -s -r; main_menu; }

# --- [ 模块 3：智能拨测与链路诊断 ] ---
smart_diagnostic() {
    clear; echo -e "${SKYBLUE}🔍 Multiy 智能链路诊断中心${PLAIN}"
    echo -e "------------------------------------------------"
    
    if [ ! -f "$M_ROOT/agent/agent.py" ]; then
        echo -e "${RED}[错误] 未检测到被控端安装，无法诊断。${PLAIN}"
        pause_back; return
    fi

    # 提取被控端配置
    A_MASTER=$(grep "MASTER =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
    A_TOKEN=$(grep "TOKEN =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
    A_PORT=$(grep "PORT =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)
    A_PREF=$(grep "PREF =" "$M_ROOT/agent/agent.py" | cut -d'"' -f2)

    echo -e "1. 目标主控: ${SKYBLUE}${A_MASTER}:${A_PORT}${PLAIN}"
    echo -e "2. 校验令牌: ${YELLOW}${A_TOKEN}${PLAIN}"
    echo -e "3. 协议偏好: $([[ $A_PREF == "1" ]] && echo "强制 IPv6" || ([[ $A_PREF == "2" ]] && echo "强制 IPv4" || echo "自动双栈"))"
    
    echo -e "\n${YELLOW}[正在执行实时拨测...]${PLAIN}"
    # 检测主控端口通透性 (使用 nc 或 curl)
    if curl -sk --max-time 3 "https://${A_MASTER}:${A_PORT}" > /dev/null 2>&1 || [ $? -eq 52 ]; then
        echo -e "👉 端口通透性: ${GREEN}成功 (主控端口已开放)${PLAIN}"
    else
        echo -e "👉 端口通透性: ${RED}失败 (主控端口不可达，请检查防火墙或端口映射)${PLAIN}"
    fi

    # 检查 Agent 进程
    if pgrep -f "multiy-agent" > /dev/null; then
        echo -e "👉 Agent 进程: ${GREEN}运行中${PLAIN}"
    else
        echo -e "👉 Agent 进程: ${RED}未运行 (正在尝试智能重启...)${PLAIN}"
        systemctl restart multiy-agent
    fi

    echo -e "\n${YELLOW}[最近 5 条通信日志]${PLAIN}"
    journalctl -u multiy-agent -n 5 --output cat
    
    echo -e "------------------------------------------------"
    echo " 1. 强制重启 Agent | 2. 修改连接凭据 | 0. 返回"
    read -p "选择: " d_opt
    case $d_opt in
        1) systemctl restart multiy-agent; echo "已下达重启指令"; sleep 2; smart_diagnostic ;;
        2) install_agent ;;
        *) main_menu ;;
    esac
}

# --- [ 模块 1：强化版主控面板 (集成卡片与自愈逻辑) ] ---
_generate_master_py() {
cat > "$M_ROOT/master/app.py" << 'EOF'
import json, asyncio, psutil, os, websockets, ssl, time
from flask import Flask, render_template_string, request, session, redirect, jsonify
from threading import Thread

def load_env():
    c = {}
    if os.path.exists('/opt/multiy_mvp/.env'):
        with open('/opt/multiy_mvp/.env') as f:
            for l in f:
                if '=' in l: k,v = l.strip().split('=', 1); c[k] = v.strip("'\"")
    return c

app = Flask(__name__)
app.jinja_env.variable_start_string, app.jinja_env.variable_end_string = '[[', ']]'
AGENTS = {}

@app.route('/api/state')
def api_state():
    conf = load_env()
    return jsonify({
        "master_token": conf.get('M_TOKEN'),
        "agents": {ip: {"stats": a['stats'], "alias": a.get('alias'), "delay": a.get('delay', 0), "last_seen": a['last_seen']} for ip,a in AGENTS.items()}
    })

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    return render_template_string("""
    <!DOCTYPE html><html><head><meta charset="UTF-8"><script src="https://cdn.tailwindcss.com"></script>
    <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
    <style>body{background:#020617;color:#fff;font-family:Inter,sans-serif}.glass{background:rgba(15,23,42,0.8);backdrop-filter:blur(20px);border:1px solid rgba(255,255,255,0.1);padding:24px;border-radius:24px}</style>
    </head><body class="p-8" x-data="panel()" x-init="start()">
        <div class="max-w-7xl mx-auto flex justify-between items-center mb-10">
            <div><h1 class="text-3xl font-black italic text-blue-500">MULTIY <span class="text-white">PRO</span></h1><p class="text-[10px] text-slate-500 tracking-widest mt-1">REAL-TIME MONITORING SYSTEM</p></div>
            <div class="flex items-center gap-6 bg-slate-900/50 p-2 px-6 rounded-2xl border border-slate-800">
                <div class="text-right"><p class="text-[9px] text-slate-500">SECURITY TOKEN</p><p class="text-blue-400 font-mono text-sm" x-text="tk"></p></div>
                <a href="/logout" class="bg-red-500/10 text-red-500 px-4 py-2 rounded-xl text-xs font-bold border border-red-500/20">LOGOUT</a>
            </div>
        </div>
        <div class="max-w-7xl mx-auto grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <template x-for="(a, ip) in agents" :key="ip">
                <div class="glass border-t-4 border-blue-500 hover:scale-[1.02] transition-all">
                    <div class="flex justify-between items-start mb-6">
                        <div class="flex items-center gap-4">
                            <div class="w-12 h-12 bg-blue-600/20 rounded-2xl flex items-center justify-center text-blue-400 font-bold text-xl" x-text="a.alias[0].toUpperCase()"></div>
                            <div><b class="text-lg block text-slate-100" x-text="a.alias"></b><span class="text-[10px] text-slate-500 font-mono" x-text="ip"></span></div>
                        </div>
                        <div class="text-right">
                            <div class="flex items-center justify-end gap-2"><span class="text-[10px] text-green-400 font-bold" x-text="a.delay+'ms'"></span><span class="w-2.5 h-2.5 bg-green-500 rounded-full shadow-[0_0_10px_#22c55e]"></span></div>
                            <p class="text-[9px] text-slate-600 mt-1 uppercase font-bold">Encrypted WSS</p>
                        </div>
                    </div>
                    <div class="space-y-4">
                        <div class="bg-black/20 p-4 rounded-2xl">
                            <div class="flex justify-between text-[10px] mb-2 font-bold text-slate-400"><span>CPU 负载</span><span x-text="a.stats.cpu+'%'"></span></div>
                            <div class="w-full bg-slate-800 h-1.5 rounded-full"><div class="bg-blue-500 h-full rounded-full transition-all duration-1000" :style="'width:'+a.stats.cpu+'%'"></div></div>
                        </div>
                        <div class="bg-black/20 p-4 rounded-2xl">
                            <div class="flex justify-between text-[10px] mb-2 font-bold text-slate-400"><span>内存占用</span><span x-text="a.stats.mem+'%'"></span></div>
                            <div class="w-full bg-slate-800 h-1.5 rounded-full"><div class="bg-indigo-500 h-full rounded-full transition-all duration-1000" :style="'width:'+a.stats.mem+'%'"></div></div>
                        </div>
                    </div>
                    <div class="mt-6 flex justify-between text-[10px] text-slate-600 font-bold uppercase tracking-tighter">
                        <span>智能拨测: <span class="text-blue-500">Connected</span></span>
                        <span x-text="'心跳: '+(Math.floor(Date.now()/1000)-a.last_seen)+'s前'"></span>
                    </div>
                </div>
            </template>
        </div>
        <script>
        function panel(){ return { agents:{}, tk:'', start(){this.fetchData();setInterval(()=>this.fetchData(),3000)}, async fetchData(){ try{const r=await fetch('/api/state');const d=await r.json();this.agents=d.agents;this.tk=d.master_token}catch(e){} } } }
        </script>
    </body></html>
    """)

@app.route('/login', methods=['GET', 'POST'])
def login():
    conf = load_env()
    app.secret_key = conf.get('M_TOKEN', 'secret')
    if request.method == 'POST' and request.form.get('u') == conf.get('M_USER') and request.form.get('p') == conf.get('M_PASS'):
        session['logged'] = True; return redirect('/')
    return """<body style="background:#020617;display:flex;justify-content:center;align-items:center;height:100vh;color:#fff;font-family:sans-serif">
    <form method="post" style="background:rgba(255,255,255,0.03);backdrop-filter:blur(20px);padding:50px;border-radius:30px;border:1px solid rgba(255,255,255,0.1);width:320px;text-align:center">
        <h2 style="color:#3b82f6;font-size:1.8rem;font-weight:900;margin-bottom:30px;font-style:italic">MULTIY LOGIN</h2>
        <input name="u" placeholder="Admin Username" style="width:100%;padding:14px;margin:10px 0;background:#000;border:1px solid #333;color:#fff;border-radius:12px;outline:none">
        <input name="p" type="password" placeholder="Password" style="width:100%;padding:14px;margin:10px 0;background:#000;border:1px solid #333;color:#fff;border-radius:12px;outline:none">
        <button style="width:100%;padding:14px;background:#3b82f6;color:#fff;border:none;border-radius:12px;font-weight:900;cursor:pointer;margin-top:20px hover:bg-blue-600 transition-all">ENTER PANEL</button>
    </form></body>"""

@app.route('/logout')
def logout(): session.pop('logged', None); return redirect('/login')

async def ws_handler(ws):
    ip = ws.remote_address[0]; conf = load_env()
    try:
        auth_raw = await asyncio.wait_for(ws.recv(), timeout=5)
        auth = json.loads(auth_raw)
        if auth.get('token') == conf.get('M_TOKEN'):
            AGENTS[ip] = {"ws":ws, "stats":{"cpu":0,"mem":0}, "alias":auth.get('hostname','Node'), "last_seen":time.time(), "delay":0}
            async for msg in ws:
                d = json.loads(msg)
                if d['type'] == 'heartbeat':
                    AGENTS[ip]['stats'] = d['data']; AGENTS[ip]['last_seen'] = time.time(); AGENTS[ip]['delay'] = d.get('delay',0)
    except: pass
    finally: AGENTS.pop(ip, None)

def start_ws():
    conf = load_env(); loop = asyncio.new_event_loop(); asyncio.set_event_loop(loop)
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ssl_ctx.load_cert_chain('cert.pem', 'key.pem')
    loop.run_until_complete(asyncio.gather(websockets.serve(ws_handler,"0.0.0.0",int(conf.get('WS_PORT',9339)),ssl=ssl_ctx),
                                          websockets.serve(ws_handler,"::",int(conf.get('WS_PORT',9339)),ssl=ssl_ctx)))
    loop.run_forever()

if __name__ == '__main__':
    Thread(target=start_ws, daemon=True).start()
    conf = load_env(); app.run(host='::', port=int(conf.get('M_PORT', 7575)))
EOF
}

# --- [ 主菜单模块 ] ---
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ Multiy Pro ${SH_VER}${PLAIN}"
    echo " 1. 安装/更新 Multiy 主控 (强化卡片版)"
    echo " 2. 安装/更新 Multiy 被控 (自愈拨测版)"
    echo " 3. 智能拨测与链路诊断 ( 实时排障中心 )"
    echo " 4. 凭据与配置中心 ( 查看双栈地址 )"
    echo " 5. 深度清理中心 ( 重置环境 )"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in
        1) install_master ;; 
        2) install_agent ;;
        3) smart_diagnostic ;;
        4) credential_center ;;
        5) deep_clean ;;
        0) exit 0 ;; *) main_menu ;;
    esac
}
# ... (其余安装/清理逻辑保持 V77.0 高效实现)
check_root; main_menu
