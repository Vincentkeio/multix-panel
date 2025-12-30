/**
 * MULTIX PRO - 核心前端逻辑 V156.0
 * 重点修复：隐藏逻辑、3X-UI 风格参数映射、别名编辑防抖
 */
function multix() {
    return {
        // --- [ 1. 状态变量 ] ---
        agents: {}, 
        master: {}, 
        config: { user: 'GUEST', token: '', ip4: '', ip6: '' }, 
        
        // 界面控制
        adminModal: false, 
        nodeModal: false, 
        isRefreshing: false,
        isLoggedIn: false, 
        showLoginModal: false,
        
        // 交互与临时变量
        editingSid: null,
        tempAlias: '',
        tempUser: '', 
        tempPass: '', 
        tempToken: '', 
        loginUser: '', 
        loginPass: '',

        // 节点配置专用：映射 3X-UI 风格参数框
        currentNode: null,
        editingInbound: {
            type: 'vless',
            tag: '',
            listen_port: 443,
            uuid: '',
            reality_priv: '',
            reality_dest: 'yahoo.com:443',
            short_id: '6f',
            email: ''
        },

        // --- [ 2. 初始化 ] ---
        async init() {
            if (localStorage.getItem('multiy_token')) {
                this.isLoggedIn = true;
            }
            await this.fetchState();
            // 3秒自动刷新，确保隐藏状态和负载实时对齐
            setInterval(() => this.fetchState(), 3000); 
        },

        // --- [ 3. 数据同步 ] ---
        async fetchState() {
            try {
                const r = await fetch('/api/state');
                if (!r.ok) throw new Error("API Offline");
                const d = await r.json();
                
                this.agents = d.agents || {};
                this.master = d.master || {};
                this.config = d.config || { user: 'ADMIN', token: '' };
                
                // 同步更新弹窗背景数据，防止编辑时卡片信息丢失
                if (this.nodeModal && this.currentNode) {
                    const latest = this.agents[this.currentNode.sid];
                    if (latest) this.currentNode = latest;
                }
            } catch(e) { 
                console.error("Data Sync Error:", e); 
            } finally { 
                this.isRefreshing = false; 
            }
        },

        // --- [ 4. 登录验证 ] ---
        async doLogin() {
            if (!this.loginUser || !this.loginPass) return alert("请输入凭据");
            try {
                const res = await fetch('/api/login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ user: this.loginUser, pass: this.loginPass })
                });
                const data = await res.json();
                if (res.ok && data.status === 'success') {
                    this.isLoggedIn = true;
                    localStorage.setItem('multiy_token', data.token);
                    this.showLoginModal = false;
                    await this.fetchState();
                } else {
                    alert("登录失败: " + (data.msg || "凭据错误"));
                }
            } catch (err) {
                alert("连接主控失败");
            }
        },

        // --- [ 5. 节点管理：3X-UI 逻辑驱动 ] ---
        
        // 打开配置弹窗并初始化默认 VLESS 参数
        openNodeModal(agent) {
            if (!this.isLoggedIn) return; 
            this.currentNode = agent;
            
            // 初始化 3X-UI 风格默认值
            this.editingInbound = {
                type: 'vless',
                tag: 'VLESS_Reality_' + agent.sid.substring(0, 4),
                listen_port: 443,
                uuid: crypto.randomUUID(),
                reality_priv: '', // 留空等待手动填入或后端同步
                reality_dest: 'yahoo.com:443',
                short_id: Math.random().toString(16).substring(2, 10),
                email: (this.config.user || 'admin') + '@' + agent.hostname.split('.')[0]
            };
            this.nodeModal = true;
        },

        // 推送参数框配置至 Agent
        async syncConfigToAgent() {
            if (!this.currentNode) return;
            const token = localStorage.getItem('multiy_token');
            
            // 将参数框扁平化数据构造为 Sing-box 标准结构
            const inboundConfig = [{
                type: this.editingInbound.type,
                tag: this.editingInbound.tag,
                listen: "::",
                listen_port: parseInt(this.editingInbound.listen_port),
                sniff: true,
                sniff_override_destination: true,
                users: [{
                    uuid: this.editingInbound.uuid,
                    flow: "xtls-rprx-vision"
                }],
                tls: {
                    enabled: true,
                    server_name: this.editingInbound.reality_dest.split(':')[0],
                    reality: {
                        enabled: true,
                        handshake: {
                            server: this.editingInbound.reality_dest.split(':')[0],
                            server_port: 443
                        },
                        private_key: this.editingInbound.reality_priv,
                        short_id: [this.editingInbound.short_id]
                    }
                }
            }];

            try {
                const res = await fetch('/api/update_node_config', {
                    method: 'POST',
                    headers: { 
                        'Content-Type': 'application/json',
                        'Authorization': token 
                    },
                    body: JSON.stringify({
                        sid: this.currentNode.sid,
                        inbounds: inboundConfig
                    })
                });
                const data = await res.json();
                if (data.res === 'ok') {
                    alert("✅ 配置已同步，Agent 正在应用...");
                    this.nodeModal = false;
                    await this.fetchState();
                } else {
                    alert("❌ 下发失败: " + data.msg);
                }
            } catch (e) {
                alert("网络通讯错误");
            }
        },

        // --- [ 6. 小鸡全局控制：修复隐藏与别名 ] ---
        async manageAgent(sid, action, value = null) {
            const token = localStorage.getItem('multiy_token');
            
            // 序号修改立即响应
            if (action === 'reorder') this.agents[sid].order = parseInt(value);

            try {
                const res = await fetch('/api/manage_agent', {
                    method: 'POST',
                    headers: { 
                        'Content-Type': 'application/json', 
                        'Authorization': token 
                    },
                    body: JSON.stringify({ sid, action, value })
                });

                if (res.ok) {
                    if (action === 'delete') delete this.agents[sid];
                    // 关键：操作完成后强制拉取最新状态，确保隐藏/显示同步
                    await this.fetchState(); 
                }
            } catch (e) { console.error("Action Failed:", e); }
        },

        // 别名编辑：使用 tempAlias 隔离，防止输入时卡片闪烁
        startEditAlias(sid, currentAlias) {
            this.editingSid = sid;
            this.tempAlias = currentAlias || '';
        },

        async saveAlias(sid) {
            await this.manageAgent(sid, 'alias', this.tempAlias);
            this.editingSid = null;
        },

        // --- [ 7. 辅助功能 ] ---
        get sortedAgents() {
            return Object.fromEntries(
                Object.entries(this.agents).sort(([,a], [,b]) => {
                    if ((a.order || 0) !== (b.order || 0)) return (a.order || 0) - (b.order || 0);
                    return a.status === 'online' ? -1 : 1;
                })
            );
        },

        copyToClipboard(text) {
            if (!text) return;
            navigator.clipboard.writeText(text).then(() => alert("已复制到剪贴板"));
        },

        logout() { 
            localStorage.removeItem('multiy_token'); 
            window.location.reload(); 
        }
    }
}
