# Browser-based access to the zellij agent sessions — a custom HTML sidebar.
#
# Two cooperating services:
#   * web-terminal      : ttyd (PTY <-> xterm.js) with -a/--url-arg, running the
#                         `web-term-launch` wrapper. The session to attach/create comes
#                         from the URL, e.g.  /?arg=attach&arg=feature1
#                         or  /?arg=create&arg=feature1&arg=claude
#   * web-terminal-ui   : a ~70-line Python stdlib server that serves the sidebar
#                         index.html plus GET /api/sessions (live JSON list). This is
#                         the URL you actually open.
#
# The sidebar is a left list of sessions + a terminal <iframe>. Clicking a session
# swaps the iframe's src (attach), so the session you were on stays running (detached)
# and the sidebar never reloads. "New session" points the iframe at the create wrapper.
#
# Sharing sessions with SSH: zellij keys sessions by ZELLIJ_SOCKET_DIR (default
# $XDG_RUNTIME_DIR, e.g. /run/user/1000). SSH logins get that from pam_systemd, a plain
# systemd service does not — so we pin ZELLIJ_SOCKET_DIR to a fixed path for BOTH the
# login shells (environment.variables) and these services, so a session made over SSH
# shows up in the web sidebar and vice-versa.
#
# No authentication: the security boundary is who can reach the port. Anyone who loads
# the page gets a shell as programs.lani.webTerminal.user, and the workbench shares the
# host's netns, so 0.0.0.0 publishes it on every address the host has. Hence the
# 127.0.0.1 default and openFirewall = false.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.lani.webTerminal;

  # nixpkgs' libwebsockets builds its event-loop backends (libuv/libev/libevent)
  # as separate dlopen-ed plugins (LWS_WITH_EVLIB_PLUGINS, on by default once libuv
  # is present). At runtime lws fails to locate the libuv plugin and aborts with
  #   E: lws_create_context: failed to load evlib_uv
  #   E: libwebsockets context creation failed
  # so ttyd exits 1 and the service crash-loops. Rebuilding lws with the plugins
  # turned OFF links the libuv backend straight into libwebsockets.so — no dlopen,
  # no missing plugin. ttyd is then pointed at this fixed lws.
  libwebsocketsNoEvlibPlugins = pkgs.libwebsockets.overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DLWS_WITH_EVLIB_PLUGINS=OFF" ];
  });
  ttyd = pkgs.ttyd.override { libwebsockets = libwebsocketsNoEvlibPlugins; };

  # Catppuccin Macchiato palette for the ttyd xterm.js terminal, so the web terminal
  # matches the sidebar and the catppuccin-macchiato zellij theme. Passed to ttyd as a
  # `-t theme=<json>` client option (xterm.js ITheme). `selection`/`selectionBackground`
  # are both set to cover older (xterm 4.x) and newer (5.x) field names.
  xtermTheme = builtins.toJSON {
    background = "#24273a"; # base
    foreground = "#cad3f5"; # text
    cursor = "#f4dbd6"; # rosewater
    cursorAccent = "#24273a"; # base
    selection = "#5b6078"; # surface2
    selectionBackground = "#5b6078"; # surface2
    black = "#494d64"; # surface1
    red = "#ed8796";
    green = "#a6da95";
    yellow = "#eed49f";
    blue = "#8aadf4";
    magenta = "#f5bde6"; # pink
    cyan = "#8bd5ca"; # teal
    white = "#b8c0e0"; # subtext1
    brightBlack = "#5b6078"; # surface2
    brightRed = "#ed8796";
    brightGreen = "#a6da95";
    brightYellow = "#eed49f";
    brightBlue = "#8aadf4";
    brightMagenta = "#f5bde6"; # pink
    brightCyan = "#8bd5ca"; # teal
    brightWhite = "#a5adcb"; # subtext0
  };

  # The sidebar page. Built client-side from location.hostname so it works on whatever
  # address you reach the Pi. Vercel/shadcn-inspired dark UI with animations.
  indexHtml = pkgs.writeText "lani-index.html" ''
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>lani</title>
    <style>
      :root {
        --bg:      #09090b;
        --surface: #18181b;
        --surf2:   #27272a;
        --border:  #3f3f46;
        --text:    #fafafa;
        --sub:     #a1a1aa;
        --muted:   #71717a;
        --accent:  #c6a0f6;
        --blue:    #8aadf4;
        --green:   #a6da95;
        --red:     #ed8796;
        --r:       8px;
        --w:       252px;
        --ease:    cubic-bezier(.16,1,.3,1);
      }
      *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
      html, body {
        height: 100%;
        background: var(--bg);
        color: var(--text);
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        font-size: 13px;
        -webkit-font-smoothing: antialiased;
      }

      /* ── Layout ── */
      #app { display: flex; height: 100vh; }

      /* ── Sidebar ── */
      #side {
        width: var(--w); flex: 0 0 var(--w);
        background: var(--bg);
        border-right: 1px solid var(--surf2);
        display: flex; flex-direction: column;
        position: relative; overflow: hidden;
      }
      /* ambient purple glow top-right */
      #side::before {
        content: "";
        position: absolute; top: -80px; right: -80px;
        width: 220px; height: 220px;
        background: radial-gradient(circle, rgba(198,160,246,.10) 0%, transparent 65%);
        pointer-events: none; z-index: 0;
      }
      #side > * { position: relative; z-index: 1; }

      /* ── Brand ── */
      #brand {
        padding: 18px 16px 14px;
        border-bottom: 1px solid var(--surf2);
        animation: fade-up .3s var(--ease) backwards;
      }
      .brand-row { display: flex; align-items: center; gap: 9px; }
      .brand-dot {
        width: 7px; height: 7px; border-radius: 50%;
        background: var(--accent);
        box-shadow: 0 0 10px var(--accent);
        animation: pulse-dot 2.4s ease-in-out infinite;
        flex-shrink: 0;
      }
      @keyframes pulse-dot {
        0%,100% { opacity: 1; transform: scale(1); box-shadow: 0 0 10px var(--accent); }
        50%      { opacity: .5; transform: scale(.75); box-shadow: 0 0 4px var(--accent); }
      }
      .brand-name {
        font-size: 14px; font-weight: 600; letter-spacing: -.3px; color: var(--text);
      }
      .brand-sub {
        margin-top: 4px; font-size: 11px; color: var(--muted);
        letter-spacing: .3px; padding-left: 16px;
      }

      /* ── Section header ── */
      .sec-hdr {
        padding: 14px 16px 6px;
        font-size: 10px; font-weight: 600;
        letter-spacing: .9px; text-transform: uppercase;
        color: var(--muted);
        display: flex; align-items: center; justify-content: space-between;
        animation: fade-up .3s var(--ease) .05s backwards;
      }
      .count {
        background: var(--surf2); color: var(--sub);
        font-size: 10px; font-weight: 500; letter-spacing: 0;
        padding: 1px 7px; border-radius: 10px;
        transition: background .2s;
      }

      /* ── Session list ── */
      #list {
        flex: 1; overflow-y: auto; overflow-x: hidden;
        padding: 4px 8px;
        scrollbar-width: thin; scrollbar-color: var(--surf2) transparent;
      }
      #list::-webkit-scrollbar { width: 3px; }
      #list::-webkit-scrollbar-thumb { background: var(--surf2); border-radius: 2px; }

      .empty {
        padding: 28px 12px 12px; text-align: center;
        color: var(--muted); font-size: 12px; line-height: 1.7;
      }
      .empty-icon { font-size: 22px; opacity: .35; margin-bottom: 8px; display: block; }

      /* skeleton loading */
      .sk {
        height: 34px; border-radius: var(--r); margin: 3px 0;
        background: linear-gradient(90deg, var(--surface) 25%, var(--surf2) 50%, var(--surface) 75%);
        background-size: 200% 100%;
        animation: shimmer 1.6s ease-in-out infinite;
      }
      @keyframes shimmer {
        0%   { background-position: 200% 0; }
        100% { background-position: -200% 0; }
      }

      /* session row */
      .row {
        display: flex; align-items: center; gap: 6px;
        padding: 7px 8px; border-radius: var(--r);
        cursor: pointer;
        border: 1px solid transparent;
        position: relative;
        transition: background .15s var(--ease), border-color .15s var(--ease);
        animation: slide-in .22s var(--ease) backwards;
      }
      @keyframes slide-in {
        from { opacity: 0; transform: translateX(-10px); }
        to   { opacity: 1; transform: translateX(0); }
      }
      .row:hover { background: var(--surface); border-color: var(--surf2); }
      .row.active {
        background: var(--surface);
        border-color: rgba(198,160,246,.38);
        box-shadow: inset 0 0 0 1px rgba(198,160,246,.08);
      }
      /* left accent bar on active */
      .row.active::before {
        content: "";
        position: absolute; left: -1px; top: 22%; bottom: 22%;
        width: 2px; border-radius: 1px;
        background: var(--accent);
        box-shadow: 0 0 7px var(--accent);
      }

      .row-dot {
        width: 6px; height: 6px; border-radius: 50%;
        background: var(--surf2); flex-shrink: 0;
        transition: background .2s, box-shadow .2s;
      }
      .row.active .row-dot {
        background: var(--green);
        box-shadow: 0 0 6px var(--green);
      }

      .nm {
        flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
        font-size: 12.5px; font-weight: 500;
        color: var(--sub); transition: color .15s;
      }
      .row.active .nm, .row:hover .nm { color: var(--text); }

      /* agent badge */
      .badge {
        font-size: 9px; font-weight: 700; letter-spacing: .4px;
        text-transform: uppercase; flex-shrink: 0;
        padding: 2px 6px; border-radius: 4px;
        border: 1px solid var(--surf2);
        background: var(--surf2); color: var(--muted);
      }
      .b-claude  { background: rgba(198,160,246,.12); color: var(--accent); border-color: rgba(198,160,246,.28); }
      .b-pi      { background: rgba(138,173,244,.12); color: var(--blue);   border-color: rgba(138,173,244,.28); }
      .b-opencode{ background: rgba(166,218,149,.12); color: var(--green);  border-color: rgba(166,218,149,.28); }
      .b-shell   { background: rgba(113,113,122,.10); color: var(--muted);  border-color: var(--surf2); }

      /* action buttons, hidden until hover */
      .acts { display: flex; gap: 1px; flex-shrink: 0; opacity: 0; transition: opacity .12s; }
      .row:hover .acts { opacity: 1; }
      .bi {
        background: none; border: none; cursor: pointer;
        color: var(--muted); width: 22px; height: 22px;
        display: flex; align-items: center; justify-content: center;
        border-radius: 4px; font-size: 12px;
        transition: background .12s, color .12s;
      }
      .bi:hover { background: var(--surf2); }
      .bi.kill:hover { color: var(--red); }
      .bi.ed:hover   { color: var(--blue); }

      /* inline rename input */
      .ri {
        flex: 1; background: var(--surf2); color: var(--text);
        border: 1px solid rgba(198,160,246,.45); border-radius: 4px;
        padding: 2px 7px; font: inherit; font-size: 12px; min-width: 0; outline: none;
        transition: box-shadow .15s;
      }
      .ri:focus { box-shadow: 0 0 0 3px rgba(198,160,246,.15); }

      /* ── New session panel ── */
      #new {
        padding: 12px;
        border-top: 1px solid var(--surf2);
        display: flex; flex-direction: column; gap: 7px;
        animation: fade-up .3s var(--ease) .1s backwards;
      }
      .new-hdr {
        font-size: 10px; font-weight: 600;
        letter-spacing: .9px; text-transform: uppercase;
        color: var(--muted); margin-bottom: 1px;
      }
      .field { position: relative; }
      .field input, .field select {
        width: 100%; background: var(--surface); color: var(--text);
        border: 1px solid var(--surf2); border-radius: var(--r);
        padding: 7px 10px; font: inherit; font-size: 12px;
        outline: none; appearance: none; -webkit-appearance: none;
        transition: border-color .15s, box-shadow .15s;
      }
      .field input::placeholder { color: var(--muted); }
      .field input:focus, .field select:focus {
        border-color: rgba(198,160,246,.5);
        box-shadow: 0 0 0 3px rgba(198,160,246,.08);
      }
      /* custom select chevron */
      .field.sel::after {
        content: "";
        position: absolute; right: 10px; top: 50%; transform: translateY(-50%);
        width: 0; height: 0;
        border-left: 4px solid transparent;
        border-right: 4px solid transparent;
        border-top: 5px solid var(--muted);
        pointer-events: none;
      }
      .field select { padding-right: 28px; cursor: pointer; }

      #go {
        width: 100%; padding: 8px 12px;
        background: var(--surf2); color: var(--text);
        border: 1px solid var(--border);
        border-radius: var(--r);
        font: inherit; font-size: 12px; font-weight: 600;
        cursor: pointer; letter-spacing: .1px;
        position: relative; overflow: hidden;
        transition: border-color .15s, box-shadow .15s, transform .1s;
      }
      #go::before {
        content: "";
        position: absolute; inset: 0;
        background: linear-gradient(135deg,
          rgba(198,160,246,.14) 0%, rgba(138,173,244,.08) 100%);
        opacity: 0; transition: opacity .2s;
      }
      #go:hover { border-color: rgba(198,160,246,.4); box-shadow: 0 0 12px rgba(198,160,246,.08); }
      #go:hover::before { opacity: 1; }
      #go:active { transform: scale(.98); }

      /* ── Main (terminal) area ── */
      #main {
        flex: 1; display: flex; flex-direction: column; min-width: 0;
        background: #24273a;
      }
      #ph {
        flex: 1; display: flex; flex-direction: column;
        align-items: center; justify-content: center; gap: 10px;
        color: var(--muted); background: #24273a;
        animation: fade-up .4s var(--ease) .15s backwards;
      }
      .ph-icon { font-size: 30px; opacity: .25; }
      .ph-text { font-size: 13px; color: var(--muted); }
      .ph-hint { font-size: 11px; color: #4a4a52; }
      iframe {
        flex: 1; border: 0; width: 100%;
        display: none; background: #24273a;
      }
      iframe.on { display: block; }

      /* ── Shared entrance animation ── */
      @keyframes fade-up {
        from { opacity: 0; transform: translateY(8px); }
        to   { opacity: 1; transform: translateY(0); }
      }

      /* ── Tab bar ── */
      .tabs { display: flex; border-bottom: 1px solid var(--surf2); flex-shrink: 0; }
      .tab {
        flex: 1; padding: 8px 4px; text-align: center; cursor: pointer;
        font-size: 10px; font-weight: 700; letter-spacing: .7px; text-transform: uppercase;
        color: var(--muted); border-bottom: 2px solid transparent;
        transition: color .15s, border-color .15s;
      }
      .tab.active { color: var(--text); border-bottom-color: var(--accent); }
      .tab:hover:not(.active) { color: var(--sub); }

      /* ── Module list ── */
      #mod-list {
        flex: 1; overflow-y: auto; overflow-x: hidden; padding: 4px 8px;
        scrollbar-width: thin; scrollbar-color: var(--surf2) transparent;
      }
      .mrow {
        display: flex; align-items: center; gap: 6px;
        padding: 7px 8px; border-radius: var(--r); cursor: pointer;
        border: 1px solid transparent;
        transition: background .15s, border-color .15s;
      }
      .mrow:hover { background: var(--surface); border-color: var(--surf2); }
      .mrow.active { background: var(--surface); border-color: rgba(198,160,246,.38); }
      .mdot { width: 6px; height: 6px; border-radius: 50%; flex-shrink: 0; transition: background .2s, box-shadow .2s; }
      .mdot.available   { background: var(--surf2); }
      .mdot.installed   { background: var(--green); box-shadow: 0 0 5px var(--green); }
      .mdot.in-progress { background: var(--blue); animation: pulse-dot 1.4s ease-in-out infinite; }
      .mnm { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 12.5px; font-weight: 500; color: var(--sub); transition: color .15s; }
      .mrow:hover .mnm, .mrow.active .mnm { color: var(--text); }
      .mbadge { font-size: 9px; font-weight: 700; letter-spacing: .3px; text-transform: uppercase; flex-shrink: 0; padding: 1px 5px; border-radius: 3px; }
      .mbadge.available   { color: var(--muted); }
      .mbadge.installed   { color: var(--green); }
      .mbadge.in-progress { color: var(--blue); }
      .ibtn {
        font-size: 9px; font-weight: 700; flex-shrink: 0; padding: 2px 7px; border-radius: 4px;
        background: none; border: 1px solid var(--surf2); color: var(--muted); cursor: pointer;
        transition: border-color .15s, color .15s;
      }
      .ibtn:hover { border-color: rgba(198,160,246,.45); color: var(--accent); }

      /* ── CI status panel ── */
      #ci { flex: 1; display: none; flex-direction: column; background: var(--bg); overflow: hidden; }
      #ci.on { display: flex; }
      .ci-top { padding: 14px 20px 12px; border-bottom: 1px solid var(--surf2); background: var(--surface); flex-shrink: 0; }
      .ci-modname { font-size: 15px; font-weight: 600; color: var(--text); }
      .ci-sub { font-size: 11px; color: var(--muted); margin-top: 2px; }
      .ci-phases { display: flex; align-items: stretch; flex-wrap: wrap; padding: 14px 20px; gap: 0; flex-shrink: 0; }
      .ci-conn { width: 18px; display: flex; align-items: center; justify-content: center; color: var(--surf2); font-size: 12px; }
      .ci-ph { background: var(--surface); border: 1px solid var(--surf2); border-radius: 5px; padding: 7px 13px; min-width: 100px; }
      .ci-lbl { font-size: 9px; text-transform: uppercase; letter-spacing: .6px; color: var(--muted); margin-bottom: 4px; }
      .ci-st { font-size: 12px; font-weight: 600; display: flex; align-items: center; gap: 4px; }
      .ci-st.done    { color: var(--green); }
      .ci-st.running { color: var(--blue);  }
      .ci-st.pending { color: var(--surf2); }
      .ci-st.fail    { color: var(--red);   }
      .ci-spin { width: 10px; height: 10px; flex-shrink: 0; border: 2px solid currentColor; border-top-color: transparent; border-radius: 50%; animation: spin .7s linear infinite; }
      @keyframes spin { to { transform: rotate(360deg); } }
      #ci-result { margin: 0 20px 10px; padding: 8px 14px; border-radius: 5px; font-size: 12px; font-weight: 600; display: none; flex-shrink: 0; }
      #ci-result.pass { background: rgba(166,218,149,.08); border: 1px solid var(--green); color: var(--green); }
      #ci-result.fail { background: rgba(237,135,150,.08); border: 1px solid var(--red);   color: var(--red);   }
      .ci-log-wrap { flex: 1; display: flex; flex-direction: column; min-height: 0; padding: 0 20px 16px; }
      .ci-log-hdr { font-size: 9px; font-weight: 700; text-transform: uppercase; letter-spacing: .6px; color: var(--muted); margin-bottom: 5px; flex-shrink: 0; }
      #ci-log { flex: 1; background: var(--surface); border: 1px solid var(--surf2); border-radius: 5px; padding: 10px 12px; overflow-y: auto; white-space: pre-wrap; word-break: break-all; font-family: "SFMono-Regular", Consolas, monospace; font-size: 11px; line-height: 1.6; color: #9ca3af; min-height: 0; scrollbar-width: thin; scrollbar-color: var(--surf2) transparent; }
    </style>
    </head>
    <body>
    <div id="app">

      <div id="side">
        <div id="brand">
          <div class="brand-row">
            <span class="brand-dot"></span>
            <span class="brand-name">lani</span>
          </div>
          <div class="brand-sub">session manager</div>
        </div>

        <div class="tabs">
          <div class="tab active" id="tab-sess" onclick="switchTab('sess')">Sessions</div>
          <div class="tab" id="tab-mods" onclick="switchTab('mods')">Modules</div>
        </div>

        <div id="sess-view" style="display:flex;flex-direction:column;flex:1;overflow:hidden">
          <div class="sec-hdr">
            Sessions
            <span class="count" id="cnt">—</span>
          </div>
          <div id="list">
            <div class="sk" style="width:88%"></div>
            <div class="sk" style="width:72%;opacity:.6"></div>
          </div>
          <div id="new">
            <div class="new-hdr">New session</div>
            <div class="field">
              <input id="nm" placeholder="session name…" autocomplete="off" spellcheck="false">
            </div>
            <div class="field sel">
              <select id="ag">
                <option value="claude">claude</option>
                <option value="pi">pi</option>
                <option value="opencode">opencode</option>
                <option value="shell">shell</option>
              </select>
            </div>
            <button id="go">＋ Create session</button>
          </div>
        </div>

        <div id="mods-view" style="display:none;flex-direction:column;flex:1;overflow:hidden">
          <div class="sec-hdr">
            Modules
            <span class="count" id="mod-cnt">—</span>
          </div>
          <div id="mod-list">
            <div class="sk" style="width:88%"></div>
            <div class="sk" style="width:72%;opacity:.6"></div>
            <div class="sk" style="width:80%;opacity:.4"></div>
          </div>
        </div>
      </div>

      <div id="main">
        <div id="ph">
          <div class="ph-icon">⌨</div>
          <div class="ph-text">No session open</div>
          <div class="ph-hint">Select a session, create one, or browse Modules</div>
        </div>
        <iframe id="term" allow="clipboard-read; clipboard-write"></iframe>
        <div id="ci">
          <div class="ci-top">
            <div class="ci-modname" id="ci-name">—</div>
            <div class="ci-sub" id="ci-sub"></div>
          </div>
          <div class="ci-phases" id="ci-phases"></div>
          <div id="ci-result"></div>
          <div class="ci-log-wrap">
            <div class="ci-log-hdr">Agent output</div>
            <div id="ci-log">Select a module from the Modules tab.</div>
          </div>
        </div>
      </div>

    </div>
    <script>
    var current = null;
    var lastList = [];
    var boot = true;
    var activeTab = "sess";
    var currentMod = null;
    var ciTimer = null;

    function base(){ return location.protocol + "//" + location.host + "/t"; }
    function cb(){ return "&_cb=" + Date.now(); }

    function nudgeFit(){
      var t = document.getElementById("term");
      t.style.width = "99%";
      setTimeout(function(){ t.style.width = "100%"; }, 60);
    }

    function hideCi(){
      var ci = document.getElementById("ci");
      ci.classList.remove("on");
      if(ciTimer){ clearInterval(ciTimer); ciTimer = null; }
    }

    function setIframe(url){
      hideCi();
      var t = document.getElementById("term");
      var ph = document.getElementById("ph");
      t.onload = function(){
        t.classList.add("on");
        ph.style.display = "none";
        setTimeout(nudgeFit, 120);
      };
      t.src = url;
    }

    function badgeCls(agent){
      var m = {claude:"b-claude", pi:"b-pi", opencode:"b-opencode", shell:"b-shell"};
      return m[agent] || "";
    }

    function attach(name){
      current = name;
      setIframe(base() + "/?arg=attach&arg=" + encodeURIComponent(name) + cb());
      render(lastList);
    }

    function create(){
      var nm = document.getElementById("nm").value.trim();
      var ag = document.getElementById("ag").value;
      if(!nm){ document.getElementById("nm").focus(); return; }
      current = nm;
      setIframe(base() + "/?arg=create&arg=" + encodeURIComponent(nm) + "&arg=" + encodeURIComponent(ag) + cb());
      document.getElementById("nm").value = "";
      setTimeout(refresh, 1200);
    }

    function render(items){
      lastList = items;
      var el = document.getElementById("list");
      el.querySelectorAll(".sk").forEach(function(s){ s.remove(); });
      var cntEl = document.getElementById("cnt");
      cntEl.textContent = items.length;

      if(!items.length){
        el.innerHTML = '<div class="empty"><span class="empty-icon">◎</span>No sessions yet.<br>Create one below.</div>';
        boot = false;
        return;
      }

      var newNames = items.map(function(s){ return s.name; });
      el.querySelectorAll(".row").forEach(function(r){
        if(newNames.indexOf(r.dataset.name) === -1) r.remove();
      });

      items.forEach(function(s, i){
        var display = s.label || s.name;
        var sel = '.row[data-name="' + s.name.replace(/"/g, '\\"') + '"]';
        var existing = el.querySelector(sel);
        if(existing){
          existing.className = "row" + (s.name === current ? " active" : "");
          var nm = existing.querySelector(".nm");
          if(nm) nm.textContent = display;
          return;
        }

        var d = document.createElement("div");
        d.className = "row" + (s.name === current ? " active" : "");
        d.dataset.name = s.name;
        if(boot) d.style.animationDelay = (i * 45) + "ms";

        var dot  = document.createElement("div"); dot.className = "row-dot";
        var n    = document.createElement("div"); n.className = "nm"; n.textContent = display;
        var b    = document.createElement("div");
        b.className = "badge " + badgeCls(s.agent);
        b.textContent = s.agent;

        var acts = document.createElement("div"); acts.className = "acts";
        var ed   = document.createElement("button"); ed.className = "bi ed"; ed.textContent = "✎"; ed.title = "rename";
        var kl   = document.createElement("button"); kl.className = "bi kill"; kl.textContent = "×"; kl.title = "kill";

        (function(sname, slabel){
          ed.onclick = function(e){
            e.stopPropagation();
            var inp = document.createElement("input");
            inp.className = "ri"; inp.value = slabel;
            inp.onclick = function(ev){ ev.stopPropagation(); };
            d.replaceChild(inp, n);
            acts.style.opacity = "1";
            inp.focus(); inp.select();
            var done = false;
            function save(){
              if(done) return; done = true;
              var v = inp.value.trim();
              fetch("/api/rename-session?name=" + encodeURIComponent(sname) + "&label=" + encodeURIComponent(v))
                .then(function(){ setTimeout(refresh, 200); }).catch(function(){ refresh(); });
            }
            inp.addEventListener("keydown", function(ev){
              if(ev.key === "Enter"){ save(); }
              else if(ev.key === "Escape"){ done = true; refresh(); }
            });
            inp.addEventListener("blur", save);
          };
          kl.onclick = function(e){
            e.stopPropagation();
            d.style.transition = "opacity .2s, transform .2s";
            d.style.opacity = ".3"; d.style.transform = "translateX(-6px)";
            fetch("/api/kill-session?name=" + encodeURIComponent(sname)).then(function(){
              if(current === sname){
                current = null;
                var t = document.getElementById("term");
                t.src = "about:blank"; t.classList.remove("on");
                document.getElementById("ph").style.display = "";
              }
              setTimeout(refresh, 300);
            }).catch(function(){});
          };
        })(s.name, display);

        acts.appendChild(ed); acts.appendChild(kl);
        d.appendChild(dot); d.appendChild(n); d.appendChild(b); d.appendChild(acts);
        d.onclick = function(){ attach(s.name); };
        el.appendChild(d);
      });

      boot = false;
    }

    function refresh(){
      fetch("/api/sessions").then(function(r){ return r.json(); }).then(render).catch(function(){});
    }

    /* ── Modules tab ── */

    function switchTab(t){
      activeTab = t;
      document.getElementById("tab-sess").classList.toggle("active", t === "sess");
      document.getElementById("tab-mods").classList.toggle("active", t === "mods");
      document.getElementById("sess-view").style.display = t === "sess" ? "flex" : "none";
      document.getElementById("mods-view").style.display = t === "mods" ? "flex" : "none";
      if(t === "mods") refreshModules();
    }

    function refreshModules(){
      fetch("/api/modules")
        .then(function(r){ return r.json(); })
        .then(renderModules)
        .catch(function(){});
    }

    function renderModules(mods){
      var el  = document.getElementById("mod-list");
      var cnt = document.getElementById("mod-cnt");
      cnt.textContent = mods.length;
      el.querySelectorAll(".sk").forEach(function(s){ s.remove(); });

      var newNames = mods.map(function(m){ return m.name; });
      el.querySelectorAll(".mrow").forEach(function(r){
        if(newNames.indexOf(r.dataset.name) === -1) r.remove();
      });

      mods.forEach(function(m){
        var existing = el.querySelector(".mrow[data-name=\"" + m.name + "\"]");
        if(existing){
          existing.querySelector(".mdot").className = "mdot " + m.status;
          var mb = existing.querySelector(".mbadge");
          mb.className = "mbadge " + m.status;
          mb.textContent = m.status === "in-progress" ? "building" : m.status;
          var ib = existing.querySelector(".ibtn");
          if(ib) ib.style.display = m.status === "available" ? "" : "none";
          existing.className = "mrow" + (m.name === currentMod ? " active" : "");
          return;
        }
        var d   = document.createElement("div"); d.className = "mrow" + (m.name === currentMod ? " active" : ""); d.dataset.name = m.name;
        var dot = document.createElement("div"); dot.className = "mdot " + m.status;
        var nm  = document.createElement("div"); nm.className = "mnm"; nm.textContent = m.name;
        var st  = document.createElement("div"); st.className = "mbadge " + m.status; st.textContent = m.status === "in-progress" ? "building" : m.status;
        d.appendChild(dot); d.appendChild(nm); d.appendChild(st);
        if(m.status === "available"){
          var ib = document.createElement("button"); ib.className = "ibtn"; ib.textContent = "Install";
          (function(mod){ ib.onclick = function(e){ e.stopPropagation(); installMod(mod); }; })(m);
          d.appendChild(ib);
        }
        (function(mod){ d.onclick = function(){ selectMod(mod); }; })(m);
        el.appendChild(d);
      });
    }

    function selectMod(m){
      currentMod = m.name;
      document.querySelectorAll(".mrow").forEach(function(r){ r.classList.toggle("active", r.dataset.name === m.name); });
      showCiPanel(m);
    }

    function showCiPanel(m){
      document.getElementById("term").classList.remove("on");
      document.getElementById("ph").style.display = "none";
      var ci = document.getElementById("ci"); ci.classList.add("on");
      document.getElementById("ci-name").textContent = m.name;
      document.getElementById("ci-sub").textContent = m.subdomain ? (m.subdomain + ".local  :" + m.port) : "";
      // Reset transient state so a previously-selected module's phases/result/log
      // don't bleed into this one (e.g. a passed module's all-green "Done" marks
      // lingering on a module that has never run CI).
      document.getElementById("ci-phases").innerHTML = "";
      document.getElementById("ci-result").style.display = "none";
      document.getElementById("ci-log").textContent = "Loading…";
      if(ciTimer){ clearInterval(ciTimer); }
      refreshCi(m.name);
      ciTimer = setInterval(function(){ refreshCi(m.name); }, 2500);
    }

    function refreshCi(name){
      fetch("/api/modules/status?name=" + encodeURIComponent(name))
        .then(function(r){ return r.ok ? r.json() : null; })
        .then(function(st){
          if(!st){
            document.getElementById("ci-phases").innerHTML = "";
            document.getElementById("ci-result").style.display = "none";
            document.getElementById("ci-log").textContent = "No CI run yet. Click Install to begin.";
            return;
          }
          if(st.phases){
            document.getElementById("ci-phases").innerHTML = st.phases.map(function(p, i){
              var icon = p.status === "done"    ? "✓"
                       : p.status === "running" ? "<span class=\"ci-spin\"></span>"
                       : p.status === "fail"    ? "✗"
                       : "<span style=\"opacity:.25\">·</span>";
              return (i > 0 ? "<div class=\"ci-conn\">›</div>" : "") +
                "<div class=\"ci-ph\"><div class=\"ci-lbl\">" + p.label + "</div>" +
                "<div class=\"ci-st " + p.status + "\">" + icon + " " + p.status + "</div></div>";
            }).join("");
          }
          if(st.result){
            var rb = document.getElementById("ci-result");
            rb.className = st.result;
            rb.textContent = st.result === "pass"
              ? "✓  " + name + " passed all health checks"
              : "✗  Failed — " + (st.detail || "see log");
            rb.style.display = "";
          }
          if(st.log){
            fetch("/api/modules/log?name=" + encodeURIComponent(name))
              .then(function(r){ return r.ok ? r.text() : null; })
              .then(function(txt){
                var box = document.getElementById("ci-log");
                if(txt === null){
                  box.textContent = "(log file not found — may have been rotated)";
                  return;
                }
                var atBot = box.scrollHeight - box.scrollTop - box.clientHeight < 80;
                box.textContent = txt || "(no output yet)";
                if(atBot) box.scrollTop = box.scrollHeight;
              }).catch(function(){});
          } else {
            document.getElementById("ci-log").textContent = "(no log captured)";
          }
        }).catch(function(){});
    }

    function installMod(m){
      currentMod = m.name;
      document.querySelectorAll(".mrow").forEach(function(r){ r.classList.toggle("active", r.dataset.name === m.name); });
      showCiPanel(m);
      document.getElementById("ci-log").textContent = "Starting installation…";
      // Trigger install via hidden iframe (creates a zellij session through ttyd)
      var hf = document.createElement("iframe");
      hf.style.cssText = "display:none;position:absolute;width:0;height:0";
      hf.src = base() + "/?arg=install&arg=" + encodeURIComponent(m.name) + cb();
      document.body.appendChild(hf);
      setTimeout(refresh, 2500);
      setTimeout(refreshModules, 3500);
    }

    document.getElementById("go").onclick = create;
    document.getElementById("nm").addEventListener("keydown", function(e){ if(e.key === "Enter"){ create(); } });
    refresh();
    setInterval(refresh, 2500);
    setInterval(function(){ if(activeTab === "mods") refreshModules(); }, 5000);
    </script>
    </body>
    </html>
  '';

  # Sidebar backend: serve index.html (with the ttyd port injected) and a JSON list of
  # sessions. Reads the same agent markers the gum/web launchers write, so badges match.
  sidebarServer = pkgs.writeText "lani-webui.py" ''
    import json, os, re, subprocess, time
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    from urllib.parse import urlparse, parse_qs

    UI_PORT      = int(os.environ.get("UI_PORT", "7683"))
    INDEX        = os.environ["INDEX_HTML"]
    STATE        = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "agent-menu")
    ANSI         = re.compile("\x1b\\[[0-9;]*m")
    CATALOG_NIX  = os.environ.get("CATALOG_NIX", "")
    SERVICES_REPO = os.environ.get("SERVICES_REPO", "/etc/nixos")
    CI_DIR       = os.environ.get("CI_DIR",       "/var/lib/lani-ci")

    _cat_cache = {"ts": 0, "raw": []}

    def _catalog_raw():
        now = time.time()
        if now - _cat_cache["ts"] < 45:
            return _cat_cache["raw"]
        try:
            r = subprocess.run(
                ["nix", "eval", "--raw", "--apply",
                 "mods: builtins.concatStringsSep \"\n\" (map (m: m.name + \"\t\" + m.subdomain + \"\t\" + (toString m.port) + \"\t\" + m.description) mods)",
                 "-f", CATALOG_NIX],
                capture_output=True, text=True, timeout=35)
            rows = [l for l in r.stdout.strip().splitlines() if l]
        except Exception:
            rows = []
        _cat_cache["raw"] = rows
        _cat_cache["ts"]  = now
        return rows

    def get_modules():
        mods = []
        for line in _catalog_raw():
            parts = line.split("\t", 3)
            if len(parts) < 4:
                continue
            name, sub, port, desc = parts
            mods.append({"name": name, "subdomain": sub, "port": port,
                          "description": desc,
                          "status": module_status(name),
                          "ci": get_ci_status(name)})
        return mods

    def module_status(name):
        try:
            r = subprocess.run(
                ["git", "-C", SERVICES_REPO, "worktree", "list", "--porcelain"],
                capture_output=True, text=True, timeout=5)
            if "refs/heads/feat/" + name in r.stdout:
                return "in-progress"
        except Exception:
            pass
        try:
            with open(os.path.join(SERVICES_REPO, "modules", "default.nix")) as f:
                if "./" + name + ".nix" in f.read():
                    return "installed"
        except Exception:
            pass
        return "available"

    def get_ci_status(name):
        try:
            p = os.path.join(CI_DIR, "status", name + ".json")
            if os.path.exists(p):
                with open(p) as f:
                    return json.load(f)
        except Exception:
            pass
        return None

    def get_ci_log(name):
        try:
            st = get_ci_status(name)
            if not st or not st.get("log"):
                return None
            p = os.path.join(CI_DIR, "logs", st["log"])
            if os.path.exists(p):
                with open(p) as f:
                    return f.read()
        except Exception:
            pass
        return None

    def sessions():
        try:
            out = subprocess.run(["zellij", "list-sessions", "-s"],
                                 capture_output=True, text=True, timeout=5).stdout
        except Exception:
            out = ""
        items = []
        for line in out.splitlines():
            parts = ANSI.sub("", line).split()
            if not parts:
                continue
            name = parts[0]
            agent = "?"
            label = name
            try:
                with open(os.path.join(STATE, "sessions", name)) as f:
                    agent = f.read().strip() or "?"
            except Exception:
                pass
            try:
                with open(os.path.join(STATE, "sessions", name + ".alias")) as f:
                    label = f.read().strip() or name
            except Exception:
                pass
            items.append({"name": name, "agent": agent, "label": label})
        return items

    class H(BaseHTTPRequestHandler):
        def _send(self, code, body, ctype):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store, must-revalidate")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path.startswith("/api/modules"):
                sub = urlparse(self.path).path[len("/api/modules"):]
                qs  = parse_qs(urlparse(self.path).query)
                name = qs.get("name", [""])[0]
                if sub in ("", "/"):
                    self._send(200, json.dumps(get_modules()).encode(), "application/json")
                elif sub == "/status":
                    st = get_ci_status(name) if name else None
                    self._send(200, json.dumps(st).encode(), "application/json")
                elif sub == "/log":
                    log = get_ci_log(name) if name else None
                    if log is not None:
                        self._send(200, log.encode("utf-8", errors="replace"), "text/plain; charset=utf-8")
                    else:
                        self._send(404, b"no log", "text/plain")
                else:
                    self._send(404, b"not found", "text/plain")
            elif self.path.startswith("/api/sessions"):
                self._send(200, json.dumps(sessions()).encode(), "application/json")
            elif self.path.startswith("/api/rename-session"):
                qs = parse_qs(urlparse(self.path).query)
                names = qs.get("name", [])
                labels = qs.get("label", [])
                if names and labels:
                    name = names[0]
                    label = labels[0].strip()
                    alias_path = os.path.join(STATE, "sessions", name + ".alias")
                    if label and label != name:
                        with open(alias_path, "w") as f:
                            f.write(label)
                    else:
                        try:
                            os.unlink(alias_path)
                        except Exception:
                            pass
                self._send(200, b'{"ok":true}', "application/json")
            elif self.path.startswith("/api/kill-session"):
                qs = parse_qs(urlparse(self.path).query)
                names = qs.get("name", [])
                if names:
                    name = names[0]
                    subprocess.run(["zellij", "kill-session", name], capture_output=True, timeout=5)
                    for suffix in ("", ".alias"):
                        try:
                            os.unlink(os.path.join(STATE, "sessions", name + suffix))
                        except Exception:
                            pass
                self._send(200, b'{"ok":true}', "application/json")
            elif self.path == "/" or self.path.startswith("/?") or self.path.startswith("/index"):
                with open(INDEX) as f:
                    html = f.read()
                self._send(200, html.encode(), "text/html; charset=utf-8")
            else:
                self._send(404, b"not found", "text/plain")

        def log_message(self, *a):
            pass

    ThreadingHTTPServer(("127.0.0.1", UI_PORT), H).serve_forever()
  '';
