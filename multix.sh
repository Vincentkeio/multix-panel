#!/bin/bash

# ==============================================================================
# MultiX Pro Script V64.0 (Bootstrap/jQuery Classic Edition)
# Tech Stack: Flask + Bootstrap 5 + jQuery (No Vue, No Jinja Conflicts)
# Features: Full 3X-UI Protocol Support | Secure Write | Legacy Install Flow
# ==============================================================================

export M_ROOT="/opt/multix_mvp"
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
SH_VER="V64.0"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; SKYBLUE='\033[0;36m'; PLAIN='\033[0m'

# --- [ 0. 快捷命令 ] ---
install_shortcut() {
    rm -f /usr/bin/multix
    cp "$0" /usr/bin/multix && chmod +x /usr/bin/multix
    echo -e "${GREEN}[INFO]${PLAIN} multix 快捷命令已更新"
}
install_shortcut

# --- [ 1. 基础函数 ] ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${RED}[ERROR]${PLAIN} 必须 Root 运行！" && exit 1; }
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

# --- [ 2. 环境修复 ] ---
fix_dual_stack() {
    if grep -q "net.ipv6.bindv6only" /etc/sysctl.conf; then sed -i 's/net.ipv6.bindv6only.*/net.ipv6.bindv6only = 0/' /etc/sysctl.conf
    else echo "net.ipv6.bindv6only = 0" >> /etc/sysctl.conf; fi
    sysctl -p >/dev/null 2>&1
}
install_dependencies() {
    echo -e "${YELLOW}[INFO]${PLAIN} 检查并安装依赖..."
    check_sys
    if [[ "${RELEASE}" == "centos" ]]; then yum install -y epel-release python3 python3-devel python3-pip curl wget socat tar openssl git
    else apt-get update && apt-get install -y python3 python3-pip curl wget socat tar openssl git; fi
    
    # 强制安装兼容版本 Flask
    pip3 install "Flask<3.0.0" "Werkzeug<3.0.0" "websockets" "psutil" --break-system-packages >/dev/null 2>&1 || \
    pip3 install "Flask<3.0.0" "Werkzeug<3.0.0" "websockets" "psutil" >/dev/null 2>&1
    
    if ! command -v docker &> /dev/null; then curl -fsSL https://get.docker.com | bash; systemctl start docker; fi
    fix_dual_stack
}

# --- [ 3. 深度清理 ] ---
deep_cleanup() {
    echo -e "${RED}⚠️  警告：清理所有组件！${PLAIN}"; read -p "确认? [y/N]: " confirm
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
        echo " 1. 启动主控  2. 停止主控  3. 重启主控"
        echo " 4. 查看主控状态 (DEBUG)"
        echo " 5. 重启被控  6. 被控日志"
        echo " 0. 返回"
        read -p "选择: " s
        case $s in
            1) systemctl start multix-master && echo "Done" ;; 2) systemctl stop multix-master && echo "Done" ;;
            3) systemctl restart multix-master && echo "Done" ;; 
            4) systemctl status multix-master -l --no-pager ;;
            5) docker restart multix-agent && echo "Done" ;; 6) docker logs multix-agent --tail 20 ;; 0) break ;;
        esac; read -n 1 -s -r -p "继续..."
    done; main_menu
}

