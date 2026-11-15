/*
 * ============================================================================
 * WebPages.h &mdash; Complete Web Dashboard in PROGMEM
 * ============================================================================
 * 
 * Single-page application with:
 *   - Dark/Light mode toggle
 *   - Glassmorphism cards
 *   - WebSocket live updates
 *   - Responsive grid layout
 *   - Material-style inline SVG icons
 *   - Toast notifications
 *   - Mobile-first design
 * 
 * Stored as raw string literal in PROGMEM to save RAM.
 * ============================================================================
 */

#ifndef WEB_PAGES_H
#define WEB_PAGES_H

#include <Arduino.h>

// ============================================================================
// Main Dashboard Page
// ============================================================================
static const char PAGE_INDEX[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<meta name="description" content="SmartHome Controller Dashboard">
<title>SmartHome Dashboard</title>
<style>
:root{
--bg:#080b11;
--bg-mesh:radial-gradient(at 0% 0%,rgba(99,102,241,0.14) 0px,transparent 50%),radial-gradient(at 100% 0%,rgba(59,130,246,0.10) 0px,transparent 50%),radial-gradient(at 50% 100%,rgba(15,23,42,0.85) 0px,transparent 65%);
--surface:rgba(17,24,39,0.72);
--surface-hover:rgba(26,36,56,0.85);
--surface-card:rgba(15,23,42,0.65);
--border:rgba(255,255,255,0.08);
--border-hover:rgba(99,102,241,0.35);
--card-border:rgba(255,255,255,0.08);
--card-glow:0 12px 36px -4px rgba(0,0,0,0.55),inset 0 1px 0 0 rgba(255,255,255,0.08);
--text:#f8fafc;
--text2:#94a3b8;
--text-muted:#64748b;
--accent:#6366f1;
--accent2:#818cf8;
--accent-grad:linear-gradient(135deg,#6366f1 0%,#3b82f6 100%);
--green:#10b981;
--green-grad:linear-gradient(135deg,#10b981 0%,#059669 100%);
--red:#f43f5e;
--red-grad:linear-gradient(135deg,#f43f5e 0%,#dc2626 100%);
--orange:#f59e0b;
--blue:#3b82f6;
--radius:16px;
--radius-sm:10px;
--radius-xs:6px;
--shadow:0 10px 30px -5px rgba(0,0,0,0.5);
--glass:rgba(17,24,39,0.72);
--glass-border:rgba(255,255,255,0.08);
}
.light{
--bg:#f8fafc;
--bg-mesh:radial-gradient(at 0% 0%,rgba(99,102,241,0.06) 0px,transparent 50%),radial-gradient(at 100% 0%,rgba(59,130,246,0.04) 0px,transparent 50%);
--surface:rgba(255,255,255,0.88);
--surface-hover:#ffffff;
--surface-card:#ffffff;
--border:rgba(226,232,240,0.9);
--border-hover:rgba(99,102,241,0.5);
--card-border:rgba(226,232,240,0.9);
--card-glow:0 10px 30px -5px rgba(0,0,0,0.06),inset 0 1px 0 0 #ffffff;
--text:#0f172a;
--text2:#475569;
--text-muted:#94a3b8;
--shadow:0 10px 30px -5px rgba(0,0,0,0.08);
--glass:rgba(255,255,255,0.88);
--glass-border:rgba(0,0,0,0.06);
}
.light .ver{background:rgba(15,23,42,0.05);color:var(--text2);}
.light .badge-guest{color:#a16207!important;}
.light .theme-btn,.light .btn-outline{background:rgba(15,23,42,0.04);}
.light .theme-btn:hover,.light .btn-outline:hover{color:var(--accent);background:rgba(99,102,241,0.1);}
.light .card:hover{box-shadow:0 16px 36px -8px rgba(15,23,42,0.12),inset 0 1px 0 0 #ffffff;}
.light .gauge,.light .relay-card,.light .log-list{background:#f1f5f9;box-shadow:inset 0 1px 2px rgba(15,23,42,0.06);}
.light .gauge-value{color:var(--text);}
.light .gas-bar-wrap{background:#e2e8f0;box-shadow:inset 0 1px 2px rgba(15,23,42,0.1);}
.light .toggle{background:#cbd5e1;}
.light .tab:hover:not(.active){background:rgba(15,23,42,0.05);}
.light input[type=range]{background:rgba(15,23,42,0.12);}
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display','Inter','Segoe UI',Roboto,sans-serif;background:var(--bg);background-image:var(--bg-mesh);background-attachment:fixed;color:var(--text);min-height:100vh;transition:background .3s,color .3s;-webkit-font-smoothing:antialiased;}
.container{max-width:1420px;margin:0 auto;padding:22px 26px;}

/* Header */
.header{display:flex;align-items:center;justify-content:space-between;padding:16px 22px;background:var(--surface);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);border:1px solid var(--border);border-radius:var(--radius);margin-bottom:20px;box-shadow:var(--card-glow);}
.header h1{font-size:1.25rem;font-weight:700;display:flex;align-items:center;gap:12px;letter-spacing:-0.02em;}
.header-logo{width:36px;height:36px;border-radius:10px;background:var(--accent-grad);display:flex;align-items:center;justify-content:center;box-shadow:0 4px 14px rgba(99,102,241,0.4);flex-shrink:0;}
.header-logo svg{width:20px;height:20px;fill:#ffffff;}
.header-actions{display:flex;gap:10px;align-items:center;}
.ver{font-size:.72rem;font-weight:600;padding:3px 8px;border-radius:20px;background:rgba(255,255,255,0.06);border:1px solid var(--border);color:var(--text2);margin-left:4px;}
.badge-guest{background:rgba(234,179,8,0.15)!important;color:#facc15!important;border:1px solid rgba(234,179,8,0.35)!important;font-size:0.72rem!important;font-weight:600!important;padding:3px 10px!important;}

/* Icon buttons (Theme, OTA) */
.theme-btn{background:rgba(255,255,255,0.04);border:1px solid var(--border);border-radius:50%;width:38px;height:38px;cursor:pointer;display:flex;align-items:center;justify-content:center;transition:all .2s;color:var(--text2);}
.theme-btn:hover{border-color:var(--accent);color:#fff;background:rgba(99,102,241,0.12);transform:scale(1.08);}
.theme-btn svg{width:18px;height:18px;fill:currentColor;}

/* Cards & Grid */
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(350px,1fr));gap:20px;margin-bottom:20px;}
.card{background:var(--surface);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);border:1px solid var(--card-border);border-radius:var(--radius);padding:22px 24px;box-shadow:var(--card-glow);transition:transform .2s ease,border-color .2s ease,box-shadow .2s ease;position:relative;}
.card:hover{transform:translateY(-2px);border-color:var(--border-hover);box-shadow:0 16px 40px -8px rgba(0,0,0,0.6),inset 0 1px 0 0 rgba(255,255,255,0.1);}
.card-title{font-size:.82rem;font-weight:700;text-transform:uppercase;letter-spacing:0.08em;color:var(--text2);margin-bottom:16px;padding-bottom:10px;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:8px;}
.card-title svg{width:17px;height:17px;fill:var(--accent2);}

/* Badges */
.badge{display:inline-flex;align-items:center;gap:5px;padding:4px 10px;border-radius:20px;font-size:.72rem;font-weight:600;letter-spacing:0.02em;}
.badge-ok{background:rgba(16,185,129,0.15);color:var(--green);border:1px solid rgba(16,185,129,0.3);}
.badge-err{background:rgba(244,63,94,0.15);color:var(--red);border:1px solid rgba(244,63,94,0.3);}
.badge-warn{background:rgba(245,158,11,0.15);color:var(--orange);border:1px solid rgba(245,158,11,0.3);}
.badge-info{background:rgba(99,102,241,0.15);color:var(--accent2);border:1px solid rgba(99,102,241,0.3);}
.pulse{animation:pulse 2s infinite;}
@keyframes pulse{0%,100%{opacity:1;}50%{opacity:.4;}}

/* Status rows */
.status-row{display:flex;justify-content:space-between;align-items:center;padding:9px 0;border-bottom:1px solid var(--border);}
.status-row:last-child{border-bottom:none;}
.status-label{color:var(--text2);font-size:.82rem;}
.status-value{font-weight:600;font-size:.86rem;letter-spacing:0.01em;}

/* Sensor gauges */
.gauge-row{display:flex;gap:16px;margin-bottom:10px;}
.gauge{flex:1;text-align:center;padding:16px 12px;background:rgba(11,15,25,0.55);border-radius:var(--radius-sm);border:1px solid var(--border);box-shadow:inset 0 1px 2px rgba(0,0,0,0.25);}
.gauge-value{font-size:2rem;font-weight:700;line-height:1.2;color:#fff;}
.gauge-label{font-size:.72rem;color:var(--text2);margin-top:6px;text-transform:uppercase;letter-spacing:1px;font-weight:600;}
.gauge-unit{font-size:.9rem;font-weight:500;color:var(--text2);margin-left:2px;}

/* Gas bar */
.gas-bar-wrap{background:rgba(11,15,25,0.6);border-radius:10px;height:24px;overflow:hidden;position:relative;border:1px solid var(--border);box-shadow:inset 0 1px 3px rgba(0,0,0,0.3);}
.gas-bar{height:100%;border-radius:8px;transition:width .5s,background .3s;background:linear-gradient(90deg,var(--green),var(--orange));box-shadow:0 0 10px rgba(16,185,129,0.3);}
.gas-bar.danger{background:linear-gradient(90deg,var(--orange),var(--red))!important;box-shadow:0 0 12px rgba(244,63,94,0.5);}
.gas-threshold{position:absolute;top:0;bottom:0;width:2px;background:var(--red);z-index:2;box-shadow:0 0 6px var(--red);}
.gas-info{display:flex;justify-content:space-between;margin-top:8px;font-size:.76rem;color:var(--text2);}

/* Relay cards */
.relay-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px;}
.relay-card{background:rgba(11,15,25,0.55);border:1px solid var(--border);border-radius:var(--radius-sm);padding:14px 12px;text-align:center;transition:all .2s;cursor:pointer;position:relative;box-shadow:inset 0 1px 2px rgba(0,0,0,0.2);}
.relay-card:hover{border-color:var(--border-hover);transform:translateY(-1px);}
.relay-card.on{border-color:rgba(16,185,129,0.5);background:rgba(16,185,129,0.06);box-shadow:0 0 20px rgba(16,185,129,0.18);}
.relay-card .r-name{font-size:.78rem;font-weight:600;color:var(--text2);margin-bottom:6px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}
.relay-card .r-state{font-size:.92rem;font-weight:700;margin-bottom:10px;letter-spacing:0.02em;}
.relay-card.on .r-state{color:var(--green);}
.relay-card.off .r-state{color:var(--text2);}
.toggle{width:46px;height:24px;border-radius:12px;background:rgba(255,255,255,0.15);position:relative;cursor:pointer;transition:background .3s;margin:0 auto;}
.toggle.on{background:var(--green);box-shadow:0 0 12px rgba(16,185,129,0.4);}
.toggle::after{content:'';position:absolute;top:2px;left:2px;width:20px;height:20px;border-radius:50%;background:#fff;transition:transform .3s;box-shadow:0 2px 4px rgba(0,0,0,.3);}
.toggle.on::after{transform:translateX(22px);}
.master-btns{display:flex;gap:10px;margin-top:14px;}

/* Buttons */
.btn{padding:9px 18px;border:none;border-radius:var(--radius-sm);font-size:.82rem;font-weight:600;letter-spacing:0.02em;cursor:pointer;transition:all .2s cubic-bezier(0.4,0,0.2,1);display:inline-flex;align-items:center;justify-content:center;gap:6px;}
.btn:active{transform:scale(.97);}
.btn-primary{background:var(--accent-grad);color:#fff;box-shadow:0 4px 14px rgba(99,102,241,0.35);}
.btn-primary:hover{box-shadow:0 6px 20px rgba(99,102,241,0.5);transform:translateY(-1px);}
.btn-green{background:var(--green-grad);color:#fff;box-shadow:0 4px 14px rgba(16,185,129,0.35);}
.btn-green:hover{box-shadow:0 6px 20px rgba(16,185,129,0.5);transform:translateY(-1px);}
.btn-red{background:var(--red-grad);color:#fff;box-shadow:0 4px 14px rgba(244,63,94,0.35);}
.btn-red:hover{box-shadow:0 6px 20px rgba(244,63,94,0.5);transform:translateY(-1px);}
.btn-outline{background:rgba(255,255,255,0.04);border:1px solid var(--border);color:var(--text);}
.btn-outline:hover{border-color:var(--accent);color:#fff;background:rgba(99,102,241,0.12);}
.btn-sm{padding:7px 14px;font-size:.78rem;}

/* Tabs */
.tabs{display:flex;gap:6px;margin-bottom:20px;overflow-x:auto;padding:6px;background:var(--surface);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);border:1px solid var(--border);border-radius:14px;box-shadow:var(--shadow);scrollbar-width:none;}
.tabs::-webkit-scrollbar{display:none;}
.tab{padding:8px 16px;border:none;border-radius:9px;background:transparent;color:var(--text2);cursor:pointer;font-size:.82rem;font-weight:500;white-space:nowrap;transition:all .2s cubic-bezier(0.4,0,0.2,1);display:inline-flex;align-items:center;gap:6px;}
.tab:hover:not(.active){color:var(--text);background:rgba(255,255,255,0.05);}
.tab.active{background:var(--accent-grad);color:#fff;font-weight:600;box-shadow:0 4px 14px rgba(99,102,241,0.35);}
.tab-content{display:none;}
.tab-content.active{display:block;}

/* Forms */
.form-group{margin-bottom:14px;}
.form-group label{display:block;font-size:.74rem;color:var(--text2);margin-bottom:5px;font-weight:600;text-transform:uppercase;letter-spacing:0.05em;}
.form-group input,.form-group select{width:100%;padding:10px 14px;border:1px solid var(--border);border-radius:var(--radius-sm);background:rgba(11,15,25,0.65);color:var(--text);font-size:.88rem;outline:none;transition:all .2s ease;box-shadow:inset 0 1px 2px rgba(0,0,0,0.2);}
.light .form-group input,.light .form-group select{background:#ffffff;color:#0f172a;}
.form-group input:focus,.form-group select:focus{border-color:var(--accent);box-shadow:0 0 0 3px rgba(99,102,241,0.25);}
.form-row{display:grid;grid-template-columns:1fr 1fr;gap:12px;}

/* Log table */
.log-list{max-height:340px;overflow-y:auto;font-family:'SF Mono',Consolas,Menlo,monospace;font-size:.75rem;background:rgba(11,15,25,0.55);border-radius:var(--radius-sm);padding:8px 12px;border:1px solid var(--border);}
.log-entry{display:grid;grid-template-columns:auto 54px 64px 1fr;gap:8px;padding:6px 0;border-bottom:1px solid var(--border);align-items:center;}
.log-entry:last-child{border-bottom:none;}
.log-time{color:var(--text2);}
.log-lvl{font-weight:700;}
.log-src{color:var(--accent2);}

/* Toast */
.toast-container{position:fixed;top:20px;right:20px;z-index:9999;display:flex;flex-direction:column;gap:8px;}
.toast{padding:12px 20px;border-radius:12px;color:#fff;font-size:.82rem;font-weight:600;animation:slideIn .3s cubic-bezier(0.4,0,0.2,1);box-shadow:0 8px 24px rgba(0,0,0,.45);display:flex;align-items:center;gap:8px;max-width:360px;border:1px solid rgba(255,255,255,0.15);}
.toast-ok{background:var(--green-grad);}
.toast-err{background:var(--red-grad);}
.toast-warn{background:linear-gradient(135deg,#f59e0b,#d97706);}
.toast-info{background:var(--accent-grad);}
@keyframes slideIn{from{transform:translateX(100%);opacity:0;}to{transform:translateX(0);opacity:1;}}

/* Range Slider */
input[type=range]{-webkit-appearance:none;width:100%;height:6px;border-radius:3px;background:rgba(255,255,255,0.12);outline:none;transition:background .2s;}
input[type=range]:hover{background:rgba(255,255,255,0.18);}
input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:18px;height:18px;border-radius:50%;background:var(--accent-grad);cursor:pointer;box-shadow:0 2px 8px rgba(99,102,241,0.6);border:2px solid #ffffff;transition:transform .15s ease;}
input[type=range]::-webkit-slider-thumb:hover{transform:scale(1.2);}

/* Alarm Modal */
.alarm-modal{display:none;position:fixed;inset:0;background:rgba(0,0,0,.75);backdrop-filter:blur(6px);z-index:9998;justify-content:center;align-items:center;}
.alarm-modal.active{display:flex;}
.alarm-box{background:var(--surface);backdrop-filter:blur(24px);-webkit-backdrop-filter:blur(24px);border-radius:var(--radius);padding:30px;max-width:500px;width:90%;box-shadow:var(--shadow);border:1px solid var(--border);}
.alarm-box h3{margin-bottom:16px;font-size:1.1rem;font-weight:700;}

/* Responsive */
@media(max-width:768px){
.grid{grid-template-columns:1fr;}
.header{padding:14px 16px;}
.header h1{font-size:1.1rem;}
.relay-grid{grid-template-columns:repeat(auto-fit,minmax(110px,1fr));}
.form-row{grid-template-columns:1fr;}
.container{padding:12px;}
}
</style>
</head>
<body>
<div class="container">
<!-- Header -->
<div class="header">
<h1>
<div class="header-logo"><svg viewBox="0 0 24 24"><path d="M12 3L4 9v12h16V9l-8-6zm0 2.5L18 10v9H6v-9l6-4.5z"/><path d="M10 14h4v5h-4z"/></svg></div>
<span id="devName">SmartHome</span>
<span class="ver" id="fwVer">v1.1.0</span>
<span id="roleBadge" class="badge badge-guest" style="display:none;">Family / Guest</span>
</h1>
<div class="header-actions">
<span class="badge badge-ok" id="wifiBadge"><span class="pulse">&#9679;</span> Connected</span>
<a href="/update" id="linkOtaUpdate" class="theme-btn" title="OTA Firmware Update" style="text-decoration:none;">
<svg viewBox="0 0 24 24"><path d="M9 16h6v-6h4l-7-7-7 7h4v6zm-4 2h14v2H5v-2z"/></svg>
</a>
<button class="theme-btn" onclick="toggleTheme()" title="Toggle Dark/Light Theme">
<svg viewBox="0 0 24 24"><path d="M12 3a9 9 0 000 18c.7 0 1-.8.6-1.3C11.7 18.5 11 16.8 11 15c0-3.9 3.1-7 7-7 .8 0 1.5.1 2.2.4.5.2 1.1-.2.9-.8A9 9 0 0012 3z"/></svg>
</button>
<button class="theme-btn" id="btnLogOut" onclick="doLogout()" title="Log Out / Switch User" style="display:none;">
<svg viewBox="0 0 24 24"><path d="M17 7l-1.41 1.41L18.17 11H8v2h10.17l-2.58 2.58L17 17l5-5zM4 5h8V3H4c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h8v-2H4V5z"/></svg>
</button>
</div>
</div>

<!-- Tabs -->
<div class="tabs">
<div class="tab active" onclick="showTab('dashboard')"><svg viewBox="0 0 24 24" width="16" height="16" style="fill:currentColor"><path d="M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z"/></svg> Dashboard</div>
<div class="tab" onclick="showTab('relays')"><svg viewBox="0 0 24 24" width="16" height="16" style="fill:currentColor"><path d="M13 3h-2v10h2V3zm4.83 2.17l-1.42 1.42A6.92 6.92 0 0119 12c0 3.87-3.13 7-7 7s-7-3.13-7-7c0-2.27 1.08-4.28 2.59-5.59L6.17 5.17A8.93 8.93 0 003 12a9 9 0 0018 0c0-2.74-1.23-5.18-3.17-6.83z"/></svg> Relays</div>
<div class="tab" onclick="showTab('sensors')"><svg viewBox="0 0 24 24" width="16" height="16" style="fill:currentColor"><path d="M15 13V5a3 3 0 00-6 0v8a5 5 0 106 0zm-3-9a1 1 0 011 1v3h-2V5a1 1 0 011-1z"/></svg> Sensors</div>
<div class="tab" onclick="showTab('alarms')"><svg viewBox="0 0 24 24" width="16" height="16" style="fill:currentColor"><path d="M11.99 2C6.47 2 2 6.48 2 12s4.47 10 9.99 10C17.52 22 22 17.52 22 12S17.52 2 11.99 2zM12 20c-4.42 0-8-3.58-8-8s3.58-8 8-8 8 3.58 8 8-3.58 8-8 8zm.5-13H11v6l5.25 3.15.75-1.23-4.5-2.67z"/></svg> Timers</div>
<div class="tab" onclick="showTab('rules')"><svg viewBox="0 0 24 24" width="16" height="16" style="fill:currentColor"><path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-7 14H6v-2h6v2zm4-4H6v-2h10v2zm0-4H6V7h10v2z"/></svg> Automations</div>
<div class="tab" id="tabNavSettings" onclick="showTab('settings')"><svg viewBox="0 0 24 24" width="16" height="16" style="fill:currentColor"><path d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58c.18-.14.23-.41.12-.61l-1.92-3.32c-.12-.22-.37-.29-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54c-.04-.24-.24-.41-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z"/></svg> Settings</div>
<div class="tab" id="tabNavHardware" onclick="showTab('hardware')"><svg viewBox="0 0 24 24" width="16" height="16" style="fill:currentColor"><path d="M15 9H9v6h6V9zm-2 4h-2v-2h2v2zm8-2V9h-2V7c0-1.1-.9-2-2-2h-2V3h-2v2h-2V3H9v2H7c-1.1 0-2 .9-2 2v2H3v2h2v2H3v2h2v2c0 1.1.9 2 2 2h2v2h2v-2h2v2h2v-2h2c1.1 0 2-.9 2-2v-2h2v-2h-2v-2h2zm-4 6H7V7h10v10z"/></svg> Hardware</div>
<div class="tab" onclick="showTab('logs')"><svg viewBox="0 0 24 24" width="16" height="16" style="fill:currentColor"><path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-5 14H7v-2h7v2zm3-4H7v-2h10v2zm0-4H7V7h10v2z"/></svg> Logs</div>
<div class="tab" id="tabNavSystem" onclick="showTab('system')"><svg viewBox="0 0 24 24" width="16" height="16" style="fill:currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z"/></svg> System</div>
<div class="tab" id="tabNavAbout" onclick="showTab('about')"><svg viewBox="0 0 24 24" width="16" height="16" style="fill:currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg> About</div>
</div>
<!-- Dashboard Tab -->
<div class="tab-content active" id="tab-dashboard">
<div class="grid">
<!-- System Info -->
<div class="card">
<div class="card-title"><svg viewBox="0 0 24 24" width="18" height="18"><path fill="currentColor" d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93 0-.62.08-1.22.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z"/></svg> System Info</div>
<div class="status-row"><span class="status-label">WiFi</span><span class="status-value" id="wifiStatus">--</span></div>
<div class="status-row"><span class="status-label">RSSI</span><span class="status-value"><span id="rssi">--</span> dBm (<span id="signal">--</span>%)</span></div>
<div class="status-row"><span class="status-label">IP Address</span><span class="status-value" id="ipAddr">--</span></div>
<div class="status-row"><span class="status-label">Hostname</span><span class="status-value" id="hostname">--</span></div>
<div class="status-row"><span class="status-label">MQTT</span><span class="status-value" id="mqttStatus">--</span></div>
<div class="status-row"><span class="status-label">Uptime</span><span class="status-value" id="uptime">--</span></div>
<div class="status-row"><span class="status-label">Free Heap</span><span class="status-value"><span id="heap">--</span> KB</span></div>
<div class="status-row"><span class="status-label">Date / Time</span><span class="status-value" id="datetime">--</span></div>
</div>

<!-- Sensors Summary -->
<div class="card">
<div class="card-title"><svg viewBox="0 0 24 24" width="18" height="18"><path fill="currentColor" d="M15 13V5a3 3 0 00-6 0v8a5 5 0 106 0zm-3-9a1 1 0 011 1v3h-2V5a1 1 0 011-1z"/></svg> Environment &amp; Sensors</div>
<div class="gauge-row" id="primaryGaugeRow">
<div class="gauge" id="cardTemp"><div class="gauge-value"><span id="temp">--</span><span class="gauge-unit">&deg;C</span></div><div class="gauge-label" id="lblTemp">Temperature</div></div>
<div class="gauge" id="cardHum"><div class="gauge-value"><span id="hum">--</span><span class="gauge-unit">%</span></div><div class="gauge-label" id="lblHum">Humidity</div></div>
<div class="gauge" id="cardPressure" style="display:none;"><div class="gauge-value"><span id="pressure">--</span><span class="gauge-unit">hPa</span></div><div class="gauge-label" id="lblPressure">Barometer</div></div>
<div class="gauge" id="cardLux" style="display:none;"><div class="gauge-value"><span id="lux">--</span><span class="gauge-unit">lx</span></div><div class="gauge-label" id="lblLux">Ambient Lux</div></div>
</div>

<div class="status-row" id="rowMotion" style="display:none;margin-top:8px;"><span class="status-label" id="lblMotion">Motion Occupancy</span><span class="badge" id="motionBadge">--</span></div>
<div class="status-row" id="rowProbe" style="display:none;"><span class="status-label" id="lblProbe">Water Temp Probe</span><span class="status-value" id="probeValWrap"><span id="probeTemp">--</span>&deg;C</span></div>

<div id="tankWidget" style="display:none;margin-top:12px;padding-top:10px;border-top:1px solid var(--card-border);">
<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px">
<span class="status-label" id="lblTank">Overhead Water Tank</span>
<span class="status-value"><span id="tankPct">--</span>% (<span id="tankDist">--</span> cm)</span>
</div>
<div style="background:var(--bg);height:14px;border-radius:7px;overflow:hidden;position:relative;border:1px solid var(--card-border);">
<div id="tankBar" style="background:#06b6d4;height:100%;width:0%;transition:width 0.5s ease;"></div>
</div>
</div>

<div id="gasWidget" style="margin-top:12px">
<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px">
<span class="status-label" id="lblGas">Gas Level</span>
<span class="badge" id="gasBadge">--</span>
</div>
<div class="gas-bar-wrap">
<div class="gas-bar" id="gasBar" style="width:0%"></div>
<div class="gas-threshold" id="gasThLine" style="left:10%"></div>
</div>
<div class="gas-info"><span>Raw: <span id="gasRaw">0</span></span><span>Threshold: <span id="gasTh">400</span></span></div>
</div>
<div id="noSensorsState" style="display:none;color:var(--text2);padding:16px;text-align:center;background:var(--bg);border-radius:10px;border:1px dashed var(--card-border);">No sensors configured in Hardware Profile.<div class="admin-only" style="margin-top:8px"><button class="btn btn-sm btn-outline" onclick="document.getElementById('tabNavHardware')?.click()">Configure in Hardware</button></div></div>
<div id="multiSensorsWrap" style="display:none;margin-top:12px;padding-top:10px;border-top:1px solid var(--card-border);"></div>
</div>

<!-- Quick Relay Status -->
<div class="card">
<div class="card-title"><svg viewBox="0 0 24 24" width="18" height="18"><path fill="currentColor" d="M13 3h-2v10h2V3zm4.83 2.17l-1.42 1.42A6.92 6.92 0 0119 12c0 3.87-3.13 7-7 7s-7-3.13-7-7c0-2.27 1.08-4.28 2.59-5.59L6.17 5.17A8.93 8.93 0 003 12a9 9 0 0018 0c0-2.74-1.23-5.18-3.17-6.83z"/></svg> Relays</div>
<div class="relay-grid" id="relayGrid"></div>
<div class="master-btns">
<button class="btn btn-green btn-sm" onclick="relayAll('on')">All ON</button>
<button class="btn btn-red btn-sm" onclick="relayAll('off')">All OFF</button>
</div>
</div>
</div>
</div>

<!-- Relays Tab -->
<div class="tab-content" id="tab-relays">
<div class="card">
<div class="card-title"><svg viewBox="0 0 24 24" width="18" height="18"><path fill="currentColor" d="M13 3h-2v10h2V3zm4.83 2.17l-1.42 1.42A6.92 6.92 0 0119 12c0 3.87-3.13 7-7 7s-7-3.13-7-7c0-2.27 1.08-4.28 2.59-5.59L6.17 5.17A8.93 8.93 0 003 12a9 9 0 0018 0c0-2.74-1.23-5.18-3.17-6.83z"/></svg> Relay Control</div>
<div id="relayDetailGrid"></div>
<div class="master-btns" style="margin-top:16px">
<button class="btn btn-green" onclick="relayAll('on')">Master ON</button>
<button class="btn btn-red" onclick="relayAll('off')">Master OFF</button>
</div>
</div>
</div>

<!-- Sensors Tab -->
<div class="tab-content" id="tab-sensors">
<div class="grid" id="sensorPrimaryGrid">
<div class="card" id="sensorClimateCard">
<div class="card-title" id="sensorClimateTitle">Climate &mdash; Temperature &amp; Humidity</div>
<div class="gauge-row">
<div class="gauge"><div class="gauge-value"><span id="temp2">--</span><span class="gauge-unit">&deg;C</span></div><div class="gauge-label">Temperature</div></div>
<div class="gauge"><div class="gauge-value"><span id="hum2">--</span><span class="gauge-unit">%</span></div><div class="gauge-label">Humidity</div></div>
</div>
<div class="status-row"><span class="status-label">Sensor Status</span><span id="dhtStatus" class="badge badge-ok">OK</span></div>
<div class="status-row"><span class="status-label">Temp Alarm Threshold</span><span class="status-value"><span id="tempTh">45</span>&deg;C</span></div>
<div class="admin-only">
<div id="climateCalSlotRow" style="display:none;margin-top:10px" class="form-group"><label>Climate Sensor Slot</label><select id="climateCalIdx" onchange="onClimateCalSlotChange()"></select></div>
<div class="form-row" style="margin-top:12px">
<div class="form-group"><label>Temp Offset (&deg;C)</label><input type="number" step="0.1" id="tempOffset" value="0"></div>
<div class="form-group"><label>Humidity Offset (%)</label><input type="number" step="0.1" id="humOffset" value="0"></div>
</div>
<div class="form-group"><label>Temp Alarm Threshold (&deg;C)</label><input type="number" step="0.5" id="tempAlarmTh" value="45"></div>
<button class="btn btn-primary btn-sm" onclick="saveSensorCal()">Save Calibration</button>
</div>
</div>
<div class="card" id="sensorMq2Card">
<div class="card-title" id="sensorMq2Title">MQ2 &mdash; Gas Sensor</div>
<div class="gauge"><div class="gauge-value"><span id="gasVal">--</span><span class="gauge-unit" id="gasMaxUnit"> /4095</span></div><div class="gauge-label">Raw ADC Value</div></div>
<div style="margin-top:12px">
<div class="gas-bar-wrap" style="height:32px">
<div class="gas-bar" id="gasBar2" style="width:0%"></div>
<div class="gas-threshold" id="gasThLine2" style="left:10%"></div>
</div>
<div class="gas-info"><span>Percentage: <span id="gasPct">0</span>%</span><span>Status: <span id="gasStat">Safe</span></span></div>
</div>
<div class="status-row" style="margin-top:8px"><span class="status-label">Warming Up</span><span id="gasWarm" class="badge badge-warn">--</span></div>
<div class="admin-only" id="sensorMq2Controls">
<div id="mq2HwNote" style="display:none;font-size:0.74rem;color:var(--orange);margin-top:8px;">MQ-2 Gas sensor is disabled or pins unassigned in Hardware Profile.</div>
<div id="mq2CalSlotRow" style="display:none;margin-top:10px" class="form-group"><label>Gas Sensor Slot</label><select id="mq2CalIdx" onchange="onMq2CalSlotChange()"></select></div>
<div class="form-group" style="margin-top:12px"><label>Gas Sensor</label>
<div style="display:flex;gap:8px;align-items:center">
<select id="gasEn" style="flex:1"><option value="1">Enabled</option><option value="0">Disabled</option></select>
<button class="btn btn-primary btn-sm" id="btnGasSave" onclick="saveGasEnable()">Save</button>
</div></div>
<div class="form-group" style="margin-top:12px"><label id="gasThLabel">Alarm Threshold (0-4095)</label>
<input type="range" min="10" max="4095" id="gasThSlider" value="400" oninput="document.getElementById('gasThVal').textContent=this.value">
<span id="gasThVal">400</span></div>
<button class="btn btn-primary btn-sm" id="btnGasThSave" onclick="saveGasTh()">Save Threshold</button>
<button class="btn btn-outline btn-sm" id="btnGasCal" onclick="calibrateMQ2()">Calibrate Baseline</button>
</div>
</div>
</div>
<div id="multiSensorCardsWrap" style="display:none;margin-top:14px;"></div>
<div id="noSensorsTabState" class="card" style="display:none;text-align:center;color:var(--text2);padding:24px;">No sensors configured in Hardware Profile.<div class="admin-only" style="margin-top:10px"><button class="btn btn-sm btn-outline" onclick="document.getElementById('tabNavHardware')?.click()">Configure in Hardware</button></div></div>
</div>

<!-- Alarms Tab -->
<div class="tab-content" id="tab-alarms">
<div class="card">
<div class="card-title">Timer Tasks</div>
<div style="color:var(--text2);font-size:.78rem;margin-bottom:12px">Create fixed-time schedules or one-shot delay timers for relay and buzzer actions.</div>
<div id="alarmList"></div>
<div class="admin-only" style="display:flex;gap:8px;flex-wrap:wrap;margin-top:12px">
<button class="btn btn-primary" onclick="showAlarmModal('clock')">+ Fixed Time</button>
<button class="btn btn-outline" onclick="showAlarmModal('delay')">+ Delay Timer</button>
</div>
</div>
</div>

<!-- Automations Tab -->
<div class="tab-content" id="tab-rules">
<div class="card">
<div class="card-title"><svg viewBox="0 0 24 24" width="18" height="18"><path fill="currentColor" d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/></svg> Sensor Automation Rules</div>
<div style="color:var(--text2);font-size:.78rem;margin-bottom:12px">Automatically control relays when temperature, humidity, or gas levels cross your defined thresholds.</div>
<div id="ruleList"></div>
<div class="admin-only" style="margin-top:16px">
<button class="btn btn-primary" onclick="showRuleModal()">+ Add New Rule</button>
</div>
</div>
</div>

<!-- Settings Tab -->
<div class="tab-content" id="tab-settings">
<div class="grid">
<!-- Card 1: WiFi Settings -->
<div class="card">
<div class="card-title"><svg viewBox="0 0 24 24"><path d="M12 3C6.95 3 2.59 5.59 0 9.5l12 14.5 12-14.5C21.41 5.59 17.05 3 12 3z"/></svg> WiFi Connection</div>
<div class="form-group"><label>Network Name (SSID)</label><input type="text" id="wifiSSID" placeholder="e.g. Home_WiFi_2.4G"></div>
<div class="form-group"><label>Network Password</label><input type="password" id="wifiPass" placeholder="Enter Wi-Fi password"></div>
<div style="margin-top:16px;">
<button class="btn btn-primary btn-sm" onclick="saveWiFi()">Save &amp; Connect</button>
</div>
</div>

<!-- Card 2: MQTT Broker Settings -->
<div class="card">
<div class="card-title"><svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 14H9V8h2v8zm4 0h-2V8h2v8z"/></svg> MQTT IoT Broker</div>
<div class="form-group"><label>MQTT Client</label><select id="mqttEn"><option value="1">Enabled</option><option value="0">Disabled</option></select></div>
<div class="form-group"><label>Broker Host / IP</label><input type="text" id="mqttBroker" placeholder="192.168.1.50"></div>
<div class="form-row">
<div class="form-group"><label>Port</label><input type="number" id="mqttPort" value="1883"></div>
<div class="form-group"><label>Topic Prefix</label><input type="text" id="mqttPrefix" value="smarthome"></div>
</div>
<div class="form-group"><label>Client ID</label><input type="text" id="mqttClientId" placeholder="smarthome-XXXX"></div>
<div class="form-row">
<div class="form-group"><label>Username</label><input type="text" id="mqttUser"></div>
<div class="form-group"><label>Password</label><input type="password" id="mqttPass"></div>
</div>
<div style="margin-top:16px;">
<button class="btn btn-primary btn-sm" onclick="saveMQTT()">Save MQTT</button>
</div>
</div>

<!-- Card 3: Device & System Clock -->
<div class="card">
<div class="card-title"><svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm.5-13H11v6l5.25 3.15.75-1.23-4.5-2.67z"/></svg> Device &amp; System Clock</div>
<div class="form-row">
<div class="form-group"><label>Device Name</label><input type="text" id="cfgDevName" maxlength="20"></div>
<div class="form-group"><label>Hostname (mDNS)</label><input type="text" id="cfgHostname" maxlength="24" placeholder="smarthome-XXXX"></div>
</div>
<div style="font-size:0.75rem;color:var(--text2);margin-bottom:12px;padding:8px 12px;background:rgba(255,255,255,0.03);border:1px solid var(--border);border-radius:var(--radius-xs);">
MAC: <span id="cfgMac" style="font-family:monospace;color:var(--accent2)">--</span> &bull; Local: <a id="cfgLocalUrl" href="#" target="_blank" style="color:var(--accent2);text-decoration:none;">--</a>
</div>
<div class="form-row">
<div class="form-group"><label>Timezone (POSIX)</label><input type="text" id="cfgTZ" value="IST-5:30"></div>
<div class="form-group"><label>Time Format</label><select id="cfg24h"><option value="1">24-hour</option><option value="0">12-hour</option></select></div>
</div>
<div style="margin-top:16px;">
<button class="btn btn-primary btn-sm" onclick="saveDevConfig()">Save Device Settings</button>
</div>
</div>

<!-- Card 4: Security & Privilege Tiers -->
<div class="card">
<div class="card-title"><svg viewBox="0 0 24 24"><path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm0 10.99h7c-.53 4.12-3.28 7.79-7 8.94V12H5V6.3l7-3.11v8.8z"/></svg> Security &amp; Privilege Tiers</div>
<div class="form-group"><label>Web Password Protection</label>
<select id="cfgWebAuth" onchange="toggleWebAuthFields()">
<option value="0">Disabled</option>
<option value="1">Enabled</option>
</select>
</div>
<div id="cfgWebAuthFields" style="display:none;">
<div class="form-row">
<div class="form-group"><label>Admin Username</label><input type="text" id="cfgWebUser" maxlength="20"></div>
<div class="form-group"><label>Admin Password</label><input type="password" id="cfgWebPass" maxlength="20" placeholder="New Password"></div>
</div>
<div style="margin-top:10px;padding:12px;background:rgba(234,179,8,0.06);border:1px solid rgba(234,179,8,0.25);border-radius:var(--radius-sm);">
<div class="form-group" style="margin-bottom:6px;">
<label style="font-weight:600;display:flex;align-items:center;gap:8px;color:#facc15;cursor:pointer;text-transform:none;font-size:0.82rem;">
<input type="checkbox" id="cfgGuestAuth" onchange="toggleGuestFields()" style="width:auto;margin:0;">
Enable Family / Guest Tier (Restricted)
</label>
</div>
<div style="font-size:0.73rem;color:var(--text2);margin-bottom:10px;line-height:1.4;">
Family and Guests can toggle switches, view sensors, and set quick timers without administrative access to GPIO settings, Wi-Fi, factory reset, or firmware updates.
</div>
<div id="cfgGuestFields" style="display:none;">
<div class="form-row">
<div class="form-group" style="margin-bottom:0;"><label>Guest Username</label><input type="text" id="cfgGuestUser" maxlength="20" placeholder="guest"></div>
<div class="form-group" style="margin-bottom:0;"><label>Guest Password</label><input type="password" id="cfgGuestPass" maxlength="20" placeholder="Leave empty for open guest"></div>
</div>
</div>
</div>
</div>
<div class="form-group" style="margin-top:12px;">
<label>ArduinoOTA (Legacy Port 3232 Flashing)</label>
<select id="cfgArduinoOta">
<option value="0">Disabled (Recommended &mdash; Protected)</option>
<option value="1">Enabled (Port 3232 Open)</option>
</select>
<div style="font-size:0.72rem;color:var(--text2);margin-top:4px">Enable only if flashing raw firmware via Arduino IDE over LAN. HTTP Web/App OTA is always active.</div>
</div>
<div style="margin-top:16px;">
<button class="btn btn-primary btn-sm" onclick="saveDevConfig()">Save Security Settings</button>
</div>
</div>

<!-- Card 5: LCD Display Settings -->
<div class="card">
<div class="card-title"><svg viewBox="0 0 24 24"><path d="M21 3H3c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h5v2h8v-2h5c1.1 0 1.99-.9 1.99-2L23 5c0-1.1-.9-2-2-2zm0 14H3V5h18v12z"/></svg> LCD Display Control</div>
<div class="form-row">
<div class="form-group"><label>LCD Enabled</label><select id="lcdEn"><option value="1">Yes</option><option value="0">No</option></select></div>
<div class="form-group"><label>Backlight Mode</label><select id="lcdBl"><option value="1">Always On</option><option value="0">Always Off</option></select></div>
</div>
<div class="form-row">
<div class="form-group"><label>Display Mode</label><select id="lcdMode"><option value="rotate">Auto Rotate</option><option value="dht_relay">DHT + Relays</option></select></div>
<div class="form-group"><label>Page Rotation (sec)</label><input type="number" id="lcdRot" min="3" max="30" value="5"></div>
</div>
<div class="form-group">
<div style="display:flex;justify-content:space-between;margin-bottom:6px;">
<label style="margin-bottom:0;">Backlight Brightness</label>
<span id="lcdBrightVal" style="font-size:0.8rem;font-weight:700;color:var(--accent2);">100%</span>
</div>
<input type="range" id="lcdBright" min="0" max="100" value="100" oninput="document.getElementById('lcdBrightVal').textContent=this.value+'%'">
</div>
<div class="form-group"><label>Auto-Dim Schedule (Night Mode)</label><select id="lcdAutoDim" onchange="toggleLcdDimFields()"><option value="0">Disabled</option><option value="1">Enabled</option></select></div>
<div id="lcdDimFields" style="display:none;">
<div class="form-row">
<div class="form-group"><label>Dim Start Time</label><input type="time" id="lcdDimStart" value="22:00"></div>
<div class="form-group"><label>Dim End Time</label><input type="time" id="lcdDimEnd" value="06:00"></div>
</div>
<div class="form-group">
<div style="display:flex;justify-content:space-between;margin-bottom:6px;">
<label style="margin-bottom:0;">Dimmed Brightness</label>
<span id="lcdDimBrightVal" style="font-size:0.8rem;font-weight:700;color:var(--accent2);">0%</span>
</div>
<input type="range" id="lcdDimBright" min="0" max="100" value="0" oninput="document.getElementById('lcdDimBrightVal').textContent=this.value+'%'">
<small style="color:var(--text2);font-size:0.73rem;display:block;margin-top:4px;">*Note: Standard I2C LCDs only support ON/OFF (0% is OFF, &gt;0% is ON).</small>
</div>
</div>
<div style="margin-top:16px;">
<button class="btn btn-primary btn-sm" id="btnLcdSave" onclick="saveLCD()">Save LCD</button>
</div>
<div id="lcdHwNote" style="display:none;font-size:0.74rem;color:var(--orange);margin-top:6px;">LCD display is disabled in Hardware Profile.</div>
</div>

<!-- Card 6: Buzzer & Acoustic Alerts -->
<div class="card">
<div class="card-title"><svg viewBox="0 0 24 24"><path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z"/></svg> Buzzer &amp; Acoustic Alert</div>
<div class="form-row">
<div class="form-group"><label>Buzzer State</label><select id="buzEn"><option value="1">Yes</option><option value="0">No</option></select></div>
<div class="form-group"><label>Volume</label><input type="range" min="0" max="255" id="buzVol" value="128"></div>
</div>
<div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:16px;">
<button class="btn btn-primary btn-sm" id="btnBuzSave" onclick="saveBuzzer()">Save Buzzer</button>
<button class="btn btn-outline btn-sm" id="btnBuzTest" onclick="testBuzzer()">Test Beep</button>
<button class="btn btn-red btn-sm" onclick="muteBuzzer()">Mute 5 min</button>
</div>
<div id="buzHwNote" style="display:none;font-size:0.74rem;color:var(--orange);margin-top:6px;">Buzzer is disabled or pin unassigned in Hardware Profile.</div>
</div>
</div>
</div>

<!-- Hardware & GPIO Template Tab -->
<div class="tab-content" id="tab-hardware">
<div class="grid">
<div class="card" style="grid-column: 1 / -1;">
<div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:10px;margin-bottom:12px;">
<div>
<div class="card-title" style="margin-bottom:2px;"><svg viewBox="0 0 24 24" width="18" height="18"><path fill="currentColor" d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-2 10h-4v4h-2v-4H7v-2h4V7h2v4h4v2z"/></svg> Hardware Profile &amp; GPIO Engine</div>
<div style="font-size:0.75rem;color:var(--text2)">Universal hardware pin mapper: Custom DIY pin budgeting &amp; Smart Presets</div>
</div>
<!-- Mode Switcher -->
<div style="display:flex;background:var(--bg);padding:3px;border-radius:10px;border:1px solid var(--border);gap:4px;">
<button type="button" id="btnHwModePreset" class="btn btn-sm btn-primary" onclick="setHwMode('preset')" style="padding:5px 12px;font-size:0.78rem;">⚡ Smart Presets</button>
<button type="button" id="btnHwModeCustom" class="btn btn-sm btn-outline" onclick="setHwMode('custom')" style="padding:5px 12px;font-size:0.78rem;border:none;">🛠️ Custom DIY Mode</button>
</div>
</div>

<!-- Preset Bar (Visible in Preset Mode) -->
<div id="hwPresetControls" style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:14px;align-items:center;padding:10px;background:var(--bg);border-radius:8px;border:1px solid var(--border);">
<span style="font-size:0.8rem;color:var(--text2);font-weight:600;">Standard Template:</span>
<select id="hwPresetSelect" onchange="onPresetSelected()" style="background:var(--surface);color:var(--text);border:1px solid var(--accent);border-radius:8px;padding:6px 12px;font-size:0.85rem;flex:1;min-width:200px;">
<option value="">-- Quick Load Preset --</option>
</select>
<button type="button" class="btn btn-outline btn-sm" onclick="applyHwPresetBtn()">Apply Preset</button>
<button type="button" class="btn btn-red btn-sm" id="btnHwReset" onclick="resetHwDefaultBtn()">Reset Default</button>
</div>

<!-- Live GPIO Pin Availability & Capability Matrix -->
<div style="margin-bottom:14px;background:var(--bg);padding:12px;border-radius:10px;border:1px solid var(--border);">
<div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px;margin-bottom:8px;">
<div>
<span style="font-weight:700;font-size:0.85rem;color:var(--accent);">⚡ LIVE GPIO PIN ALLOCATION MATRIX</span>
<span style="font-size:0.72rem;color:var(--text2);margin-left:8px;">Real-time pin budget &amp; assignment map</span>
</div>
<div id="hwPinStatsBadge" style="font-size:0.72rem;color:var(--text2);font-weight:600;"></div>
</div>
<div id="hwPinMatrixGrid" style="display:grid;grid-template-columns:repeat(auto-fill, minmax(130px, 1fr));gap:6px;"></div>
</div>

<div id="hwConflictAlert" style="display:none;padding:10px 14px;background:rgba(239,68,68,0.15);border:1px solid #ef4444;border-radius:8px;color:#fca5a5;font-size:0.85rem;margin-bottom:14px;"></div>

<div class="form-row">
<div class="form-group"><label>Board Template Name</label><input type="text" id="hwBoardName" maxlength="30" value=")rawliteral"
#if defined(ESP8266)
"SmartHome ESP8266 2-CH Dual"
#else
"SmartHome 5-CH Standard"
#endif
R"rawliteral("></div>
<div class="form-group">
<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:4px;">
<label style="margin:0;">Active Relays Count (0 to 8)</label>
<div style="display:flex;gap:4px;">
<button type="button" class="btn btn-sm btn-outline" style="padding:2px 8px;font-size:0.75rem;" onclick="addHwRelayChannel()">+ Add Channel</button>
<button type="button" class="btn btn-sm btn-outline" style="padding:2px 8px;font-size:0.75rem;" onclick="removeHwRelayChannel()">− Remove</button>
</div>
</div>
<select id="hwNumRelays" onchange="setHwMode('custom');renderHwChannelsFromUI()"><option value="0">0 (Sensor Only)</option><option value="1">1 Relay</option><option value="2")rawliteral"
#if defined(ESP8266)
" selected"
#endif
R"rawliteral(>2 Relays</option><option value="3">3 Relays</option><option value="4">4 Relays</option><option value="5")rawliteral"
#if !defined(ESP8266)
" selected"
#endif
R"rawliteral(>5 Relays (Standard)</option><option value="6">6 Relays</option><option value="7">7 Relays</option><option value="8">8 Relays (Max)</option></select>
</div>
</div>

<div class="card-title" style="margin-top:10px;font-size:0.95rem;">Relay Channels &amp; Wall Switches</div>
<div id="hwChannelsContainer" style="display:flex;flex-direction:column;gap:10px;margin-bottom:16px;"></div>

<div class="card-title" style="margin-top:14px;font-size:0.95rem;">Sensors (Dynamic Multi-Instance) &amp; Peripherals</div>
<div style="display:flex;flex-direction:column;gap:12px;margin-bottom:16px;">

<div style="background:var(--bg);padding:12px;border-radius:8px;border:1px solid var(--card-border)">
<div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px;margin-bottom:8px;">
<div style="font-weight:600;color:var(--accent2)">Climate Sensors (DHT11 / DHT22 / BME280 / AHT20 / SHT3x) <span id="hwClimatesCount" class="badge badge-info">0 / 4</span></div>
<div style="display:flex;gap:4px;">
<button type="button" class="btn btn-sm btn-outline" style="padding:2px 8px;font-size:0.75rem;" onclick="addHwSensor('climates')">+ Add</button>
<button type="button" class="btn btn-sm btn-outline" style="padding:2px 8px;font-size:0.75rem;" onclick="removeHwSensor('climates')">&minus; Remove</button>
</div>
</div>
<div id="hwClimatesContainer" style="display:flex;flex-direction:column;gap:8px;"></div>
</div>

<div style="background:var(--bg);padding:12px;border-radius:8px;border:1px solid var(--card-border)">
<div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px;margin-bottom:8px;">
<div style="font-weight:600;color:var(--accent2)">Ambient Light Sensors (BH1750 I2C: 0x23 / 0x5C) <span id="hwLightsCount" class="badge badge-info">0 / 2</span></div>
<div style="display:flex;gap:4px;">
<button type="button" class="btn btn-sm btn-outline" style="padding:2px 8px;font-size:0.75rem;" onclick="addHwSensor('lights')">+ Add</button>
<button type="button" class="btn btn-sm btn-outline" style="padding:2px 8px;font-size:0.75rem;" onclick="removeHwSensor('lights')">&minus; Remove</button>
</div>
</div>
<div id="hwLightsContainer" style="display:flex;flex-direction:column;gap:8px;"></div>
</div>

<div style="background:var(--bg);padding:12px;border-radius:8px;border:1px solid var(--card-border)">
<div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px;margin-bottom:8px;">
<div style="font-weight:600;color:var(--accent2)">Motion &amp; Occupancy Sensors (PIR / mmWave Radar) <span id="hwMotionsCount" class="badge badge-info">0 / 6</span></div>
<div style="display:flex;gap:4px;">
<button type="button" class="btn btn-sm btn-outline" style="padding:2px 8px;font-size:0.75rem;" onclick="addHwSensor('motions')">+ Add</button>
<button type="button" class="btn btn-sm btn-outline" style="padding:2px 8px;font-size:0.75rem;" onclick="removeHwSensor('motions')">&minus; Remove</button>
</div>
</div>
<div id="hwMotionsContainer" style="display:flex;flex-direction:column;gap:8px;"></div>
</div>

<div style="background:var(--bg);padding:12px;border-radius:8px;border:1px solid var(--card-border)">
<div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px;margin-bottom:8px;">
<div style="font-weight:600;color:var(--accent2)">Water Temperature Probes (DS18B20 1-Wire) <span id="hwProbesCount" class="badge badge-info">0 / 4</span></div>
<div style="display:flex;gap:4px;">
<button type="button" class="btn btn-sm btn-outline" style="padding:2px 8px;font-size:0.75rem;" onclick="addHwSensor('probes')">+ Add</button>
<button type="button" class="btn btn-sm btn-outline" style="padding:2px 8px;font-size:0.75rem;" onclick="removeHwSensor('probes')">&minus; Remove</button>
</div>
</div>
<div id="hwProbesContainer" style="display:flex;flex-direction:column;gap:8px;"></div>
</div>

<div style="background:var(--bg);padding:12px;border-radius:8px;border:1px solid var(--card-border)">
<div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px;margin-bottom:8px;">
<div style="font-weight:600;color:var(--accent2)">Ultrasonic Distance &amp; Water Tank Monitors <span id="hwUltrasonicsCount" class="badge badge-info">0 / 4</span></div>
<div style="display:flex;gap:4px;">
<button type="button" class="btn btn-sm btn-outline" style="padding:2px 8px;font-size:0.75rem;" onclick="addHwSensor('ultrasonics')">+ Add</button>
<button type="button" class="btn btn-sm btn-outline" style="padding:2px 8px;font-size:0.75rem;" onclick="removeHwSensor('ultrasonics')">&minus; Remove</button>
</div>
</div>
<div id="hwUltrasonicsContainer" style="display:flex;flex-direction:column;gap:8px;"></div>
</div>

<div style="background:var(--bg);padding:12px;border-radius:8px;border:1px solid var(--card-border)">
<div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px;margin-bottom:8px;">
<div style="font-weight:600;color:var(--accent2)">Gas &amp; Smoke Sensors (MQ-2) <span id="hwMq2sCount" class="badge badge-info">0 / 4</span></div>
<div style="display:flex;gap:4px;">
<button type="button" class="btn btn-sm btn-outline" style="padding:2px 8px;font-size:0.75rem;" onclick="addHwSensor('mq2s')">+ Add</button>
<button type="button" class="btn btn-sm btn-outline" style="padding:2px 8px;font-size:0.75rem;" onclick="removeHwSensor('mq2s')">&minus; Remove</button>
</div>
</div>
<div id="hwMq2sContainer" style="display:flex;flex-direction:column;gap:8px;"></div>
</div>

</div>

<div class="grid" style="grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));gap:12px;margin-bottom:16px;">

<div style="background:var(--bg);padding:12px;border-radius:8px;border:1px solid var(--card-border)">
<div style="font-weight:600;margin-bottom:6px;color:var(--accent2)">Alarm Buzzer</div>
<div class="form-group"><label>Buzzer</label><select id="hwBuzEn" onchange="onPeripheralToggle();checkHwConflicts()"><option value="1" selected>Enabled</option><option value="0">Disabled</option></select></div>
<div class="form-group"><label>LEDC PWM GPIO Pin</label><select id="hwBuzPin" onchange="checkHwConflicts()"></select></div>
</div>

<div style="background:var(--bg);padding:12px;border-radius:8px;border:1px solid var(--card-border)">
<div style="font-weight:600;margin-bottom:6px;color:var(--accent2)">I2C LCD Display (1602/2004)</div>
<div class="form-group"><label>LCD Status</label><select id="hwLcdEn" onchange="onPeripheralToggle();checkHwConflicts()"><option value="1" selected>Enabled</option><option value="0">Disabled</option></select></div>
<div class="form-row">
<div class="form-group"><label>I2C Address</label><select id="hwLcdAddr" onchange="checkHwConflicts()"><option value="39">0x27 (Standard)</option><option value="63">0x3F</option></select></div>
<div class="form-group"><label>Size</label><select id="hwLcdSize"><option value="16x2" selected>16 &times; 2</option><option value="20x4">20 &times; 4</option></select></div>
</div>
<div class="form-row">
<div class="form-group"><label>SDA Pin</label><select id="hwLcdSda" onchange="checkHwConflicts()"></select></div>
<div class="form-group"><label>SCL Pin</label><select id="hwLcdScl" onchange="checkHwConflicts()"></select></div>
</div>
</div>

<div style="background:var(--bg);padding:12px;border-radius:8px;border:1px solid var(--card-border)">
<div style="font-weight:600;margin-bottom:6px;color:var(--accent2)">Multi-Function Status Button</div>
<div class="form-group"><label>Button GPIO Pin (INPUT_PULLUP)</label><select id="hwBtnMultiPin" onchange="checkHwConflicts()"></select></div>
</div>
</div>

<div style="display:flex;gap:10px;justify-content:flex-end;margin-top:12px;">
<button class="btn btn-outline" onclick="loadHardware()">Reload Profile</button>
<button class="btn btn-primary" onclick="saveHardware()">Save &amp; Reboot Controller</button>
</div>
</div>
</div>
</div>

<!-- Logs Tab -->
<div class="tab-content" id="tab-logs">
<div class="card">
<div class="card-title">Event Log</div>
<div class="log-list" id="logList"><div style="color:var(--text2);padding:20px;text-align:center;">Loading...</div></div>
<div style="margin-top:12px;display:flex;gap:8px;">
<button class="btn btn-outline btn-sm" onclick="refreshLogs()">Refresh</button>
<button class="btn btn-outline btn-sm" onclick="downloadLogs()">Download CSV</button>
<button class="btn btn-red btn-sm admin-only" onclick="clearLogs()">Clear All</button>
</div>
</div>
</div>

<!-- System Tab -->
<div class="tab-content" id="tab-system">
<div class="grid">
<div class="card">
<div class="card-title">Diagnostics</div>
<div class="status-row"><span class="status-label">Firmware</span><span class="status-value" id="dFw">--</span></div>
<div class="status-row"><span class="status-label">Build Date</span><span class="status-value" id="dBuild">--</span></div>
<div class="status-row"><span class="status-label">Chip</span><span class="status-value" id="dChip">--</span></div>
<div class="status-row"><span class="status-label">Chip ID</span><span class="status-value" id="dChipId">--</span></div>
<div class="status-row"><span class="status-label">CPU</span><span class="status-value"><span id="dCpu">--</span> MHz</span></div>
<div class="status-row"><span class="status-label">Flash</span><span class="status-value"><span id="dFlash">--</span> MB</span></div>
<div class="status-row"><span class="status-label">Free Heap</span><span class="status-value"><span id="dHeap">--</span> bytes</span></div>
<div class="status-row"><span class="status-label">Min Heap</span><span class="status-value"><span id="dMinHeap">--</span> bytes</span></div>
<div class="status-row"><span class="status-label">Heap Fragmentation</span><span class="status-value"><span id="dFrag">--</span>%</span></div>
<div class="status-row"><span class="status-label">SDK</span><span class="status-value" id="dSdk">--</span></div>
<div class="status-row"><span class="status-label">Reset Reason</span><span class="status-value" id="dReset">--</span></div>
<div class="status-row"><span class="status-label">Uptime</span><span class="status-value" id="dUptime">--</span></div>
<div class="status-row"><span class="status-label">OTA Status</span><span class="status-value" id="dOta">--</span></div>
</div>
<div class="card">
<div class="card-title">Maintenance</div>
<div style="display:flex;flex-wrap:wrap;gap:8px;">
<button class="btn btn-primary" onclick="restartESP()">Restart ESP</button>
<button class="btn btn-red" onclick="factoryReset()">Factory Reset</button>
<button class="btn btn-outline" onclick="resetWiFi()">Reset WiFi</button>
<button class="btn btn-outline" onclick="backupConfig()">Backup Config</button>
<button class="btn btn-outline" onclick="testBuzzer()">Test Buzzer</button>
</div>
<div style="margin-top:16px">
<div class="form-group"><label>Restore Config (Upload file or paste JSON)</label><input type="file" id="restoreFile" accept=".json,application/json" onchange="loadRestoreFile(event)" style="display:block;margin-bottom:8px;font-size:.8rem;color:var(--text2)"><textarea id="restoreJson" rows="4" placeholder="Or paste backup JSON here..." style="width:100%;background:var(--bg);color:var(--text);border:1px solid var(--card-border);border-radius:8px;padding:8px;font-size:.8rem;resize:vertical;"></textarea></div>
<button class="btn btn-primary btn-sm" onclick="restoreConfig()">Restore Config</button>
</div>
</div>
</div>
</div>
</div>

<!-- About & Sponsor Tab -->
<div class="tab-content" id="tab-about">
<div class="grid" style="grid-template-columns:1fr;">

<!-- Hero Card -->
<div class="card" style="text-align:center;border:1px solid rgba(99,102,241,0.3);">
<div style="display:inline-flex;align-items:center;justify-content:center;width:64px;height:64px;border-radius:18px;background:var(--accent-grad);box-shadow:0 8px 24px rgba(99,102,241,0.4);margin-bottom:14px;">
<svg viewBox="0 0 24 24" width="36" height="36" style="fill:#fff;"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg>
</div>
<h2 style="margin:0;font-size:1.4rem;font-weight:800;letter-spacing:-0.03em;">SmartHome Pro</h2>
<p style="color:var(--text2);font-size:.82rem;margin:6px 0 14px;">Multi-Channel Controller Suite</p>
<div style="display:flex;flex-wrap:wrap;gap:8px;justify-content:center;">
<span class="badge badge-info">v1.0.0 Stable</span>
<span class="badge badge-ok">100% Local-First</span>
<span class="badge" style="background:rgba(59,130,246,0.15);color:var(--blue);border:1px solid rgba(59,130,246,0.3);">Zero Cloud Required</span>
</div>
</div>
</div>

<!-- Sponsor Section Header -->
<div style="display:flex;align-items:center;gap:10px;margin:8px 0 6px;">
<div style="padding:6px;background:rgba(244,63,94,0.15);border-radius:8px;display:flex;align-items:center;justify-content:center;">
<svg viewBox="0 0 24 24" width="16" height="16" style="fill:var(--red);"><path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/></svg>
</div>
<span style="font-size:.78rem;font-weight:800;letter-spacing:0.08em;color:var(--text);">SPONSOR &amp; SUPPORT PROJECT</span>
</div>
<p style="font-size:.8rem;color:var(--text2);line-height:1.5;margin-bottom:14px;">SmartHome is an independent Smart Home & Environmental Monitoring System . If it brings value to your home or maker setups, consider sponsoring to fuel ongoing firmware development, hardware lab testing, and new features!</p>

<div class="grid">

<!-- UPI Card (India) -->
<div class="card" style="border:1px solid rgba(16,185,129,0.35);">
<div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:14px;">
<div style="display:flex;align-items:center;gap:12px;">
<div style="padding:8px;background:rgba(16,185,129,0.12);border-radius:10px;display:flex;align-items:center;justify-content:center;">
<svg viewBox="0 0 24 24" width="22" height="22" style="fill:var(--green);"><path d="M3 11h8V3H3v8zm2-6h4v4H5V5zm8-2v8h8V3h-8zm6 6h-4V5h4v4zM3 21h8v-8H3v8zm2-6h4v4H5v-4zm13-2h-2v4h-4v2h4v4h2v-4h4v-2h-4v-4z"/></svg>
</div>
<div>
<div style="font-size:.95rem;font-weight:700;">India &bull; UPI Payment</div>
<div style="font-size:.72rem;color:var(--text2);">Zero transaction fee &bull; Instant</div>
</div>
</div>
<span class="badge badge-ok">BHIM / UPI</span>
</div>
<div style="background:var(--bg);border:1px solid var(--card-border);border-radius:10px;padding:10px 14px;display:flex;align-items:center;gap:10px;margin-bottom:12px;">
<svg viewBox="0 0 24 24" width="18" height="18" style="fill:var(--green);flex-shrink:0;"><path d="M21 18v1c0 1.1-.9 2-2 2H5c-1.11 0-2-.9-2-2V5c0-1.1.89-2 2-2h14c1.1 0 2 .9 2 2v1h-9c-1.11 0-2 .9-2 2v8c0 1.1.89 2 2 2h9zm-9-2h10V8H12v8zm4-2.5c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5z"/></svg>
<div style="flex:1;">
<div style="font-size:.62rem;font-weight:700;color:var(--text-muted);letter-spacing:0.05em;text-transform:uppercase;">UPI VPA ID</div>
<div style="font-size:1rem;font-weight:800;letter-spacing:0.05em;font-family:monospace;" id="upiIdText">1vikash@ybl</div>
</div>
<button class="btn btn-outline btn-sm" id="btnCopyUpi" onclick="copyAboutText('1vikash@ybl','UPI ID','btnCopyUpi')" title="Copy UPI ID" style="padding:6px 10px;">
<svg viewBox="0 0 24 24" width="16" height="16" style="fill:currentColor;"><path d="M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/></svg>
Copy
</button>
</div>
<div style="display:flex;gap:8px;margin-bottom:12px;">
<button class="btn btn-green" style="flex:1;" onclick="copyAboutText('upi://pay?pa=1vikash@ybl&pn=Vikash%20Choudhary&cu=INR&tn=SmartHome%20Project%20Sponsorship','UPI deep link','btnCopyUpi')">
<svg viewBox="0 0 24 24" width="16" height="16" style="fill:currentColor;"><path d="M7 2v11h3v9l7-12h-4l4-8z"/></svg>
Pay via Any UPI App
</button>
</div>
<div style="display:flex;flex-wrap:wrap;gap:6px;">
<span style="font-size:.68rem;font-weight:600;color:var(--text2);padding:3px 8px;background:var(--bg);border-radius:6px;border:1px solid var(--card-border);">Google Pay</span>
<span style="font-size:.68rem;font-weight:600;color:var(--text2);padding:3px 8px;background:var(--bg);border-radius:6px;border:1px solid var(--card-border);">PhonePe</span>
<span style="font-size:.68rem;font-weight:600;color:var(--text2);padding:3px 8px;background:var(--bg);border-radius:6px;border:1px solid var(--card-border);">Paytm</span>
<span style="font-size:.68rem;font-weight:600;color:var(--text2);padding:3px 8px;background:var(--bg);border-radius:6px;border:1px solid var(--card-border);">BHIM</span>
<span style="font-size:.68rem;font-weight:600;color:var(--text2);padding:3px 8px;background:var(--bg);border-radius:6px;border:1px solid var(--card-border);">Cred</span>
<span style="font-size:.68rem;font-weight:600;color:var(--text2);padding:3px 8px;background:var(--bg);border-radius:6px;border:1px solid var(--card-border);">Amazon Pay</span>
</div>
</div>

<!-- PayPal Card (International) -->
<div class="card" style="border:1px solid rgba(0,112,186,0.4);">
<div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:14px;">
<div style="display:flex;align-items:center;gap:12px;">
<div style="padding:8px;background:rgba(0,112,186,0.15);border-radius:10px;display:flex;align-items:center;justify-content:center;">
<svg viewBox="0 0 24 24" width="22" height="22" style="fill:#38bdf8;"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z"/></svg>
</div>
<div>
<div style="font-size:.95rem;font-weight:700;">International &bull; PayPal</div>
<div style="font-size:.72rem;color:var(--text2);">Global donations &bull; Cards &amp; PayPal balance</div>
</div>
</div>
<span class="badge" style="background:rgba(0,112,186,0.18);color:#38bdf8;border:1px solid rgba(0,112,186,0.4);">Worldwide</span>
</div>
<div style="background:var(--bg);border:1px solid var(--card-border);border-radius:10px;padding:10px 14px;display:flex;align-items:center;gap:10px;margin-bottom:12px;">
<svg viewBox="0 0 24 24" width="18" height="18" style="fill:#38bdf8;flex-shrink:0;"><path d="M3.9 12c0-1.71 1.39-3.1 3.1-3.1h4V7H7c-2.76 0-5 2.24-5 5s2.24 5 5 5h4v-1.9H7c-1.71 0-3.1-1.39-3.1-3.1zM8 13h8v-2H8v2zm9-6h-4v1.9h4c1.71 0 3.1 1.39 3.1 3.1s-1.39 3.1-3.1 3.1h-4V17h4c2.76 0 5-2.24 5-5s-2.24-5-5-5z"/></svg>
<div style="flex:1;">
<div style="font-size:.62rem;font-weight:700;color:var(--text-muted);letter-spacing:0.05em;text-transform:uppercase;">PAYPAL ME LINK</div>
<div style="font-size:.88rem;font-weight:700;">https://paypal.me/1vikash</div>
</div>
<button class="btn btn-outline btn-sm" id="btnCopyPaypal" onclick="copyAboutText('https://paypal.me/1vikash','PayPal link','btnCopyPaypal')" title="Copy PayPal link" style="padding:6px 10px;">
<svg viewBox="0 0 24 24" width="16" height="16" style="fill:currentColor;"><path d="M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/></svg>
Copy
</button>
</div>
<div style="display:flex;gap:8px;">
<a href="https://paypal.me/1vikash" target="_blank" rel="noopener" class="btn btn-primary" style="flex:1;text-decoration:none;">
<svg viewBox="0 0 24 24" width="16" height="16" style="fill:currentColor;"><path d="M19 19H5V5h7V3H5c-1.11 0-2 .9-2 2v14c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2v-7h-2v7zM14 3v2h3.59l-9.83 9.83 1.41 1.41L19 6.41V10h2V3h-7z"/></svg>
Donate via PayPal.Me
</a>
</div>
</div>
</div>

<!-- Features Section -->
<div style="display:flex;align-items:center;gap:10px;margin:8px 0 6px;">
<div style="padding:6px;background:rgba(99,102,241,0.15);border-radius:8px;display:flex;align-items:center;justify-content:center;">
<svg viewBox="0 0 24 24" width="16" height="16" style="fill:var(--accent2);"><path d="M11.99 18.54l-7.37-5.73L3 14.07l9 7 9-7-1.63-1.27-7.38 5.74zM12 16l7.36-5.73L21 9l-9-7-9 7 1.63 1.27L12 16z"/></svg>
</div>
<span style="font-size:.78rem;font-weight:800;letter-spacing:0.08em;color:var(--text);">ARCHITECTURE &amp; KEY CAPABILITIES</span>
</div>

<div class="grid" style="grid-template-columns:1fr;">
<div class="card">
<div style="display:flex;flex-direction:column;gap:16px;">

<div style="display:flex;gap:14px;align-items:flex-start;">
<div style="padding:8px;background:rgba(16,185,129,0.12);border-radius:10px;flex-shrink:0;display:flex;align-items:center;justify-content:center;">
<svg viewBox="0 0 24 24" width="20" height="20" style="fill:var(--green);"><path d="M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm-2 16l-4-4 1.41-1.41L10 14.17l6.59-6.59L18 9l-8 8z"/></svg>
</div>
<div><div style="font-weight:700;font-size:.88rem;">100% Local &amp; Private</div><div style="font-size:.76rem;color:var(--text2);line-height:1.4;margin-top:3px;">Complete operational independence with zero cloud subscriptions, zero telemetry, and zero mandatory external connections.</div></div>
</div>

<div style="border-top:1px solid var(--border);"></div>

<div style="display:flex;gap:14px;align-items:flex-start;">
<div style="padding:8px;background:rgba(99,102,241,0.12);border-radius:10px;flex-shrink:0;display:flex;align-items:center;justify-content:center;">
<svg viewBox="0 0 24 24" width="20" height="20" style="fill:var(--accent2);"><path d="M15 9H9v6h6V9zm-2 4h-2v-2h2v2zm8-2V9h-2V7c0-1.1-.9-2-2-2h-2V3h-2v2h-2V3H9v2H7c-1.1 0-2 .9-2 2v2H3v2h2v2H3v2h2v2c0 1.1.9 2 2 2h2v2h2v-2h2v2h2v-2h2c1.1 0 2-.9 2-2v-2h2v-2h-2v-2h2zm-4 6H7V7h10v10z"/></svg>
</div>
<div><div style="font-weight:700;font-size:.88rem;">Flash-Persistent Automations</div><div style="font-size:.76rem;color:var(--text2);line-height:1.4;margin-top:3px;">Timers and conditional sensor rules execute deterministically on-chip and persist across reboots via LittleFS / Flash.</div></div>
</div>

<div style="border-top:1px solid var(--border);"></div>

<div style="display:flex;gap:14px;align-items:flex-start;">
<div style="padding:8px;background:rgba(139,92,246,0.12);border-radius:10px;flex-shrink:0;display:flex;align-items:center;justify-content:center;">
<svg viewBox="0 0 24 24" width="20" height="20" style="fill:#8b5cf6;"><path d="M16 6l2.29 2.29-4.88 4.88-4-4L2 16.59 3.41 18l6-6 4 4 6.3-6.29L22 12V6z"/></svg>
</div>
<div><div style="font-weight:700;font-size:.88rem;">Custom DIY Pin Matrix</div><div style="font-size:.76rem;color:var(--text2);line-height:1.4;margin-top:3px;">Dynamic pin mapping with boot-glitch prevention, active HIGH/LOW polarity, and real-time pin conflict detection.</div></div>
</div>

<div style="border-top:1px solid var(--border);"></div>

<div style="display:flex;gap:14px;align-items:flex-start;">
<div style="padding:8px;background:rgba(6,182,212,0.12);border-radius:10px;flex-shrink:0;display:flex;align-items:center;justify-content:center;">
<svg viewBox="0 0 24 24" width="20" height="20" style="fill:#06b6d4;"><path d="M15 13V5a3 3 0 00-6 0v8a5 5 0 106 0zm-3-9a1 1 0 011 1v3h-2V5a1 1 0 011-1z"/></svg>
</div>
<div><div style="font-weight:700;font-size:.88rem;">Multi-Sensor Engine</div><div style="font-size:.76rem;color:var(--text2);line-height:1.4;margin-top:3px;">Real-time metrics for DHT11/DHT22 climate, BME280 barometric, MQ-2 gas/smoke, and ultrasonic tank monitoring.</div></div>
</div>

<div style="border-top:1px solid var(--border);"></div>

<div style="display:flex;gap:14px;align-items:flex-start;">
<div style="padding:8px;background:rgba(245,158,11,0.12);border-radius:10px;flex-shrink:0;display:flex;align-items:center;justify-content:center;">
<svg viewBox="0 0 24 24" width="20" height="20" style="fill:var(--orange);"><path d="M20 18.69L7.84 6.14 5.27 3.49 4 4.76l2.8 2.8v.01c-.52.99-.8 2.16-.8 3.43v5l-2 2v1h13.73l2 2L21 19.72l-1-1.03zM12 22c1.11 0 2-.89 2-2h-4c0 1.11.89 2 2 2zm6-7.32V11c0-3.08-1.64-5.64-4.5-6.32V4c0-.83-.67-1.5-1.5-1.5s-1.5.67-1.5 1.5v.68c-.15.03-.29.08-.42.12-.1.03-.2.07-.3.11h-.01c-.01 0-.01 0-.02.01-.23.09-.46.2-.68.31 0 0-.01 0-.01.01L18 14.68z"/></svg>
</div>
<div><div style="font-weight:700;font-size:.88rem;">Safe Over-the-Air (OTA) Updates</div><div style="font-size:.76rem;color:var(--text2);line-height:1.4;margin-top:3px;">Rollback-protected dual partition on ESP32, MD5-verified flash streaming for ESP8266.</div></div>
</div>

</div>
</div>
</div>

<!-- Developer & Repository -->
<div style="display:flex;align-items:center;gap:10px;margin:8px 0 6px;">
<div style="padding:6px;background:rgba(129,140,248,0.15);border-radius:8px;display:flex;align-items:center;justify-content:center;">
<svg viewBox="0 0 24 24" width="16" height="16" style="fill:var(--accent2);"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>
</div>
<span style="font-size:.78rem;font-weight:800;letter-spacing:0.08em;color:var(--text);">DEVELOPER &amp; REPOSITORY</span>
</div>

<div class="grid" style="grid-template-columns:1fr;">
<div class="card">
<div style="display:flex;align-items:center;gap:14px;margin-bottom:14px;">
<div style="width:44px;height:44px;border-radius:50%;background:rgba(99,102,241,0.2);display:flex;align-items:center;justify-content:center;font-weight:700;font-size:1rem;color:var(--accent2);flex-shrink:0;">VC</div>
<div>
<div style="font-weight:700;font-size:.95rem;">Vikash Choudhary</div>
<div style="font-size:.72rem;color:var(--text2);">Project Creator &amp; Embedded Systems Engineer</div>
</div>
</div>
<a href="https://github.com/1VikashChoudhary/SmartHome" target="_blank" rel="noopener" class="btn btn-outline" style="width:100%;text-decoration:none;">
<svg viewBox="0 0 24 24" width="16" height="16" style="fill:currentColor;"><path d="M9.4 16.6L4.8 12l4.6-4.6L8 6l-6 6 6 6 1.4-1.4zm5.2 0l4.6-4.6-4.6-4.6L16 6l6 6-6 6-1.4-1.4z"/></svg>
View Project on GitHub
</a>
</div>
</div>

<!-- Footer -->
<div style="text-align:center;padding:10px 0 4px;">
<div style="font-size:.72rem;font-weight:600;color:var(--text-muted);">SmartHome Pro</div>
<div style="font-size:.66rem;color:var(--text-muted);margin-top:3px;">Smart Home & Environmental Monitoring System</div>
</div>

</div>

<!-- Alarm Add/Edit Modal -->
<div class="alarm-modal" id="alarmModal">
<div class="alarm-box">
<h3 id="alarmModalTitle">Add Timer</h3>
<input type="hidden" id="alarmEditId" value="0">
<div class="form-group"><label>Timer Mode</label>
<select id="alarmMode">
<option value="0">At fixed time</option>
<option value="1">After delay</option>
</select></div>
<div id="clockFields">
<div class="form-row">
<div class="form-group"><label>Hour</label>
<select id="alarmHour12">
<option value="1">1</option><option value="2">2</option><option value="3">3</option><option value="4">4</option>
<option value="5">5</option><option value="6">6</option><option value="7">7</option><option value="8" selected>8</option>
<option value="9">9</option><option value="10">10</option><option value="11">11</option><option value="12">12</option>
</select></div>
<div class="form-group"><label>Minute</label><select id="alarmMin12"></select></div>
</div>
<div class="form-group"><label>AM / PM</label>
<select id="alarmAmPm"><option value="AM">AM</option><option value="PM">PM</option></select></div>
<div class="form-group"><label>Schedule Type</label>
<select id="alarmType"><option value="0">Once</option><option value="1">Daily</option><option value="2">Weekly</option><option value="3">Weekdays</option><option value="4">Weekends</option></select></div>
<div class="form-group" id="dowGroup" style="display:none"><label>Day of Week</label>
<select id="alarmDow"><option value="0">Sunday</option><option value="1">Monday</option><option value="2">Tuesday</option><option value="3">Wednesday</option><option value="4">Thursday</option><option value="5">Friday</option><option value="6">Saturday</option></select></div>
</div>
<div id="delayFields" style="display:none">
<div style="font-size:0.75rem;color:var(--text2);margin-bottom:6px">Quick Presets:</div>
<div style="display:flex;gap:6px;flex-wrap:wrap;margin-bottom:10px">
<button type="button" class="btn btn-outline btn-sm" onclick="setAlarmDelayPreset(5)">5m</button>
<button type="button" class="btn btn-outline btn-sm" onclick="setAlarmDelayPreset(10)">10m</button>
<button type="button" class="btn btn-outline btn-sm" onclick="setAlarmDelayPreset(30)">30m</button>
<button type="button" class="btn btn-outline btn-sm" onclick="setAlarmDelayPreset(60)">1h</button>
<button type="button" class="btn btn-outline btn-sm" onclick="setAlarmDelayPreset(120)">2h</button>
</div>
<div class="form-row">
<div class="form-group"><label>After Hours</label><input type="number" id="alarmDelayHours" min="0" max="168" value="0"></div>
<div class="form-group"><label>After Minutes</label><input type="number" id="alarmDelayMinutes" min="0" max="59" value="30"></div>
</div>
</div>
<div class="form-group"><label>Action</label>
<select id="alarmAction" onchange="updateAlarmActionFields()"><option value="0">Relay ON</option><option value="1">Relay OFF</option><option value="2">Relay Toggle</option><option value="3">Buzzer</option><option value="4">All Relays ON</option><option value="5">All Relays OFF</option></select></div>
<div class="form-group" id="alarmRelayGroup"><label>Target Relay</label>
<select id="alarmRelay"><option value="0">Relay 1</option><option value="1">Relay 2</option><option value="2">Relay 3</option><option value="3">Relay 4</option><option value="4">Relay 5</option><option value="255">All</option></select></div>
<div style="display:flex;gap:8px;margin-top:16px">
<button class="btn btn-primary" onclick="saveAlarm()">Save</button>
<button class="btn btn-outline" onclick="closeAlarmModal()">Cancel</button>
</div>
</div>
</div>

<!-- Relay Config Modal -->
<div class="alarm-modal" id="relayConfigModal">
<div class="alarm-box">
<h3>Relay Settings</h3>
<input type="hidden" id="relayConfigId" value="0">
<div class="form-group"><label>Relay Name</label>
<input type="text" id="relayConfigName" maxlength="19"></div>
<div class="form-row">
<div class="form-group"><label>Trigger Mode</label>
<select id="relayConfigTrigger">
<option value="0">Active LOW (Default)</option>
<option value="1">Active HIGH</option>
</select></div>
<div class="form-group"><label>Boot State</label>
<select id="relayConfigBoot">
<option value="0">Restore last state</option>
<option value="1">Always ON</option>
<option value="2">Always OFF</option>
</select></div>
</div>
<div class="form-row">
<div class="form-group"><label>Auto-OFF (minutes, 0=disabled)</label>
<input type="number" id="relayConfigAutoOff" min="0" max="1440" value="0"></div>
<div class="form-group"><label>Auto-ON (minutes, 0=disabled)</label>
<input type="number" id="relayConfigAutoOn" min="0" max="1440" value="0"></div>
</div>
<div class="form-group"><label>Failsafe (Turn OFF on sensor failure)</label>
<select id="relayConfigFailsafe">
<option value="0">Disabled</option>
<option value="1">Enabled</option>
</select></div>
<div style="display:flex;gap:8px;margin-top:16px">
<button class="btn btn-primary" onclick="saveRelayConfig()">Save</button>
<button class="btn btn-outline" onclick="closeRelayConfigModal()">Cancel</button>
</div>
</div>
</div>

<!-- Quick Timer Modal -->
<div class="alarm-modal" id="quickTimerModal">
<div class="alarm-box">
<h3 id="quickTimerTitle">Relay Timer</h3>
<input type="hidden" id="quickTimerRelayId" value="0">
<div style="font-size:0.8rem;color:var(--text2);margin-bottom:8px;">Quick Presets:</div>
<div style="display:flex;gap:6px;flex-wrap:wrap;margin-bottom:14px;">
<button type="button" class="btn btn-outline btn-sm" onclick="setTimerPreset(5)">5m</button>
<button type="button" class="btn btn-outline btn-sm" onclick="setTimerPreset(10)">10m</button>
<button type="button" class="btn btn-outline btn-sm" onclick="setTimerPreset(30)">30m</button>
<button type="button" class="btn btn-outline btn-sm" onclick="setTimerPreset(60)">1h</button>
<button type="button" class="btn btn-outline btn-sm" onclick="setTimerPreset(120)">2h</button>
</div>
<div class="form-row">
<div class="form-group"><label>Hours</label><input type="number" id="quickTimerHours" min="0" max="72" value="0"></div>
<div class="form-group"><label>Minutes</label><input type="number" id="quickTimerMinutes" min="0" max="59" value="10"></div>
</div>
<div class="form-group"><label>Action when timer expires</label>
<select id="quickTimerAction">
<option value="off">Auto Turn OFF</option>
<option value="on">Auto Turn ON</option>
</select></div>
<div style="display:flex;gap:8px;margin-top:16px">
<button class="btn btn-primary" onclick="startRelayTimer()">Start Timer</button>
<button class="btn btn-outline" onclick="closeQuickTimerModal()">Cancel</button>
</div>
</div>
</div>

<!-- Rule Modal -->
<div class="alarm-modal" id="ruleModal">
<div class="alarm-box">
<h3 id="ruleModalTitle">Add Automation Rule</h3>
<input type="hidden" id="ruleEditId" value="0">
<div class="form-group"><label>Rule Name</label>
<input type="text" id="ruleName" maxlength="23" placeholder="e.g. Fan on High Temp"></div>
<div class="form-row">
<div class="form-group"><label>Sensor</label>
<select id="ruleSensor" onchange="updateRuleSensorFields()">
<option value="0">Temperature (&deg;C)</option>
<option value="1">Humidity (%)</option>
<option value="2">Gas Sensor (MQ2 ADC)</option>
<option value="3">Ambient Light (Lux)</option>
<option value="4">Water Probe Temp (&deg;C)</option>
<option value="5">Water Tank Level (%)</option>
<option value="6">Motion / Occupancy (1/0)</option>
</select></div>
<div class="form-group"><label>Condition</label>
<select id="ruleCondition" onchange="onRuleConditionChange()">
<option value="0">Rises Above (&gt;=)</option>
<option value="1">Falls Below (&lt;=)</option>
</select></div>
</div>
<div class="form-group" id="ruleSensorIdxGroup"><label>Sensor Instance</label>
<select id="ruleSensorIdx"></select></div>
<div class="form-row">
<div class="form-group"><label>Threshold Value</label>
<input type="number" step="0.5" id="ruleThreshold" value="30.0"></div>
<div class="form-group"><label>Hysteresis (Anti-flapping)</label>
<input type="number" step="0.1" id="ruleHysteresis" value="0.5"></div>
</div>
<div class="form-row">
<div class="form-group"><label>Target Relay</label>
<select id="ruleTargetRelay"></select></div>
<div class="form-group"><label>Action</label>
<select id="ruleAction">
<option value="0">Turn Relay ON</option>
<option value="1">Turn Relay OFF</option>
</select></div>
</div>
<div style="display:flex;gap:8px;margin-top:16px">
<button class="btn btn-primary" onclick="saveRule()">Save Rule</button>
<button class="btn btn-outline" onclick="closeRuleModal()">Cancel</button>
</div>
</div>
</div>

<div class="toast-container" id="toasts"></div>

<script>
function escapeHtml(s){if(s===null||s===undefined)return '';return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');}
let ws,wsData={},alarmCache=[],theme=localStorage.getItem('theme')||'dark',webPassSet=false,wsToken='',gAuthRole='admin';
if(theme==='light')document.body.classList.add('light');

// Theme
function toggleTheme(){
document.body.classList.toggle('light');
theme=document.body.classList.contains('light')?'light':'dark';
localStorage.setItem('theme',theme);
}
function doLogout(){
if(!confirm('Log out of SmartHome? You will be prompted to sign in again.')) return;
const xhr = new XMLHttpRequest();
xhr.open('GET', '/api/logout', true, 'logout_' + Date.now(), 'logout_nonce');
xhr.onreadystatechange = function(){
if(xhr.readyState === 4){
try { sessionStorage.clear(); localStorage.removeItem('smarthome_ws_token'); } catch(e){}
window.location.href = '/logout';
}
};
xhr.onerror = function(){
window.location.href = '/logout';
};
xhr.send();
}

// Tabs
function showTab(id){
document.querySelectorAll('.tab').forEach(t=>t.classList.toggle('active',(t.getAttribute('onclick')||'').includes(`'${id}'`)));
document.querySelectorAll('.tab-content').forEach(t=>t.classList.remove('active'));
const el=document.getElementById('tab-'+id);
if(el)el.classList.add('active');
if(id==='logs')refreshLogs();
if(id==='system')loadDiag();
if(id==='settings'||id==='sensors')loadSettings();
if(id==='hardware')loadHardware();
if(id==='alarms')loadAlarms();
if(id==='rules')loadRules();
}

// Toast
function toast(msg,level='info'){
const d=document.createElement('div');
d.className='toast toast-'+level;
d.textContent=msg;
document.getElementById('toasts').appendChild(d);
setTimeout(()=>d.remove(),4000);
}

// Copy to clipboard (About tab)
function copyAboutText(text,label,btnId){
navigator.clipboard.writeText(text).then(()=>{
toast(label+' copied to clipboard!','ok');
const btn=document.getElementById(btnId);
if(btn){const orig=btn.innerHTML;btn.innerHTML='<svg viewBox="0 0 24 24" width="16" height="16" style="fill:var(--green);"><path d="M9 16.2L4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4L9 16.2z"/></svg> Copied';setTimeout(()=>{btn.innerHTML=orig;},3000);}
}).catch(()=>{toast('Copy failed','err');});
}

// WebSocket
function sendWsSubscribe(){
if(ws&&ws.readyState===1){
ws.send(JSON.stringify({type:'subscribe',stream:'status',interval_ms:5000,token:wsToken}));
}
}
function initWS(){
const proto=location.protocol==='https:'?'wss:':'ws:';
ws=new WebSocket(proto+'//'+location.host+'/ws');
ws.onopen=()=>{console.log('WS connected');sendWsSubscribe();};
ws.onclose=()=>{console.log('WS closed');setTimeout(initWS,3000);};
ws.onerror=()=>ws.close();
ws.onmessage=(e)=>{
try{
const d=JSON.parse(e.data);
if(d.type==='auth_error'){
fetch('/api/config').then(r=>r.ok?r.json():null).then(cfg=>{
if(cfg){if(cfg.auth_role){gAuthRole=cfg.auth_role;applyRoleUI();}if(cfg.ws_token){wsToken=cfg.ws_token;sendWsSubscribe();}}
}).catch(()=>{});
return;
}
if(d.type==='toast'){toast(d.msg,d.level);return;}
if(d.type==='relay'){updateSingleRelay(d.id,d.state);return;}
if(d.type==='relay_timer'){
if(wsData&&wsData.relays&&wsData.relays[d.id]){
wsData.relays[d.id].timer_active=d.timer_active;
wsData.relays[d.id].timer_target=d.timer_target;
wsData.relays[d.id].timer_remaining=d.timer_remaining;
renderRelays(wsData.relays);
}
return;
}
if(d.type==='alarm'){if(d.active)toast('\u26A0 '+d.alarm+' alarm!','err');return;}
wsData=d;updateDashboard(d);
}catch(ex){}
};
}

function applyRoleUI(){
const isGuest=(gAuthRole==='guest');
document.querySelectorAll('.admin-only').forEach(el=>{el.style.display=isGuest?'none':'';});
const rb=document.getElementById('roleBadge');if(rb)rb.style.display=isGuest?'inline-block':'none';
const lo=document.getElementById('linkOtaUpdate');if(lo)lo.style.display=isGuest?'none':'inline-flex';
const ts=document.getElementById('tabNavSettings');if(ts)ts.style.display=isGuest?'none':'inline-flex';
const th=document.getElementById('tabNavHardware');if(th)th.style.display=isGuest?'none':'inline-flex';
const ty=document.getElementById('tabNavSystem');if(ty)ty.style.display=isGuest?'none':'inline-flex';
}

// Update dashboard from WS data
function updateDashboard(d){
if(d.auth_required){
const blo=document.getElementById('btnLogOut');if(blo)blo.style.display='inline-flex';
}
if(d.auth_role)gAuthRole=d.auth_role;
applyRoleUI();
setText('wifiStatus',d.wifi_state||'--');
setText('rssi',(d.rssi!==undefined&&d.rssi!==null)?d.rssi:'--');
setText('signal',(d.signal!==undefined&&d.signal!==null)?d.signal:'--');
setText('ipAddr',d.ip||'--');
setText('hostname',d.hostname||'--');
setText('mqttStatus',d.mqtt_state||'--');
setText('uptime',d.uptime||'--');
setText('heap',d.free_heap?Math.round(d.free_heap/1024):'--');
setText('datetime',d.datetime||'--');
setText('devName',d.device_name||'SmartHome');
setText('fwVer','v'+(d.fw_version||'1.0.0'));
document.title=(d.device_name||'SmartHome')+' Dashboard';

// WiFi badge
const wb=document.getElementById('wifiBadge');
const wifiStateStr=d.wifi_state||'Disconnected';
if(wifiStateStr==='Connected'){wb.className='badge badge-ok';wb.innerHTML='<span class="pulse">&#9679;</span> Connected';}
else{wb.className='badge badge-err';wb.innerHTML='&#9679; '+escapeHtml(wifiStateStr);}

function isCustomSensorLabel(lbl,prefix){
if(!lbl)return false;
const s=String(lbl).trim();
if(!s)return false;
return !new RegExp('^'+prefix+'(\\s*#?\\d+)?$','i').test(s);
}

// Active multi-instance sensor slices
const activeClimates=(d.climates||[]).filter(c=>c&&c.enabled);
const activeLights=(d.lights||[]).filter(l=>l&&l.enabled);
const activeMotions=(d.motions||[]).filter(m=>m&&m.enabled);
const activeProbes=(d.probes||[]).filter(p=>p&&p.enabled);
const activeTanks=(d.tanks||[]).filter(t=>t&&t.enabled);
const activeMq2s=(d.mq2s||[]).filter(g=>g&&(g.enabled||g.hw_allowed));

// Temperature & humidity
const cliEn=(d.dht_enabled!==false);
const cardT=document.getElementById('cardTemp');if(cardT)cardT.style.display=cliEn?'block':'none';
const cardH=document.getElementById('cardHum');if(cardH)cardH.style.display=cliEn?'block':'none';
const sCliCard=document.getElementById('sensorClimateCard');if(sCliCard)sCliCard.style.display=cliEn?'block':'none';
if(!cliEn){
setText('temp','--');setText('temp2','--');
setText('hum','--');setText('hum2','--');
const ds=document.getElementById('dhtStatus');
if(ds){ds.className='badge badge-info';setText('dhtStatus','Disabled');}
}else{
const primaryCliFault=activeClimates.length>0?!!activeClimates[0].fault:!!d.dht_fault;
const pTemp=activeClimates.length>0?parseFloat(activeClimates[0].temperature):parseFloat(d.temperature);
const pHum=activeClimates.length>0?parseFloat(activeClimates[0].humidity):parseFloat(d.humidity);
const hasCliRead=(!isNaN(pTemp)&&pTemp!==0)||(!isNaN(pHum)&&pHum>0);
if(primaryCliFault){
setText('temp','ERR');setText('temp2','ERR');
setText('hum','ERR');setText('hum2','ERR');
}else if(hasCliRead){
setText('temp',pTemp.toFixed(1));setText('temp2',pTemp.toFixed(1));
setText('hum',pHum.toFixed(1));setText('hum2',pHum.toFixed(1));
}else{
setText('temp','--');setText('temp2','--');
setText('hum','--');setText('hum2','--');
}
const ds=document.getElementById('dhtStatus');
if(ds){
if(primaryCliFault){ds.className='badge badge-err';setText('dhtStatus','FAULT');}
else{ds.className='badge badge-ok';setText('dhtStatus','OK');}
}
const cliCustom=activeClimates.length>=1&&isCustomSensorLabel(activeClimates[0].label,'Climate');
setText('lblTemp',cliCustom?(activeClimates[0].label+' Temp'):'Temperature');
setText('lblHum',cliCustom?(activeClimates[0].label+' Humidity'):'Humidity');
const sCliTitle=document.getElementById('sensorClimateTitle');
if(sCliTitle)sCliTitle.textContent=cliCustom?('Climate \u2014 '+activeClimates[0].label):'Climate \u2014 Temperature & Humidity';
}
setText('tempTh',d.temp_threshold||'45');

// Additional Telemetry
const showPressure=!!(cliEn&&d.pressure_enabled&&d.pressure!==undefined&&parseFloat(d.pressure)>300);
const cp=document.getElementById('cardPressure');if(cp)cp.style.display=showPressure?'block':'none';
if(showPressure){
setText('pressure',parseFloat(d.pressure).toFixed(1));
const activeBaro=activeClimates.find(c=>c.barometer);
setText('lblPressure',(activeBaro&&isCustomSensorLabel(activeBaro.label,'Climate'))?(activeBaro.label+' Baro'):'Barometer');
}

const showLux=(d.lux!==undefined&&d.lux_enabled!==false);
const cl=document.getElementById('cardLux');if(cl)cl.style.display=showLux?'block':'none';
if(showLux){
setText('lux',parseFloat(d.lux).toFixed(1));
const luxCustom=activeLights.length>=1&&isCustomSensorLabel(activeLights[0].label,'Light');
setText('lblLux',luxCustom?activeLights[0].label:'Ambient Lux');
}

const pGaugeRow=document.getElementById('primaryGaugeRow');
if(pGaugeRow)pGaugeRow.style.display=(cliEn||showPressure||showLux)?'':'none';

const showMotion=(d.motion!==undefined&&d.motion_enabled!==false);
const rm=document.getElementById('rowMotion');if(rm)rm.style.display=showMotion?'flex':'none';
if(showMotion){
const motCustom=activeMotions.length>=1&&isCustomSensorLabel(activeMotions[0].label,'Motion');
setText('lblMotion',motCustom?activeMotions[0].label:'Motion Occupancy');
const mb=document.getElementById('motionBadge');
if(mb){
mb.className=d.motion?'badge badge-err':'badge badge-ok';
mb.textContent=d.motion?'Motion Detected':(d.motion_age_s<3600?d.motion_age_s+'s ago':'Clear');
}
}

const showProbe=(d.probe_enabled!==false)&&((d.probe_temp!==undefined&&parseFloat(d.probe_temp)>-55)||!!d.probe_fault);
const rp=document.getElementById('rowProbe');if(rp)rp.style.display=showProbe?'flex':'none';
if(showProbe){
const prbCustom=activeProbes.length>=1&&isCustomSensorLabel(activeProbes[0].label,'Probe');
setText('lblProbe',prbCustom?activeProbes[0].label:'Water Temp Probe');
const pw=document.getElementById('probeValWrap');
if(pw){
if(d.probe_fault){pw.innerHTML='<span class="badge badge-err">FAULT</span>';}
else{pw.innerHTML='<span id="probeTemp">'+parseFloat(d.probe_temp).toFixed(1)+'</span>&deg;C';}
}
}

const showTank=(d.tank_level_pct!==undefined&&d.tank_enabled!==false);
const tw=document.getElementById('tankWidget');if(tw)tw.style.display=showTank?'block':'none';
if(showTank){
const hasAboveTank=cliEn||showPressure||showLux||showMotion||showProbe;
if(tw){
tw.style.borderTop=hasAboveTank?'1px solid var(--card-border)':'none';
tw.style.paddingTop=hasAboveTank?'10px':'0';
tw.style.marginTop=hasAboveTank?'12px':'0';
}
const tnkCustom=activeTanks.length>=1&&isCustomSensorLabel(activeTanks[0].label,'Tank');
setText('lblTank',tnkCustom?activeTanks[0].label:'Overhead Water Tank');
setText('tankPct',d.tank_level_pct);
setText('tankDist',(d.distance_cm!==undefined)?d.distance_cm:'--');
const tb=document.getElementById('tankBar');
if(tb){
tb.style.width=Math.min(100,Math.max(0,d.tank_level_pct))+'%';
tb.style.background=d.tank_level_pct<20?'#ef4444':(d.tank_level_pct>80?'#10b981':'#06b6d4');
}
}

// Gas
const hasMq2=(d.gas_enabled===true)||(d.gas_hw_allowed===true)||activeMq2s.length>0;
const gw=document.getElementById('gasWidget');
if(gw){
gw.style.display=hasMq2?'block':'none';
gw.style.marginTop=(cliEn||showPressure||showLux||showMotion||showProbe||showTank)?'12px':'0';
}
const sMq2Card=document.getElementById('sensorMq2Card');if(sMq2Card)sMq2Card.style.display=hasMq2?'block':'none';
const sPriGrid=document.getElementById('sensorPrimaryGrid');if(sPriGrid)sPriGrid.style.display=(cliEn||hasMq2)?'':'none';
if(hasMq2){
const gasCustom=activeMq2s.length>=1&&isCustomSensorLabel(activeMq2s[0].label,'Gas');
setText('lblGas',gasCustom?(activeMq2s[0].label+' (Gas)'):'Gas Level');
const sMq2Title=document.getElementById('sensorMq2Title');
if(sMq2Title)sMq2Title.textContent=gasCustom?('MQ2 \u2014 '+activeMq2s[0].label):'MQ2 \u2014 Gas Sensor';
}
if(hasMq2&&d.gas_raw!==undefined){
const gasMax=d.gas_max||(d.platform==='ESP8266'?1023:4095);
const gUnit=document.getElementById('gasMaxUnit');if(gUnit)gUnit.textContent=' /'+gasMax;
const gLbl=document.getElementById('gasThLabel');if(gLbl)gLbl.textContent='Alarm Threshold (0-'+gasMax+')';
const gSlider=document.getElementById('gasThSlider');if(gSlider){gSlider.min=10;if(gSlider.max!==String(gasMax)){gSlider.max=gasMax;}}
setText('gasRaw',d.gas_raw);setText('gasVal',d.gas_raw);
setText('gasPct',d.gas_percent||0);
const pct=Math.min(100,Math.round(d.gas_raw/gasMax*100));
const bar=document.getElementById('gasBar');
const bar2=document.getElementById('gasBar2');
if(bar)bar.style.width=pct+'%';if(bar2)bar2.style.width=pct+'%';
if(d.gas_alarm){if(bar)bar.className='gas-bar danger';if(bar2)bar2.className='gas-bar danger';}
else{if(bar)bar.className='gas-bar';if(bar2)bar2.className='gas-bar';}
const thPct=(d.gas_threshold||400)/gasMax*100;
const thLine1=document.getElementById('gasThLine');if(thLine1)thLine1.style.left=thPct+'%';
const thLine2=document.getElementById('gasThLine2');if(thLine2)thLine2.style.left=thPct+'%';
setText('gasTh',d.gas_threshold!==undefined?d.gas_threshold:(gIsEsp8266?100:400));
const gb=document.getElementById('gasBadge');
if(gb){
if(d.gas_enabled===false){gb.className='badge badge-info';gb.textContent='Disabled';}
else if(d.gas_warming){gb.className='badge badge-warn';gb.textContent='Warming';}
else if(d.gas_alarm){gb.className='badge badge-err';gb.textContent='DANGER';}
else{gb.className='badge badge-ok';gb.textContent='Safe';}
}
setText('gasStat',d.gas_enabled===false?'Disabled':(d.gas_alarm?'DANGER':'Safe'));
const gwBadge=document.getElementById('gasWarm');
setText('gasWarm',d.gas_enabled===false?'Off':(d.gas_warming?'Yes':'No'));
if(gwBadge)gwBadge.className='badge '+(d.gas_enabled===false?'badge-info':(d.gas_warming?'badge-warn':'badge-ok'));
}

const anySensorActive=cliEn||showPressure||showLux||showMotion||showProbe||showTank||hasMq2;
const nsDash=document.getElementById('noSensorsState');
if(nsDash)nsDash.style.display=anySensorActive?'none':'block';

renderMultiSensors(d,cliEn,hasMq2);

// Relays
if(d.relays){renderRelays(d.relays);}
}

function renderMultiSensors(d,cliEn,hasMq2){
const wrap=document.getElementById('multiSensorsWrap');
const grid=document.getElementById('multiSensorCardsWrap');
const chips=[];
const cards=[];
const climates=(d.climates||[]).filter(c=>c&&c.enabled);
if(climates.length>1){
climates.forEach(c=>{
const nm=escapeHtml(c.label||('Climate #'+(c.index+1)));
const val=c.fault?'FAULT':(parseFloat(c.temperature||0).toFixed(1)+'°C / '+parseFloat(c.humidity||0).toFixed(1)+'%'+(c.barometer?(' / '+parseFloat(c.pressure||0).toFixed(0)+' hPa'):''));
const baroGauge=c.barometer?`<div class="gauge"><div class="gauge-value">${c.fault?'--':parseFloat(c.pressure||0).toFixed(0)}<span class="gauge-unit">hPa</span></div><div class="gauge-label">Pressure</div></div>`:'';
chips.push(`<span><b>${nm}:</b> ${val}</span>`);
cards.push(`<div class="card"><div class="card-title">${nm} <span class="badge ${c.fault?'badge-err':'badge-ok'}">${escapeHtml(c.type_name||'Climate')}</span></div><div class="gauge-row"><div class="gauge"><div class="gauge-value">${c.fault?'--':parseFloat(c.temperature||0).toFixed(1)}<span class="gauge-unit">&deg;C</span></div><div class="gauge-label">Temperature</div></div><div class="gauge"><div class="gauge-value">${c.fault?'--':parseFloat(c.humidity||0).toFixed(1)}<span class="gauge-unit">%</span></div><div class="gauge-label">Humidity</div></div>${baroGauge}</div></div>`);
});
}
const lights=(d.lights||[]).filter(l=>l&&l.enabled);
if(lights.length>0){
lights.forEach(l=>{
const nm=(lights.length===1&&!isCustomSensorLabel(l.label,'Light'))?'Ambient Light Sensor':escapeHtml(l.label||('Light #'+(l.index+1)));
if(lights.length>1)chips.push(`<span><b>${nm}:</b> ${parseFloat(l.lux||0).toFixed(1)} lx</span>`);
cards.push(`<div class="card"><div class="card-title">${nm} <span class="badge badge-ok">0x${(l.i2c_addr||35).toString(16).toUpperCase()}</span></div><div class="gauge"><div class="gauge-value">${parseFloat(l.lux||0).toFixed(1)}<span class="gauge-unit">lx</span></div><div class="gauge-label">Ambient Illuminance</div></div></div>`);
});
}
const motions=(d.motions||[]).filter(m=>m&&m.enabled);
if(motions.length>0){
motions.forEach(m=>{
const nm=(motions.length===1&&!isCustomSensorLabel(m.label,'Motion'))?'Motion / Radar Occupancy':escapeHtml(m.label||('Motion #'+(m.index+1)));
const st=m.detected?'DETECTED':(m.age_s<3600?(m.age_s+'s ago'):'Clear');
if(motions.length>1)chips.push(`<span><b>${nm}:</b> <span class="badge ${m.detected?'badge-err':'badge-ok'}">${st}</span></span>`);
cards.push(`<div class="card"><div class="card-title">${nm} <span class="badge ${m.detected?'badge-err':'badge-ok'}">${st}</span></div></div>`);
});
}
const probes=(d.probes||[]).filter(p=>p&&p.enabled);
if(probes.length>0){
probes.forEach(p=>{
const nm=(probes.length===1&&!isCustomSensorLabel(p.label,'Probe'))?'Water Temp Probe':escapeHtml(p.label||('Probe #'+(p.index+1)));
const pTemp=parseFloat(p.temperature||-127);
const val=p.fault?'FAULT':(pTemp>-55?(pTemp.toFixed(1)+'°C'):'--');
if(probes.length>1)chips.push(`<span><b>${nm}:</b> ${val}</span>`);
cards.push(`<div class="card"><div class="card-title">${nm} <span class="badge ${p.fault?'badge-err':'badge-ok'}">${val}</span></div></div>`);
});
}
const tanks=(d.tanks||[]).filter(t=>t&&t.enabled);
if(tanks.length>0){
tanks.forEach(t=>{
const nm=(tanks.length===1&&!isCustomSensorLabel(t.label,'Tank'))?'Overhead Water Tank':escapeHtml(t.label||('Tank #'+(t.index+1)));
if(tanks.length>1)chips.push(`<span><b>${nm}:</b> ${t.level_pct||0}% (${t.distance_cm||0} cm)</span>`);
cards.push(`<div class="card"><div class="card-title">${nm}</div><div class="gauge"><div class="gauge-value">${t.level_pct||0}<span class="gauge-unit">%</span></div><div class="gauge-label">${t.distance_cm||0} cm</div></div></div>`);
});
}
const mq2s=(d.mq2s||[]).filter(g=>g&&(g.enabled||g.hw_allowed));
if(mq2s.length>1){
mq2s.forEach(g=>{
const nm=escapeHtml(g.label||('Gas #'+(g.index+1)));
const st=!g.enabled?'Disabled':(g.warming?'Warming':(g.alarm?'DANGER':'Safe'));
const bCls=!g.enabled?'badge-info':(g.alarm?'badge-err':(g.warming?'badge-warn':'badge-ok'));
chips.push(`<span><b>${nm}:</b> ${g.raw||0} <span class="badge ${bCls}">${st}</span></span>`);
cards.push(`<div class="card"><div class="card-title">${nm} <span class="badge ${bCls}">${st}</span></div><div class="gauge"><div class="gauge-value">${g.raw||0}<span class="gauge-unit"> (${g.percent||0}%)</span></div><div class="gauge-label">Threshold: ${g.threshold||0}</div></div></div>`);
});
}
if(wrap){
wrap.style.display=chips.length?'block':'none';
wrap.innerHTML=chips.length?('<div style="font-size:0.74rem;color:var(--text2);margin-bottom:6px;font-weight:600;">All Active Sensor Slots</div><div style="display:flex;flex-wrap:wrap;gap:10px;font-size:0.78rem;">'+chips.join('')+'</div>'):'';
}
if(grid){
grid.style.display=cards.length?'block':'none';
grid.style.marginTop=(cliEn||hasMq2)?'14px':'0';
grid.innerHTML=cards.length?('<div class="grid">'+cards.join('')+'</div>'):'';
}
const nsTab=document.getElementById('noSensorsTabState');
if(nsTab)nsTab.style.display=(!cliEn&&!hasMq2&&cards.length===0)?'block':'none';
}

// Render relay grid
function renderRelays(relays){
const isGuest=(gAuthRole==='guest');
let html='',detailHtml='';
relays.forEach((r,i)=>{
const isEn=(r.enabled!==false);
const on=isEn&&r.state;
const hasTimer=isEn&&r.timer_active&&(r.timer_remaining>0);
if(isEn){
html+=`<div class="relay-card ${on?'on':'off'}" onclick="toggleRelay(${i})">
<div class="r-name">${escapeHtml(r.name)}</div>
<div class="r-state">${on?'ON':'OFF'}</div>
${hasTimer?`<div style="font-size:.68rem;padding:2px 6px;border-radius:6px;background:rgba(99,102,241,0.25);color:#818cf8;margin-top:4px;display:inline-block">⏱️ ${r.timer_target?'ON':'OFF'} in ${formatSeconds(r.timer_remaining)}</div>`:''}
<div class="toggle ${on?'on':''}"></div></div>`;
}

if(isEn){
detailHtml+=`<div style="display:flex;align-items:center;gap:12px;padding:12px;background:var(--bg);border-radius:12px;margin-bottom:8px;border:1px solid ${on?'var(--green)':'var(--card-border)'}">
<div style="flex:1">
<div style="font-weight:600;margin-bottom:4px">${escapeHtml(r.name)} <span class="badge ${on?'badge-ok':'badge-err'}">${on?'ON':'OFF'}</span></div>
<div style="font-size:.72rem;color:var(--text2)">Trigger: ${r.trigger==0?'Active LOW':'Active HIGH'} | Boot: ${['Restore','Always ON','Always OFF'][r.boot]||'Restore'} | Wall Switch: ${r.switch_enabled===false?'Disabled':'Enabled'}</div>
${hasTimer?`<div style="margin-top:6px;display:flex;align-items:center;gap:6px">
<span class="badge" style="background:rgba(99,102,241,0.25);color:#818cf8;border:1px solid rgba(99,102,241,0.4)">⏱️ Auto ${r.timer_target?'ON':'OFF'} in ${formatSeconds(r.timer_remaining)}</span>
<button class="btn btn-sm btn-outline" style="padding:2px 8px;font-size:0.7rem;border-color:var(--red);color:var(--red)" onclick="cancelRelayTimer(${i})">Cancel</button>
</div>`:''}
</div>
<div style="display:flex;gap:6px">
<button class="btn btn-sm ${on?'btn-red':'btn-green'}" onclick="toggleRelay(${i})">${on?'Turn OFF':'Turn ON'}</button>
<button class="btn btn-sm btn-outline" onclick="openQuickTimer(${i})">⏱️ Timer</button>
${isGuest?'':`<button class="btn btn-sm btn-outline" onclick="configRelay(${i})">Config</button>`}
</div></div>`;
}else{
detailHtml+=`<div style="display:flex;align-items:center;gap:12px;padding:12px;background:var(--bg);border-radius:12px;margin-bottom:8px;border:1px dashed var(--card-border);opacity:0.65">
<div style="flex:1">
<div style="font-weight:600;margin-bottom:4px">${escapeHtml(r.name)} <span class="badge badge-info">DISABLED (Unused)</span></div>
<div style="font-size:.72rem;color:var(--text2)">Channel ${i+1} is disabled in Hardware Profile &mdash; GPIO pins are released</div>
</div>
<div style="display:flex;gap:6px">
${isGuest?'':`<button class="btn btn-sm btn-outline" onclick="document.getElementById('tabNavHardware')?.click()">Enable in Hardware</button>`}
</div></div>`;
}
});
if(!html){
html='<div style="grid-column:1/-1;color:var(--text2);padding:16px;text-align:center;background:var(--bg);border-radius:10px;border:1px dashed var(--card-border)">No active relay channels enabled. Enable channels in the <b>Hardware</b> tab.</div>';
}
const rg=document.getElementById('relayGrid');
if(rg)rg.innerHTML=html;
const rdg=document.getElementById('relayDetailGrid');
if(rdg)rdg.innerHTML=detailHtml;
}

function updateSingleRelay(id,state){
if(wsData.relays&&wsData.relays[id]){wsData.relays[id].state=state;}
if(wsData.relays)renderRelays(wsData.relays);
}

// API calls
function api(method,url,data){
const opts={method,headers:{'Content-Type':'application/json','X-Requested-With':'SmartHome'}};
if(data)opts.body=JSON.stringify(data);
return fetch(url,opts).then(async r=>{
const payload=await r.json();
if(!r.ok||payload.status==='error'){
throw new Error(payload.message||'Request failed');
}
return payload;
}).catch(e=>{toast(e.message||'Request failed','err');throw e;});
}

function toggleRelay(i){api('POST','/api/relay',{id:i,action:'toggle'}).then(()=>toast('Relay toggled','ok'));}
function relayAll(action){api('POST','/api/relay/all',{action}).then(()=>toast('All relays '+action.toUpperCase(),'ok'));}

function configRelay(i){
const r=wsData.relays?wsData.relays[i]:null;
if(!r)return;
document.getElementById('relayConfigId').value = i;
document.getElementById('relayConfigName').value = r.name || '';
document.getElementById('relayConfigTrigger').value = String(r.trigger || 0);
document.getElementById('relayConfigBoot').value = String(r.boot || 0);
document.getElementById('relayConfigAutoOff').value = String(r.auto_off !== undefined ? r.auto_off : (r.autoOff || 0));
document.getElementById('relayConfigAutoOn').value = String(r.auto_on !== undefined ? r.auto_on : (r.autoOn || 0));
document.getElementById('relayConfigFailsafe').value = r.failsafe ? '1' : '0';
document.getElementById('relayConfigModal').classList.add('active');
}
function closeRelayConfigModal(){
document.getElementById('relayConfigModal').classList.remove('active');
}
function saveRelayConfig(){
const id = parseInt(document.getElementById('relayConfigId').value);
const name = document.getElementById('relayConfigName').value.trim();
if(!name) { toast('Name cannot be empty', 'err'); return; }
const trigger = parseInt(document.getElementById('relayConfigTrigger').value);
const boot = parseInt(document.getElementById('relayConfigBoot').value);
const autoOff = parseInt(document.getElementById('relayConfigAutoOff').value || 0);
const autoOn = parseInt(document.getElementById('relayConfigAutoOn').value || 0);
if (isNaN(autoOff) || autoOff < 0 || autoOff > 1440 || isNaN(autoOn) || autoOn < 0 || autoOn > 1440) {
    toast('Auto-OFF and Auto-ON must be 0 to 1440 minutes', 'err');
    return;
}
const failsafe = document.getElementById('relayConfigFailsafe').value === '1';

api('POST','/api/relay/config',{
id,
name,
trigger,
boot,
autoOff,
autoOn,
failsafe
}).then(()=>{
toast('Relay config saved','ok');
closeRelayConfigModal();
if (wsData.relays && wsData.relays[id]) {
wsData.relays[id].name = name;
wsData.relays[id].trigger = trigger;
wsData.relays[id].boot = boot;
wsData.relays[id].autoOff = autoOff;
wsData.relays[id].autoOn = autoOn;
wsData.relays[id].auto_off = autoOff;
wsData.relays[id].auto_on = autoOn;
wsData.relays[id].failsafe = failsafe;
}
renderRelays(wsData.relays);
loadAlarms();
});
}

let gSensorCalData = null;
function getSelectedCalIdx(id){const el=document.getElementById(id);return el?(parseInt(el.value)||0):0;}
function onClimateCalSlotChange(){
if(!gSensorCalData||!Array.isArray(gSensorCalData.climates))return;
const idx=getSelectedCalIdx('climateCalIdx');
const c=gSensorCalData.climates.find(x=>x.index===idx)||gSensorCalData.climates[0];
if(c){
document.getElementById('tempOffset').value=c.temp_offset||0;
document.getElementById('humOffset').value=c.hum_offset||0;
}
}
function onMq2CalSlotChange(){
if(!gSensorCalData||!Array.isArray(gSensorCalData.mq2_sensors))return;
const idx=getSelectedCalIdx('mq2CalIdx');
const m=gSensorCalData.mq2_sensors.find(x=>x.index===idx)||gSensorCalData.mq2_sensors[0];
if(m){
const allowed=(m.hw_allowed!==false);
document.getElementById('gasEn').value=(allowed&&m.enabled!==false)?'1':'0';
document.getElementById('gasEn').disabled=!allowed;
const sGasMax=gIsEsp8266?1023:4095;
const gThSlider=document.getElementById('gasThSlider');
if(gThSlider){
gThSlider.min=10;gThSlider.max=sGasMax;gThSlider.disabled=!allowed;
gThSlider.value=Math.min(sGasMax,Math.max(10,m.threshold||(gIsEsp8266?100:1500)));
}
document.getElementById('gasThVal').textContent=(gThSlider?gThSlider.value:400);
const mq2Note=document.getElementById('mq2HwNote');if(mq2Note)mq2Note.style.display=allowed?'none':'block';
['btnGasSave','btnGasThSave','btnGasCal'].forEach(id=>{const b=document.getElementById(id);if(b)b.disabled=!allowed;});
}
}
function saveSensorCal(){
const idx=getSelectedCalIdx('climateCalIdx');
const to=parseFloat(document.getElementById('tempOffset').value);
const ho=parseFloat(document.getElementById('humOffset').value);
api('POST','/api/config/sensor',{
sensor_index:idx,
temp_offset:to,
hum_offset:ho,
temp_alarm:parseFloat(document.getElementById('tempAlarmTh').value)
}).then(()=>{
if(gSensorCalData&&Array.isArray(gSensorCalData.climates)){
const c=gSensorCalData.climates.find(x=>x.index===idx)||gSensorCalData.climates[idx];
if(c){c.temp_offset=to;c.hum_offset=ho;}
}
toast('Calibration saved','ok');
});
}
function saveGasEnable(){
const idx=getSelectedCalIdx('mq2CalIdx');
const en=document.getElementById('gasEn').value==='1';
api('POST','/api/config/sensor',{
sensor_index:idx,
mq2_enabled:en
}).then(()=>{
if(gSensorCalData&&Array.isArray(gSensorCalData.mq2_sensors)){
const m=gSensorCalData.mq2_sensors.find(x=>x.index===idx)||gSensorCalData.mq2_sensors[idx];
if(m)m.enabled=en;
}
toast('Gas sensor '+(en?'enabled':'disabled'),'ok');
});
}
function saveGasTh(){
const idx=getSelectedCalIdx('mq2CalIdx');
const th=parseInt(document.getElementById('gasThSlider').value);
api('POST','/api/config/sensor',{
sensor_index:idx,
mq2_threshold:th
}).then(()=>{
if(gSensorCalData&&Array.isArray(gSensorCalData.mq2_sensors)){
const m=gSensorCalData.mq2_sensors.find(x=>x.index===idx)||gSensorCalData.mq2_sensors[idx];
if(m)m.threshold=th;
}
toast('Threshold saved','ok');
});
}
function calibrateMQ2(){
const idx=getSelectedCalIdx('mq2CalIdx');
api('POST','/api/config/sensor',{sensor_index:idx,calibrate_mq2:true}).then(()=>toast('MQ2 calibrated','ok'));
}
function saveWiFi(){
api('POST','/api/config/wifi',{ssid:document.getElementById('wifiSSID').value,pass:document.getElementById('wifiPass').value})
.then(()=>toast('WiFi saved, reconnecting...','info'));
}
function saveMQTT(){
api('POST','/api/config/mqtt',{
enabled:document.getElementById('mqttEn').value==='1',
broker:document.getElementById('mqttBroker').value,
port:parseInt(document.getElementById('mqttPort').value),
prefix:document.getElementById('mqttPrefix').value,
client_id:document.getElementById('mqttClientId').value,
user:document.getElementById('mqttUser').value,
pass:document.getElementById('mqttPass').value
}).then(()=>toast('MQTT saved','ok'));
}
function toggleWebAuthFields(){
const authEn = document.getElementById('cfgWebAuth').value === '1';
document.getElementById('cfgWebAuthFields').style.display = authEn ? 'block' : 'none';
}
function toggleGuestFields(){
const en = document.getElementById('cfgGuestAuth').checked;
document.getElementById('cfgGuestFields').style.display = en ? 'block' : 'none';
}
function saveDevConfig(){
const devName = document.getElementById('cfgDevName').value.trim();
const hostname = document.getElementById('cfgHostname').value.trim();
const tz = document.getElementById('cfgTZ').value.trim();
const use24h = document.getElementById('cfg24h').value === '1';
const webAuth = document.getElementById('cfgWebAuth').value === '1';
const webUser = document.getElementById('cfgWebUser').value.trim();
const webPass = document.getElementById('cfgWebPass').value;
const guestAuth = document.getElementById('cfgGuestAuth').checked;
const guestUser = document.getElementById('cfgGuestUser').value.trim();
const guestPass = document.getElementById('cfgGuestPass').value;
const arduinoOta = document.getElementById('cfgArduinoOta').value === '1';

if (webAuth) {
    if (!webUser) { toast('Username cannot be empty', 'err'); return; }
    if (!webPass && !webPassSet) { toast('Password cannot be empty', 'err'); return; }
}

api('POST','/api/config',{
device_name:devName,
hostname:hostname,
timezone:tz,
use_24h:use24h,
web_auth:webAuth,
web_user:webUser,
web_pass:webPass,
guest_auth:guestAuth,
guest_user:guestUser,
guest_pass:guestPass,
arduino_ota:arduinoOta
}).then(res=>{
if(res&&res.ws_token){wsToken=res.ws_token;}
toast('Config saved','ok');
if (webAuth && webPass) {
    webPassSet = true;
    document.getElementById('cfgWebPass').value = '';
}
});
}
function toggleLcdDimFields(){
const dimEn = document.getElementById('lcdAutoDim').value === '1';
document.getElementById('lcdDimFields').style.display = dimEn ? 'block' : 'none';
}
function saveLCD(){
api('POST','/api/config/lcd',{
enabled:document.getElementById('lcdEn').value==='1',
backlight:document.getElementById('lcdBl').value==='1',
display_mode:document.getElementById('lcdMode').value,
rotation:parseInt(document.getElementById('lcdRot').value),
brightness:parseInt(document.getElementById('lcdBright').value),
auto_dim:document.getElementById('lcdAutoDim').value==='1',
dim_start:document.getElementById('lcdDimStart').value,
dim_end:document.getElementById('lcdDimEnd').value,
dim_brightness:parseInt(document.getElementById('lcdDimBright').value)
}).then(()=>toast('LCD saved','ok'));
}
function saveBuzzer(){
api('POST','/api/buzzer',{enabled:document.getElementById('buzEn').value==='1',volume:parseInt(document.getElementById('buzVol').value)})
.then(()=>toast('Buzzer settings saved','ok'));
}
function testBuzzer(){api('POST','/api/buzzer',{action:'test'}).then(()=>toast('Buzzer test','info'));}
function muteBuzzer(){api('POST','/api/buzzer',{action:'mute'}).then(()=>toast('Buzzer muted','info'));}
function restartESP(){if(confirm('Restart device?'))api('POST','/api/reboot').then(()=>toast('Restarting...','warn'));}
function factoryReset(){if(confirm('FACTORY RESET? All settings will be lost!'))api('POST','/api/factory-reset').then(()=>toast('Factory reset...','err'));}
function resetWiFi(){if(confirm('Reset WiFi credentials?'))api('POST','/api/config/wifi',{action:'reset'}).then(()=>toast('WiFi reset','warn'));}
function loadRestoreFile(e){
const file=e.target.files&&e.target.files[0];
if(!file)return;
const reader=new FileReader();
reader.onload=ev=>{document.getElementById('restoreJson').value=ev.target.result;toast('Backup file loaded','ok');};
reader.readAsText(file);
}
function backupConfig(){
fetch('/api/backup',{headers:{'X-Requested-With':'SmartHome'}}).then(r=>{
if(!r.ok)throw new Error('Backup failed ('+r.status+')');
return r.text();
}).then(data=>{
const blob=new Blob([data],{type:'application/json'});
const url=URL.createObjectURL(blob);
const a=document.createElement('a');a.href=url;
a.download='smarthome_backup.json';a.click();toast('Config downloaded','ok');
}).catch(e=>toast(e.message||'Backup failed','err'));
}
function restoreConfig(){
const json=document.getElementById('restoreJson').value.trim();
if(!json){toast('Paste or select config JSON first','warn');return;}
let parsed;
try{parsed=JSON.parse(json);}catch(e){toast('Invalid JSON syntax: '+e.message,'err');return;}
api('POST','/api/restore',parsed).then(()=>{
toast('Config restored, restarting...','ok');
setTimeout(()=>location.reload(),3500);
});
}

// Logs
function refreshLogs(){
fetch('/api/logs').then(r=>r.json()).then(data=>{
const list=document.getElementById('logList');
if(!data.length){list.innerHTML='<div style="color:var(--text2);padding:20px;text-align:center;">No logs</div>';return;}
let html='';
data.forEach(e=>{
const date=new Date(e.ts*1000).toLocaleString();
const colors={INFO:'var(--blue)',WARN:'var(--orange)',ERROR:'var(--red)',CRIT:'var(--red)'};
html+=`<div class="log-entry"><span class="log-time">${date}</span><span class="log-lvl" style="color:${colors[e.lvl_s]||'var(--text)'}">${escapeHtml(e.lvl_s)}</span><span class="log-src">${escapeHtml(e.src)}</span><span>${escapeHtml(e.msg)}</span></div>`;
});
list.innerHTML=html;
});
}
function downloadLogs(){
fetch('/api/logs?format=csv').then(r=>r.text()).then(data=>{
const a=document.createElement('a');a.href='data:text/csv;charset=utf-8,'+encodeURIComponent(data);
a.download='smarthome_logs.csv';a.click();
});
}
function clearLogs(){if(confirm('Clear all logs?'))api('POST','/api/logs/clear').then(()=>{toast('Logs cleared','ok');refreshLogs();});}

// Diagnostics
function loadDiag(){
fetch('/api/diagnostics').then(r=>r.json()).then(d=>{
setText('dFw',d.fw_version);setText('dBuild',d.fw_build);
setText('dChip',d.chip_model+' rev'+d.chip_rev);setText('dChipId',d.chip_id);
setText('dCpu',d.cpu_freq);setText('dFlash',(d.flash_size/1048576).toFixed(1));
setText('dHeap',d.free_heap);setText('dMinHeap',d.min_heap);setText('dFrag',d.heap_frag);
setText('dSdk',d.sdk_version);setText('dReset',d.reset_reason);setText('dUptime',d.uptime);
setText('dOta',d.ota_status||'Idle');
});
}

// Settings
function loadSettings(){
return fetch('/api/config').then(r=>r.json()).then(d=>{
if(d.auth_role){gAuthRole=d.auth_role;applyRoleUI();}
if(d.ws_token){wsToken=d.ws_token;sendWsSubscribe();}
if(d.device_name)document.getElementById('cfgDevName').value=d.device_name;
if(d.hostname){
document.getElementById('cfgHostname').value=d.hostname;
const link=document.getElementById('cfgLocalUrl');
if(link){link.textContent=`http://${d.hostname}.local`;link.href=`http://${d.hostname}.local`;}
}
if(d.mac){const m=document.getElementById('cfgMac');if(m)m.textContent=d.mac;}
if(d.timezone)document.getElementById('cfgTZ').value=d.timezone;
if(d.use_24h!==undefined)document.getElementById('cfg24h').value=d.use_24h?'1':'0';
document.getElementById('cfgWebAuth').value=d.web_auth?'1':'0';
if(d.arduino_ota!==undefined)document.getElementById('cfgArduinoOta').value=d.arduino_ota?'1':'0';
document.getElementById('cfgWebUser').value=d.web_user||'';
document.getElementById('cfgWebPass').value='';
webPassSet=d.web_pass_set||false;
document.getElementById('cfgGuestAuth').checked=d.guest_auth||false;
document.getElementById('cfgGuestUser').value=d.guest_user||'guest';
document.getElementById('cfgGuestPass').value='';
guestPassSet=d.guest_pass_set||false;
toggleWebAuthFields();
toggleGuestFields();
if(d.mqtt){
document.getElementById('mqttEn').value=d.mqtt.enabled?'1':'0';
document.getElementById('mqttBroker').value=d.mqtt.broker||'';
document.getElementById('mqttPort').value=d.mqtt.port||1883;
document.getElementById('mqttPrefix').value=d.mqtt.prefix||'smarthome';
document.getElementById('mqttClientId').value=d.mqtt.client_id||'';
document.getElementById('mqttUser').value=d.mqtt.user||'';
}
if(d.lcd){
const lcdAllowed=(d.lcd.hw_allowed!==false);
document.getElementById('lcdEn').value=(lcdAllowed&&d.lcd.enabled)?'1':'0';
document.getElementById('lcdEn').disabled=!lcdAllowed;
const btnLcd=document.getElementById('btnLcdSave');if(btnLcd)btnLcd.disabled=!lcdAllowed;
const lcdNote=document.getElementById('lcdHwNote');if(lcdNote)lcdNote.style.display=lcdAllowed?'none':'block';
document.getElementById('lcdBl').value=d.lcd.backlight?'1':'0';
document.getElementById('lcdMode').value=(d.lcd.display_mode==='dht_relay')?'dht_relay':'rotate';
document.getElementById('lcdRot').value=d.lcd.rotation||5;
document.getElementById('lcdBright').value=d.lcd.brightness!==undefined?d.lcd.brightness:100;
document.getElementById('lcdBrightVal').textContent=document.getElementById('lcdBright').value+'%';
document.getElementById('lcdAutoDim').value=d.lcd.auto_dim?'1':'0';
document.getElementById('lcdDimStart').value=d.lcd.dim_start||'22:00';
document.getElementById('lcdDimEnd').value=d.lcd.dim_end||'06:00';
document.getElementById('lcdDimBright').value=d.lcd.dim_brightness!==undefined?d.lcd.dim_brightness:0;
document.getElementById('lcdDimBrightVal').textContent=document.getElementById('lcdDimBright').value+'%';
toggleLcdDimFields();
}
if(d.buzzer){
const buzAllowed=(d.buzzer.hw_allowed!==false);
document.getElementById('buzEn').value=(buzAllowed&&d.buzzer.enabled)?'1':'0';
document.getElementById('buzEn').disabled=!buzAllowed;
const btnBuz=document.getElementById('btnBuzSave');if(btnBuz)btnBuz.disabled=!buzAllowed;
const btnBuzT=document.getElementById('btnBuzTest');if(btnBuzT)btnBuzT.disabled=!buzAllowed;
const buzNote=document.getElementById('buzHwNote');if(buzNote)buzNote.style.display=buzAllowed?'none':'block';
document.getElementById('buzVol').value=d.buzzer.volume||128;
}
if(d.sensor){
gSensorCalData=d.sensor;
const cRow=document.getElementById('climateCalSlotRow');
const cSel=document.getElementById('climateCalIdx');
const cArr=Array.isArray(d.sensor.climates)?d.sensor.climates:[];
if(cSel){
cSel.innerHTML='';
const cnt=Math.max(1,cArr.length);
for(let i=0;i<cnt;i++){
const opt=document.createElement('option');opt.value=i;
const wsLabel=(wsData&&Array.isArray(wsData.climates)&&wsData.climates[i]&&wsData.climates[i].label)?wsData.climates[i].label:'';
opt.textContent='Climate #'+(i+1)+(wsLabel?(' ('+wsLabel+')'):'');
cSel.appendChild(opt);
}
}
if(cRow)cRow.style.display=(cArr.length>1)?'block':'none';
document.getElementById('tempOffset').value=d.sensor.temp_offset||0;
document.getElementById('humOffset').value=d.sensor.hum_offset||0;
document.getElementById('tempAlarmTh').value=d.sensor.temp_alarm||45;
if(cArr.length>0)onClimateCalSlotChange();

const mRow=document.getElementById('mq2CalSlotRow');
const mSel=document.getElementById('mq2CalIdx');
const mArr=Array.isArray(d.sensor.mq2_sensors)?d.sensor.mq2_sensors:[];
if(mSel){
mSel.innerHTML='';
const cnt=Math.max(1,mArr.length);
for(let i=0;i<cnt;i++){
const opt=document.createElement('option');opt.value=i;
const wsLabel=(wsData&&Array.isArray(wsData.mq2s)&&wsData.mq2s[i]&&wsData.mq2s[i].label)?wsData.mq2s[i].label:'';
opt.textContent='Gas MQ-2 #'+(i+1)+(wsLabel?(' ('+wsLabel+')'):'');
mSel.appendChild(opt);
}
}
if(mRow)mRow.style.display=(mArr.length>1)?'block':'none';

const mq2Allowed=(d.sensor.mq2_hw_allowed!==false);
document.getElementById('gasEn').value=(mq2Allowed&&d.sensor.mq2_enabled!==false)?'1':'0';
document.getElementById('gasEn').disabled=!mq2Allowed;
const sGasMax = gIsEsp8266 ? 1023 : 4095;
const gThSlider = document.getElementById('gasThSlider');
if (gThSlider) {
gThSlider.min = 10;
gThSlider.max = sGasMax;
gThSlider.disabled = !mq2Allowed;
const rawTh = d.sensor.mq2_threshold || (gIsEsp8266 ? 100 : 1500);
gThSlider.value = Math.min(sGasMax, Math.max(10, rawTh));
}
document.getElementById('gasThVal').textContent = (gThSlider ? gThSlider.value : 400);
const mq2Note = document.getElementById('mq2HwNote'); if (mq2Note) mq2Note.style.display = mq2Allowed ? 'none' : 'block';
['btnGasSave','btnGasThSave','btnGasCal'].forEach(id => { const b = document.getElementById(id); if (b) b.disabled = !mq2Allowed; });
if(mArr.length>0)onMq2CalSlotChange();
}
});
}

function populateMinuteOptions(){
const sel=document.getElementById('alarmMin12');
if(!sel||sel.options.length)return;
let html='';
for(let i=0;i<60;i++){
const v=String(i).padStart(2,'0');
html+=`<option value="${i}">${v}</option>`;
}
sel.innerHTML=html;
sel.value='0';
}

function setClockPicker(hour24,minute){
populateMinuteOptions();
const ampm=hour24>=12?'PM':'AM';
let hour12=hour24%12;
if(hour12===0)hour12=12;
document.getElementById('alarmHour12').value=String(hour12);
document.getElementById('alarmMin12').value=String(minute||0);
document.getElementById('alarmAmPm').value=ampm;
}

function getClockPickerValue(){
let hour12=parseInt(document.getElementById('alarmHour12').value||'12');
const minute=parseInt(document.getElementById('alarmMin12').value||'0');
const ampm=document.getElementById('alarmAmPm').value;
hour12=hour12%12;
const hour=(ampm==='PM')?(hour12+12):hour12;
return {hour,minute};
}

function getRelayName(i) {
    if (wsData && wsData.relays && wsData.relays[i]) {
        return wsData.relays[i].name || ('Relay ' + (i + 1));
    }
    return 'Relay ' + (i + 1);
}

function populateAlarmRelayOptions(preferredVal) {
    const select = document.getElementById('alarmRelay');
    if (!select) return;
    const val = (preferredVal !== undefined && preferredVal !== null) ? String(preferredVal) : select.value;
    const count = (wsData && wsData.relays) ? wsData.relays.length : (wsData.num_relays !== undefined ? wsData.num_relays : (gIsEsp8266 ? 2 : 5));
    let html = '';
    let hasVal = false;
    for (let i = 0; i < count; i++) {
        if (wsData && wsData.relays && wsData.relays[i] && wsData.relays[i].enabled === false) continue;
        if (String(i) === val) hasVal = true;
        html += `<option value="${i}">${escapeHtml(getRelayName(i))}</option>`;
    }
    html += `<option value="255">All Active Relays</option>`;
    if (val === '255') hasVal = true;
    select.innerHTML = html;
    if (hasVal && val !== '') select.value = val;
    else if (select.options.length > 0) select.selectedIndex = 0;
}

function updateAlarmActionFields() {
    const act = parseInt(document.getElementById('alarmAction').value || '0');
    const grp = document.getElementById('alarmRelayGroup');
    if (grp) grp.style.display = (act >= 3) ? 'none' : 'block';
}

// Timers
function loadAlarms(){
fetch('/api/alarms').then(r=>r.json()).then(data=>{
const list=document.getElementById('alarmList');
alarmCache=data||[];
if(!alarmCache.length){list.innerHTML='<div style="color:var(--text2);padding:16px;text-align:center;">No timer tasks configured</div>';return;}
const types=['Once','Daily','Weekly','Weekdays','Weekends'];
const actions=['Relay ON','Relay OFF','Toggle','Buzzer','All ON','All OFF'];
const days=['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
const isGuest=(gAuthRole==='guest');
let html='';
alarmCache.forEach(a=>{
const isDelay=parseInt(a.mode||0)===1;
const time=isDelay?formatDelay(a.delay||0):formatFixedTime(a.hour||0,a.min||0);
const info=isDelay?'Delay timer':(types[a.type]||'Once')+(a.type===2?' ('+(days[a.dow]||'Sun')+')':'');
const baseAct=actions[a.action]||'Action';
const act=(a.action<=2)?(baseAct+' - '+(a.relay===255?'All Active Relays':getRelayName(a.relay))):baseAct;
html+=`<div style="display:flex;align-items:center;gap:12px;padding:10px;background:var(--bg);border-radius:10px;margin-bottom:6px;border:1px solid var(--card-border);opacity:${a.en?1:0.5}">
<div style="font-size:1.2rem;font-weight:700;min-width:56px">${time}</div>
<div style="flex:1"><div style="font-size:.82rem;font-weight:500">${escapeHtml(info)}</div><div style="font-size:.72rem;color:var(--text2)">${escapeHtml(act)}</div></div>
${isGuest?'':`<button class="btn btn-sm btn-outline" onclick="editAlarm(${a.id})">Edit</button>
<button class="btn btn-sm btn-outline" onclick="toggleAlarmEn(${a.id},${!a.en})">${a.en?'Disable':'Enable'}</button>
<button class="btn btn-sm btn-red" onclick="deleteAlarm(${a.id})">&#10005;</button>`}
</div>`;
});
list.innerHTML=html;
});
}
function formatDelay(totalMinutes){
const h=Math.floor(totalMinutes/60);
const m=totalMinutes%60;
if(h&&m)return `${h}h ${m}m`;
if(h)return `${h}h`;
return `${m}m`;
}
function formatFixedTime(hour24,minute){
const ampm=hour24>=12?'PM':'AM';
let hour12=hour24%12;
if(hour12===0)hour12=12;
return `${String(hour12).padStart(2,'0')}:${String(minute).padStart(2,'0')} ${ampm}`;
}
function updateAlarmMode(){
const delay=document.getElementById('alarmMode').value==='1';
document.getElementById('clockFields').style.display=delay?'none':'block';
document.getElementById('delayFields').style.display=delay?'block':'none';
}
function showAlarmModal(mode='clock'){
populateAlarmRelayOptions(0);
document.getElementById('alarmModal').classList.add('active');
document.getElementById('alarmModalTitle').textContent=mode==='delay'?'Add Delay Timer':'Add Fixed-Time Task';
document.getElementById('alarmEditId').value='0';
document.getElementById('alarmMode').value=mode==='delay'?'1':'0';
setClockPicker(8,0);
document.getElementById('alarmType').value='0';
document.getElementById('alarmDow').value='0';
document.getElementById('alarmDelayHours').value='0';
document.getElementById('alarmDelayMinutes').value='30';
document.getElementById('alarmAction').value='0';
updateAlarmMode();
updateAlarmActionFields();
document.getElementById('dowGroup').style.display='none';
}
function closeAlarmModal(){document.getElementById('alarmModal').classList.remove('active');}
document.getElementById('alarmType').onchange=function(){document.getElementById('dowGroup').style.display=this.value==='2'?'block':'none';};
document.getElementById('alarmMode').onchange=updateAlarmMode;
function editAlarm(id){
const a=alarmCache.find(x=>x.id===id);
if(!a)return;
const targetRelay=(a.relay!=null)?a.relay:0;
populateAlarmRelayOptions(targetRelay);
document.getElementById('alarmModal').classList.add('active');
document.getElementById('alarmEditId').value=String(a.id);
document.getElementById('alarmMode').value=String(a.mode||0);
setClockPicker((a.hour!=null)?a.hour:8,(a.min!=null)?a.min:0);
document.getElementById('alarmType').value=(a.type!=null)?a.type:0;
document.getElementById('alarmDow').value=(a.dow!=null)?a.dow:0;
document.getElementById('alarmAction').value=(a.action!=null)?a.action:0;
const totalDelay=parseInt(a.delay||0);
document.getElementById('alarmDelayHours').value=Math.floor(totalDelay/60);
document.getElementById('alarmDelayMinutes').value=totalDelay%60;
document.getElementById('alarmModalTitle').textContent=(parseInt(a.mode||0)===1)?'Edit Delay Timer':'Edit Fixed-Time Task';
updateAlarmMode();
updateAlarmActionFields();
document.getElementById('dowGroup').style.display=document.getElementById('alarmType').value==='2'?'block':'none';
}
function saveAlarm(){
const mode=parseInt(document.getElementById('alarmMode').value);
const id=parseInt(document.getElementById('alarmEditId').value||'0');
const existing=id?alarmCache.find(x=>x.id===id):null;
const clock=getClockPickerValue();
const alarm={
id:id||undefined,
mode,
hour:clock.hour,
min:clock.minute,
type:parseInt(document.getElementById('alarmType').value),
dow:parseInt(document.getElementById('alarmDow').value),
delay:(parseInt(document.getElementById('alarmDelayHours').value||'0')*60)+parseInt(document.getElementById('alarmDelayMinutes').value||'0'),
action:parseInt(document.getElementById('alarmAction').value),
relay:parseInt(document.getElementById('alarmRelay').value),
en:existing?existing.en!==false:true
};
if(mode===1&&alarm.delay<=0){toast('Set a delay first','warn');return;}
api('POST','/api/alarm',alarm).then(()=>{toast(id?'Timer updated':'Timer saved','ok');closeAlarmModal();loadAlarms();});
}
function toggleAlarmEn(id,en){api('POST','/api/alarm',{id,en}).then(()=>loadAlarms());}
function deleteAlarm(id){if(confirm('Delete timer task?'))api('POST','/api/alarm',{id,delete:true}).then(()=>{toast('Deleted','ok');loadAlarms();});}

// Timer helper & countdown ticker
function formatSeconds(sec){
if(sec<=0)return '0s';
const h=Math.floor(sec/3600);
const m=Math.floor((sec%3600)/60);
const s=sec%60;
if(h>0)return `${h}h ${m}m ${s}s`;
if(m>0)return `${m}m ${s}s`;
return `${s}s`;
}

setInterval(()=>{
if(!wsData.relays)return;
let ch=false;
wsData.relays.forEach(r=>{
if(r.timer_active&&r.timer_remaining>0){
r.timer_remaining--;
if(r.timer_remaining===0){r.timer_active=false;}
ch=true;
}
});
if(ch)renderRelays(wsData.relays);
},1000);

function openQuickTimer(i){
const r=wsData.relays?wsData.relays[i]:null;
document.getElementById('quickTimerRelayId').value=i;
document.getElementById('quickTimerTitle').textContent=`⏱️ Timer: ${r?r.name:'Relay '+(i+1)}`;
document.getElementById('quickTimerHours').value='0';
document.getElementById('quickTimerMinutes').value='10';
if(r){
document.getElementById('quickTimerAction').value=r.state?'off':'on';
}
document.getElementById('quickTimerModal').classList.add('active');
}
function closeQuickTimerModal(){
document.getElementById('quickTimerModal').classList.remove('active');
}
function setTimerPreset(mins){
const h=Math.floor(mins/60);
const m=mins%60;
document.getElementById('quickTimerHours').value=h;
document.getElementById('quickTimerMinutes').value=m;
}
function setAlarmDelayPreset(mins){
const h=Math.floor(mins/60);
const m=mins%60;
document.getElementById('alarmDelayHours').value=h;
document.getElementById('alarmDelayMinutes').value=m;
}
function startRelayTimer(){
const id=parseInt(document.getElementById('quickTimerRelayId').value);
const h=parseInt(document.getElementById('quickTimerHours').value||'0');
const m=parseInt(document.getElementById('quickTimerMinutes').value||'0');
const action=document.getElementById('quickTimerAction').value;
const totalSec=(h*3600)+(m*60);
if(totalSec<=0){toast('Please set a duration greater than 0','warn');return;}
api('POST','/api/relay/timer',{id,action,duration:totalSec}).then(()=>{
toast(`Timer set for ${h>0?h+'h ':''}${m}m`,'ok');
closeQuickTimerModal();
if(wsData.relays&&wsData.relays[id]){
wsData.relays[id].timer_active=true;
wsData.relays[id].timer_target=(action==='on');
wsData.relays[id].timer_remaining=totalSec;
renderRelays(wsData.relays);
}
});
}
function cancelRelayTimer(id){
api('POST','/api/relay/timer',{id,action:'cancel'}).then(()=>{
toast('Timer cancelled','ok');
if(wsData.relays&&wsData.relays[id]){
wsData.relays[id].timer_active=false;
wsData.relays[id].timer_remaining=0;
renderRelays(wsData.relays);
}
});
}

// Automation Rules
let ruleCache=[];
function loadRules(){
api('GET','/api/rules').then(rules=>{
ruleCache=Array.isArray(rules)?rules:[];
renderRules(ruleCache);
}).catch(()=>{});
}
function renderRules(rules){
const el=document.getElementById('ruleList');
if(!el)return;
if(!rules||!rules.length){
el.innerHTML='<div style="color:var(--text2);font-size:0.85rem;padding:12px 0;">No automation rules configured. Click "+ Add New Rule" to create one.</div>';
return;
}
const sensorNames=['Temperature','Humidity','Gas MQ-2','Ambient Light','Water Probe Temp','Water Tank Level','Motion'];
const sensorUnits=['°C','%','','lx','°C','%',''];
const condNames=['≥ (Rises above)','≤ (Falls below)'];
const actNames=['Turn ON','Turn OFF'];
const isGuest=(gAuthRole==='guest');
let html='';
rules.forEach(r=>{
const sIdx=(r.s_idx!==undefined)?r.s_idx:((r.sensor_index!==undefined)?r.sensor_index:0);
const sBase=sensorNames[r.sensor]||'Sensor';
const sName=sBase+(sIdx>0?(' #'+(sIdx+1)):'');
const sUnit=sensorUnits[r.sensor]||'';
const cName=condNames[r.cond]||'';
const aName=actNames[r.act]||'Action';
const rName=(r.relay===255)?'All Relays':getRelayName(r.relay);
html+=`<div style="display:flex;align-items:center;gap:12px;padding:12px;background:var(--bg);border-radius:12px;margin-bottom:8px;border:1px solid ${r.en?'var(--card-border)':'rgba(255,255,255,0.05)'}">
<div style="flex:1">
<div style="display:flex;align-items:center;gap:8px;margin-bottom:4px">
<span style="font-weight:600">${escapeHtml(r.name||'Rule')}</span>
<span class="badge ${r.en?'badge-ok':'badge-err'}">${r.en?'Active':'Disabled'}</span>
${r.trig?'<span class="badge" style="background:rgba(245,158,11,0.2);color:#fbbf24;border:1px solid rgba(245,158,11,0.4)">Triggered</span>':''}
</div>
<div style="font-size:0.75rem;color:var(--text2)">
IF <b>${sName}</b> ${cName} <b>${r.th}${sUnit}</b> &plusmn;${r.hyst}${sUnit} &rarr; <b>${aName}</b> <u>${escapeHtml(rName)}</u>
</div>
</div>
${isGuest?'':`<div style="display:flex;gap:6px">
<button class="btn btn-sm ${r.en?'btn-red':'btn-green'}" onclick="toggleRuleEn(${r.id},${!r.en})">${r.en?'Disable':'Enable'}</button>
<button class="btn btn-sm btn-outline" onclick="editRule(${r.id})">Edit</button>
<button class="btn btn-sm btn-outline" style="border-color:var(--red);color:var(--red)" onclick="deleteRule(${r.id})">Delete</button>
</div>`}
</div>`;
});
el.innerHTML=html;
}
function populateRuleRelayOptions(selectedRelay){
const sel=document.getElementById('ruleTargetRelay');
if(!sel)return;
sel.innerHTML='';
const count=(wsData&&wsData.relays)?wsData.relays.length:(wsData.num_relays!==undefined?wsData.num_relays:(gIsEsp8266?2:5));
let target=(selectedRelay!==undefined&&selectedRelay!==null)?selectedRelay:0;
let matched=false;
for(let i=0;i<count;i++){
if(wsData&&wsData.relays&&wsData.relays[i]&&wsData.relays[i].enabled===false)continue;
const opt=document.createElement('option');
opt.value=i;
opt.textContent=getRelayName(i);
if(i===target){opt.selected=true;matched=true;}
sel.appendChild(opt);
}
const allOpt=document.createElement('option');
allOpt.value=255;
allOpt.textContent='All Active Relays';
if(target===255){allOpt.selected=true;matched=true;}
sel.appendChild(allOpt);
if(!matched&&sel.options.length>0)sel.selectedIndex=0;
}
function populateRuleSensorIdxOptions(sensorType, selectedIdx){
const grp=document.getElementById('ruleSensorIdxGroup');
const sel=document.getElementById('ruleSensorIdx');
if(!sel)return;
let arr=[];
if(wsData){
if(sensorType===0||sensorType===1)arr=wsData.climates||[];
else if(sensorType===2)arr=wsData.mq2s||[];
else if(sensorType===3)arr=wsData.lights||[];
else if(sensorType===4)arr=wsData.probes||[];
else if(sensorType===5)arr=wsData.tanks||[];
else if(sensorType===6)arr=wsData.motions||[];
}
sel.innerHTML='';
const count=Math.max(1,arr.length,(selectedIdx||0)+1);
for(let i=0;i<count;i++){
const item=arr[i];
const lbl=(item&&item.label)?item.label:'';
const opt=document.createElement('option');
opt.value=i;
opt.textContent='Slot #'+(i+1)+(lbl?(' ('+lbl+')'):'')+((item&&item.enabled===false)?' [Disabled]':'');
if(i===(selectedIdx||0))opt.selected=true;
sel.appendChild(opt);
}
if(grp)grp.style.display=(count>1)?'block':'none';
}
function onRuleConditionChange(){
const s=parseInt(document.getElementById('ruleSensor').value);
if(s===6){
const cond=parseInt(document.getElementById('ruleCondition').value);
document.getElementById('ruleThreshold').value=(cond===1?'0':'1');
}
}
function updateRuleSensorFields(selectedIdx){
const s=parseInt(document.getElementById('ruleSensor').value);
const cond=parseInt(document.getElementById('ruleCondition').value);
populateRuleSensorIdxOptions(s, selectedIdx!==undefined?selectedIdx:0);
const th=document.getElementById('ruleThreshold');
const hy=document.getElementById('ruleHysteresis');
if(s===0){th.step='0.5';th.value='30.0';hy.value='0.5';}
else if(s===1){th.step='1';th.value='70';hy.value='2.0';}
else if(s===2){th.step='10';th.value='500';hy.value='50';}
else if(s===3){th.step='10';th.value='100';hy.value='15';}
else if(s===4){th.step='0.5';th.value='35.0';hy.value='0.5';}
else if(s===5){th.step='1';th.value='20';hy.value='3.0';}
else if(s===6){th.step='1';th.value=(cond===1?'0':'1');hy.value='0';}
}
function showRuleModal(){
document.getElementById('ruleModalTitle').textContent='Add Automation Rule';
document.getElementById('ruleEditId').value='0';
document.getElementById('ruleName').value='';
document.getElementById('ruleSensor').value='0';
document.getElementById('ruleCondition').value='0';
document.getElementById('ruleThreshold').value='30.0';
document.getElementById('ruleHysteresis').value='0.5';
updateRuleSensorFields(0);
populateRuleRelayOptions(0);
document.getElementById('ruleAction').value='0';
document.getElementById('ruleModal').classList.add('active');
}
function editRule(id){
const r=ruleCache.find(x=>x.id===id);
if(!r)return;
document.getElementById('ruleModalTitle').textContent='Edit Automation Rule';
document.getElementById('ruleEditId').value=r.id;
document.getElementById('ruleName').value=r.name||'';
document.getElementById('ruleSensor').value=String(r.sensor);
document.getElementById('ruleCondition').value=String(r.cond);
document.getElementById('ruleThreshold').value=r.th;
document.getElementById('ruleHysteresis').value=r.hyst;
populateRuleSensorIdxOptions(r.sensor,(r.s_idx!==undefined?r.s_idx:(r.sensor_index||0)));
populateRuleRelayOptions(r.relay);
document.getElementById('ruleAction').value=String(r.act);
document.getElementById('ruleModal').classList.add('active');
}
function closeRuleModal(){
document.getElementById('ruleModal').classList.remove('active');
}
function saveRule(){
const id=parseInt(document.getElementById('ruleEditId').value||'0');
const name=document.getElementById('ruleName').value.trim();
if(!name){toast('Please enter a rule name','warn');return;}
const sensor=parseInt(document.getElementById('ruleSensor').value);
const s_idx=parseInt((document.getElementById('ruleSensorIdx')||{}).value||'0')||0;
const cond=parseInt(document.getElementById('ruleCondition').value);
const th=parseFloat(document.getElementById('ruleThreshold').value);
const hyst=parseFloat(document.getElementById('ruleHysteresis').value);
const relay=parseInt(document.getElementById('ruleTargetRelay').value);
const act=parseInt(document.getElementById('ruleAction').value);
if(isNaN(th)){toast('Please enter a valid threshold','warn');return;}
const payload={id,en:true,name,sensor,s_idx,cond,th,hyst:isNaN(hyst)?0:hyst,relay,act};
api('POST','/api/rule',payload).then(()=>{
toast(id>0?'Rule updated':'Rule added','ok');
closeRuleModal();
loadRules();
});
}
function toggleRuleEn(id,en){
api('POST','/api/rule',{id,en}).then(()=>{
toast(en?'Rule enabled':'Rule disabled','ok');
loadRules();
});
}
function deleteRule(id){
if(!confirm('Delete this automation rule?'))return;
api('POST','/api/rule',{id,delete:true}).then(()=>{
toast('Rule deleted','ok');
loadRules();
});
}


// ============================================================================
// Hardware & GPIO Template Management
// ============================================================================
let SAFE_OUTPUT_PINS = [2, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33];
let SAFE_INPUT_PINS  = [0, 2, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33, 34, 35, 36, 39];
let ADC1_PINS        = [32, 33, 34, 35, 36, 39];

const ESP8266_OUTPUT_PINS = [0, 2, 4, 5, 12, 13, 14, 15, 16];
const ESP8266_INPUT_PINS  = [0, 2, 4, 5, 12, 13, 14, 15, 16];
const ESP8266_ADC_PINS    = [17];

const ESP8266_PIN_NAMES = {
    0: 'D3 (GPIO 0 - Flash Button)',
    2: 'D4 (GPIO 2 - TxD1 / Buzzer)',
    4: 'D2 (GPIO 4 - I2C SDA)',
    5: 'D1 (GPIO 5 - I2C SCL)',
    12: 'D6 (GPIO 12 - Relay 1)',
    13: 'D7 (GPIO 13 - Switch 1)',
    14: 'D5 (GPIO 14 - Relay 2)',
    15: 'D8 (GPIO 15 - Boot Low)',
    16: 'D0 (GPIO 16 - Switch 2 / Wake)',
    17: 'A0 (ADC0 - Analog Input Only)'
};

let gHwConfig = null;
let gIsEsp8266 = )rawliteral"
#if defined(ESP8266)
"true;\n"
#else
"false;\n"
#endif
R"rawliteral(

function populatePinOptions(selectId, pinList, selectedPin, allowNone = true) {
    const el = document.getElementById(selectId);
    if (!el) return;
    el.innerHTML = '';
    if (allowNone) {
        const optNone = document.createElement('option');
        optNone.value = 255;
        optNone.textContent = 'None / Disabled';
        if (selectedPin === 255 || selectedPin === undefined) optNone.selected = true;
        el.appendChild(optNone);
    }
    pinList.forEach(p => {
        const opt = document.createElement('option');
        opt.value = p;
        let label = (gIsEsp8266 && ESP8266_PIN_NAMES[p]) ? ESP8266_PIN_NAMES[p] : ('GPIO ' + p);
        if (!gIsEsp8266) {
            if (p === 34 || p === 35 || p === 36 || p === 39) label += ' (Input-Only)';
            if (p === 0 || p === 2 || p === 12 || p === 15) label += ' (Strapping)';
        }
        opt.textContent = label;
        if (p === selectedPin) opt.selected = true;
        el.appendChild(opt);
    });
}

let gHwSensors = { climates: [], lights: [], motions: [], probes: [], ultrasonics: [], mq2s: [] };
let gSensorLimits = { relays: 8, climates: 4, lights: 2, motions: 6, probes: 4, ultrasonics: 4, mq2s: 4 };

const SENSOR_GROUP_META = {
    climates:    { containerId: 'hwClimatesContainer',    badgeId: 'hwClimatesCount',    emptyText: 'No Climate sensors added — click + Add' },
    lights:      { containerId: 'hwLightsContainer',      badgeId: 'hwLightsCount',      emptyText: 'No Ambient Light sensors added — click + Add' },
    motions:     { containerId: 'hwMotionsContainer',     badgeId: 'hwMotionsCount',     emptyText: 'No Motion / Radar sensors added — click + Add' },
    probes:      { containerId: 'hwProbesContainer',      badgeId: 'hwProbesCount',      emptyText: 'No DS18B20 Water Probes added — click + Add' },
    ultrasonics: { containerId: 'hwUltrasonicsContainer', badgeId: 'hwUltrasonicsCount', emptyText: 'No Ultrasonic Tank Monitors added — click + Add' },
    mq2s:        { containerId: 'hwMq2sContainer',        badgeId: 'hwMq2sCount',        emptyText: 'No MQ-2 Gas sensors added — click + Add' }
};

function getI2cClimateAddrs(type) {
    if (type === 3) return [0x76, 0x77];
    if (type === 4) return [0x38];
    if (type === 5) return [0x44, 0x45];
    return [];
}

function formatHexAddr(a) {
    return '0x' + Number(a).toString(16).toUpperCase().padStart(2, '0');
}

function getUsedI2cAddrs(excludeGroup, excludeIdx) {
    const used = new Set();
    const lcdEn = document.getElementById('hwLcdEn');
    if (lcdEn && lcdEn.value === '1') {
        const la = parseInt((document.getElementById('hwLcdAddr') || {}).value || '39');
        if (!isNaN(la) && la > 0) used.add(la);
    }
    gHwSensors.climates.forEach((c, i) => {
        if (excludeGroup === 'climates' && excludeIdx === i) return;
        if (c && c.type >= 3 && c.i2c_addr > 0) used.add(c.i2c_addr);
    });
    gHwSensors.lights.forEach((l, i) => {
        if (excludeGroup === 'lights' && excludeIdx === i) return;
        if (l && l.type === 1 && l.i2c_addr > 0) used.add(l.i2c_addr);
    });
    return used;
}

function pickFreePinFromSet(usedSet, list, preferred) {
    const strapSet = new Set(gIsEsp8266 ? [0, 2, 15] : [0, 2, 12, 15]);
    if (preferred !== undefined && preferred !== 255 && list.includes(preferred) && !usedSet.has(preferred)) {
        return preferred;
    }
    const clean = list.find(p => !usedSet.has(p) && !strapSet.has(p));
    if (clean !== undefined) return clean;
    const anyFree = list.find(p => !usedSet.has(p));
    return anyFree !== undefined ? anyFree : 255;
}

function hasAnyI2cSensorActive() {
    return gHwSensors.climates.some(c => c && c.type >= 3) ||
           gHwSensors.lights.some(l => l && l.type === 1);
}

function ensureI2cPinsAssigned() {
    const lcdEn = document.getElementById('hwLcdEn');
    if (!hasAnyI2cSensorActive() && (!lcdEn || lcdEn.value !== '1')) return;
    const strapSet = new Set(gIsEsp8266 ? [0, 2, 15] : [0, 2, 12, 15]);
    const ensureBusPin = (elId, defPin) => {
        const el = document.getElementById(elId);
        if (!el) return;
        const cur = parseInt(el.value);
        if (cur !== 255 && !isNaN(cur)) return;
        const used = getAllFormUsedPins(elId);
        const picked = pickFreePinFromSet(used, SAFE_OUTPUT_PINS, defPin);
        if (picked !== 255) el.value = String(picked);
    };
    ensureBusPin('hwLcdSda', gIsEsp8266 ? 4 : 21);
    ensureBusPin('hwLcdScl', gIsEsp8266 ? 5 : 22);
}

function syncHwSensorsFromDOM() {
    const numOr = (id, def) => {
        const el = document.getElementById(id);
        if (!el) return def;
        const v = parseInt(el.value);
        return isNaN(v) ? def : v;
    };
    const strOr = (id, def) => {
        const el = document.getElementById(id);
        return el ? el.value.trim() : def;
    };
    gHwSensors.climates.forEach((c, i) => {
        if (!document.getElementById(`hw_cli_type_${i}`)) return;
        c.type     = numOr(`hw_cli_type_${i}`, c.type);
        c.pin      = (c.type === 1 || c.type === 2) ? numOr(`hw_cli_pin_${i}`, c.pin ?? 255) : 255;
        c.i2c_addr = (c.type >= 3) ? numOr(`hw_cli_addr_${i}`, c.i2c_addr || getI2cClimateAddrs(c.type)[0] || 0) : 0;
        c.label    = strOr(`hw_cli_lbl_${i}`, c.label || '');
    });
    gHwSensors.lights.forEach((l, i) => {
        if (!document.getElementById(`hw_lgt_type_${i}`)) return;
        l.type     = numOr(`hw_lgt_type_${i}`, l.type);
        l.i2c_addr = (l.type === 1) ? numOr(`hw_lgt_addr_${i}`, l.i2c_addr || 0x23) : 0;
        l.label    = strOr(`hw_lgt_lbl_${i}`, l.label || '');
    });
    gHwSensors.motions.forEach((m, i) => {
        if (!document.getElementById(`hw_mot_type_${i}`)) return;
        m.type  = numOr(`hw_mot_type_${i}`, m.type);
        m.pin   = numOr(`hw_mot_pin_${i}`, m.pin ?? 255);
        m.label = strOr(`hw_mot_lbl_${i}`, m.label || '');
    });
    gHwSensors.probes.forEach((p, i) => {
        if (!document.getElementById(`hw_prb_type_${i}`)) return;
        p.type  = numOr(`hw_prb_type_${i}`, p.type);
        p.pin   = numOr(`hw_prb_pin_${i}`, p.pin ?? 255);
        p.label = strOr(`hw_prb_lbl_${i}`, p.label || '');
    });
    gHwSensors.ultrasonics.forEach((u, i) => {
        if (!document.getElementById(`hw_us_type_${i}`)) return;
        u.type       = numOr(`hw_us_type_${i}`, u.type);
        u.trig_pin   = numOr(`hw_us_trig_${i}`, u.trig_pin ?? 255);
        u.echo_pin   = numOr(`hw_us_echo_${i}`, u.echo_pin ?? 255);
        u.tank_depth = numOr(`hw_us_depth_${i}`, u.tank_depth || 150);
        u.air_gap    = numOr(`hw_us_gap_${i}`, u.air_gap || 15);
        u.label      = strOr(`hw_us_lbl_${i}`, u.label || '');
    });
    gHwSensors.mq2s.forEach((g, i) => {
        if (!document.getElementById(`hw_mq2_en_${i}`)) return;
        g.enabled     = (document.getElementById(`hw_mq2_en_${i}`).value === '1');
        g.analog_pin  = numOr(`hw_mq2_apin_${i}`, g.analog_pin ?? 255);
        g.digital_pin = numOr(`hw_mq2_dpin_${i}`, g.digital_pin ?? 255);
        g.label       = strOr(`hw_mq2_lbl_${i}`, g.label || '');
    });
}

function renderHwSensorGroup(key) {
    const meta = SENSOR_GROUP_META[key];
    if (!meta) return;
    const container = document.getElementById(meta.containerId);
    const badge = document.getElementById(meta.badgeId);
    const list = gHwSensors[key] || [];
    const limit = gSensorLimits[key] || 1;
    if (badge) {
        badge.textContent = `${list.length} / ${limit}`;
        badge.className = 'badge ' + (list.length > 0 ? 'badge-ok' : 'badge-info');
    }
    if (!container) return;
    container.innerHTML = '';
    if (list.length === 0) {
        container.innerHTML = `<div style="color:var(--text2);font-size:0.78rem;padding:6px 4px;">${meta.emptyText}</div>`;
        return;
    }

    list.forEach((item, i) => {
        const card = document.createElement('div');
        card.style.cssText = 'background:var(--surface);padding:10px;border-radius:8px;border:1px solid var(--card-border);';
        const header = `<div style="display:flex;align-items:center;justify-content:space-between;gap:8px;margin-bottom:8px;">
            <span style="font-weight:600;font-size:0.8rem;color:var(--accent);">Slot #${i + 1}</span>
            <button type="button" class="btn btn-sm btn-outline" style="padding:1px 7px;font-size:0.72rem;color:var(--red);border-color:rgba(239,68,68,0.4);" onclick="removeHwSensor('${key}',${i})" title="Remove Slot #${i + 1}">&times;</button>
        </div>`;

        if (key === 'climates') {
            const isI2c = item.type >= 3;
            const addrs = getI2cClimateAddrs(item.type);
            const addrOpts = addrs.map(a => `<option value="${a}" ${item.i2c_addr === a ? 'selected' : ''}>${formatHexAddr(a)}</option>`).join('');
            card.innerHTML = header + `<div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:8px;">
                <div class="form-group" style="margin:0"><label style="font-size:0.72rem">Model</label>
                    <select id="hw_cli_type_${i}" onchange="onClimateSlotTypeChange(${i})">
                        <option value="0" ${item.type===0?'selected':''}>Disabled</option>
                        <option value="1" ${item.type===1?'selected':''}>DHT11</option>
                        <option value="2" ${item.type===2?'selected':''}>DHT22 / AM2302</option>
                        <option value="3" ${item.type===3?'selected':''}>BME280 (I2C Baro)</option>
                        <option value="4" ${item.type===4?'selected':''}>AHT20 (I2C)</option>
                        <option value="5" ${item.type===5?'selected':''}>SHT3x (I2C)</option>
                    </select>
                </div>
                <div class="form-group" style="margin:0;${isI2c || item.type===0 ? 'display:none' : ''}"><label style="font-size:0.72rem">Data GPIO Pin</label><select id="hw_cli_pin_${i}" onchange="syncHwSensorsFromDOM();setHwMode('custom');checkHwConflicts()"></select></div>
                <div class="form-group" style="margin:0;${!isI2c ? 'display:none' : ''}"><label style="font-size:0.72rem">I2C Address (Shared Bus)</label><select id="hw_cli_addr_${i}" ${addrs.length<=1?'disabled':''} onchange="syncHwSensorsFromDOM();setHwMode('custom');checkHwConflicts()">${addrOpts}</select></div>
                <div class="form-group" style="margin:0"><label style="font-size:0.72rem">Label (Optional)</label><input type="text" id="hw_cli_lbl_${i}" maxlength="15" placeholder="e.g. Living Room" value="${escapeHtml(item.label || '')}" oninput="syncHwSensorsFromDOM()"></div>
            </div>`;
            container.appendChild(card);
            populatePinOptions(`hw_cli_pin_${i}`, SAFE_OUTPUT_PINS, item.pin, true);
        } else if (key === 'lights') {
            card.innerHTML = header + `<div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:8px;">
                <div class="form-group" style="margin:0"><label style="font-size:0.72rem">Model</label>
                    <select id="hw_lgt_type_${i}" onchange="syncHwSensorsFromDOM();setHwMode('custom');ensureI2cPinsAssigned();renderHwSensorGroup('lights');checkHwConflicts()">
                        <option value="0" ${item.type===0?'selected':''}>Disabled</option>
                        <option value="1" ${item.type===1?'selected':''}>BH1750 (I2C Lux)</option>
                    </select>
                </div>
                <div class="form-group" style="margin:0;${item.type===0?'display:none':''}"><label style="font-size:0.72rem">I2C Address</label>
                    <select id="hw_lgt_addr_${i}" onchange="syncHwSensorsFromDOM();setHwMode('custom');checkHwConflicts()">
                        <option value="35" ${(item.i2c_addr||35)===35?'selected':''}>0x23 (ADDR LOW)</option>
                        <option value="92" ${item.i2c_addr===92?'selected':''}>0x5C (ADDR HIGH)</option>
                    </select>
                </div>
                <div class="form-group" style="margin:0"><label style="font-size:0.72rem">Label (Optional)</label><input type="text" id="hw_lgt_lbl_${i}" maxlength="15" placeholder="e.g. Porch Lux" value="${escapeHtml(item.label || '')}" oninput="syncHwSensorsFromDOM()"></div>
            </div>`;
            container.appendChild(card);
        } else if (key === 'motions') {
            card.innerHTML = header + `<div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:8px;">
                <div class="form-group" style="margin:0"><label style="font-size:0.72rem">Sensor Type</label>
                    <select id="hw_mot_type_${i}" onchange="syncHwSensorsFromDOM();setHwMode('custom');checkHwConflicts()">
                        <option value="0" ${item.type===0?'selected':''}>Disabled</option>
                        <option value="1" ${item.type===1?'selected':''}>PIR Motion Sensor</option>
                        <option value="2" ${item.type===2?'selected':''}>mmWave Radar (LD2410)</option>
                    </select>
                </div>
                <div class="form-group" style="margin:0"><label style="font-size:0.72rem">Digital Input GPIO Pin</label><select id="hw_mot_pin_${i}" onchange="syncHwSensorsFromDOM();setHwMode('custom');checkHwConflicts()"></select></div>
                <div class="form-group" style="margin:0"><label style="font-size:0.72rem">Label (Optional)</label><input type="text" id="hw_mot_lbl_${i}" maxlength="15" placeholder="e.g. Hallway PIR" value="${escapeHtml(item.label || '')}" oninput="syncHwSensorsFromDOM()"></div>
            </div>`;
            container.appendChild(card);
            populatePinOptions(`hw_mot_pin_${i}`, SAFE_INPUT_PINS, item.pin, true);
        } else if (key === 'probes') {
            card.innerHTML = header + `<div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:8px;">
                <div class="form-group" style="margin:0"><label style="font-size:0.72rem">Probe Type</label>
                    <select id="hw_prb_type_${i}" onchange="syncHwSensorsFromDOM();setHwMode('custom');checkHwConflicts()">
                        <option value="0" ${item.type===0?'selected':''}>Disabled</option>
                        <option value="1" ${item.type===1?'selected':''}>DS18B20 (1-Wire Probe)</option>
                    </select>
                </div>
                <div class="form-group" style="margin:0"><label style="font-size:0.72rem">1-Wire GPIO Pin (4.7k&Omega; Pull-up)</label><select id="hw_prb_pin_${i}" onchange="syncHwSensorsFromDOM();setHwMode('custom');checkHwConflicts()"></select></div>
                <div class="form-group" style="margin:0"><label style="font-size:0.72rem">Label (Optional)</label><input type="text" id="hw_prb_lbl_${i}" maxlength="15" placeholder="e.g. Solar Tank" value="${escapeHtml(item.label || '')}" oninput="syncHwSensorsFromDOM()"></div>
            </div>`;
            container.appendChild(card);
            populatePinOptions(`hw_prb_pin_${i}`, SAFE_OUTPUT_PINS, item.pin, true);
        } else if (key === 'ultrasonics') {
            const note5v = item.type === 2 ? `<div style="background:rgba(245,158,11,0.12);border-left:4px solid #f59e0b;padding:8px 10px;border-radius:6px;margin-top:8px;font-size:0.76rem;color:var(--text1);"><b>5V Warning:</b> HC-SR04 ECHO outputs 5V &mdash; use a 1k&Omega;/2k&Omega; voltage divider to protect the 3.3V GPIO.</div>` : '';
            const note3v = item.type === 1 ? `<div style="background:rgba(16,185,129,0.12);border-left:4px solid #10b981;padding:6px 10px;border-radius:6px;margin-top:8px;font-size:0.76rem;color:var(--text1);"><b style="color:#10b981">&#10003; 3.3V Safe:</b> HC-SR04P operates directly at 3.3V logic.</div>` : '';
            card.innerHTML = header + `<div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:8px;">
                <div class="form-group" style="margin:0"><label style="font-size:0.72rem">Module Model</label>
                    <select id="hw_us_type_${i}" onchange="syncHwSensorsFromDOM();setHwMode('custom');renderHwSensorGroup('ultrasonics');checkHwConflicts()">
                        <option value="0" ${item.type===0?'selected':''}>Disabled</option>
                        <option value="1" ${item.type===1?'selected':''}>HC-SR04P (3.3V Safe)</option>
                        <option value="2" ${item.type===2?'selected':''}>HC-SR04 (5V Divider Req)</option>
                        <option value="3" ${item.type===3?'selected':''}>JSN-SR04T (Waterproof)</option>
                    </select>
                </div>
                <div class="form-group" style="margin:0"><label style="font-size:0.72rem">Trigger Pin</label><select id="hw_us_trig_${i}" onchange="syncHwSensorsFromDOM();setHwMode('custom');checkHwConflicts()"></select></div>
                <div class="form-group" style="margin:0"><label style="font-size:0.72rem">Echo Pin</label><select id="hw_us_echo_${i}" onchange="syncHwSensorsFromDOM();setHwMode('custom');checkHwConflicts()"></select></div>
                <div class="form-group" style="margin:0"><label style="font-size:0.72rem">Depth (cm)</label><input type="number" id="hw_us_depth_${i}" value="${item.tank_depth||150}" min="20" max="500" oninput="syncHwSensorsFromDOM();checkHwConflicts()"></div>
                <div class="form-group" style="margin:0"><label style="font-size:0.72rem">Air Gap (cm)</label><input type="number" id="hw_us_gap_${i}" value="${item.air_gap||15}" min="5" max="100" oninput="syncHwSensorsFromDOM();checkHwConflicts()"></div>
                <div class="form-group" style="margin:0"><label style="font-size:0.72rem">Label (Optional)</label><input type="text" id="hw_us_lbl_${i}" maxlength="15" placeholder="e.g. Roof Tank" value="${escapeHtml(item.label || '')}" oninput="syncHwSensorsFromDOM()"></div>
            </div>${note5v}${note3v}`;
            container.appendChild(card);
            populatePinOptions(`hw_us_trig_${i}`, SAFE_OUTPUT_PINS, item.trig_pin, true);
            populatePinOptions(`hw_us_echo_${i}`, SAFE_INPUT_PINS, item.echo_pin, true);
        } else if (key === 'mq2s') {
            card.innerHTML = header + `<div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:8px;">
                <div class="form-group" style="margin:0"><label style="font-size:0.72rem">Status</label>
                    <select id="hw_mq2_en_${i}" onchange="syncHwSensorsFromDOM();setHwMode('custom');checkHwConflicts()">
                        <option value="1" ${item.enabled!==false?'selected':''}>Enabled</option>
                        <option value="0" ${item.enabled===false?'selected':''}>Disabled</option>
                    </select>
                </div>
                <div class="form-group" style="margin:0"><label style="font-size:0.72rem">Analog Pin (ADC1 only)</label><select id="hw_mq2_apin_${i}" onchange="syncHwSensorsFromDOM();setHwMode('custom');checkHwConflicts()"></select></div>
                <div class="form-group" style="margin:0"><label style="font-size:0.72rem">Digital DO Pin</label><select id="hw_mq2_dpin_${i}" onchange="syncHwSensorsFromDOM();setHwMode('custom');checkHwConflicts()"></select></div>
                <div class="form-group" style="margin:0"><label style="font-size:0.72rem">Label (Optional)</label><input type="text" id="hw_mq2_lbl_${i}" maxlength="15" placeholder="e.g. Kitchen Gas" value="${escapeHtml(item.label || '')}" oninput="syncHwSensorsFromDOM()"></div>
            </div>`;
            container.appendChild(card);
            populatePinOptions(`hw_mq2_apin_${i}`, ADC1_PINS, item.analog_pin, true);
            populatePinOptions(`hw_mq2_dpin_${i}`, SAFE_INPUT_PINS, item.digital_pin, true);
        }
    });
}

function renderAllHwSensors() {
    Object.keys(SENSOR_GROUP_META).forEach(k => renderHwSensorGroup(k));
}

function onClimateSlotTypeChange(idx) {
    syncHwSensorsFromDOM();
    const c = gHwSensors.climates[idx];
    if (!c) return;
    if (c.type >= 3) {
        const allowed = getI2cClimateAddrs(c.type);
        if (!allowed.includes(c.i2c_addr)) {
            const usedI2c = getUsedI2cAddrs('climates', idx);
            c.i2c_addr = allowed.find(a => !usedI2c.has(a)) || allowed[0];
        }
        c.pin = 255;
        ensureI2cPinsAssigned();
    } else if (c.type === 1 || c.type === 2) {
        c.i2c_addr = 0;
        if (c.pin === 255 || c.pin === undefined) {
            const used = getAllFormUsedPins();
            c.pin = pickFreePinFromSet(used, SAFE_OUTPUT_PINS, gIsEsp8266 ? 14 : 4);
        }
    }
    setHwMode('custom');
    renderHwSensorGroup('climates');
    checkHwConflicts();
}

function addHwSensor(key) {
    syncHwSensorsFromDOM();
    const list = gHwSensors[key];
    const limit = gSensorLimits[key] || 1;
    if (!list) return;
    if (list.length >= limit) {
        toast(`Maximum ${limit} ${key} sensors supported`, 'warn');
        return;
    }

    const usedPins = getAllFormUsedPins();
    const usedI2c = getUsedI2cAddrs();
    let warned = '';

    if (key === 'climates') {
        const freeGpio = pickFreePinFromSet(usedPins, SAFE_OUTPUT_PINS, list.length === 0 ? (gIsEsp8266 ? 14 : 4) : undefined);
        if (freeGpio !== 255) {
            list.push({ type: 2, pin: freeGpio, i2c_addr: 0, label: '' });
        } else {
            const i2cChoices = [
                { type: 5, addr: 0x44 }, { type: 5, addr: 0x45 },
                { type: 3, addr: 0x76 }, { type: 3, addr: 0x77 },
                { type: 4, addr: 0x38 }
            ];
            const pick = i2cChoices.find(x => !usedI2c.has(x.addr));
            if (pick) {
                list.push({ type: pick.type, pin: 255, i2c_addr: pick.addr, label: '' });
                ensureI2cPinsAssigned();
            } else {
                list.push({ type: 2, pin: 255, i2c_addr: 0, label: '' });
                warned = 'no free output GPIO or unused I2C address';
            }
        }
    } else if (key === 'lights') {
        const freeAddr = [0x23, 0x5C].find(a => !usedI2c.has(a));
        if (freeAddr === undefined) {
            toast('Both BH1750 I2C addresses (0x23 & 0x5C) are already assigned', 'warn');
            return;
        }
        list.push({ type: 1, i2c_addr: freeAddr, label: '' });
        ensureI2cPinsAssigned();
    } else if (key === 'motions') {
        const freePin = pickFreePinFromSet(usedPins, SAFE_INPUT_PINS, list.length === 0 ? (gIsEsp8266 ? 14 : 32) : undefined);
        list.push({ type: 1, pin: freePin, label: '' });
        if (freePin === 255) warned = 'no free Input GPIO';
    } else if (key === 'probes') {
        const freePin = pickFreePinFromSet(usedPins, SAFE_OUTPUT_PINS, list.length === 0 ? (gIsEsp8266 ? 13 : 15) : undefined);
        list.push({ type: 1, pin: freePin, label: '' });
        if (freePin === 255) warned = 'no free Output/1-Wire GPIO';
    } else if (key === 'ultrasonics') {
        const trig = pickFreePinFromSet(usedPins, SAFE_OUTPUT_PINS, list.length === 0 ? (gIsEsp8266 ? 14 : 15) : undefined);
        const uCopy = new Set(usedPins);
        if (trig !== 255) uCopy.add(trig);
        const echo = pickFreePinFromSet(uCopy, SAFE_INPUT_PINS, list.length === 0 ? (gIsEsp8266 ? 12 : 35) : undefined);
        list.push({ type: 1, trig_pin: trig, echo_pin: echo, tank_depth: 150, air_gap: 15, label: '' });
        if (trig === 255 || echo === 255) warned = 'not enough free GPIOs for Trig + Echo';
    } else if (key === 'mq2s') {
        const aPin = pickFreePinFromSet(usedPins, ADC1_PINS, list.length === 0 ? (gIsEsp8266 ? 17 : 34) : undefined);
        const uCopy = new Set(usedPins);
        if (aPin !== 255) uCopy.add(aPin);
        let dPin = 255;
        if (aPin === 255) {
            dPin = pickFreePinFromSet(uCopy, SAFE_INPUT_PINS);
        } else if (!gIsEsp8266 && list.length === 0 && !uCopy.has(35)) {
            dPin = 35;
        }
        list.push({ enabled: true, analog_pin: aPin, digital_pin: dPin, label: '' });
        if (aPin === 255 && dPin === 255) warned = 'no free ADC1 or digital DO GPIO';
        else if (aPin === 255 && gIsEsp8266) toast('Slot added using Digital DO pin (ESP8266 has 1 A0 ADC)', 'info');
    }

    setHwMode('custom');
    renderHwSensorGroup(key);
    checkHwConflicts();
    if (warned) toast(`Slot added (${warned} — free a pin or disable another item)`, 'warn');
}

function removeHwSensor(key, idx) {
    syncHwSensorsFromDOM();
    const list = gHwSensors[key];
    if (!list || list.length === 0) return;
    if (idx !== undefined && idx >= 0 && idx < list.length) list.splice(idx, 1);
    else list.pop();
    setHwMode('custom');
    renderHwSensorGroup(key);
    checkHwConflicts();
}

function initHwDefaults() {
    if (gIsEsp8266) {
        SAFE_OUTPUT_PINS = ESP8266_OUTPUT_PINS;
        SAFE_INPUT_PINS  = ESP8266_INPUT_PINS;
        ADC1_PINS        = ESP8266_ADC_PINS;
    }
    applyHwDataToForm({
        board_name: gIsEsp8266 ? 'SmartHome ESP8266 2-CH Dual' : 'SmartHome 5-CH Standard',
        num_relays: gIsEsp8266 ? 2 : 5,
        channels: gIsEsp8266 ? [
            { enabled: true, switch_enabled: true, relay_pin: 12, switch_pin: 13, switch_mode: 0, trigger: 0 },
            { enabled: true, switch_enabled: true, relay_pin: 14, switch_pin: 16, switch_mode: 0, trigger: 0 }
        ] : [],
        climates: gIsEsp8266 ? [] : [{ type: 2, pin: 4, i2c_addr: 0, label: '' }],
        lights: [],
        motions: [],
        probes: [],
        ultrasonics: [],
        mq2_sensors: [{ enabled: true, analog_pin: gIsEsp8266 ? 17 : 34, digital_pin: gIsEsp8266 ? 255 : 35, label: '' }],
        buzzer: { enabled: true, pin: gIsEsp8266 ? 2 : 5 },
        lcd: { enabled: true, i2c_addr: 39, cols: 16, rows: 2, sda_pin: gIsEsp8266 ? 4 : 21, scl_pin: gIsEsp8266 ? 5 : 22 },
        btn_multi_pin: gIsEsp8266 ? 0 : 33
    });
}

function onPeripheralToggle() {
    setHwMode('custom');
    const buzEn = document.getElementById('hwBuzEn');
    if (buzEn && buzEn.value === '1') {
        const bp = document.getElementById('hwBuzPin');
        if (bp && (parseInt(bp.value) === 255 || isNaN(parseInt(bp.value)))) {
            const p = pickFreePinFromSet(getAllFormUsedPins('hwBuzPin'), SAFE_OUTPUT_PINS, gIsEsp8266 ? 2 : 5);
            if (p !== 255) bp.value = String(p);
        }
    }
    ensureI2cPinsAssigned();
}

function getFormNonChannelUsedPins() {
    syncHwSensorsFromDOM();
    const used = new Set();
    const addPin = (p) => { if (p !== undefined && p !== null && !isNaN(p) && p !== 255) used.add(Number(p)); };
    gHwSensors.climates.forEach(c => { if (c && (c.type === 1 || c.type === 2)) addPin(c.pin); });
    gHwSensors.motions.forEach(m => { if (m && m.type !== 0) addPin(m.pin); });
    gHwSensors.probes.forEach(p => { if (p && p.type !== 0) addPin(p.pin); });
    gHwSensors.ultrasonics.forEach(u => { if (u && u.type !== 0) { addPin(u.trig_pin); addPin(u.echo_pin); } });
    gHwSensors.mq2s.forEach(g => { if (g && g.enabled !== false) { addPin(g.analog_pin); addPin(g.digital_pin); } });

    const addEl = (id) => { const el = document.getElementById(id); if (el) addPin(parseInt(el.value)); };
    if ((document.getElementById('hwBuzEn') || {}).value === '1') addEl('hwBuzPin');
    const lcdOn = (document.getElementById('hwLcdEn') || {}).value === '1';
    if (lcdOn || hasAnyI2cSensorActive()) { addEl('hwLcdSda'); addEl('hwLcdScl'); }
    addEl('hwBtnMultiPin');
    return used;
}

function getAllFormUsedPins(excludeElId) {
    const used = getFormNonChannelUsedPins();
    const num = parseInt((document.getElementById('hwNumRelays') || {}).value || '0') || 0;
    for (let i = 0; i < num; i++) {
        const enEl = document.getElementById(`hw_en_${i}`);
        const swEnEl = document.getElementById(`hw_swen_${i}`);
        if (enEl && enEl.value !== '1') continue;
        const rEl = document.getElementById(`hw_rpin_${i}`);
        if (rEl && rEl.id !== excludeElId) {
            const rp = parseInt(rEl.value);
            if (!isNaN(rp) && rp !== 255) used.add(rp);
        }
        const isSwEn = !swEnEl || swEnEl.value === '1';
        const sEl = document.getElementById(`hw_spin_${i}`);
        if (isSwEn && sEl && sEl.id !== excludeElId) {
            const sp = parseInt(sEl.value);
            if (!isNaN(sp) && sp !== 255) used.add(sp);
        }
    }
    if (excludeElId) {
        const exEl = document.getElementById(excludeElId);
        if (exEl) {
            const ep = parseInt(exEl.value);
            if (!isNaN(ep) && ep !== 255) used.delete(ep);
        }
    }
    return used;
}

function applyHwDataToForm(data) {
    if (data.platform) gIsEsp8266 = (data.platform === 'ESP8266');
    else if (data.board_name && data.board_name.includes('ESP8266')) gIsEsp8266 = true;

    if (data.pin_capabilities) {
        SAFE_OUTPUT_PINS = data.pin_capabilities.outputs || SAFE_OUTPUT_PINS;
        SAFE_INPUT_PINS  = data.pin_capabilities.inputs  || SAFE_INPUT_PINS;
        ADC1_PINS        = data.pin_capabilities.adc1    || ADC1_PINS;
        if (data.pin_capabilities.sensor_limits) {
            Object.assign(gSensorLimits, data.pin_capabilities.sensor_limits);
        }
    } else if (gIsEsp8266) {
        SAFE_OUTPUT_PINS = ESP8266_OUTPUT_PINS;
        SAFE_INPUT_PINS  = ESP8266_INPUT_PINS;
        ADC1_PINS        = ESP8266_ADC_PINS;
    }

    document.getElementById('hwBoardName').value = data.board_name || (gIsEsp8266 ? 'SmartHome ESP8266 2-CH Dual' : 'SmartHome 5-CH Standard');
    const numRelays = data.num_relays !== undefined ? data.num_relays : (gIsEsp8266 ? 2 : 5);
    document.getElementById('hwNumRelays').value = numRelays;

    // Populate multi-instance sensors (new array format OR legacy slot-0 fallback)
    if (Array.isArray(data.climates)) {
        gHwSensors.climates = data.climates.map(c => ({
            type: c.type ?? 0, pin: c.pin ?? 255, i2c_addr: c.i2c_addr ?? (c.type >= 3 ? getI2cClimateAddrs(c.type)[0] : 0), label: c.label || ''
        }));
    } else if (data.dht && data.dht.type > 0) {
        gHwSensors.climates = [{ type: data.dht.type, pin: data.dht.pin ?? 255, i2c_addr: data.dht.i2c_addr || (data.dht.type >= 3 ? getI2cClimateAddrs(data.dht.type)[0] : 0), label: '' }];
    } else {
        gHwSensors.climates = [];
    }

    if (Array.isArray(data.lights)) {
        gHwSensors.lights = data.lights.map(l => ({ type: l.type ?? 0, i2c_addr: l.i2c_addr || 0x23, label: l.label || '' }));
    } else if (data.light && data.light.type > 0) {
        gHwSensors.lights = [{ type: data.light.type, i2c_addr: data.light.i2c_addr || 0x23, label: '' }];
    } else {
        gHwSensors.lights = [];
    }

    if (Array.isArray(data.motions)) {
        gHwSensors.motions = data.motions.map(m => ({ type: m.type ?? 0, pin: m.pin ?? 255, label: m.label || '' }));
    } else if (data.motion && data.motion.type > 0) {
        gHwSensors.motions = [{ type: data.motion.type, pin: data.motion.pin ?? 255, label: '' }];
    } else {
        gHwSensors.motions = [];
    }

    if (Array.isArray(data.probes)) {
        gHwSensors.probes = data.probes.map(p => ({ type: p.type ?? 0, pin: p.pin ?? 255, label: p.label || '' }));
    } else if (data.probe && data.probe.type > 0) {
        gHwSensors.probes = [{ type: data.probe.type, pin: data.probe.pin ?? 255, label: '' }];
    } else {
        gHwSensors.probes = [];
    }

    if (Array.isArray(data.ultrasonics)) {
        gHwSensors.ultrasonics = data.ultrasonics.map(u => ({
            type: u.type ?? 0, trig_pin: u.trig_pin ?? 255, echo_pin: u.echo_pin ?? 255,
            tank_depth: u.tank_depth ?? 150, air_gap: u.air_gap ?? 15, label: u.label || ''
        }));
    } else if (data.ultrasonic && data.ultrasonic.type > 0) {
        gHwSensors.ultrasonics = [{
            type: data.ultrasonic.type, trig_pin: data.ultrasonic.trig_pin ?? 255, echo_pin: data.ultrasonic.echo_pin ?? 255,
            tank_depth: data.ultrasonic.tank_depth ?? 150, air_gap: data.ultrasonic.air_gap ?? 15, label: ''
        }];
    } else {
        gHwSensors.ultrasonics = [];
    }

    if (Array.isArray(data.mq2_sensors)) {
        gHwSensors.mq2s = data.mq2_sensors.map(g => ({
            enabled: g.enabled !== false, analog_pin: g.analog_pin ?? 255, digital_pin: g.digital_pin ?? 255, label: g.label || ''
        }));
    } else if (data.mq2 && data.mq2.enabled !== false && ((data.mq2.analog_pin !== undefined && data.mq2.analog_pin !== 255) || (data.mq2.digital_pin !== undefined && data.mq2.digital_pin !== 255))) {
        gHwSensors.mq2s = [{ enabled: data.mq2.enabled !== false, analog_pin: data.mq2.analog_pin ?? 255, digital_pin: data.mq2.digital_pin ?? 255, label: '' }];
    } else {
        gHwSensors.mq2s = [];
    }

    // Buzzer
    document.getElementById('hwBuzEn').value = (data.buzzer && data.buzzer.enabled !== undefined) ? (data.buzzer.enabled ? '1' : '0') : '1';
    populatePinOptions('hwBuzPin', SAFE_OUTPUT_PINS, (data.buzzer && data.buzzer.pin !== undefined) ? data.buzzer.pin : (gIsEsp8266 ? 2 : 5), true);

    // LCD
    document.getElementById('hwLcdEn').value = (data.lcd && data.lcd.enabled !== undefined) ? (data.lcd.enabled ? '1' : '0') : '1';
    document.getElementById('hwLcdAddr').value = (data.lcd && data.lcd.i2c_addr !== undefined) ? data.lcd.i2c_addr : 39;
    document.getElementById('hwLcdSize').value = (data.lcd && data.lcd.rows === 4) ? '20x4' : '16x2';
    populatePinOptions('hwLcdSda', SAFE_OUTPUT_PINS, (data.lcd && data.lcd.sda_pin !== undefined) ? data.lcd.sda_pin : (gIsEsp8266 ? 4 : 21), true);
    populatePinOptions('hwLcdScl', SAFE_OUTPUT_PINS, (data.lcd && data.lcd.scl_pin !== undefined) ? data.lcd.scl_pin : (gIsEsp8266 ? 5 : 22), true);

    // Multi-button
    populatePinOptions('hwBtnMultiPin', SAFE_INPUT_PINS, data.btn_multi_pin !== undefined ? data.btn_multi_pin : (gIsEsp8266 ? 0 : 33), true);

    renderAllHwSensors();
    renderHwChannels(numRelays, data.channels || []);
    checkHwConflicts();
}

function loadHardware() {
    api('GET', '/api/hardware').then(data => {
        gHwConfig = data;
        gIsEsp8266 = (data.platform === 'ESP8266') || (data.board_name && data.board_name.includes('ESP8266'));

        const sel = document.getElementById('hwPresetSelect');
        if (sel && data.presets && Array.isArray(data.presets)) {
            sel.innerHTML = '<option value="">-- Quick Load Preset --</option>';
            data.presets.forEach(p => {
                const opt = document.createElement('option');
                opt.value = p;
                opt.textContent = p;
                sel.appendChild(opt);
            });
        }

        const btnReset = document.getElementById('btnHwReset');
        if (btnReset) {
            btnReset.textContent = gIsEsp8266 ? 'Reset Default 2-CH' : 'Reset Default 5-CH';
        }

        applyHwDataToForm(data);
        const isPreset = data.presets && data.presets.includes(data.board_name);
        if (data.board_name && !isPreset) {
            setHwMode('custom');
        } else {
            setHwMode('preset');
            if (sel && isPreset) sel.value = data.board_name;
        }
    }).catch(err => {
        toast('Failed to load hardware profile: ' + (err.message || ''), 'err');
    });
}

function renderHwChannelsFromUI() {
    const num = parseInt(document.getElementById('hwNumRelays').value) || 0;
    const currentChannels = [];
    for (let i = 0; i < 8; i++) {
        const rPin = document.getElementById(`hw_rpin_${i}`);
        const sPin = document.getElementById(`hw_spin_${i}`);
        const sMode = document.getElementById(`hw_smode_${i}`);
        const trig = document.getElementById(`hw_trig_${i}`);
        const enEl = document.getElementById(`hw_en_${i}`);
        const swEnEl = document.getElementById(`hw_swen_${i}`);
        if (rPin) {
            currentChannels.push({
                enabled: enEl ? (enEl.value === '1') : true,
                switch_enabled: swEnEl ? (swEnEl.value === '1') : true,
                relay_pin: parseInt(rPin.value),
                switch_pin: parseInt(sPin.value),
                switch_mode: parseInt(sMode.value),
                trigger: parseInt(trig.value)
            });
        }
    }
    renderHwChannels(num, currentChannels);
    checkHwConflicts();
}

function onHwChannelToggle(i) {
    const enEl = document.getElementById(`hw_en_${i}`);
    const swEnEl = document.getElementById(`hw_swen_${i}`);
    const badgeEl = document.getElementById(`hw_badge_${i}`);
    const relayRow = document.getElementById(`hw_relay_row_${i}`);
    const swRow = document.getElementById(`hw_sw_row_${i}`);
    const cardEl = document.getElementById(`hw_card_${i}`);

    const isChEn = !enEl || enEl.value === '1';
    const isSwEn = isChEn && (!swEnEl || swEnEl.value === '1');

    if (badgeEl) {
        badgeEl.className = 'badge ' + (isChEn ? 'badge-ok' : 'badge-err');
        badgeEl.textContent = isChEn ? 'ACTIVE' : 'DISABLED';
    }
    if (cardEl) {
        cardEl.style.borderColor = isChEn ? 'var(--card-border)' : 'rgba(239,68,68,0.35)';
    }
    if (relayRow) {
        relayRow.style.opacity = isChEn ? '1' : '0.4';
        relayRow.style.pointerEvents = isChEn ? 'auto' : 'none';
    }
    if (swEnEl) {
        swEnEl.disabled = !isChEn;
        swEnEl.style.opacity = isChEn ? '1' : '0.5';
    }
    if (swRow) {
        swRow.style.opacity = isSwEn ? '1' : '0.4';
        swRow.style.pointerEvents = isSwEn ? 'auto' : 'none';
    }
    checkHwConflicts();
}

function checkHwConflicts() {
    syncHwSensorsFromDOM();
    const alertBox = document.getElementById('hwConflictAlert');
    const num = parseInt(document.getElementById('hwNumRelays').value) || 0;
    const usedPins = {};
    const usedI2c = {};
    const conflicts = [];
    const conflictPins = new Set();
    const inOnlyPins = gIsEsp8266 ? [17] : [34, 35, 36, 39];

    function claim(pin, name, isOutput, isAdc = false) {
        if (pin === 255 || pin === undefined || isNaN(pin)) return;
        if (gIsEsp8266 && pin === 17 && !isAdc) {
            conflictPins.add(pin);
            conflicts.push(`A0 (GPIO 17) is Analog ADC-only and CANNOT be used for digital "${name}".`);
        }
        if (isOutput && inOnlyPins.includes(pin)) {
            conflictPins.add(pin);
            conflicts.push(`GPIO ${pin} ("${name}") is an Input-Only pin and CANNOT be used as an output or bidirectional line.`);
        }
        if (usedPins[pin]) {
            conflictPins.add(pin);
            conflicts.push(`GPIO ${pin} is assigned to both "${usedPins[pin]}" and "${name}"`);
        } else {
            usedPins[pin] = name;
        }
    }

    function claimI2c(addr, name) {
        if (!addr || isNaN(addr)) return;
        if (usedI2c[addr]) {
            conflicts.push(`I2C address ${formatHexAddr(addr)} is assigned to both "${usedI2c[addr]}" and "${name}".`);
        } else {
            usedI2c[addr] = name;
        }
    }

    for (let i = 0; i < num; i++) {
        const enEl = document.getElementById(`hw_en_${i}`);
        const swEnEl = document.getElementById(`hw_swen_${i}`);
        const isChEn = !enEl || enEl.value === '1';
        const isSwEn = isChEn && (!swEnEl || swEnEl.value === '1');
        if (!isChEn) continue;

        const rEl = document.getElementById(`hw_rpin_${i}`);
        const sEl = document.getElementById(`hw_spin_${i}`);
        if (rEl) {
            const rp = parseInt(rEl.value);
            if (rp === 255 || isNaN(rp)) conflicts.push(`Relay ${i + 1} is Enabled but has no Output Pin assigned.`);
            else claim(rp, `Relay ${i + 1} Output`, true);
        }
        if (isSwEn && sEl) {
            const sp = parseInt(sEl.value);
            if (sp === 255 || isNaN(sp)) conflicts.push(`Relay ${i + 1} Switch is Enabled but has no Input Pin assigned.`);
            else claim(sp, `Relay ${i + 1} Switch`, false);
        }
    }

    gHwSensors.climates.forEach((c, i) => {
        if (!c || c.type === 0) return;
        const slotName = `Climate #${i + 1}`;
        if (c.type === 1 || c.type === 2) {
            if (c.pin === 255 || isNaN(c.pin)) conflicts.push(`${slotName} (${c.type===1?'DHT11':'DHT22'}) has no Data Pin assigned.`);
            else claim(c.pin, slotName, true);
        } else {
            const addr = c.i2c_addr || getI2cClimateAddrs(c.type)[0] || 0;
            claimI2c(addr, slotName);
        }
    });

    gHwSensors.lights.forEach((l, i) => {
        if (!l || l.type === 0) return;
        claimI2c(l.i2c_addr || 0x23, `Light #${i + 1}`);
    });

    gHwSensors.motions.forEach((m, i) => {
        if (!m || m.type === 0) return;
        const slotName = `Motion #${i + 1}`;
        if (m.pin === 255 || isNaN(m.pin)) conflicts.push(`${slotName} has no Signal Pin assigned.`);
        else claim(m.pin, slotName, false);
    });

    gHwSensors.probes.forEach((p, i) => {
        if (!p || p.type === 0) return;
        const slotName = `Probe #${i + 1}`;
        if (p.pin === 255 || isNaN(p.pin)) conflicts.push(`${slotName} has no Data Pin assigned.`);
        else claim(p.pin, slotName, true);
    });

    gHwSensors.ultrasonics.forEach((u, i) => {
        if (!u || u.type === 0) return;
        const slotName = `Tank #${i + 1}`;
        if (u.trig_pin === 255 || isNaN(u.trig_pin) || u.echo_pin === 255 || isNaN(u.echo_pin)) {
            conflicts.push(`${slotName} is Enabled but Trig or Echo pin is unassigned.`);
        } else {
            claim(u.trig_pin, `${slotName} Trig`, true);
            claim(u.echo_pin, `${slotName} Echo`, false);
        }
        if (isNaN(u.tank_depth) || u.tank_depth < 20 || u.tank_depth > 500 || isNaN(u.air_gap) || u.air_gap < 5 || u.air_gap > 100 || u.tank_depth <= u.air_gap) {
            conflicts.push(`${slotName} Tank Depth (20-500 cm) must exceed Air Gap (5-100 cm).`);
        }
    });

    gHwSensors.mq2s.forEach((g, i) => {
        if (!g || g.enabled === false) return;
        const slotName = `Gas #${i + 1}`;
        const hasAnalog = (g.analog_pin !== 255 && !isNaN(g.analog_pin));
        const hasDigital = (g.digital_pin !== 255 && !isNaN(g.digital_pin));
        if (!hasAnalog && !hasDigital) {
            conflicts.push(`${slotName} is Enabled but neither Analog nor Digital DO pin is assigned.`);
        } else {
            if (hasAnalog) claim(g.analog_pin, `${slotName} A0`, false, true);
            if (hasDigital) claim(g.digital_pin, `${slotName} DO`, false);
        }
    });

    const buzEn = document.getElementById('hwBuzEn').value === '1';
    if (buzEn) {
        const bp = parseInt(document.getElementById('hwBuzPin').value);
        if (bp === 255 || isNaN(bp)) conflicts.push('Buzzer is Enabled but no GPIO pin is selected.');
        else claim(bp, 'Buzzer', true);
    }

    const lcdEn = document.getElementById('hwLcdEn').value === '1';
    if (lcdEn) claimI2c(parseInt(document.getElementById('hwLcdAddr').value || '39'), 'I2C LCD');

    if (lcdEn || hasAnyI2cSensorActive()) {
        const sda = parseInt(document.getElementById('hwLcdSda').value);
        const scl = parseInt(document.getElementById('hwLcdScl').value);
        if (sda === 255 || isNaN(sda) || scl === 255 || isNaN(scl)) conflicts.push('I2C Bus is active (LCD/Sensor) but SDA or SCL pin is unassigned.');
        else {
            claim(sda, 'I2C SDA (Shared Bus)', true);
            claim(scl, 'I2C SCL (Shared Bus)', true);
        }
    }

    claim(parseInt(document.getElementById('hwBtnMultiPin').value), 'Multi-Button', false);

    renderPinMatrix(usedPins, conflicts, conflictPins);

    if (alertBox) {
        if (conflicts.length > 0) {
            alertBox.innerHTML = '<strong>GPIO Conflict / Hardware Incompatibility Detected:</strong><br>' + conflicts.join('<br>');
            alertBox.style.display = 'block';
            return false;
        } else {
            alertBox.style.display = 'none';
            return true;
        }
    }
    return conflicts.length === 0;
}

function renderHwChannels(num, existingChannels) {
    const container = document.getElementById('hwChannelsContainer');
    if (!container) return;
    container.innerHTML = '';

    if (num === 0) {
        container.innerHTML = '<div style="color:var(--text2);padding:14px;background:var(--bg);border-radius:8px;text-align:center;">Sensor-Only Node (0 Relays active)</div>';
        return;
    }

    const defaultRelayPins = gIsEsp8266 ? [12, 14, 4, 5, 13, 15, 0, 16] : [16, 17, 18, 19, 23, 25, 26, 27];
    const defaultSwitchPins = gIsEsp8266 ? [13, 16, 255, 255, 255, 255, 255, 255] : [13, 14, 27, 26, 25, 255, 255, 255];
    const usedNow = getFormNonChannelUsedPins();
    if (existingChannels) {
        existingChannels.forEach((c, idx) => {
            if (idx < num && c && c.enabled !== false) {
                if (c.relay_pin !== undefined && c.relay_pin !== 255) usedNow.add(c.relay_pin);
                if (c.switch_enabled !== false && c.switch_pin !== undefined && c.switch_pin !== 255) usedNow.add(c.switch_pin);
            }
        });
    }
    const strapSet = new Set(gIsEsp8266 ? [0, 2, 15] : [0, 2, 12, 15]);
    const pickFreePin = (list, preferred) => {
        if (preferred !== undefined && preferred !== 255 && list.includes(preferred) && !usedNow.has(preferred)) {
            usedNow.add(preferred);
            return preferred;
        }
        const clean = list.find(p => !usedNow.has(p) && !strapSet.has(p));
        if (clean !== undefined) { usedNow.add(clean); return clean; }
        const anyFree = list.find(p => !usedNow.has(p));
        if (anyFree !== undefined) { usedNow.add(anyFree); return anyFree; }
        return 255;
    };

    for (let i = 0; i < num; i++) {
        let ch;
        if (existingChannels && existingChannels[i]) {
            ch = existingChannels[i];
        } else {
            const rPin = pickFreePin(SAFE_OUTPUT_PINS, defaultRelayPins[i]);
            const wantsDefSw = (defaultSwitchPins[i] !== undefined && defaultSwitchPins[i] !== 255 && !usedNow.has(defaultSwitchPins[i]));
            const sPin = wantsDefSw ? pickFreePin(SAFE_INPUT_PINS, defaultSwitchPins[i]) : 255;
            ch = {
                enabled: true,
                switch_enabled: (sPin !== 255),
                relay_pin: rPin,
                switch_pin: sPin,
                switch_mode: 0,
                trigger: 0
            };
        }
        const isChEn = ch.enabled !== false;
        const isSwEn = ch.switch_enabled !== false;

        const row = document.createElement('div');
        row.id = `hw_card_${i}`;
        row.style.background = 'var(--bg)';
        row.style.padding = '12px';
        row.style.borderRadius = '8px';
        row.style.border = '1px solid ' + (isChEn ? 'var(--card-border)' : 'rgba(239,68,68,0.35)');
        row.innerHTML = `
            <div style="display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:8px;margin-bottom:10px;padding-bottom:8px;border-bottom:1px solid var(--card-border);">
                <div style="display:flex;align-items:center;gap:8px;">
                    <span style="font-weight:600;font-size:0.88rem;color:var(--accent);">Relay Channel ${i + 1}</span>
                    <span id="hw_badge_${i}" class="badge ${isChEn ? 'badge-ok' : 'badge-err'}">${isChEn ? 'ACTIVE' : 'DISABLED'}</span>
                </div>
                <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap;">
                    <div style="display:flex;align-items:center;gap:6px;">
                        <label style="font-size:0.72rem;margin:0;color:var(--text2);">Channel:</label>
                        <select id="hw_en_${i}" onchange="onHwChannelToggle(${i})" style="width:auto;padding:4px 8px;font-size:0.75rem;">
                            <option value="1" ${isChEn ? 'selected' : ''}>Enabled (Active)</option>
                            <option value="0" ${!isChEn ? 'selected' : ''}>Disabled (Unused)</option>
                        </select>
                    </div>
                    <div style="display:flex;align-items:center;gap:6px;">
                        <label style="font-size:0.72rem;margin:0;color:var(--text2);">Wall Switch:</label>
                        <select id="hw_swen_${i}" onchange="onHwChannelToggle(${i})" style="width:auto;padding:4px 8px;font-size:0.75rem;" ${!isChEn ? 'disabled' : ''}>
                            <option value="1" ${isSwEn ? 'selected' : ''}>Switch Enabled</option>
                            <option value="0" ${!isSwEn ? 'selected' : ''}>Switch Disabled</option>
                        </select>
                    </div>
                </div>
            </div>
            <div class="form-row" style="margin-bottom:0">
                <div id="hw_relay_row_${i}" style="display:contents;opacity:${isChEn ? '1' : '0.4'};pointer-events:${isChEn ? 'auto' : 'none'}">
                    <div class="form-group" style="margin-bottom:6px">
                        <label style="font-size:0.75rem">Relay Output Pin</label>
                        <select id="hw_rpin_${i}" onchange="checkHwConflicts()"></select>
                    </div>
                    <div class="form-group" style="margin-bottom:6px">
                        <label style="font-size:0.75rem">Trigger Logic</label>
                        <select id="hw_trig_${i}">
                            <option value="0" ${ch.trigger === 0 ? 'selected' : ''}>Active LOW (0V = ON)</option>
                            <option value="1" ${ch.trigger === 1 ? 'selected' : ''}>Active HIGH (3.3V = ON)</option>
                        </select>
                    </div>
                </div>
                <div id="hw_sw_row_${i}" style="display:contents;opacity:${(isChEn && isSwEn) ? '1' : '0.4'};pointer-events:${(isChEn && isSwEn) ? 'auto' : 'none'}">
                    <div class="form-group" style="margin-bottom:6px">
                        <label style="font-size:0.75rem">Wall Switch Pin</label>
                        <select id="hw_spin_${i}" onchange="checkHwConflicts()"></select>
                    </div>
                    <div class="form-group" style="margin-bottom:6px">
                        <label style="font-size:0.75rem">Switch Mode</label>
                        <select id="hw_smode_${i}">
                            <option value="0" ${ch.switch_mode === 0 ? 'selected' : ''}>Toggle Rocker (Any Edge)</option>
                            <option value="1" ${ch.switch_mode === 1 ? 'selected' : ''}>Follow (Closed = ON)</option>
                            <option value="2" ${ch.switch_mode === 2 ? 'selected' : ''}>Follow Inverted</option>
                            <option value="3" ${ch.switch_mode === 3 ? 'selected' : ''}>Push-Button (Momentary)</option>
                            <option value="4" ${ch.switch_mode === 4 ? 'selected' : ''}>Detached (Decoupled)</option>
                        </select>
                    </div>
                </div>
            </div>
        `;
        container.appendChild(row);

        populatePinOptions(`hw_rpin_${i}`, SAFE_OUTPUT_PINS, ch.relay_pin, true);
        populatePinOptions(`hw_spin_${i}`, SAFE_INPUT_PINS, ch.switch_pin, true);
        onHwChannelToggle(i);
    }
}

function setHwMode(mode) {
    const btnPre = document.getElementById('btnHwModePreset');
    const btnCus = document.getElementById('btnHwModeCustom');
    const preBar = document.getElementById('hwPresetControls');
    if (mode === 'preset') {
        if (btnPre) { btnPre.className = 'btn btn-sm btn-primary'; btnPre.style.border = ''; }
        if (btnCus) { btnCus.className = 'btn btn-sm btn-outline'; btnCus.style.border = 'none'; }
        if (preBar) preBar.style.display = 'flex';
    } else {
        if (btnCus) { btnCus.className = 'btn btn-sm btn-primary'; btnCus.style.border = ''; }
        if (btnPre) { btnPre.className = 'btn btn-sm btn-outline'; btnPre.style.border = 'none'; }
        if (preBar) preBar.style.display = 'none';
        const bName = document.getElementById('hwBoardName');
        const isKnownPreset = bName && (
            (gHwConfig && Array.isArray(gHwConfig.presets) && gHwConfig.presets.includes(bName.value)) ||
            /(Standard|Mini|Dual|Pro|Quad|Max|Sensor Node)/.test(bName.value)
        );
        if (bName && (!bName.value || isKnownPreset)) {
            bName.value = gIsEsp8266 ? 'SmartHome ESP8266 Custom DIY' : 'SmartHome Custom DIY Controller';
        }
    }
}

function addHwRelayChannel() {
    const sel = document.getElementById('hwNumRelays');
    let cur = parseInt(sel.value) || 0;
    if (cur >= 8) {
        toast('Maximum 8 relays supported', 'warn');
        return;
    }
    cur++;
    sel.value = String(cur);
    setHwMode('custom');
    renderHwChannelsFromUI();
    const newPinEl = document.getElementById(`hw_rpin_${cur - 1}`);
    if (newPinEl && parseInt(newPinEl.value) === 255) {
        toast(`Relay Channel ${cur} added (no free output GPIO — free a pin or disable a sensor)`, 'warn');
    } else {
        toast(`Relay Channel ${cur} added`, 'ok');
    }
}

function removeHwRelayChannel() {
    const sel = document.getElementById('hwNumRelays');
    let cur = parseInt(sel.value) || 0;
    if (cur <= 0) return;
    cur--;
    sel.value = String(cur);
    setHwMode('custom');
    renderHwChannelsFromUI();
    toast(`Relay Channel ${cur + 1} removed`, 'info');
}

function renderPinMatrix(usedPins, conflicts, conflictPins) {
    const grid = document.getElementById('hwPinMatrixGrid');
    if (!grid) return;
    const pins = gIsEsp8266 ? [16, 5, 4, 0, 2, 14, 12, 13, 15, 17] : [0, 2, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33, 34, 35, 36, 39];
    const strapPins = gIsEsp8266 ? [0, 2, 15] : [0, 2, 12, 15];
    const inOnlyPins = gIsEsp8266 ? [17] : [34, 35, 36, 39];

    let usedCount = 0;
    let html = '';

    pins.forEach(p => {
        const isStrap = strapPins.includes(p);
        const isInOnly = inOnlyPins.includes(p);
        const isAdc8266 = (gIsEsp8266 && p === 17);
        const assigned = usedPins[p];
        const isConflict = conflictPins ? conflictPins.has(p) : (conflicts && conflicts.some(c => c.includes(`GPIO ${p} `)));
        if (assigned) usedCount++;

        let borderCol = 'var(--card-border)';
        let bgCol = 'var(--surface)';
        let statusBadge = '<span style="color:#10b981;font-weight:600;">🟢 Free</span>';

        if (isConflict) {
            borderCol = '#ef4444';
            bgCol = 'rgba(239,68,68,0.18)';
            statusBadge = '<span style="color:#f87171;font-weight:700;">🔴 CONFLICT</span>';
        } else if (assigned) {
            borderCol = 'rgba(99,102,241,0.45)';
            bgCol = 'rgba(99,102,241,0.12)';
            statusBadge = `<span style="color:#818cf8;font-weight:600;font-size:0.7rem;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;display:block;" title="${escapeHtml(assigned)}">${escapeHtml(assigned)}</span>`;
        }

        const pinLabel = (gIsEsp8266 && ESP8266_PIN_NAMES[p]) ? ESP8266_PIN_NAMES[p] : (`GPIO ${p}`);

        html += `<div style="background:${bgCol};border:1px solid ${borderCol};border-radius:8px;padding:6px 8px;display:flex;flex-direction:column;gap:3px;min-width:0;box-sizing:border-box;">
            <div style="display:flex;align-items:center;justify-content:space-between;gap:4px;">
                <span style="font-weight:700;font-size:0.75rem;color:var(--text);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${pinLabel}</span>
                <div style="display:flex;gap:2px;">
                    ${isStrap ? '<span style="font-size:0.58rem;padding:1px 3px;border-radius:3px;background:rgba(245,158,11,0.25);color:#fbbf24;" title="Strapping Boot Pin">BOOT</span>' : ''}
                    ${isAdc8266 ? '<span style="font-size:0.58rem;padding:1px 3px;border-radius:3px;background:rgba(6,182,212,0.25);color:#22d3ee;" title="Analog ADC0 Input Only">ADC</span>' : (isInOnly ? '<span style="font-size:0.58rem;padding:1px 3px;border-radius:3px;background:rgba(168,85,247,0.25);color:#c084fc;" title="Input-Only Pin">IN</span>' : '')}
                </div>
            </div>
            <div style="font-size:0.7rem;">${statusBadge}</div>
        </div>`;
    });

    grid.innerHTML = html;
    const statsEl = document.getElementById('hwPinStatsBadge');
    if (statsEl) {
        const freeCount = pins.length - usedCount;
        statsEl.innerHTML = `Total: <b>${pins.length}</b> Pins &bull; Used: <b>${usedCount}</b> &bull; Free: <b style="color:#10b981">${freeCount} Available</b>`;
    }
}

function onPresetSelected() {
    const val = document.getElementById('hwPresetSelect').value;
    if (!val) return;
    if (gIsEsp8266) {
        if (val.includes('1-CH')) {
            applyHwDataToForm({
                board_name: val,
                num_relays: 1,
                channels: [{ enabled: true, switch_enabled: true, relay_pin: 12, switch_pin: 13, switch_mode: 3, trigger: 0 }],
                dht: { type: 2, pin: 14 },
                mq2: { enabled: true, analog_pin: 17, digital_pin: 255 },
                buzzer: { enabled: true, pin: 2 },
                lcd: { enabled: true, i2c_addr: 39, cols: 16, rows: 2, sda_pin: 4, scl_pin: 5 },
                btn_multi_pin: 0
            });
        } else if (val.includes('3-CH')) {
            applyHwDataToForm({
                board_name: val,
                num_relays: 3,
                channels: [
                    { enabled: true, switch_enabled: true, relay_pin: 12, switch_pin: 13, switch_mode: 0, trigger: 0 },
                    { enabled: true, switch_enabled: true, relay_pin: 14, switch_pin: 16, switch_mode: 0, trigger: 0 },
                    { enabled: true, switch_enabled: false, relay_pin: 15, switch_pin: 255, switch_mode: 0, trigger: 0 }
                ],
                dht: { type: 0, pin: 255 },
                mq2: { enabled: true, analog_pin: 17, digital_pin: 255 },
                buzzer: { enabled: true, pin: 2 },
                lcd: { enabled: true, i2c_addr: 39, cols: 16, rows: 2, sda_pin: 4, scl_pin: 5 },
                btn_multi_pin: 0
            });
        } else if (val.includes('4-CH')) {
            applyHwDataToForm({
                board_name: val,
                num_relays: 4,
                channels: [
                    { enabled: true, switch_enabled: true, relay_pin: 12, switch_pin: 13, switch_mode: 0, trigger: 0 },
                    { enabled: true, switch_enabled: true, relay_pin: 14, switch_pin: 16, switch_mode: 0, trigger: 0 },
                    { enabled: true, switch_enabled: false, relay_pin: 4, switch_pin: 255, switch_mode: 0, trigger: 0 },
                    { enabled: true, switch_enabled: false, relay_pin: 5, switch_pin: 255, switch_mode: 0, trigger: 0 }
                ],
                dht: { type: 0, pin: 255 },
                mq2: { enabled: true, analog_pin: 17, digital_pin: 255 },
                buzzer: { enabled: true, pin: 2 },
                lcd: { enabled: false, i2c_addr: 39, cols: 16, rows: 2, sda_pin: 255, scl_pin: 255 },
                btn_multi_pin: 0
            });
        } else if (val.includes('8-CH')) {
            const rPins = [12, 14, 4, 5, 13, 15, 0, 16];
            applyHwDataToForm({
                board_name: val,
                num_relays: 8,
                channels: rPins.map(p => ({ enabled: true, switch_enabled: false, relay_pin: p, switch_pin: 255, switch_mode: 0, trigger: 0 })),
                dht: { type: 0, pin: 255 },
                mq2: { enabled: true, analog_pin: 17, digital_pin: 255 },
                buzzer: { enabled: true, pin: 2 },
                lcd: { enabled: false, i2c_addr: 39, cols: 16, rows: 2, sda_pin: 255, scl_pin: 255 },
                btn_multi_pin: 255
            });
        } else if (val.includes('Sensor Node')) {
            applyHwDataToForm({
                board_name: val,
                num_relays: 0,
                channels: [],
                dht: { type: 2, pin: 12 },
                motion: { type: 1, pin: 14 },
                probe: { type: 1, pin: 13 },
                mq2: { enabled: true, analog_pin: 17, digital_pin: 255 },
                buzzer: { enabled: true, pin: 2 },
                lcd: { enabled: true, i2c_addr: 39, cols: 16, rows: 2, sda_pin: 4, scl_pin: 5 },
                btn_multi_pin: 0
            });
        } else {
            // Default 2-CH Dual
            applyHwDataToForm({
                board_name: val,
                num_relays: 2,
                channels: [
                    { enabled: true, switch_enabled: true, relay_pin: 12, switch_pin: 13, switch_mode: 0, trigger: 0 },
                    { enabled: true, switch_enabled: true, relay_pin: 14, switch_pin: 16, switch_mode: 0, trigger: 0 }
                ],
                dht: { type: 0, pin: 255 },
                mq2: { enabled: true, analog_pin: 17, digital_pin: 255 },
                buzzer: { enabled: true, pin: 2 },
                lcd: { enabled: true, i2c_addr: 39, cols: 16, rows: 2, sda_pin: 4, scl_pin: 5 },
                btn_multi_pin: 0
            });
        }
    } else {
        if (val.includes('1-CH')) {
            applyHwDataToForm({
                board_name: val,
                num_relays: 1,
                channels: [{ enabled: true, switch_enabled: true, relay_pin: 16, switch_pin: 13, switch_mode: 3, trigger: 0 }],
                dht: { type: 2, pin: 4 },
                mq2: { enabled: false, analog_pin: 255, digital_pin: 255 },
                buzzer: { enabled: false, pin: 255 },
                lcd: { enabled: false, i2c_addr: 39, cols: 16, rows: 2, sda_pin: 255, scl_pin: 255 },
                btn_multi_pin: 33
            });
        } else if (val.includes('2-CH')) {
            applyHwDataToForm({
                board_name: val,
                num_relays: 2,
                channels: [
                    { enabled: true, switch_enabled: true, relay_pin: 16, switch_pin: 13, switch_mode: 0, trigger: 0 },
                    { enabled: true, switch_enabled: true, relay_pin: 17, switch_pin: 14, switch_mode: 0, trigger: 0 }
                ],
                dht: { type: 2, pin: 4 },
                mq2: { enabled: true, analog_pin: 34, digital_pin: 35 },
                buzzer: { enabled: true, pin: 5 },
                lcd: { enabled: true, i2c_addr: 39, cols: 16, rows: 2, sda_pin: 21, scl_pin: 22 },
                btn_multi_pin: 33
            });
        } else if (val.includes('4-CH')) {
            applyHwDataToForm({
                board_name: val,
                num_relays: 4,
                channels: [
                    { enabled: true, switch_enabled: true, relay_pin: 16, switch_pin: 13, switch_mode: 0, trigger: 0 },
                    { enabled: true, switch_enabled: true, relay_pin: 17, switch_pin: 14, switch_mode: 0, trigger: 0 },
                    { enabled: true, switch_enabled: true, relay_pin: 18, switch_pin: 27, switch_mode: 0, trigger: 0 },
                    { enabled: true, switch_enabled: true, relay_pin: 19, switch_pin: 26, switch_mode: 0, trigger: 0 }
                ],
                dht: { type: 2, pin: 4 },
                mq2: { enabled: true, analog_pin: 34, digital_pin: 35 },
                buzzer: { enabled: true, pin: 5 },
                lcd: { enabled: true, i2c_addr: 39, cols: 16, rows: 2, sda_pin: 21, scl_pin: 22 },
                btn_multi_pin: 33
            });
        } else if (val.includes('8-CH')) {
            const rPins = [16, 17, 18, 19, 23, 25, 26, 27];
            applyHwDataToForm({
                board_name: val,
                num_relays: 8,
                channels: rPins.map(p => ({ enabled: true, switch_enabled: false, relay_pin: p, switch_pin: 255, switch_mode: 0, trigger: 0 })),
                dht: { type: 2, pin: 4 },
                mq2: { enabled: false, analog_pin: 255, digital_pin: 255 },
                buzzer: { enabled: true, pin: 5 },
                lcd: { enabled: true, i2c_addr: 39, cols: 16, rows: 2, sda_pin: 21, scl_pin: 22 },
                btn_multi_pin: 33
            });
        } else if (val.includes('Sensor Node')) {
            applyHwDataToForm({
                board_name: val,
                num_relays: 0,
                channels: [],
                dht: { type: 2, pin: 4 },
                mq2: { enabled: true, analog_pin: 34, digital_pin: 35 },
                buzzer: { enabled: true, pin: 5 },
                lcd: { enabled: true, i2c_addr: 39, cols: 16, rows: 2, sda_pin: 21, scl_pin: 22 },
                btn_multi_pin: 33
            });
        } else {
            applyHwDataToForm({
                board_name: val,
                num_relays: 5,
                channels: [
                    { enabled: true, switch_enabled: true, relay_pin: 16, switch_pin: 13, switch_mode: 0, trigger: 0 },
                    { enabled: true, switch_enabled: true, relay_pin: 17, switch_pin: 14, switch_mode: 0, trigger: 0 },
                    { enabled: true, switch_enabled: true, relay_pin: 18, switch_pin: 27, switch_mode: 0, trigger: 0 },
                    { enabled: true, switch_enabled: true, relay_pin: 19, switch_pin: 26, switch_mode: 0, trigger: 0 },
                    { enabled: true, switch_enabled: true, relay_pin: 23, switch_pin: 25, switch_mode: 0, trigger: 0 }
                ],
                dht: { type: 2, pin: 4 },
                mq2: { enabled: true, analog_pin: 34, digital_pin: 35 },
                buzzer: { enabled: true, pin: 5 },
                lcd: { enabled: true, i2c_addr: 39, cols: 16, rows: 2, sda_pin: 21, scl_pin: 22 },
                btn_multi_pin: 33
            });
        }
    }
}

function applyHwPresetBtn() {
    const val = document.getElementById('hwPresetSelect').value;
    if (!val) { toast('Please choose a preset from the dropdown first', 'warn'); return; }
    if (!confirm(`Apply hardware preset "${val}" and reboot controller?`)) return;

    api('POST', '/api/hardware/template', { template: val }).then(res => {
        toast('Preset applied. Controller is rebooting...', 'ok');
        setTimeout(() => location.reload(), 3000);
    }).catch(err => toast(err.message || 'Failed to apply preset', 'err'));
}

function resetHwDefaultBtn() {
    const label = gIsEsp8266 ? 'standard 2-CH default' : 'standard 5-CH default';
    if (!confirm(`Reset hardware configuration back to ${label} and reboot?`)) return;
    api('POST', '/api/hardware/reset', {}).then(res => {
        toast('Hardware reset to default. Rebooting...', 'ok');
        setTimeout(() => location.reload(), 3000);
    }).catch(err => toast(err.message || 'Failed to reset hardware', 'err'));
}

function saveHardware() {
    if (!checkHwConflicts()) {
        toast('Cannot save: Resolve GPIO conflicts first!', 'err');
        return;
    }

    const num = parseInt(document.getElementById('hwNumRelays').value) || 0;
    const channels = [];
    for (let i = 0; i < num; i++) {
        const enEl = document.getElementById(`hw_en_${i}`);
        const swEnEl = document.getElementById(`hw_swen_${i}`);
        channels.push({
            enabled: !enEl || enEl.value === '1',
            switch_enabled: !swEnEl || swEnEl.value === '1',
            relay_pin: parseInt(document.getElementById(`hw_rpin_${i}`).value),
            switch_pin: parseInt(document.getElementById(`hw_spin_${i}`).value),
            switch_mode: parseInt(document.getElementById(`hw_smode_${i}`).value),
            trigger: parseInt(document.getElementById(`hw_trig_${i}`).value)
        });
    }

    const lcdSize = document.getElementById('hwLcdSize').value;
    const is20x4 = (lcdSize === '20x4');

    const payload = {
        board_name: document.getElementById('hwBoardName').value.trim() || 'Custom',
        num_relays: num,
        channels: channels,
        climates: gHwSensors.climates.map(c => ({
            type: c.type || 0,
            pin: (c.type === 1 || c.type === 2) ? (c.pin ?? 255) : 255,
            i2c_addr: (c.type >= 3) ? (c.i2c_addr || getI2cClimateAddrs(c.type)[0] || 0) : 0,
            label: (c.label || '').slice(0, 15)
        })),
        lights: gHwSensors.lights.map(l => ({
            type: l.type || 0,
            i2c_addr: l.type === 1 ? (l.i2c_addr || 0x23) : 0,
            label: (l.label || '').slice(0, 15)
        })),
        motions: gHwSensors.motions.map(m => ({
            type: m.type || 0,
            pin: m.pin ?? 255,
            label: (m.label || '').slice(0, 15)
        })),
        probes: gHwSensors.probes.map(p => ({
            type: p.type || 0,
            pin: p.pin ?? 255,
            label: (p.label || '').slice(0, 15)
        })),
        ultrasonics: gHwSensors.ultrasonics.map(u => ({
            type: u.type || 0,
            trig_pin: u.trig_pin ?? 255,
            echo_pin: u.echo_pin ?? 255,
            tank_depth: u.tank_depth || 150,
            air_gap: u.air_gap || 15,
            label: (u.label || '').slice(0, 15)
        })),
        mq2_sensors: gHwSensors.mq2s.map(g => ({
            enabled: g.enabled !== false,
            analog_pin: g.analog_pin ?? 255,
            digital_pin: g.digital_pin ?? 255,
            label: (g.label || '').slice(0, 15)
        })),
        dht: gHwSensors.climates.length > 0 ? { type: gHwSensors.climates[0].type, pin: gHwSensors.climates[0].pin, i2c_addr: gHwSensors.climates[0].i2c_addr || 0 } : { type: 0, pin: 255 },
        light: gHwSensors.lights.length > 0 ? { type: gHwSensors.lights[0].type, i2c_addr: gHwSensors.lights[0].i2c_addr || 0 } : { type: 0 },
        motion: gHwSensors.motions.length > 0 ? { type: gHwSensors.motions[0].type, pin: gHwSensors.motions[0].pin } : { type: 0, pin: 255 },
        probe: gHwSensors.probes.length > 0 ? { type: gHwSensors.probes[0].type, pin: gHwSensors.probes[0].pin } : { type: 0, pin: 255 },
        ultrasonic: gHwSensors.ultrasonics.length > 0 ? {
            type: gHwSensors.ultrasonics[0].type, trig_pin: gHwSensors.ultrasonics[0].trig_pin,
            echo_pin: gHwSensors.ultrasonics[0].echo_pin, tank_depth: gHwSensors.ultrasonics[0].tank_depth,
            air_gap: gHwSensors.ultrasonics[0].air_gap
        } : { type: 0, trig_pin: 255, echo_pin: 255, tank_depth: 150, air_gap: 15 },
        mq2: gHwSensors.mq2s.length > 0 ? { enabled: gHwSensors.mq2s[0].enabled !== false, analog_pin: gHwSensors.mq2s[0].analog_pin, digital_pin: gHwSensors.mq2s[0].digital_pin } : { enabled: false, analog_pin: 255, digital_pin: 255 },
        buzzer: {
            enabled: document.getElementById('hwBuzEn').value === '1',
            pin: parseInt(document.getElementById('hwBuzPin').value)
        },
        lcd: {
            enabled: document.getElementById('hwLcdEn').value === '1',
            i2c_addr: parseInt(document.getElementById('hwLcdAddr').value),
            cols: is20x4 ? 20 : 16,
            rows: is20x4 ? 4 : 2,
            sda_pin: parseInt(document.getElementById('hwLcdSda').value),
            scl_pin: parseInt(document.getElementById('hwLcdScl').value)
        },
        btn_multi_pin: parseInt(document.getElementById('hwBtnMultiPin').value)
    };

    if (!confirm('Save hardware profile and reboot controller?')) return;

    api('POST', '/api/hardware', payload).then(res => {
        toast('Hardware profile saved! Controller rebooting...', 'ok');
        setTimeout(() => location.reload(), 3000);
    }).catch(err => {
        toast('Save failed: ' + (err.message || 'Unknown error'), 'err');
    });
}

// Helper
function setText(id,val){const el=document.getElementById(id);if(el)el.textContent=val;}

// Init
populateMinuteOptions();
initHwDefaults();
loadSettings().catch(()=>{}).finally(()=>{initWS();});
</script>
</body>
</html>
)rawliteral";

// ============================================================================
// Captive Portal Page (shown in AP mode)
// ============================================================================
static const char PAGE_CAPTIVE[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>SmartHome &bull; Wi-Fi Onboarding</title>
<style>
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display','Inter','Segoe UI',Roboto,sans-serif;background:#080b11;background-image:radial-gradient(at 50% 0%,rgba(99,102,241,0.2) 0px,transparent 60%),radial-gradient(at 100% 100%,rgba(59,130,246,0.12) 0px,transparent 60%);color:#f8fafc;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:16px;}
.box{background:rgba(17,24,39,0.85);backdrop-filter:blur(24px);-webkit-backdrop-filter:blur(24px);border:1px solid rgba(255,255,255,0.1);border-radius:20px;padding:36px 32px;max-width:440px;width:100%;box-shadow:0 20px 50px rgba(0,0,0,0.6),inset 0 1px 0 rgba(255,255,255,0.1);}
.logo{width:48px;height:48px;border-radius:14px;background:linear-gradient(135deg,#6366f1,#3b82f6);display:flex;align-items:center;justify-content:center;margin:0 auto 16px;box-shadow:0 6px 20px rgba(99,102,241,0.45);}
.logo svg{width:26px;height:26px;fill:#ffffff;}
h2{font-size:1.4rem;font-weight:700;text-align:center;letter-spacing:-0.02em;margin-bottom:6px;}
.subtitle{text-align:center;font-size:.84rem;color:#94a3b8;margin-bottom:24px;line-height:1.4;}
.form-group{margin-bottom:16px;}
.form-group label{display:block;font-size:.76rem;color:#94a3b8;margin-bottom:6px;font-weight:600;text-transform:uppercase;letter-spacing:0.05em;}
.form-group input{width:100%;padding:11px 14px;border:1px solid rgba(255,255,255,0.1);border-radius:10px;background:rgba(11,15,25,0.7);color:#f8fafc;font-size:.9rem;outline:none;transition:all .2s;}
.form-group input:focus{border-color:#6366f1;box-shadow:0 0 0 3px rgba(99,102,241,0.25);}
.btn{width:100%;padding:13px;background:linear-gradient(135deg,#6366f1,#3b82f6);color:#fff;border:none;border-radius:10px;font-size:.95rem;font-weight:600;cursor:pointer;transition:all .2s;box-shadow:0 4px 16px rgba(99,102,241,0.4);display:flex;align-items:center;justify-content:center;gap:8px;}
.btn:hover{box-shadow:0 6px 22px rgba(99,102,241,0.55);transform:translateY(-1px);}
.btn:active{transform:scale(0.98);}
.rescan-btn{background:none;border:none;color:#818cf8;font-size:.78rem;cursor:pointer;font-weight:600;display:flex;align-items:center;gap:4px;}
.rescan-btn:hover{color:#a5b4fc;}
#netList{max-height:190px;overflow-y:auto;border:1px solid rgba(255,255,255,0.1);border-radius:10px;background:rgba(11,15,25,0.7);scrollbar-width:thin;}
.net-item{display:flex;align-items:center;justify-content:space-between;padding:11px 14px;border-bottom:1px solid rgba(255,255,255,0.06);cursor:pointer;font-size:.88rem;transition:background .15s;}
.net-item:hover{background:rgba(99,102,241,0.15);}
.net-item:last-child{border-bottom:none;}
.net-badge{font-size:.72rem;color:#94a3b8;font-weight:500;}
.msg{text-align:center;margin-top:20px;font-size:.8rem;color:#94a3b8;line-height:1.5;}
.msg b{color:#f8fafc;}
</style></head><body>
<div class="box">
<div class="logo"><svg viewBox="0 0 24 24"><path d="M12 3L4 9v12h16V9l-8-6zm0 2.5L18 10v9H6v-9l6-4.5z"/><path d="M10 14h4v5h-4z"/></svg></div>
<h2>SmartHome Setup</h2>
<div class="subtitle">Select your 2.4 GHz Wi-Fi network below or enter credentials manually to join your smart home network.</div>
<div class="form-group">
<label style="display:flex;justify-content:space-between;align-items:center;">
<span>Available Networks</span>
<button type="button" class="rescan-btn" onclick="scanWifi(true)">&#8635; Rescan</button>
</label>
<div id="netList"><div style="padding:16px;text-align:center;color:#94a3b8;font-size:.84rem;">Scanning nearby Wi-Fi networks...</div></div>
</div>
<form method="POST" action="/api/config/wifi">
<div class="form-group"><label>Wi-Fi Network (SSID)</label><input type="text" id="ssidIn" name="ssid" required placeholder="Select above or type SSID"></div>
<div class="form-group"><label>Wi-Fi Password</label><input type="password" id="passIn" name="pass" placeholder="Enter Wi-Fi password"></div>
<button class="btn" type="submit">Save &amp; Connect Controller</button>
</form>
<div class="msg">After connecting, launch the <b>SmartHome Pro</b> mobile app or visit <b>smarthome.local</b> in your browser.</div>
</div>
<script>
function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');}
function pickNet(el,ssid){
document.getElementById('ssidIn').value=ssid;
document.getElementById('passIn').focus();
}
function scanWifi(refresh){
const box=document.getElementById('netList');
if(refresh)box.innerHTML='<div style="padding:16px;text-align:center;color:#94a3b8;font-size:.84rem;">Scanning 2.4 GHz networks...</div>';
fetch('/api/wifi/scan'+(refresh?'?refresh=1':''))
.then(r=>r.json()).then(d=>{
if(d.scanning){setTimeout(()=>scanWifi(false),1500);return;}
const nets=d.networks||[];
if(!nets.length){box.innerHTML='<div style="padding:16px;text-align:center;color:#94a3b8;font-size:.84rem;">No networks found. Tap Rescan.</div>';return;}
nets.sort((a,b)=>(b.rssi||-100)-(a.rssi||-100));
let h='';
nets.forEach(n=>{
h+='<div class="net-item" data-ssid="'+esc(n.ssid)+'" onclick="pickNet(this,this.dataset.ssid)"><span><b>'+esc(n.ssid)+'</b></span><span class="net-badge">'+(n.secure?'&#128274; ':'Open ')+'&bull; '+(n.signal||0)+'%</span></div>';
});
box.innerHTML=h;
}).catch(()=>{box.innerHTML='<div style="padding:16px;text-align:center;color:#94a3b8;font-size:.84rem;">Scan unavailable &mdash; enter SSID manually</div>';});
}
scanWifi(false);
</script>
</body></html>
)rawliteral";


// ============================================================================
// Firmware Update Page (/update)
// ============================================================================
static const char PAGE_OTA_UPDATE[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>Firmware Update &mdash; SmartHome</title>
<style>
:root{--bg:#080b11;--card:rgba(17,24,39,0.85);--border:rgba(255,255,255,0.1);--text:#f8fafc;--text2:#94a3b8;
--accent:#6366f1;--accent2:#818cf8;--accent-grad:linear-gradient(135deg,#6366f1,#3b82f6);--green:#10b981;--red:#f43f5e;--orange:#f59e0b;--radius:20px;}
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display','Inter','Segoe UI',Roboto,sans-serif;background:var(--bg);background-image:radial-gradient(at 50% 0%,rgba(99,102,241,0.18) 0px,transparent 60%),radial-gradient(at 100% 100%,rgba(59,130,246,0.10) 0px,transparent 60%);color:var(--text);
min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px;-webkit-font-smoothing:antialiased;}
.wrap{width:100%;max-width:520px;}
.card{background:var(--card);backdrop-filter:blur(24px);-webkit-backdrop-filter:blur(24px);border:1px solid var(--border);border-radius:var(--radius);
padding:32px 36px;box-shadow:0 20px 50px rgba(0,0,0,.6),inset 0 1px 0 rgba(255,255,255,.1);}
h1{font-size:1.35rem;font-weight:700;margin-bottom:6px;display:flex;align-items:center;gap:12px;letter-spacing:-0.02em;}
h1 svg{width:28px;height:28px;fill:var(--accent);}
.sub{font-size:.84rem;color:var(--text2);margin-bottom:22px;line-height:1.4;}
.fw-info{background:rgba(99,102,241,.1);border:1px solid rgba(99,102,241,.25);
border-radius:10px;padding:12px 16px;font-size:.82rem;color:var(--text2);margin-bottom:18px;}
.fw-info b{color:var(--accent2);}
.tabs{display:flex;gap:8px;margin-bottom:20px;background:rgba(11,15,25,0.6);padding:5px;border-radius:12px;border:1px solid var(--border);}
.tab{flex:1;padding:10px;border:none;border-radius:8px;background:transparent;
color:var(--text2);font-size:.84rem;font-weight:600;cursor:pointer;transition:all .2s;text-align:center;}
.tab.active{background:var(--accent-grad);color:#fff;box-shadow:0 4px 12px rgba(99,102,241,.35);}
.drop-zone{border:2px dashed rgba(255,255,255,0.18);border-radius:14px;padding:36px 20px;text-align:center;
cursor:pointer;transition:all .2s;position:relative;margin-bottom:18px;background:rgba(11,15,25,0.4);}
.drop-zone:hover,.drop-zone.over{border-color:var(--accent);background:rgba(99,102,241,.08);transform:scale(1.01);}
.drop-zone input{position:absolute;inset:0;opacity:0;cursor:pointer;width:100%;height:100%;}
.drop-icon svg{width:44px;height:44px;fill:var(--accent2);margin-bottom:12px;filter:drop-shadow(0 4px 8px rgba(99,102,241,.3));}
.drop-text{color:var(--text2);font-size:.85rem;line-height:1.5;}
.drop-text b{color:var(--text);display:block;font-size:1rem;margin-bottom:4px;font-weight:600;}
.file-info{background:rgba(99,102,241,.12);border:1px solid rgba(99,102,241,.3);
border-radius:10px;padding:12px 16px;font-size:.84rem;margin-bottom:18px;display:none;}
.file-info span{color:var(--text2);}
.file-info b{color:var(--accent2);}
.btn{width:100%;padding:14px;background:var(--accent-grad);color:#fff;border:none;
border-radius:11px;font-size:.95rem;font-weight:700;cursor:pointer;transition:all .2s;
display:flex;align-items:center;justify-content:center;gap:8px;box-shadow:0 4px 16px rgba(99,102,241,.4);}
.btn:hover:not(:disabled){box-shadow:0 6px 22px rgba(99,102,241,.55);transform:translateY(-1px);}
.btn:disabled{opacity:.45;cursor:not-allowed;transform:none;}
.btn svg{width:18px;height:18px;fill:#fff;}
.progress-wrap{margin-top:22px;display:none;}
.progress-bar-bg{background:rgba(11,15,25,0.7);border:1px solid var(--border);border-radius:10px;
height:30px;overflow:hidden;position:relative;box-shadow:inset 0 1px 3px rgba(0,0,0,0.4);}
.progress-bar{height:100%;background:linear-gradient(90deg,#6366f1,#3b82f6,#06b6d4);
width:0%;transition:width .3s;border-radius:10px;box-shadow:0 0 14px rgba(99,102,241,0.5);}
.progress-label{position:absolute;inset:0;display:flex;align-items:center;
justify-content:center;font-size:.8rem;font-weight:700;color:#fff;text-shadow:0 1px 3px rgba(0,0,0,.6);}
.status-msg{text-align:center;margin-top:14px;font-size:.84rem;color:var(--text2);min-height:22px;}
.status-msg.ok{color:var(--green);font-weight:600;}
.status-msg.err{color:var(--red);font-weight:600;}
.alert{border-radius:11px;padding:12px 16px;font-size:.83rem;margin-bottom:18px;
display:flex;gap:12px;align-items:flex-start;}
.alert-warn{background:rgba(245,158,11,.1);border:1px solid rgba(245,158,11,.25);color:var(--orange);}
.alert svg{width:18px;height:18px;fill:currentColor;flex-shrink:0;margin-top:1px;}
.result-box{margin-top:18px;border-radius:11px;padding:16px 20px;font-size:.84rem;display:none;}
.result-ok{background:rgba(16,185,129,.12);border:1px solid rgba(16,185,129,.35);color:var(--green);}
.result-err{background:rgba(244,63,94,.12);border:1px solid rgba(244,63,94,.35);color:var(--red);}
.result-box b{display:block;font-size:.92rem;margin-bottom:4px;}
.back-link{display:block;text-align:center;margin-top:20px;color:var(--text2);
font-size:.84rem;text-decoration:none;transition:color .2s;font-weight:500;}
.back-link:hover{color:#fff;}
</style>
</head>
<body>
<div class="wrap">
  <div class="card">
    <h1>
      <svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10
        10-4.48 10-10S17.52 2 12 2zm-1 14H9V8h2v8zm4 0h-2V8h2v8z"/></svg>
      Firmware Update
    </h1>
    <div class="sub">Upload a .bin file to update firmware or filesystem</div>

    <div class="fw-info" id="fwInfo">
      Current: <b id="fwVer">loading...</b> &nbsp;|&nbsp; Build: <b id="fwDate">&mdash;</b>
    </div>

    <div class="alert alert-warn">
      <svg viewBox="0 0 24 24"><path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/></svg>
      <span>Do not power off during update. Device will reboot automatically when done.</span>
    </div>

    <div class="tabs">
      <div class="tab active" id="tabFw" onclick="setType('firmware')">Firmware</div>
      <div class="tab" id="tabFs" onclick="setType('fs')">Filesystem</div>
    </div>

    <div class="drop-zone" id="dropZone">
      <input type="file" id="fileInput" accept=".bin" onchange="onFileSelected(this)">
      <div class="drop-icon"><svg viewBox="0 0 24 24"><path d="M19.35 10.04A7.49 7.49 0
        0 0 12 4C9.11 4 6.6 5.64 5.35 8.04A5.994 5.994 0 0 0 0 14c0 3.31 2.69 6
        6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM14 13v4h-4v-4H7l5-5
        5 5h-3z"/></svg></div>
      <div class="drop-text"><b>Drop .bin file here</b>or click to browse</div>
    </div>

    <div class="file-info" id="fileInfo">
      <span>Selected: </span><b id="fileName">&mdash;</b>
      &nbsp;&nbsp;<span>Size: </span><b id="fileSize">&mdash;</b>
    </div>

    <button class="btn" id="uploadBtn" onclick="startUpload()" disabled>
      <svg viewBox="0 0 24 24"><path d="M9 16h6v-6h4l-7-7-7 7h4v6zm-4 2h14v2H5v-2z"/></svg>
      Upload &amp; Flash
    </button>

    <div class="progress-wrap" id="progressWrap">
      <div class="progress-bar-bg">
        <div class="progress-bar" id="progressBar"></div>
        <div class="progress-label" id="progressLabel">0%</div>
      </div>
      <div class="status-msg" id="statusMsg">Uploading...</div>
    </div>

    <div class="result-box" id="resultBox">
      <b id="resultTitle"></b>
      <span id="resultDetail"></span>
    </div>
  </div>
  <a class="back-link" href="/">&#8592; Back to Dashboard</a>
</div>

<script>
var updateType = 'firmware';
var selectedFile = null;
var polling = null;
var preVersion = '';  // Firmware version before update
var preBuild = '';    // Build date before update
var preMd5 = '';      // Sketch MD5 before update

// ---- Fetch current firmware version on page load ----
(function() {
  var x = new XMLHttpRequest();
  x.open('GET', '/api/ota/status', true);
  x.timeout = 3000;
  x.onload = function() {
    try {
      var d = JSON.parse(x.responseText);
      preVersion = d.fw_version || '';
      preBuild = d.fw_date || '';
      preMd5 = d.fw_md5 || '';
      document.getElementById('fwVer').textContent = preVersion || '?';
      document.getElementById('fwDate').textContent = preBuild || '?';
    } catch(e) {}
  };
  x.onerror = x.ontimeout = function() {
    document.getElementById('fwVer').textContent = 'unknown';
  };
  x.send();
})();

function setType(t) {
  updateType = t;
  document.getElementById('tabFw').classList.toggle('active', t === 'firmware');
  document.getElementById('tabFs').classList.toggle('active', t === 'fs');
}

function onFileSelected(input) {
  var f = input.files[0];
  if (!f) return;
  // Validate file
  if (!f.name.toLowerCase().endsWith('.bin')) {
    setStatus('Please select a .bin file', 'err');
    return;
  }
  if (f.size < 10000) {
    setStatus('File too small \u2014 doesn\'t look like valid firmware', 'err');
    return;
  }
  selectedFile = f;
  document.getElementById('fileName').textContent = f.name;
  document.getElementById('fileSize').textContent = formatBytes(f.size);
  document.getElementById('fileInfo').style.display = 'block';
  document.getElementById('uploadBtn').disabled = false;
  document.getElementById('resultBox').style.display = 'none';
  setStatus('', '');
  if (f.name.toLowerCase().indexOf('spiffs') >= 0 ||
      f.name.toLowerCase().indexOf('littlefs') >= 0) setType('fs');
}

// Drag & drop
var dz = document.getElementById('dropZone');
dz.addEventListener('dragover', function(e){ e.preventDefault(); dz.classList.add('over'); });
dz.addEventListener('dragleave', function(){ dz.classList.remove('over'); });
dz.addEventListener('drop', function(e){
  e.preventDefault(); dz.classList.remove('over');
  var f = e.dataTransfer.files[0];
  if (f && f.name.endsWith('.bin')) {
    // Trigger through input for consistency
    var dt = new DataTransfer();
    dt.items.add(f);
    document.getElementById('fileInput').files = dt.files;
    onFileSelected(document.getElementById('fileInput'));
  }
});

// ============================================================================
// Upload flow &mdash; proper error handling + real progress + version verification
//
// Phase 1: UPLOADING  &mdash; XHR sends file to ESP32, shows real upload %
//          The ESP32 writes to flash as it receives each chunk, so by the
//          time the upload finishes, the firmware is already written.
// Phase 2: CONFIRMING &mdash; Server responds 200 (success) or 500 (error)
//          On success, the ESP32 schedules a restart via Ticker (1s delay)
// Phase 3: REBOOTING  &mdash; Wait for device to go offline, then come back up
// Phase 4: VERIFYING  &mdash; Fetch /api/ota/status and check firmware version
// ============================================================================

var uploadComplete = false;  // Track if upload reached 100%

function startUpload() {
  if (!selectedFile) return;
  uploadComplete = false;
  document.getElementById('uploadBtn').disabled = true;
  document.getElementById('progressWrap').style.display = 'block';
  document.getElementById('resultBox').style.display = 'none';
  setStatus('Uploading & flashing to device...', '');
  setProgress(0, 'Starting upload...');

  var fd = new FormData();
  fd.append('file', selectedFile, selectedFile.name);

  var xhr = new XMLHttpRequest();
  xhr.open('POST', '/api/ota/upload?type=' + updateType, true);
  xhr.setRequestHeader('X-Requested-With', 'SmartHome');

  // Phase 1: Upload progress &mdash; the ESP32 writes to flash in real-time
  // as it receives each chunk, so upload progress IS flash progress
  xhr.upload.onprogress = function(e) {
    if (e.lengthComputable) {
      var pct = Math.round(e.loaded * 100 / e.total);
      if (pct >= 100) uploadComplete = true;
      // Cap at 90% during upload &mdash; last 10% is for verify+reboot
      var barPct = Math.min(Math.round(pct * 0.9), 90);
      setProgress(barPct, 'Uploading & flashing ' + pct + '%');
      if (pct >= 100) {
        setStatus('Finalizing flash write...', '');
      }
    }
  };

  // Phase 2: Server responded &mdash; means flash was successful (or failed)
  xhr.onload = function() {
    if (xhr.status === 200) {
      // Server confirmed success and scheduled reboot
      setProgress(92, 'Flash complete!');
      setStatus('Firmware written successfully. Device rebooting...', '');
      enterRebootPhase();
    } else {
      // Server reported error
      var msg = 'Upload failed';
      try {
        var r = JSON.parse(xhr.responseText);
        msg = r.message || r.error || xhr.responseText;
      } catch(ex) {
        msg = xhr.responseText || 'Unknown error (HTTP ' + xhr.status + ')';
      }
      showError(msg);
    }
  };

  // Connection lost &mdash; could be reboot (success) or crash (failure)
  // Only treat as success if upload had reached 100% (all data sent)
  xhr.onerror = function() {
    if (uploadComplete) {
      // Upload was 100% complete when connection dropped &mdash; ESP32 likely
      // rebooted after successful flash. Proceed to reboot detection.
      setProgress(92, 'Flash complete!');
      setStatus('Connection closed \u2014 device is rebooting...', '');
      enterRebootPhase();
    } else {
      // Upload was NOT complete &mdash; this is a real connection failure
      showError('Connection lost during upload. Please check your WiFi and try again.');
    }
  };

  xhr.ontimeout = function() {
    if (uploadComplete) {
      enterRebootPhase();
    } else {
      showError('Upload timed out. The device may be busy or unreachable.');
    }
  };

  // Set generous timeout (firmware can be several MB)
  xhr.timeout = 120000; // 2 minutes

  xhr.send(fd);
}

// ============================================================================
// Phase 3: Wait for device to go offline then come back online
// ============================================================================
function enterRebootPhase() {
  setProgress(93, 'Rebooting...');
  setStatus('Waiting for device to restart...', '');

  var dotCount = 0;
  var offlineDetected = false;
  var tickCount = 0;
  var maxTicks = 40;  // 40 seconds max wait

  polling = setInterval(function() {
    tickCount++;
    dotCount = (dotCount + 1) % 4;
    var dots = '.'.repeat(dotCount + 1);

    if (tickCount > maxTicks) {
      // Timeout &mdash; device might be fine but unreachable
      clearInterval(polling);
      setProgress(100, 'Done');
      showResult(true,
        'Update appears complete',
        'Device did not respond within ' + maxTicks + 's. It may have changed IP address. Check your router or try accessing the device directly.');
      return;
    }

    if (tickCount <= 2) {
      setProgress(93, 'Rebooting' + dots);
      setStatus('Waiting for reboot' + dots, '');
      return;
    }

    if (!offlineDetected) {
      // Step A: Wait for device to go offline (confirms reboot started)
      var pct = Math.min(93 + Math.floor(tickCount / 2), 96);
      setProgress(pct, 'Rebooting' + dots);
      setStatus('Waiting for reboot' + dots, '');

      pingDevice(function(alive) {
        if (!alive) {
          offlineDetected = true;
          setProgress(96, 'Restarting' + dots);
          setStatus('Device restarting, please wait' + dots, '');
        } else if (tickCount >= 12) {
          // Device never observed offline &mdash; fast reboot, proceed to verification
          offlineDetected = true;
        }
      });
    } else {
      // Step B: Wait for device to come back online
      var pct2 = Math.min(96 + Math.floor(tickCount / 3), 99);
      setProgress(pct2, 'Reconnecting' + dots);
      setStatus('Waiting for device' + dots, '');

      pingDevice(function(alive) {
        if (alive) {
          clearInterval(polling);
          enterVerifyPhase(1);
        }
      });
    }
  }, 1000);
}

// ============================================================================
// Phase 4: Verify firmware version actually changed
// ============================================================================
function enterVerifyPhase(attempt) {
  attempt = attempt || 1;
  var maxAttempts = 5;
  setProgress(99, 'Verifying...');
  setStatus('Verifying firmware update' + (attempt > 1 ? ' (retry ' + attempt + '/' + maxAttempts + ')' : '') + '...', '');

  function retryOrFallback() {
    if (attempt < maxAttempts) {
      setTimeout(function() { enterVerifyPhase(attempt + 1); }, 1200);
    } else {
      setProgress(100, '\u2713 Done');
      showResult(true, 'Update Complete',
        'Device is online but version check failed. Refresh the dashboard to verify.');
    }
  }

  var x = new XMLHttpRequest();
  x.open('GET', '/api/ota/status?_=' + Date.now(), true);
  x.timeout = 6000;
  x.onload = function() {
    if (x.status !== 200) {
      retryOrFallback();
      return;
    }
    try {
      var d = JSON.parse(x.responseText);
      if (!d || !d.fw_version) {
        retryOrFallback();
        return;
      }
      setProgress(100, '\u2713 Done');
      var newVer = d.fw_version || 'unknown';
      var newBuild = d.fw_date || '';
      var newMd5 = d.fw_md5 || '';
      document.getElementById('fwVer').textContent = newVer;
      if (newBuild) document.getElementById('fwDate').textContent = newBuild;

      var detail = 'Running: v' + newVer;
      if (newBuild) detail += ' (build: ' + newBuild + ')';
      if (preVersion && newVer !== preVersion) {
        detail += ' \u2014 upgraded from v' + preVersion;
      } else if ((preVersion && preBuild && newBuild !== preBuild) ||
                 (preMd5 && newMd5 && newMd5 !== preMd5)) {
        detail += ' \u2014 new build active';
      } else {
        detail += ' \u2014 firmware image verified & active';
      }
      showResult(true, 'Update Successful!', detail);
    } catch(e) {
      retryOrFallback();
    }
  };
  x.onerror = x.ontimeout = function() {
    retryOrFallback();
  };
  x.send();
}

// ============================================================================
// Lightweight discovery ping to verify HTTP stack is back online
// ============================================================================
function pingDevice(cb) {
  var ctrl = new XMLHttpRequest();
  ctrl.open('GET', '/api/discovery?_=' + Date.now(), true);
  ctrl.timeout = 2500;
  ctrl.onload  = function() { cb(ctrl.status === 200); };
  ctrl.onerror = function() { cb(false); };
  ctrl.ontimeout = function() { cb(false); };
  try { ctrl.send(); } catch(e) { cb(false); }
}

// ============================================================================
// UI Helpers
// ============================================================================
function showResult(success, title, detail) {
  var box = document.getElementById('resultBox');
  box.className = 'result-box ' + (success ? 'result-ok' : 'result-err');
  document.getElementById('resultTitle').textContent = title;
  document.getElementById('resultDetail').textContent = detail;
  box.style.display = 'block';
  setStatus(success ? 'Done!' : 'Update failed', success ? 'ok' : 'err');

  if (success) {
    // Auto-redirect to dashboard after 5 seconds
    setTimeout(function(){ window.location.href = '/'; }, 5000);
  } else {
    document.getElementById('uploadBtn').disabled = false;
  }
}

function showError(msg) {
  clearInterval(polling);
  setProgress(0, '\u2717 Failed');
  showResult(false, 'Update Failed', msg);
}

function setProgress(pct, label) {
  document.getElementById('progressBar').style.width = pct + '%';
  document.getElementById('progressLabel').textContent = label || (pct + '%');
}

function setStatus(msg, cls) {
  var el = document.getElementById('statusMsg');
  el.textContent = msg;
  el.className = 'status-msg' + (cls ? ' ' + cls : '');
}

function formatBytes(b) {
  if (b < 1024) return b + ' B';
  if (b < 1048576) return (b/1024).toFixed(1) + ' KB';
  return (b/1048576).toFixed(2) + ' MB';
}

</script>
</body>
</html>
)rawliteral";



// ============================================================================
// Logged Out Landing Page (/logout)
// ============================================================================
static const char PAGE_LOGGED_OUT[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>Logged Out &mdash; SmartHome</title>
<style>
:root{--bg:#080b11;--card:rgba(17,24,39,0.85);--border:rgba(255,255,255,0.1);--text:#f8fafc;--text2:#94a3b8;
--accent:#6366f1;--accent2:#818cf8;--accent-grad:linear-gradient(135deg,#6366f1,#3b82f6);--green:#10b981;--radius:20px;}
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display','Inter','Segoe UI',Roboto,sans-serif;background:var(--bg);background-image:radial-gradient(at 50% 0%,rgba(99,102,241,0.2) 0px,transparent 60%),radial-gradient(at 100% 100%,rgba(59,130,246,0.1) 0px,transparent 60%);color:var(--text);min-height:100vh;display:flex;align-items:center;justify-content:center;padding:16px;-webkit-font-smoothing:antialiased;}
.box{background:var(--card);backdrop-filter:blur(24px);-webkit-backdrop-filter:blur(24px);border:1px solid var(--border);border-radius:var(--radius);padding:40px 32px;max-width:440px;width:100%;box-shadow:0 20px 50px rgba(0,0,0,.6),inset 0 1px 0 rgba(255,255,255,.1);text-align:center;}
.icon-box{width:64px;height:64px;border-radius:18px;background:linear-gradient(135deg,rgba(99,102,241,0.2),rgba(59,130,246,0.15));border:1px solid rgba(99,102,241,0.35);display:flex;align-items:center;justify-content:center;margin:0 auto 20px;box-shadow:0 8px 24px rgba(99,102,241,0.3);}
.icon-box svg{width:32px;height:32px;fill:var(--accent2);}
h2{font-size:1.4rem;font-weight:700;letter-spacing:-0.02em;margin-bottom:8px;}
.desc{font-size:.85rem;color:var(--text2);margin-bottom:24px;line-height:1.5;}
.tier-info{background:rgba(255,255,255,0.03);border:1px solid var(--border);border-radius:12px;padding:12px 14px;font-size:.78rem;color:var(--text2);margin-bottom:24px;text-align:left;}
.tier-row{display:flex;align-items:center;gap:8px;margin-bottom:6px;}
.tier-row:last-child{margin-bottom:0;}
.tier-badge{padding:2px 8px;border-radius:12px;font-size:.7rem;font-weight:700;}
.badge-admin{background:rgba(99,102,241,0.2);color:#a5b4fc;border:1px solid rgba(99,102,241,0.4);}
.badge-guest{background:rgba(234,179,8,0.2);color:#facc15;border:1px solid rgba(234,179,8,0.4);}
.btn{width:100%;padding:13px;background:var(--accent-grad);color:#fff;border:none;border-radius:10px;font-size:.95rem;font-weight:600;cursor:pointer;transition:all .2s;box-shadow:0 4px 16px rgba(99,102,241,0.4);display:flex;align-items:center;justify-content:center;gap:8px;text-decoration:none;}
.btn:hover{box-shadow:0 6px 22px rgba(99,102,241,0.55);transform:translateY(-1px);}
.btn:active{transform:scale(0.98);}
</style>
</head>
<body>
<div class="box">
<div class="icon-box">
<svg viewBox="0 0 24 24"><path d="M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zm-6 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm3.1-9H8.9V6c0-1.71 1.39-3.1 3.1-3.1 1.71 0 3.1 1.39 3.1 3.1v2z"/></svg>
</div>
<h2>Logged Out</h2>
<div class="desc">You have successfully logged out of SmartHome.<br>To access the controller again, please sign in below.</div>
<div class="tier-info">
<div class="tier-row"><span class="tier-badge badge-admin">Admin</span><span>Full access to GPIO profiles, Wi-Fi, backups &amp; OTA updates</span></div>
<div class="tier-row"><span class="tier-badge badge-guest">Family/Guest</span><span>Control switches, view live sensors, and set quick timers</span></div>
</div>
<a href="/" class="btn">
<svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor"><path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/></svg>
Sign In to SmartHome
</a>
</div>
</body>
</html>
)rawliteral";

#endif // WEB_PAGES_H