in
{
  options.programs.lani.webTerminal = {
    enable = lib.mkEnableOption "the web sidebar + ttyd terminal for zellij agent sessions";

    port = lib.mkOption {
      type = lib.types.port;
      default = 7681;
      description = "TCP port for the sidebar UI — this is the URL you open.";
    };

    ttydPort = lib.mkOption {
      type = lib.types.port;
      default = 7682;
      description = "TCP port for the ttyd terminal the sidebar iframe connects to.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "lani";
      description = ''
        Account the terminal, and therefore the zellij client, runs as. Must match the
        account whose SSH sessions you want to see, or they will not share a socket.
      '';
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      example = "0.0.0.0";
      description = ''
        **There is no authentication.** Whoever loads the page gets a shell as
        {option}`programs.lani.webTerminal.user`. Loopback by default; tunnel in with
        `ssh -L <port>:127.0.0.1:<port> <host>`.
      '';
    };

    socketDir = lib.mkOption {
      type = lib.types.path;
      default = "/run/zellij";
      description = ''
        Fixed ZELLIJ_SOCKET_DIR shared by SSH login shells and the web terminal, so
        both list/attach the same sessions. Lives under /run (wiped each boot, like
        the default runtime dir).
      '';
    };

    servicesRepo = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos";
      description = ''
        Services repository, read by the sidebar to tell whether each module is available,
        in progress, or installed.
      '';
    };

    catalogPath = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Catalog source tree containing `catalog.nix`. Set by the Lani module.";
    };

    ciDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/lani-ci";
      description = "CI state directory the sidebar reads build status and logs from.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open {option}`programs.lani.webTerminal.port` in the firewall. Read the warning on
        {option}`programs.lani.webTerminal.listenAddress` first.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.programs.lani.menu.enable;
        message = "programs.lani.webTerminal needs programs.lani.menu.enable = true (it reuses its launchers).";
      }
    ];

    # Pin the zellij socket dir everywhere so SSH and web share sessions.
    environment.variables.ZELLIJ_SOCKET_DIR = cfg.socketDir;
    systemd.tmpfiles.rules = [
      "d ${cfg.socketDir} 0700 ${cfg.user} users - -"
    ];

    # Shared bits for both services: run as the user, share the zellij socket + config.
    systemd.services =
      let
        common = {
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            User = cfg.user;
            Group = "users";
            WorkingDirectory = "/home/${cfg.user}";
            Restart = "always";
            RestartSec = 2;
          };
        };
        baseEnv = {
          HOME = "/home/${cfg.user}";
          ZELLIJ_SOCKET_DIR = cfg.socketDir;
        };
      in
      {
        # The terminal: ttyd passes the URL's ?arg=... to web-term-launch.
        web-terminal = lib.recursiveUpdate common {
          description = "ttyd terminal for zellij agent sessions";
          environment = baseEnv // {
            TERM = "xterm-256color";
            # Same zellij theme/config the SSH menu uses (set by agent-menu.nix). A system
            # service doesn't inherit environment.variables, so pass it explicitly.
            ZELLIJ_CONFIG_DIR = config.environment.variables.ZELLIJ_CONFIG_DIR;
          };
          serviceConfig.ExecStart = lib.escapeShellArgs [
            "${ttyd}/bin/ttyd"
            "--writable" # allow keyboard input (ttyd is read-only otherwise)
            "--url-arg" # pass ?arg=... from the URL to the command (no auth, as asked)
            "-t"
            "fontSize=13" # xterm.js font size: smaller = more columns across the width
            "-t"
            "theme=${xtermTheme}" # Catppuccin Macchiato (matches sidebar + zellij)
            "-t"
            "copyOnSelect=true" # auto-copy selected text to clipboard
            "-t"
            "macOptionIsMeta=true" # Option+Enter = Alt+Enter = literal newline in Claude
            "--interface"
            "127.0.0.1"
            "--port"
            (toString cfg.ttydPort)
            "${config.programs.lani.menu.webLauncher}/bin/web-term-launch"
          ];
        };

        # The sidebar UI + /api/sessions (internal; nginx fronts it on cfg.port).
        web-terminal-ui = lib.recursiveUpdate common {
          description = "Lani web sidebar (session list and UI)";
          environment = baseEnv // {
            UI_PORT = toString (cfg.port + 2);
            INDEX_HTML = "${indexHtml}";
            CATALOG_NIX = "${cfg.catalogPath}/catalog.nix";
            SERVICES_REPO = cfg.servicesRepo;
            CI_DIR = cfg.ciDir;
          };
          path = [
            pkgs.zellij
            pkgs.nix
            pkgs.git
          ];
          serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 ${sidebarServer}";
        };
      };

    # One port for both: the browser must see them as the same origin, or clipboard
    # access is blocked over plain http.
    services.nginx = {
      enable = true;
      virtualHosts."lani-web-terminal" = {
        listen = [
          {
            addr = cfg.listenAddress;
            port = cfg.port;
            ssl = false;
          }
        ];
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString (cfg.port + 2)}";
          extraConfig = "proxy_read_timeout 86400;";
        };
        locations."/t/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.ttydPort}/";
          proxyWebsockets = true;
          extraConfig = "proxy_read_timeout 86400;";
        };
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
