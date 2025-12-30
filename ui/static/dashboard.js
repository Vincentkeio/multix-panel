function multix() {
    return {
        agents: {}, master: {}, config: { user: 'GUEST', token: '' },
        drawer: false, adminModal: false, isRefreshing: false, isLoggedIn: false, showLoginModal: false,
        curSid: '', curNode: {}, editingSid: null, tempUser: '', tempPass: '', tempToken: '', tempAlias: '', loginUser: '', loginPass: '',

        async init() {
            if (localStorage.getItem('multiy_token')) this.isLoggedIn = true;
            await this.fetchState();
            setInterval(() => this.fetchState(), 3000);
        },

        async fetchState() {
            try {
                const r = await fetch('/api/state');
                const d = await r.json();
                this.agents = d.agents || {};
                this.master = d.master || {};
                this.config = d.config || { user: 'ADMIN', token: '' };
                if (this.drawer && this.curSid) this.curNode = this.agents[this.curSid];
            } catch(e) { console.error(e); } finally { this.isRefreshing = false; }
        },

        async doLogin() {
            const res = await fetch('/api/login', {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ user: this.loginUser, pass: this.loginPass })
            });
            const data = await res.json();
            if (res.ok && data.status === 'success') {
                this.isLoggedIn = true;
                localStorage.setItem('multiy_token', data.token);
                this.showLoginModal = false;
                await this.fetchState();
            } else { alert("登录失败"); }
        },

        // 小鸡管理核心逻辑
        async manageAgent(sid, action, value = null) {
            const token = localStorage.getItem('multiy_token');
            
            // 前端立即响应：删除或隐藏
            if (action === 'delete' || action === 'hide') {
                const confirmMsg = action === 'delete' ? '已执行物理删除，小鸡将彻底断连。' : '小鸡已在主界面隐藏。';
                
                // 发送后端指令
                const res = await fetch('/api/manage_agent', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json', 'Authorization': token },
                    body: JSON.stringify({ sid, action, value })
                });

                if (res.ok) {
                    delete this.agents[sid]; // 立即从前端内存中移除，面板随之刷新
                    alert(confirmMsg);
                }
                return;
            }

            // 排序逻辑
            if (action === 'reorder') {
                await fetch('/api/manage_agent', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json', 'Authorization': token },
                    body: JSON.stringify({ sid, action: 'reorder', value })
                });
            }
        },

        async confirmUpdateAdmin() {
            const token = localStorage.getItem('multiy_token');
            const res = await fetch('/api/update_admin', {
                method: 'POST', 
                headers: { 'Content-Type': 'application/json', 'Authorization': token },
                body: JSON.stringify({ user: this.tempUser, pass: this.tempPass, token: this.tempToken })
            });
            if (res.ok) {
                alert("凭据已同步，请重新登录");
                this.logout();
            }
        },

        copyToClipboard(text) {
            if (!navigator.clipboard || !window.isSecureContext) {
                const textArea = document.createElement("textarea");
                textArea.value = text; document.body.appendChild(textArea);
                textArea.select(); document.execCommand('copy'); document.body.removeChild(textArea);
                alert("Token已复制(兼容模式)");
            } else {
                navigator.clipboard.writeText(text).then(() => alert("Token已复制"));
            }
        },

        logout() { localStorage.removeItem('multiy_token'); window.location.reload(); },

        get sortedAgents() {
            return Object.fromEntries(Object.entries(this.agents).sort(([,a], [,b]) => (a.order || 0) - (b.order || 0)));
        },

        async saveAlias(sid) {
            await this.manageAgent(sid, 'alias', this.tempAlias);
            this.editingSid = null;
            await this.fetchState();
        }
    }
}