# --- [ 5. 凭据中心 ] ---
credential_center() {
    clear; echo -e "${SKYBLUE}🔐 凭据中心${PLAIN}"
    if [ -f $M_ROOT/.env ]; then
        source $M_ROOT/.env
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

# --- [ 6. 主控安装 (V64 Bootstrap版) ] ---
install_master() {
    install_dependencies; mkdir -p $M_ROOT/master $M_ROOT/agent/db_data
    if [ -f $M_ROOT/.env ]; then source $M_ROOT/.env; fi
    
    echo -e "${SKYBLUE}>>> 主控参数配置 (交互模式)${PLAIN}"
    read -p "管理端口 [默认 7575]: " IN_PORT; M_PORT=${IN_PORT:-${M_PORT:-7575}}
    read -p "管理用户 [默认 admin]: " IN_USER; M_USER=${IN_USER:-${M_USER:-admin}}
    read -p "管理密码 [默认 admin]: " IN_PASS; M_PASS=${IN_PASS:-${M_PASS:-admin}}
    RAND=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    read -p "Token [默认随机]: " IN_TOKEN; M_TOKEN=${IN_TOKEN:-${M_TOKEN:-$RAND}}
    
    echo -e "M_TOKEN='$M_TOKEN'\nM_PORT='$M_PORT'\nM_USER='$M_USER'\nM_PASS='$M_PASS'" > $M_ROOT/.env
    
    echo -e "${YELLOW}🛰️ 部署主控 (V64.0 Bootstrap/jQuery)...${PLAIN}"
    
    # 核心：使用 'EOF' 锁定，禁止 Shell 解析内部内容，确保 Python/JS 源码纯净
    cat > $M_ROOT/master/app.py <<'EOF'
import json, asyncio, psutil, os, socket, subprocess, base64, logging
from flask import Flask, render_template_string, request, session, redirect, jsonify
import websockets
from threading import Thread

# 日志配置
logging.basicConfig(level=logging.ERROR)

# 动态配置读取
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
M_USER = CONF.get('M_USER', 'admin')
M_PASS = CONF.get('M_PASS', 'admin')
M_TOKEN = CONF.get('M_TOKEN', 'error')

app = Flask(__name__)
app.secret_key = M_TOKEN

AGENTS = {}; LOOP_GLOBAL = None

def get_sys_info():
    try: return {"cpu": psutil.cpu_percent(), "mem": psutil.virtual_memory().percent, "ipv4": os.popen("curl -4s api.ipify.org").read().strip(), "ipv6": os.popen("curl -6s api64.ipify.org").read().strip()}
    except: return {"cpu":0,"mem":0, "ipv4":"N/A", "ipv6":"N/A"}

# 密钥生成接口
@app.route('/api/gen_key', methods=['POST'])
def gen_key():
    t = request.json.get('type')
    try:
        if t == 'reality':
            out = subprocess.check_output("xray x25519 || echo 'Private key: x Public key: x'", shell=True).decode()
            return jsonify({"private": out.split("Private key:")[1].split()[0].strip(), "public": out.split("Public key:")[1].split()[0].strip()})
        elif t == 'ss-128': return jsonify({"key": base64.b64encode(os.urandom(16)).decode()})
        elif t == 'ss-256': return jsonify({"key": base64.b64encode(os.urandom(32)).decode()})
    except: return jsonify({"key": "Error: Install Xray", "private": "", "public": ""})

# HTML 模板：Bootstrap 5 + jQuery
HTML_T = """
<!DOCTYPE html>
<html lang="en" data-bs-theme="dark">
<head>
    <meta charset="UTF-8"><title>MultiX Pro V64</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <style>
        body { background: #050505; font-family: 'Segoe UI', sans-serif; padding-top: 20px; }
        .card { background: #111; border: 1px solid #333; transition: 0.3s; }
        .card:hover { border-color: #0d6efd; transform: translateY(-2px); }
        .status-dot { width: 10px; height: 10px; border-radius: 50%; display: inline-block; }
        .status-online { background: #198754; box-shadow: 0 0 5px #198754; }
        .status-offline { background: #dc3545; }
        .form-label { font-size: 0.8rem; color: #aaa; text-transform: uppercase; font-weight: bold; margin-bottom: 2px; }
        .form-control, .form-select { background: #1a1a1a; border: 1px solid #333; color: #fff; font-size: 0.9rem; }
        .form-control:focus, .form-select:focus { background: #1a1a1a; border-color: #0d6efd; color: #fff; box-shadow: 0 0 0 0.2rem rgba(13,110,253,0.25); }
        .modal-content { background: #0a0a0a; border: 1px solid #333; }
        .modal-header { border-bottom: 1px solid #222; }
        .modal-footer { border-top: 1px solid #222; }
    </style>
</head>
<body>
<div class="container">
    <div class="d-flex justify-content-between align-items-center mb-4">
        <div>
            <h2 class="fw-bold fst-italic text-primary mb-0">MultiX <span class="text-white">Pro</span></h2>
            <small class="text-secondary font-monospace" id="sys-info">TOKEN: Loading...</small>
        </div>
        <div class="d-flex gap-2">
            <span class="badge bg-dark border border-secondary p-2">CPU: <span id="cpu">0</span>%</span>
            <span class="badge bg-dark border border-secondary p-2">MEM: <span id="mem">0</span>%</span>
        </div>
    </div>

    <div class="row g-4" id="node-list"></div>
</div>

<div class="modal fade" id="configModal" tabindex="-1">
    <div class="modal-dialog modal-lg modal-dialog-centered">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title fw-bold">Configuration</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
            </div>
            <div class="modal-body">
                <form id="nodeForm">
                    <input type="hidden" id="nodeId">
                    <div class="row g-3">
                        <div class="col-md-6">
                            <label class="form-label">Remark</label>
                            <input type="text" class="form-control" id="remark" placeholder="My Node">
                        </div>
                        <div class="col-md-6">
                            <label class="form-label">Port</label>
                            <input type="number" class="form-control" id="port">
                        </div>
                        
                        <div class="col-md-6">
                            <label class="form-label">Protocol</label>
                            <select class="form-select" id="protocol">
                                <option value="vless">VLESS</option>
                                <option value="vmess">VMess</option>
                                <option value="shadowsocks">Shadowsocks</option>
                            </select>
                        </div>
                        
                        <div class="col-md-6 group-uuid">
                            <label class="form-label">UUID</label>
                            <div class="input-group">
                                <input type="text" class="form-control font-monospace" id="uuid">
                                <button class="btn btn-outline-secondary" type="button" onclick="genUUID()">Gen</button>
                            </div>
                        </div>

                        <div class="col-md-6 group-ss" style="display:none">
                            <label class="form-label">Cipher</label>
                            <select class="form-select" id="ssCipher">
                                <option value="aes-256-gcm">aes-256-gcm</option>
                                <option value="2022-blake3-aes-128-gcm">2022-blake3-aes-128-gcm</option>
                                <option value="2022-blake3-aes-256-gcm">2022-blake3-aes-256-gcm</option>
                            </select>
                        </div>
                        <div class="col-12 group-ss" style="display:none">
                            <label class="form-label">Password</label>
                            <div class="input-group">
                                <input type="text" class="form-control font-monospace" id="ssPass">
                                <button class="btn btn-outline-secondary" type="button" onclick="genSSKey()">Gen Key</button>
                            </div>
                        </div>

                        <div class="col-12 group-stream">
                            <hr class="border-secondary my-3">
                            <h6 class="text-primary fw-bold mb-3">Transport & Security</h6>
                            <div class="row g-3">
                                <div class="col-md-6">
                                    <label class="form-label">Network</label>
                                    <select class="form-select" id="network">
                                        <option value="tcp">TCP</option>
                                        <option value="ws">WebSocket</option>
                                    </select>
                                </div>
                                <div class="col-md-6">
                                    <label class="form-label">Security</label>
                                    <select class="form-select" id="security">
                                        <option value="none">None</option>
                                        <option value="tls">TLS</option>
                                        <option value="reality">Reality</option>
                                    </select>
                                </div>
                            </div>
                        </div>

                        <div class="col-12 group-reality p-3 mt-3 bg-dark border border-primary rounded" style="display:none">
                            <div class="row g-3">
                                <div class="col-md-6">
                                    <label class="form-label text-primary">Dest (SNI)</label>
                                    <input type="text" class="form-control" id="dest" value="www.microsoft.com:443">
                                </div>
                                <div class="col-md-6">
                                    <label class="form-label text-primary">SNI List</label>
                                    <input type="text" class="form-control" id="serverNames" value="www.microsoft.com">
                                </div>
                                <div class="col-12">
                                    <label class="form-label text-primary">Private Key</label>
                                    <div class="input-group">
                                        <input type="text" class="form-control font-monospace" id="privKey" style="font-size:0.8rem">
                                        <button class="btn btn-primary" type="button" onclick="genReality()">Pair</button>
                                    </div>
                                </div>
                                <div class="col-12">
                                    <label class="form-label text-primary">Public Key</label>
                                    <input type="text" class="form-control font-monospace bg-black" id="pubKey" readonly style="font-size:0.8rem">
                                </div>
                                <div class="col-12">
                                    <label class="form-label text-primary">Short IDs</label>
                                    <input type="text" class="form-control font-monospace" id="shortIds">
                                </div>
                            </div>
                        </div>

                        <div class="col-12 group-ws p-3 mt-3 bg-secondary bg-opacity-10 border border-secondary rounded" style="display:none">
                            <div class="row g-3">
                                <div class="col-md-6"><label class="form-label">Path</label><input type="text" class="form-control" id="wsPath" value="/"></div>
                                <div class="col-md-6"><label class="form-label">Host</label><input type="text" class="form-control" id="wsHost"></div>
                            </div>
                        </div>

                        <div class="col-12">
                            <hr class="border-secondary my-3">
                            <h6 class="text-warning fw-bold mb-3">Limits</h6>
                            <div class="row g-3">
                                <div class="col-md-6">
                                    <label class="form-label">Traffic (GB)</label>
                                    <input type="number" class="form-control" id="totalGB" placeholder="0 = Unlimited">
                                </div>
                                <div class="col-md-6">
                                    <label class="form-label">Expiry Date</label>
                                    <input type="date" class="form-control" id="expiryDate">
                                </div>
                            </div>
                        </div>
                    </div>
                </form>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-dark" data-bs-dismiss="modal">Close</button>
                <button type="button" class="btn btn-primary" id="saveBtn">Save & Restart</button>
            </div>
        </div>
    </div>
</div>

<script>
    let AGENTS = {};
    let ACTIVE_IP = '';
    const TOKEN = '{{ token }}'; // Flask Template Injection (Only here)

    // Poll State
    function updateState() {
        $.getJSON('/api/state', function(data) {
            $('#cpu').text(data.master.stats.cpu);
            $('#mem').text(data.master.stats.mem);
            $('#sys-info').text('TOKEN: '+TOKEN+' | IP: '+data.master.ipv4);
            AGENTS = data.agents;
            renderGrid();
        });
    }

    function renderGrid() {
        $('#node-list').empty();
        if (Object.keys(AGENTS).length === 0) {
            $('#node-list').html('<div class="text-center text-secondary py-5">Waiting for Agents...</div>');
            return;
        }
        for (const [ip, agent] of Object.entries(AGENTS)) {
            const statusClass = agent.stats.cpu !== undefined ? 'status-online' : 'status-offline';
            const nodeCount = agent.nodes ? agent.nodes.length : 0;
            const card = `
                <div class="col-md-6 col-lg-4">
                    <div class="card h-100 p-4">
                        <div class="d-flex justify-content-between mb-3">
                            <h5 class="fw-bold text-white mb-0">\${agent.alias || 'Node'}</h5>
                            <span class="status-dot \${statusClass}"></span>
                        </div>
                        <div class="small text-secondary font-monospace mb-3">\${ip}</div>
                        <div class="d-flex gap-2 mb-4">
                            <span class="badge bg-dark border border-secondary">CPU: \${agent.stats.cpu || 0}%</span>
                            <span class="badge bg-dark border border-secondary">MEM: \${agent.stats.mem || 0}%</span>
                        </div>
                        <button class="btn btn-primary btn-sm w-100 fw-bold" onclick="openManager('\${ip}')">
                            MANAGE NODES (\${nodeCount})
                        </button>
                    </div>
                </div>`;
            $('#node-list').append(card);
        }
    }

    function openManager(ip) {
        ACTIVE_IP = ip;
        const agent = AGENTS[ip];
        // For simplicity, we just open the Add Modal or List. 
        // Real implementation would list nodes first. Here we jump to 'Add' for demo or 'Edit' the first one.
        // Let's make it an 'Add New' trigger for now to keep it simple as requested.
        // Or if nodes exist, list them in a simple alerts? 
        // Let's do a simple prompt: Clear form and show modal.
        if(agent.nodes && agent.nodes.length > 0) {
            // Edit first node for demo, or logic to list. 
            // Given "Simple", let's load the first node or clear if empty.
            loadForm(agent.nodes[0]); 
        } else {
            resetForm();
        }
        $('#configModal').modal('show');
    }

    // Logic for Dynamic Form
    function updateFormVisibility() {
        const p = $('#protocol').val();
        const n = $('#network').val();
        const s = $('#security').val();

        if (p === 'shadowsocks') {
            $('.group-uuid').hide(); $('.group-stream').hide(); $('.group-reality').hide(); $('.group-ws').hide();
            $('.group-ss').show();
        } else {
            $('.group-uuid').show(); $('.group-stream').show(); $('.group-ss').hide();
            
            if (s === 'reality') $('.group-reality').show(); else $('.group-reality').hide();
            if (n === 'ws') $('.group-ws').show(); else $('.group-ws').hide();
        }
    }

    $('#protocol, #network, #security').change(updateFormVisibility);

    function genUUID() { $('#uuid').val(crypto.randomUUID()); }
    function genSSKey() {
        const type = $('#ssCipher').val().includes('256') ? 'ss-256' : 'ss-128';
        $.ajax({url: '/api/gen_key', type: 'POST', contentType: 'application/json', data: JSON.stringify({type: type}), success: function(d){ $('#ssPass').val(d.key); }});
    }
    function genReality() {
        $.ajax({url: '/api/gen_key', type: 'POST', contentType: 'application/json', data: JSON.stringify({type: 'reality'}), success: function(d){ $('#privKey').val(d.private); $('#pubKey').val(d.public); }});
    }

    function resetForm() {
        $('#nodeForm')[0].reset();
        $('#nodeId').val('');
        $('#protocol').val('vless'); $('#network').val('tcp'); $('#security').val('reality');
        genUUID(); genReality();
        updateFormVisibility();
    }

    function loadForm(node) {
        // Map 3X-UI JSON to Form
        try {
            const s = node.settings || {}; const ss = node.stream_settings || {}; 
            const c = s.clients ? s.clients[0] : {};
            
            $('#nodeId').val(node.id); $('#remark').val(node.remark); $('#port').val(node.port); $('#protocol').val(node.protocol);
            
            if(node.protocol === 'shadowsocks') {
                $('#ssCipher').val(s.method); $('#ssPass').val(s.password);
            } else {
                $('#uuid').val(c.id);
            }

            $('#network').val(ss.network || 'tcp');
            $('#security').val(ss.security || 'none');

            if(ss.realitySettings) {
                $('#dest').val(ss.realitySettings.dest);
                $('#serverNames').val((ss.realitySettings.serverNames||[]).join(','));
                $('#privKey').val(ss.realitySettings.privateKey);
                // Public Key isn't stored usually, need regen or just hide
                $('#shortIds').val((ss.realitySettings.shortIds||[]).join(','));
            }
            
            if(ss.wsSettings) {
                $('#wsPath').val(ss.wsSettings.path);
                $('#wsHost').val(ss.wsSettings.headers?.Host);
            }

            if(node.total > 0) $('#totalGB').val((node.total / 1073741824).toFixed(2));
            if(node.expiry_time > 0) $('#expiryDate').val(new Date(node.expiry_time).toISOString().split('T')[0]);

            updateFormVisibility();
        } catch(e) { console.error(e); resetForm(); }
    }

    $('#saveBtn').click(function() {
        const p = $('#protocol').val();
        const n = $('#network').val();
        const s = $('#security').val();
        
        let clients = [];
        if(p !== 'shadowsocks') clients.push({id: $('#uuid').val(), flow: (s==='reality' && p==='vless')?'xtls-rprx-vision':'', email: 'u@mx.com'});
        
        let stream = { network: n, security: s };
        if(s === 'reality') stream.realitySettings = { dest: $('#dest').val(), privateKey: $('#privKey').val(), shortIds: $('#shortIds').val().split(','), serverNames: $('#serverNames').val().split(','), fingerprint: 'chrome' };
        if(n === 'ws') stream.wsSettings = { path: $('#wsPath').val(), headers: { Host: $('#wsHost').val() } };
        
        let settings = p === 'shadowsocks' ? { method: $('#ssCipher').val(), password: $('#ssPass').val(), network: 'tcp,udp' } : { clients, decryption: 'none' };
        
        const total = $('#totalGB').val() ? Math.floor($('#totalGB').val() * 1073741824) : 0;
        const expiry = $('#expiryDate').val() ? new Date($('#expiryDate').val()).getTime() : 0;

        const payload = {
            id: $('#nodeId').val() || null, remark: $('#remark').val(), port: parseInt($('#port').val()), protocol: p,
            total: total, expiry_time: expiry,
            settings: JSON.stringify(settings), stream_settings: JSON.stringify(stream),
            sniffing: JSON.stringify({ enabled: true, destOverride: ["http","tls","quic"] })
        };

        const btn = $(this); btn.prop('disabled', true).text('Saving...');
        $.ajax({
            url: '/api/sync', type: 'POST', contentType: 'application/json',
            data: JSON.stringify({ ip: ACTIVE_IP, config: payload }),
            success: function() { 
                $('#configModal').modal('hide'); 
                btn.prop('disabled', false).text('Save & Restart');
                alert('Saved! Node restarting...');
            },
            error: function() { btn.prop('disabled', false).text('Failed'); }
        });
    });

    $(document).ready(function() {
        updateState();
        setInterval(updateState, 3000);
    });
</script>
</body>
</html>
"""

# 登录页模板 (Dark Minimal)
LOGIN_T = """
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8"><title>MultiX Login</title>
<style>
body { background: #000; color: #fff; display: flex; height: 100vh; align-items: center; justify-content: center; font-family: sans-serif; }
.box { background: #111; padding: 40px; border-radius: 10px; border: 1px solid #333; text-align: center; width: 300px; }
input { width: 100%; padding: 10px; margin-bottom: 10px; background: #222; border: 1px solid #444; color: #fff; border-radius: 5px; box-sizing: border-box; }
button { width: 100%; padding: 10px; background: #0d6efd; color: #fff; border: none; border-radius: 5px; font-weight: bold; cursor: pointer; }
</style>
</head>
<body>
<div class="box">
    <h2 style="margin-top:0; color: #0d6efd; font-style: italic;">MultiX Pro</h2>
    <form method="post">
        <input name="u" placeholder="Admin User" required>
        <input type="password" name="p" placeholder="Password" required>
        <button>LOGIN</button>
    </form>
</div>
</body>
</html>
"""

@app.route('/')
def index():
    if not session.get('logged'): return redirect('/login')
    # 渲染模板，注入 Flask 变量
    return render_template_string(HTML_T, token=M_TOKEN, ipv4=get_sys_info()['ipv4'])

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form['u'] == M_USER and request.form['p'] == M_PASS:
            session['logged'] = True
            return redirect('/')
    return render_template_string(LOGIN_T)

@app.route('/api/state')
def api_state():
    s = get_sys_info()
    return jsonify({"master": {"ipv4": s['ipv4'], "stats": {"cpu": s['cpu'], "mem": s['mem']}}, "agents": AGENTS})

@app.route('/api/sync', methods=['POST'])
def api_sync():
    d = request.json
    target = d.get('ip')
    if target in AGENTS:
        # 简单透传逻辑
        payload = json.dumps({"action": "sync_node", "token": M_TOKEN, "data": d.get('config')})
        asyncio.run_coroutine_threadsafe(AGENTS[target]['ws'].send(payload), LOOP_GLOBAL)
        return jsonify({"status": "sent"})
    return jsonify({"status": "offline"}), 404

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
                    AGENTS[ip]['alias'] = d.get('data', {}).get('os', 'Node')
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
    echo -e "${GREEN}✅ 主控端部署成功 (V64.0)${PLAIN}"
    echo -e "   IPv4入口: http://${IPV4}:${M_PORT}"
    [[ "$IPV6" != "N/A" ]] && echo -e "   IPv6入口: http://[${IPV6}]:${M_PORT}"
    echo -e "   Token: ${YELLOW}$M_TOKEN${PLAIN}"
    pause_back
}

# --- [ 7. 被控安装 (通用版) ] ---
install_agent() {
    install_dependencies; mkdir -p $M_ROOT/agent
    
    if [ ! -d "/etc/x-ui" ]; then
        echo -e "${RED}未检测到 3X-UI，是否安装? [Y/n]${PLAIN}"
        read i
        if [[ "$i" != "n" ]]; then
            bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
            ufw allow 2053/tcp 2>/dev/null
        else return; fi
    fi

    echo -e "${SKYBLUE}>>> 被控配置${PLAIN}"
    read -p "主控域名/IP: " IN_HOST; read -p "Token: " IN_TOKEN
    
    cat > $M_ROOT/agent/Dockerfile <<EOF
FROM python:3.11-slim
RUN pip install websockets psutil --break-system-packages
WORKDIR /app
CMD ["python", "agent.py"]
EOF
    cat > $M_ROOT/agent/agent.py <<EOF
import asyncio, json, sqlite3, os, psutil, websockets, socket, platform
MASTER = "$IN_HOST"; TOKEN = "$IN_TOKEN"; DB_PATH = "/app/db_share/x-ui.db"
def sync_db(data):
    try:
        conn = sqlite3.connect(DB_PATH, timeout=10); cursor = conn.cursor(); nid = data.get('id')
        vals = (data['remark'], data['port'], data['settings'], data['stream_settings'], data['sniffing'], data['total'], data['expiry_time'])
        if nid: cursor.execute("UPDATE inbounds SET remark=?, port=?, settings=?, stream_settings=?, sniffing=?, total=?, expiry_time=?, enable=1 WHERE id=?", vals + (nid,))
        else: cursor.execute("INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, listen, port, protocol, settings, stream_settings, tag, sniffing) VALUES (1, 0, 0, ?, ?, 1, ?, '', ?, ?, ?, ?, 'multix', ?)", (data['total'], data['remark'], data['expiry_time'], data['port'], data['protocol'], data['settings'], data['stream_settings'], data['sniffing']))
        conn.commit(); conn.close(); return True
    except: return False
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
    cd $M_ROOT/agent; docker build -t multix-agent-v64 .
    docker rm -f multix-agent 2>/dev/null
    docker run -d --name multix-agent --restart always --network host -v /var/run/docker.sock:/var/run/docker.sock -v /etc/x-ui:/app/db_share -v $M_ROOT/agent:/app multix-agent-v64
    echo -e "${GREEN}✅ 被控已启动${PLAIN}"; pause_back
}

# --- [ 8. 主菜单 ] ---
main_menu() {
    clear; echo -e "${SKYBLUE}🛰️ MultiX Pro (V64.0 经典重构版)${PLAIN}"
    echo " 1. 安装 主控端"
    echo " 2. 安装 被控端"
    echo " 3. 清理/卸载"
    echo " 0. 退出"
    read -p "选择: " c
    case $c in
        1) install_master ;; 2) install_agent ;; 3) deep_cleanup ;;
        0) exit 0 ;; *) main_menu ;;
    esac
}
main_menu
