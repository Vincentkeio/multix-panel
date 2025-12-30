/**
 * HubX Panel Ver 1.0 (Build 202512) 核心控制引擎
 * 功能：响应式状态管理、双栈监控、动态 i18n、配置同步自愈
 */

function multix() {
    return {
        // --- [ 1. 响应式基础状态 ] ---
        lang: localStorage.getItem('m_lang') || 'zh',
        isLoggedIn: false,
        isRefreshing: false,
        showToken: false,
        showIP: false,
        searchQuery: '',
        
        // --- [ 2. 国际化语言包 (i18n) ] ---
        // HubX Panel 品牌名在各语种中保持一致
        i18n: {
            zh: { 
                login: "登录", logout: "注销", guest: "访客身份", identity: "当前身份", 
                control: "管理中心", node_manage: "节点管理列表", sys: "主控机状态", 
                search: "搜索节点名称、IP或别名...", total: "总计", online: "在线",
                unlock: "解除管理限制", back: "返回访客模式", virtual: "演示节点",
                restarting: "系统正在重启，请稍后刷新页面...", sync_ok: "同步成功！请使用新凭据重新登录。",
                export_success: "节点配置备份已生成并开始下载。",
                copy_ok: "已复制到剪贴板"
            },
            en: { 
                login: "Login", logout: "Logout", guest: "Guest Mode", identity: "Identity Status", 
                control: "Control Center", node_manage: "Node Management", sys: "Master Status", 
                search: "Search by Name, IP or Alias...", total: "Total", online: "Online",
                unlock: "Unlock Console", back: "Back to Guest", virtual: "Demo Node",
                restarting: "System restarting, please refresh later...", sync_ok: "Success! Please login with new credentials.",
                export_success: "Node backup generated and downloading.",
                copy_ok: "Copied to clipboard"
            }
        },
        t(key) { return this.i18n[this.lang][key] || key; },
        switchLang() { 
            this.lang = this.lang === 'zh' ? 'en' : 'zh'; 
            localStorage.setItem('m_lang', this.lang); 
        },

        // --- [ 3. 核心数据容器 ] ---
        master: { cpu: 0, mem: 0, disk: 0, sys_ver: 'Loading...', sb_ver: 'N/A' },
        agents: {},
        config: { user: 'GUEST', token: '', host: '', port: 7575, ws_port: 9339 },
        
        // --- [ 4. 弹窗控制变量 ] ---
        showLoginModal: false,
        adminModal: false,
        showSettings: false, // 安全凭据弹窗控制
        nodeModal: false,
        subModal: false,
        
        // --- [ 5. 交互临时变量 ] ---
        loginForm: { user: '', pass: '' },
        tempUser: '', tempPass: '', tempToken: '', tempHost: '',
        tempPort: 7575, tempWsPort: 9339,
        editingSid: null, tempAlias: '', 
        subType: 'v2ray', 
        
        // --- [ 6. 生命周期钩子 ] ---
        async init() {
            const savedToken = localStorage.getItem('m_token');
            if (savedToken) {
                this.isLoggedIn = true;
                this.token = savedToken;
            }
            await this.fetchState();
            // 每5秒拉取一次最新硬件指标
            setInterval(() => this.fetchState(), 5000); 
        },

        // --- [ 7. 异步数据同步中心 ] ---
        async fetchState() {
            try {
                const res = await fetch(`/api/state?v=${Date.now()}`);
                if (!res.ok) throw new Error("Offline");
                const data = await res.json();
                
                this.master = data.master || this.master;
                this.agents = data.agents || {};
                this.config = data.config || this.config;
                
                // 仅在首次拉取成功后初始化安全设置表单
                if (this.isLoggedIn && !this.tempUser) {
                    this.initAdminForm();
                }
            } catch (e) { 
                console.error("HubX Sync Error:", e); 
            } finally { 
                this.isRefreshing = false; 
            }
        },

        initAdminForm() {
            this.tempUser = this.config.user;
            this.tempToken = this.config.token;
            this.tempHost = this.config.ip4; // 对应后端 M_HOST
            this.tempPort = this.config.port;
            this.tempWsPort = this.config.ws_port;
            this.tempPass = ""; 
        },

        // --- [ 8. 物理配置同步逻辑 (安全凭据修改) ] ---
        async confirmUpdateAdmin() {
            const msg = this.lang === 'zh' 
                ? "确认同步新配置？HubX Panel 将物理重启服务，主面板将即时同步新域名与端口。" 
                : "Sync new config? HubX Panel will restart and update domain/port immediately.";
            
            if(!confirm(msg)) return;

            const payload = {
                user: this.tempUser,
                pass: this.tempPass || "", 
                token: this.tempToken,
                host: this.tempHost,
                port: parseInt(this.tempPort) || 7575,
                ws_port: parseInt(this.tempWsPort) || 9339
            };

            try {
                const res = await fetch('/api/update_admin', {
                    method: 'POST',
                    headers: { 
                        'Content-Type': 'application/json',
                        'Authorization': this.token 
                    },
                    body: JSON.stringify(payload)
                });
                
                if (res.ok) {
                    alert(this.t('restarting'));
                    localStorage.removeItem('m_token');
                    // 动态计算重定向：如果修改了域名或端口，自动跳转
                    const protocol = window.location.protocol;
                    const host = payload.host.includes(':') ? `[${payload.host}]` : payload.host;
                    const newUrl = `${protocol}//${host}:${payload.port}`;
                    
                    setTimeout(() => { window.location.href = newUrl; }, 1500);
                }
            } catch (e) {
                alert(this.t('restarting'));
                setTimeout(() => { window.location.reload(); }, 5000);
            }
        },

        // --- [ 9. 超级导出：节点备份逻辑 ] ---
        exportGlobalNodes() {
            const backup = {
                brand: "HubX Panel",
                version: "1.0",
                timestamp: new Date().toISOString(),
                agents: this.agents
            };
            const dataStr = "data:text/json;charset=utf-8," + encodeURIComponent(JSON.stringify(backup, null, 4));
            const dlAnchorElem = document.createElement('a');
            dlAnchorElem.setAttribute("href", dataStr);
            dlAnchorElem.setAttribute("download", `HubX_Backup_${new Date().getTime()}.json`);
            dlAnchorElem.click();
            alert(this.t('export_success'));
        },

        // --- [ 10. 节点搜索与排序逻辑 ] ---
        get sortedAgents() {
            return Object.fromEntries(
                Object.entries(this.agents).sort(([, a], [, b]) => (a.order || 999) - (b.order || 999))
            );
        },

        get filteredAgents() {
            let list = Object.entries(this.agents);
            const q = this.searchQuery.toLowerCase();
            let filtered = list.filter(([sid, a]) => {
                const searchStr = `${sid} ${a.alias || ''} ${a.hostname}`.toLowerCase();
                return searchStr.includes(q) && !a.hidden;
            });
            return Object.fromEntries(filtered.sort(([, a], [, b]) => (a.order || 999) - (b.order || 999)));
        },

        async manageAgent(sid, action, value = null) {
            try {
                const res = await fetch('/api/manage_agent', {
                    method: 'POST',
                    headers: { 
                        'Content-Type': 'application/json', 
                        'Authorization': this.token 
                    },
                    body: JSON.stringify({ sid, action, value })
                });
                if (res.ok) await this.fetchState();
            } catch (e) { console.error("Agent Management Failed"); }
        },

        // --- [ 11. 鉴权与辅助工具 ] ---
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
                    window.location.reload(); 
                } else { alert("Login Failed"); }
            } catch (e) { alert("Connect Error"); }
        },

        logout() {
            if (confirm(this.t('logout') + "?")) {
                localStorage.removeItem('m_token');
                window.location.reload();
            }
        },

        copyToClipboard(text) {
            navigator.clipboard.writeText(text).then(() => alert(this.t('copy_ok')));
        },
        
        generateSubLink() {
            return `${window.location.origin}/sub?token=${this.config.token}&type=${this.subType}`;
        }
    }
}
