/**
 * Multiy Pro 旗舰版核心逻辑控制中心 - 深度增强全功能版
 */
function multix() {
    return {
        // --- [ 1. 基础响应式状态 ] ---
        lang: localStorage.getItem('m_lang') || 'zh',
        isLoggedIn: false,
        isRefreshing: false,
        showToken: false,
        showIP: false, // 控制主控 IP 显示状态
        searchQuery: '',
        
        // --- [ 国际化语言包 ] ---
        i18n: {
            zh: { 
                login: "登录", logout: "注销", guest: "访客身份", identity: "身份状态", 
                control: "管理中心", nodes: "集群节点", sys: "主控状态", 
                search: "搜索节点名称、IP或别名...", total: "总计", online: "在线",
                unlock: "解除管理限制", back: "返回访客模式", virtual: "演示节点",
                restarting: "系统正在重启，请稍后刷新页面...", sync_ok: "同步成功！请使用新凭据重新登录。"
            },
            en: { 
                login: "Login", logout: "Logout", guest: "Guest Mode", identity: "Identity", 
                control: "Control Center", nodes: "Cluster Nodes", sys: "Master Status", 
                search: "Search by Name, IP or Alias...", total: "Total", online: "Online",
                unlock: "Unlock Console", back: "Back to Guest", virtual: "Demo Node",
                restarting: "System restarting, please refresh later...", sync_ok: "Success! Please login with new credentials."
            }
        },
        t(key) { return this.i18n[this.lang][key] || key; },
        switchLang() { 
            this.lang = this.lang === 'zh' ? 'en' : 'zh'; 
            localStorage.setItem('m_lang', this.lang); 
        },

        // --- [ 2. 数据容器 ] ---
        master: { cpu: 0, mem: 0, disk: 0, sys_ver: '加载中...', sb_ver: 'N/A' },
        agents: {},
        config: { user: 'GUEST', token: '', ip4: '', port: 7575, ws_port: 9339 },
        
        // --- [ 3. 弹窗控制变量 ] ---
        showLoginModal: false,
        adminModal: false,
        nodeModal: false,
        subModal: false,
        globalExportModal: false,
        
        // --- [ 4. 表单与交互临时变量 ] ---
        loginForm: { user: '', pass: '' },
        tempUser: '', tempPass: '', tempToken: '', 
        tempPort: 7575, tempWsPort: 9339, // 端口修改临时变量
        editingSid: null, tempAlias: '', 
        subType: 'v2ray', 
        globalLinks: '',
        
        // --- [ 5. 节点详情变量 ] ---
        currentNode: null,
        currentNodeInbounds: [],
        editingInbound: null,

        // --- [ 6. 初始化核心 ] ---
        async init() {
            console.log("Multiy Engine Initializing...");
            const savedToken = localStorage.getItem('m_token');
            if (savedToken) this.isLoggedIn = true;
            
            await this.fetchState();
            setInterval(() => this.fetchState(), 5000); 
        },

        // --- [ 7. 核心数据同步 ] ---
        async fetchState() {
            try {
                const res = await fetch(`/api/state?v=${Date.now()}`);
                if (!res.ok) throw new Error("Backend Offline");
                const data = await res.json();
                
                this.master = data.master || this.master;
                this.agents = data.agents || {};
                this.config = data.config || this.config;
                
                // 仅在首次登录成功后初始化管理表单
                if (this.isLoggedIn && !this.tempUser) {
                    this.initAdminForm();
                }
            } catch (e) { 
                console.error("同步失败:", e); 
            } finally { 
                this.isRefreshing = false; 
            }
        },

        // 填充管理表单初始值
        initAdminForm() {
            this.tempUser = this.config.user;
            this.tempToken = this.config.token;
            this.tempPort = this.config.port;
            this.tempWsPort = this.config.ws_port;
            this.tempPass = ""; // 密码安全考虑不回显
        },

        // --- [ 8. 核心：修改管理员凭据与端口并触发重启 ] ---
        async confirmUpdateAdmin() {
            const msg = this.lang === 'zh' ? "确认同步新配置？系统将物理重启服务。" : "Sync new config? System will restart service.";
            if(!confirm(msg)) return;
            
            const payload = {
                user: this.tempUser,
                pass: this.tempPass || this.ADMIN_PASS, // 如果没填则后端保持不变
                token: this.tempToken,
                port: this.tempPort,
                ws_port: this.tempWsPort
            };

            try {
                const res = await fetch('/api/update_admin', {
                    method: 'POST',
                    headers: { 
                        'Content-Type': 'application/json',
                        'Authorization': localStorage.getItem('m_token') 
                    },
                    body: JSON.stringify(payload)
                });
                
                const data = await res.json();
                if (res.ok && data.res === "ok") {
                    alert(this.t('sync_ok'));
                    localStorage.removeItem('m_token');
                    // 如果修改了 Web 端口，重定向到新地址
                    const newUrl = `${window.location.protocol}//${window.location.hostname}:${payload.port}`;
                    window.location.href = newUrl;
                } else {
                    alert("Error: " + (data.msg || "Update failed"));
                }
            } catch (e) {
                // 重启过程中 fetch 会失败，属于正常现象
                alert(this.t('restarting'));
                setTimeout(() => window.location.reload(), 3000);
            }
        },

        // --- [ 9. 节点管理逻辑 ] ---
        get sortedAgents() {
            return Object.fromEntries(
                Object.entries(this.agents).sort(([, a], [, b]) => (a.order || 999) - (b.order || 999))
            );
        },

        get filteredAgents() {
            let list = Object.entries(this.agents);
            if (list.length === 0) {
                return {
                    "virtual-001": {
                        hostname: "PRO-NODE-DEMO",
                        alias: this.t('virtual'),
                        is_demo: true, 
                        order: 1,
                        status: "online",
                        metrics: { cpu: 12, mem: 24, load: "0.15", net_out: "0B/s", net_in: "0B/s", latency: "28" }
                    }
                };
            }
            const q = this.searchQuery.toLowerCase();
            let filtered = list.filter(([sid, a]) => {
                const matchSearch = (a.alias && a.alias.toLowerCase().includes(q)) || 
                                    a.hostname.toLowerCase().includes(q) || 
                                    sid.includes(q);
                return matchSearch && !a.hidden;
            });
            return Object.fromEntries(filtered.sort(([, a], [, b]) => (a.order || 999) - (b.order || 999)));
        },

        async manageAgent(sid, action, value = null) {
            try {
                const res = await fetch('/api/manage_agent', {
                    method: 'POST',
                    headers: { 
                        'Content-Type': 'application/json', 
                        'Authorization': localStorage.getItem('m_token') || '' 
                    },
                    body: JSON.stringify({ sid, action, value })
                });
                if (res.ok) await this.fetchState();
            } catch (e) { alert("Operation Failed"); }
        },

        // --- [ 10. 认证管理与登录流程 ] ---
        async login() {
            if (!this.loginForm.user || !this.loginForm.pass) return;
            try {
                const res = await fetch('/api/login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(this.loginForm)
                });
                const data = await res.json();
                if (res.ok && data.status === "success") {
                    localStorage.setItem('m_token', data.token);
                    this.isLoggedIn = true;
                    this.showLoginModal = false;
                    await this.fetchState();
                    window.location.reload(); 
                } else { alert(this.t('login') + " Failed"); }
            } catch (e) { alert("Server Connection Error"); }
        },

        logout() {
            if (confirm(this.t('logout') + "?")) {
                localStorage.removeItem('m_token');
                window.location.reload();
            }
        },

        // 辅助功能：复制与二维码
        copyToClipboard(text) {
            navigator.clipboard.writeText(text).then(() => alert(this.lang === 'zh' ? "已复制到剪贴板" : "Copied"));
        },
        
        generateSubLink() {
            return `http://${window.location.host}/sub?token=${this.config.token}&type=${this.subType}`;
        }
    }
}
