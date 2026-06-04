#!/usr/bin/env python3
"""맥북 팬 · 전원 관리 — Intel MacBook / macOS Sequoia"""

import tkinter as tk
from tkinter import messagebox, ttk
import subprocess, threading, re, time, shutil, os, sys, tempfile, struct
import urllib.request, json, webbrowser

VERSION = "1.4.3"
GITHUB_API = "https://api.github.com/repos/eondcom/mac-fan-control/releases/latest"
SETTINGS_PATH = os.path.expanduser('~/.macfancontrol.json')

# ── 설정 저장/불러오기 ────────────────────────────────────────────────────────

def load_settings():
    defaults = {'mb_show_temp': True, 'mb_show_fan': True}
    try:
        with open(SETTINGS_PATH) as f:
            defaults.update(json.load(f))
    except Exception:
        pass
    return defaults

def save_settings(s):
    try:
        with open(SETTINGS_PATH, 'w') as f:
            json.dump(s, f, indent=2)
    except Exception:
        pass

# ── macOS 메뉴바 위젯 (PyObjC) ───────────────────────────────────────────────
try:
    import objc
    from AppKit import (NSStatusBar, NSMenu, NSMenuItem, NSObject,
                        NSApplication, NSImage, NSSize)
    _APPKIT = True
except ImportError:
    _APPKIT = False

# ── smc 바이너리 탐색 ────────────────────────────────────────────────────────
SMC_CANDIDATES = [
    '/usr/local/bin/smc',
    '/opt/homebrew/bin/smc',
    os.path.expanduser('~/bin/smc'),
    '/Applications/smcFanControl.app/Contents/Resources/smc',
]
SMC = next((p for p in SMC_CANDIDATES if os.path.isfile(p) and os.access(p, os.X_OK)), None) \
      or shutil.which('smc')

# ── 시스템 명령 ──────────────────────────────────────────────────────────────

def shell(cmd):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return r.stdout, r.stderr

def admin(cmd):
    escaped = cmd.replace('\\', '\\\\').replace('"', '\\"')
    r = subprocess.run(
        ['osascript', '-e', f'do shell script "{escaped}" with administrator privileges'],
        capture_output=True, text=True
    )
    return r.returncode == 0

# ── 상태 읽기 ────────────────────────────────────────────────────────────────

def get_power_mode():
    out, _ = shell('pmset -g')
    m = re.search(r'lowpowermode\s+(\d)', out)
    return 'low' if (m and m.group(1) == '1') else 'normal'

def _smc_read_decimal(key):
    if not SMC:
        return None
    out, _ = shell(f'"{SMC}" -k {key} -r 2>/dev/null')
    # flt 포맷: "F0Ac  [flt ]  (bytes f5 b6 07 45)"
    m_flt = re.search(r'\[flt\s*\].*\(bytes\s+([0-9a-f]{2})\s+([0-9a-f]{2})\s+([0-9a-f]{2})\s+([0-9a-f]{2})', out)
    if m_flt:
        try:
            raw = bytes.fromhex(''.join(m_flt.groups()))
            return struct.unpack('<f', raw)[0]
        except Exception:
            pass
    # 소수 포맷: "123.45 (bytes ...)"
    m = re.search(r'([\d]+\.[\d]+)\s*\(bytes', out)
    if m:
        try:
            return float(m.group(1))
        except Exception:
            pass
    return None

def get_thermal():
    cpu_temp = gpu_temp = battery_temp = fan_rpm = fan_min = fan_max = None

    # CPU 온도
    for key in ('TC0P', 'TC0D', 'TC0H', 'TCXC', 'Ts0S'):
        val = _smc_read_decimal(key)
        if val and 0 < val < 120:
            cpu_temp = val
            break

    # GPU 온도
    val = _smc_read_decimal('TG0P')
    if val and 0 < val < 120:
        gpu_temp = val

    # 배터리 온도
    val = _smc_read_decimal('TB0T')
    if val and 0 < val < 80:
        battery_temp = val

    # 팬 현재/최소/최대 속도
    val = _smc_read_decimal('F0Ac')
    if val and val > 0:
        fan_rpm = int(val)
    val = _smc_read_decimal('F0Mn')
    if val and val > 0:
        fan_min = int(val)
    val = _smc_read_decimal('F0Mx')
    if val and val > 0:
        fan_max = int(val)

    # 팬 속도 폴백 — smc -f
    if fan_rpm is None and SMC:
        out, _ = shell(f'"{SMC}" -f 2>/dev/null')
        m = re.search(r'(?:[Cc]urrent|[Aa]ctual)\s+[Ss]peed\s*:\s*(\d+)', out)
        if m:
            fan_rpm = int(m.group(1))
        m = re.search(r'[Mm]inimum\s+[Ss]peed\s*:\s*(\d+)', out)
        if m:
            fan_min = int(m.group(1))
        m = re.search(r'[Mm]aximum\s+[Ss]peed\s*:\s*(\d+)', out)
        if m:
            fan_max = int(m.group(1))

    # 팬 속도 폴백 — ioreg
    if fan_rpm is None:
        out, _ = shell('ioreg -r -c AppleSMCFan 2>/dev/null')
        m = re.search(r'"CurrentSpeed"\s*=\s*(\d+)', out)
        if m:
            fan_rpm = int(m.group(1))

    # CPU 온도 폴백 — ioreg
    if cpu_temp is None:
        out, _ = shell('ioreg -l 2>/dev/null | grep -i "CPU die temperature"')
        m = re.search(r'(\d+\.?\d*)', out)
        if m:
            val = float(m.group(1))
            cpu_temp = val / 100.0 if val > 1000 else val

    # 팬 모드 (0=자동, 1=수동)
    fan_manual = False
    if SMC:
        out, _ = shell(f'"{SMC}" -k F0Md -r 2>/dev/null')
        m = re.search(r'\(bytes\s+([0-9a-f]{2})', out)
        if m and m.group(1) != '00':
            fan_manual = True

    return cpu_temp, gpu_temp, battery_temp, fan_rpm, fan_min, fan_max, fan_manual

def get_battery_info():
    """충전 횟수, 용량(%, mAh), 잔여 시간, 상태 반환."""
    out, _ = shell('system_profiler SPPowerDataType 2>/dev/null')
    cycle = capacity = condition = None

    m = re.search(r'Cycle Count:\s*(\d+)', out)
    if m:
        cycle = int(m.group(1))

    # macOS 버전에 따라 포맷이 다름 — 두 방식 모두 시도
    m = re.search(r'Maximum Capacity:\s*(\d+)\s*%', out)
    if m:
        capacity = int(m.group(1))
    else:
        # Sequoia: ioreg 에서 MaxCapacity / DesignCapacity 로 계산
        ir, _ = shell('ioreg -r -c AppleSmartBattery 2>/dev/null')
        m_max = re.search(r'"MaxCapacity"\s*=\s*(\d+)', ir)
        m_des = re.search(r'"DesignCapacity"\s*=\s*(\d+)', ir)
        if m_max and m_des:
            max_mah = int(m_max.group(1))
            des_mah = int(m_des.group(1))
            if des_mah > 0:
                capacity = round(max_mah / des_mah * 100)

    m = re.search(r'Condition:\s*(\S[\w ]*)', out)
    if m:
        condition = m.group(1).strip()

    # 잔여 시간 — pmset
    out2, _ = shell('pmset -g batt 2>/dev/null')
    remain = None
    m2 = re.search(r'(\d+:\d+)\s+remaining', out2)
    if m2:
        remain = m2.group(1)
    # 'discharging'에 'charging'이 포함되므로 단어 경계로 매칭
    m_status = re.search(r'\d+%;\s*([\w ]+?)\s*;', out2)
    status_word = m_status.group(1).lower() if m_status else ''
    charging = status_word == 'charging'

    return cycle, capacity, condition, remain, charging

def set_fan_speed(rpm):
    """F0Md/F1Md=1(수동) + F0Tg/F1Tg=rpm. smc 바이너리가 setuid root라 비번 불필요."""
    if not SMC:
        return False
    raw = struct.pack('<f', float(rpm)).hex()
    for key_md, key_tg in [('F0Md', 'F0Tg'), ('F1Md', 'F1Tg')]:
        shell(f'"{SMC}" -k {key_md} -w 01')
        shell(f'"{SMC}" -k {key_tg} -w {raw}')
    return True

def reset_fan_to_auto():
    """F0Md/F1Md=0 으로 자동 모드 복구. 비번 불필요."""
    if not SMC:
        return False
    shell(f'"{SMC}" -k F0Md -w 00')
    shell(f'"{SMC}" -k F1Md -w 00')
    return True

# ── 상태 레이블 ──────────────────────────────────────────────────────────────

def temp_label(temp):
    if temp is None:
        return 'N/A', DIM
    if temp < 60:
        return f'{temp:.1f}°C   안정', GREEN
    if temp < 75:
        return f'{temp:.1f}°C   적정', YELLOW
    if temp < 85:
        return f'{temp:.1f}°C   주의', PEACH
    return f'{temp:.1f}°C   위험', RED

def fan_label(rpm):
    if not rpm:
        return 'N/A', DIM
    if rpm < 2000:
        return f'{rpm:,} rpm   최소', BLUE
    if rpm < 4000:
        return f'{rpm:,} rpm   기본', GREEN
    return f'{rpm:,} rpm   고속', RED

# ── 업데이트 ─────────────────────────────────────────────────────────────────

def _parse_version(v):
    try:
        return tuple(int(x) for x in v.lstrip('v').split('.'))
    except Exception:
        return (0,)

def fetch_release_info():
    """(version_str, dmg_url) 반환. 실패 시 (None, None)."""
    try:
        req = urllib.request.Request(GITHUB_API,
              headers={'User-Agent': f'MacFanControl/{VERSION}'})
        with urllib.request.urlopen(req, timeout=6) as resp:
            data = json.loads(resp.read())
        tag = data.get('tag_name', '').lstrip('v')
        url = next((a['browser_download_url'] for a in data.get('assets', [])
                    if a['name'].endswith('.dmg')), None)
        return tag, url
    except Exception:
        return None, None

def get_app_path():
    """PyInstaller로 실행 중이면 .app 경로, 소스 실행이면 None."""
    if getattr(sys, 'frozen', False):
        exe = os.path.abspath(sys.executable)
        # .app/Contents/MacOS/MacFanControl → 3단계 위
        p = os.path.dirname(os.path.dirname(os.path.dirname(exe)))
        if p.endswith('.app'):
            return p
    return None

def do_auto_update(dmg_url, app_path, progress_cb=None):
    """DMG 다운로드 → 마운트 → .app 교체 → 재시작 스크립트 실행."""
    tmp = tempfile.mktemp(suffix='.dmg', prefix='MacFanControl_upd_')

    def hook(count, block, total):
        if progress_cb and total > 0:
            progress_cb(min(98, int(count * block * 100 / total)))
    urllib.request.urlretrieve(dmg_url, tmp, hook)
    if progress_cb:
        progress_cb(100)

    # DMG 마운트
    r = subprocess.run(['hdiutil', 'attach', '-nobrowse', tmp],
                       capture_output=True, text=True)
    mount = None
    for line in r.stdout.strip().splitlines():
        parts = line.split('\t')
        if parts and '/Volumes/' in parts[-1]:
            mount = parts[-1].strip()
            break
    if not mount:
        os.unlink(tmp)
        return False

    install_dir = os.path.dirname(app_path)
    script = f'''#!/bin/bash
sleep 0.8
cp -Rf "{mount}/MacFanControl.app" "{install_dir}/"
hdiutil detach "{mount}" -quiet 2>/dev/null || true
rm -f "{tmp}"
open "{app_path}"
'''
    sp = '/tmp/fan_control_update.sh'
    with open(sp, 'w') as f:
        f.write(script)
    os.chmod(sp, 0o755)
    subprocess.Popen(['/bin/bash', sp],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return True

# ── 색상 ─────────────────────────────────────────────────────────────────────

BG      = '#1e1e2e'
SURFACE = '#313244'
BORDER  = '#45475a'
TEXT    = '#cdd6f4'
SUBTEXT = '#a6adc8'
DIM     = '#585b70'
BLUE    = '#89b4fa'
GREEN   = '#a6e3a1'
YELLOW  = '#f9e2af'
PEACH   = '#fab387'
RED     = '#f38ba8'

# ── FlatBtn: macOS 네이티브 Button 렌더링을 우회하는 커스텀 버튼 ─────────────

class FlatBtn(tk.Frame):
    """Frame+Label 기반 완전 커스텀 버튼. macOS에서 fg 색상이 정확히 표시됨."""

    def __init__(self, parent, text, bg, fg, command,
                 font=('Helvetica Neue', 12, 'bold'),
                 padx=12, pady=10,
                 hover_bg=None, hover_fg=None,
                 state='normal'):
        super().__init__(parent, bg=bg)
        self._bg  = bg;  self._fg  = fg
        self._hbg = hover_bg or bg
        self._hfg = hover_fg or fg
        self._cmd = command
        self._on  = (state == 'normal')
        self._lbl = tk.Label(self, text=text, bg=bg, fg=fg, font=font,
                              padx=padx, pady=pady, cursor='hand2' if self._on else '')
        self._lbl.pack(fill='both', expand=True)
        for w in (self, self._lbl):
            w.bind('<Button-1>', self._click)
            w.bind('<Enter>',    self._enter)
            w.bind('<Leave>',    self._leave)

    # ── 이벤트 핸들러 ────────────────────────────────────────────────────────
    def _click(self, e=None):
        if self._on and self._cmd: self._cmd()
    def _enter(self, e=None):
        if self._on:
            super().configure(bg=self._hbg)
            self._lbl.configure(bg=self._hbg, fg=self._hfg)
    def _leave(self, e=None):
        super().configure(bg=self._bg)
        self._lbl.configure(bg=self._bg, fg=self._fg)

    # ── 외부 API ─────────────────────────────────────────────────────────────
    def set_colors(self, bg=None, fg=None, hover_bg=None, hover_fg=None):
        if bg  is not None: self._bg  = bg
        if fg  is not None: self._fg  = fg
        if hover_bg is not None: self._hbg = hover_bg
        if hover_fg is not None: self._hfg = hover_fg
        super().configure(bg=self._bg)
        self._lbl.configure(bg=self._bg, fg=self._fg)

    def configure(self, **kw):
        if 'text' in kw: self._lbl.configure(text=kw.pop('text'))
        if 'state' in kw:
            self._on = (kw.pop('state') == 'normal')
            cur = 'hand2' if self._on else ''
            self.config(cursor=cur); self._lbl.configure(cursor=cur)
        if 'bg' in kw: self._bg = kw['bg']
        if 'fg' in kw: self._fg = kw['fg']
        if kw: super().configure(**kw)
        super().configure(bg=self._bg)
        self._lbl.configure(bg=self._bg, fg=self._fg)

    config = configure

# ── macOS 메뉴바 델리게이트 ──────────────────────────────────────────────────

if _APPKIT:
    class _MenuBarDelegate(NSObject):
        _show_cb        = None
        _quit_cb        = None
        _toggle_temp_cb = None
        _toggle_fan_cb  = None

        @objc.python_method
        def set_callbacks(self, show_cb, quit_cb, toggle_temp_cb, toggle_fan_cb):
            self._show_cb        = show_cb
            self._quit_cb        = quit_cb
            self._toggle_temp_cb = toggle_temp_cb
            self._toggle_fan_cb  = toggle_fan_cb

        def showApp_(self, sender):
            if self._show_cb: self._show_cb()

        def quitApp_(self, sender):
            if self._quit_cb: self._quit_cb()

        def toggleTemp_(self, sender):
            new = 1 - sender.state()
            sender.setState_(new)
            if self._toggle_temp_cb: self._toggle_temp_cb(bool(new))

        def toggleFan_(self, sender):
            new = 1 - sender.state()
            sender.setState_(new)
            if self._toggle_fan_cb: self._toggle_fan_cb(bool(new))
else:
    _MenuBarDelegate = None

# ── GUI ──────────────────────────────────────────────────────────────────────

class FanApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title('맥북 팬 관리')
        self.resizable(True, True)
        self.configure(bg=BG)
        self._mode           = get_power_mode()
        self._settings       = load_settings()
        self._mb_item        = None   # NSStatusItem
        self._mb_show_win_mi = None
        self._window_visible = True
        # 앱 시작 시 현재 팬 RPM 읽어서 슬라이더 초기값으로 사용
        _fan_now = _smc_read_decimal('F0Ac')
        self._init_fan_rpm = max(1200, min(6000, int(_fan_now))) if _fan_now and _fan_now > 0 else 2500
        self._build()
        self._refresh()
        self._refresh_battery()
        threading.Thread(target=self._refresh_battery_full, daemon=True).start()
        self._schedule_refresh()
        threading.Thread(target=self._auto_check_update, daemon=True).start()
        if _APPKIT:
            self.after(200, self._setup_menubar)
        # 창 닫기 → 숨기기 (메뉴바 앱으로 계속 실행)
        self.protocol('WM_DELETE_WINDOW', self._hide_window)

    # ── 레이아웃 ─────────────────────────────────────────────────────────────

    def _build(self):
        self.geometry('860x560')
        self.minsize(720, 480)

        # ── ttk 다크 스타일 ───────────────────────────────────────────────────
        style = ttk.Style(self)
        style.theme_use('default')
        style.configure('Dark.TNotebook', background=BG, borderwidth=0, tabmargins=[0, 0, 0, 0])
        style.configure('Dark.TNotebook.Tab', background=SURFACE, foreground=TEXT,
                        padding=[20, 8], font=('Helvetica Neue', 12), borderwidth=0, focuscolor=BG)
        style.map('Dark.TNotebook.Tab',
                  background=[('selected', '#2a2a3e'), ('active', BORDER)],
                  foreground=[('selected', BLUE), ('active', TEXT)])

        # ── 타이틀 헤더 ───────────────────────────────────────────────────────
        hdr = tk.Frame(self, bg='#16161e', padx=18, pady=10)
        hdr.pack(fill='x')
        tk.Label(hdr, text='🖥  맥북 팬 · 전원 관리', bg='#16161e', fg=TEXT,
                 font=('Helvetica Neue', 15, 'bold')).pack(side='left')
        tk.Label(hdr, text=f'v{VERSION}', bg='#16161e', fg=BORDER,
                 font=('Helvetica Neue', 10)).pack(side='left', padx=(8, 0))
        self._update_btn = tk.Button(hdr, text='업데이트 확인', bg='#16161e', fg=SUBTEXT,
                                     font=('Helvetica Neue', 10), bd=0, relief='flat',
                                     cursor='hand2', activebackground='#16161e',
                                     activeforeground=BLUE,
                                     command=self._check_update_manual)
        self._update_btn.pack(side='right')

        # ── 상태 스트립 (항상 표시) ───────────────────────────────────────────
        strip = tk.Frame(self, bg=SURFACE, padx=18, pady=6)
        strip.pack(fill='x')
        self._strip_labels = {}
        for i, (key, icon) in enumerate([('cpu', 'CPU'), ('gpu', 'GPU'),
                                          ('bat_t', '배터리'), ('fan', '팬'), ('mode', '모드')]):
            if i > 0:
                tk.Label(strip, text='│', bg=SURFACE, fg=BORDER,
                         font=('Helvetica Neue', 11)).pack(side='left', padx=8)
            tk.Label(strip, text=f'{icon}  ', bg=SURFACE, fg=SUBTEXT,
                     font=('Helvetica Neue', 10)).pack(side='left')
            lbl = tk.Label(strip, text='—', bg=SURFACE, fg=TEXT,
                           font=('Helvetica Neue', 10, 'bold'))
            lbl.pack(side='left')
            self._strip_labels[key] = lbl

        # ── Notebook ──────────────────────────────────────────────────────────
        nb = ttk.Notebook(self, style='Dark.TNotebook')
        nb.pack(fill='both', expand=True, pady=(1, 0))

        # ── Tab 1: 대시보드 ───────────────────────────────────────────────────
        t1 = tk.Frame(nb, bg=BG)
        nb.add(t1, text='  📊 대시보드  ')

        temp_row = tk.Frame(t1, bg=BG)
        temp_row.pack(fill='x', padx=16, pady=(16, 8))
        for i in range(3):
            temp_row.columnconfigure(i, weight=1, uniform='tc')

        def _temp_card(title, col, accent):
            card = tk.Frame(temp_row, bg=SURFACE, padx=16, pady=14)
            card.grid(row=0, column=col, sticky='nsew', padx=(0 if col == 0 else 6, 0))
            tk.Label(card, text=title, bg=SURFACE, fg=accent,
                     font=('Helvetica Neue', 10, 'bold')).pack(anchor='w')
            lbl = tk.Label(card, text='—', bg=SURFACE, fg=TEXT,
                           font=('Helvetica Neue', 22, 'bold'))
            lbl.pack(anchor='w', pady=(6, 0))
            return lbl

        self._temp_lbl = _temp_card('CPU 온도', 0, PEACH)
        self._gpu_lbl  = _temp_card('GPU 온도', 1, BLUE)
        self._bat_lbl  = _temp_card('배터리 온도', 2, GREEN)

        info_row = tk.Frame(t1, bg=BG)
        info_row.pack(fill='x', padx=16, pady=(0, 8))
        info_row.columnconfigure(0, weight=1)
        info_row.columnconfigure(1, weight=1)

        # 팬 상태 카드
        fan_card = tk.Frame(info_row, bg=SURFACE, padx=16, pady=14)
        fan_card.grid(row=0, column=0, sticky='nsew', padx=(0, 6))
        tk.Label(fan_card, text='팬 상태', bg=SURFACE, fg=SUBTEXT,
                 font=('Helvetica Neue', 10, 'bold')).pack(anchor='w', pady=(0, 8))
        for key, attr in [('현재 속도', '_fan_lbl'), ('속도 범위', '_fan_rng_lbl'), ('제어 모드', '_fan_mode_lbl')]:
            r = tk.Frame(fan_card, bg=SURFACE)
            r.pack(fill='x', pady=2)
            tk.Label(r, text=key, bg=SURFACE, fg=SUBTEXT,
                     font=('Helvetica Neue', 10), width=8, anchor='w').pack(side='left')
            lbl = tk.Label(r, text='—', bg=SURFACE, fg=TEXT,
                           font=('Helvetica Neue', 12, 'bold'), anchor='w')
            lbl.pack(side='left', fill='x', padx=(6, 0))
            setattr(self, attr, lbl)

        # 전원 모드 카드
        mode_card = tk.Frame(info_row, bg=SURFACE, padx=16, pady=14)
        mode_card.grid(row=0, column=1, sticky='nsew')
        tk.Label(mode_card, text='전원 모드', bg=SURFACE, fg=SUBTEXT,
                 font=('Helvetica Neue', 10, 'bold')).pack(anchor='w')
        self._mode_lbl = tk.Label(mode_card, text='—', bg=SURFACE, fg=GREEN,
                                   font=('Helvetica Neue', 18, 'bold'))
        self._mode_lbl.pack(anchor='w', pady=(6, 12))
        mode_btn_row = tk.Frame(mode_card, bg=SURFACE)
        mode_btn_row.pack(fill='x')
        self._btn_low    = self._mode_btn(mode_btn_row, '🌙 절전', BLUE, 'low')
        self._btn_normal = self._mode_btn(mode_btn_row, '⚡ 기본', GREEN, 'normal')
        self._btn_low.pack(side='left', expand=True, fill='x', padx=(0, 4))
        self._btn_normal.pack(side='left', expand=True, fill='x')

        self._hint_lbl = tk.Label(t1, bg=BG, fg=SUBTEXT,
                                   font=('Helvetica Neue', 10), wraplength=800)
        self._hint_lbl.pack(anchor='w', padx=16, pady=(4, 2))
        tk.Label(t1, text='* 전원 모드 변경 시 시스템 암호가 필요합니다.',
                 bg=BG, fg=DIM, font=('Helvetica Neue', 9)).pack(anchor='w', padx=16)
        self._update_mode_ui()

        # ── Tab 2: 팬 제어 ────────────────────────────────────────────────────
        t2 = tk.Frame(nb, bg=BG)
        nb.add(t2, text='  🌀 팬 제어  ')

        tk.Label(t2, text='팬 속도 프리셋', bg=BG, fg=SUBTEXT,
                 font=('Helvetica Neue', 10, 'bold')).pack(anchor='w', padx=16, pady=(18, 8))

        s_fan = 'normal' if SMC else 'disabled'
        preset_row = tk.Frame(t2, bg=BG)
        preset_row.pack(fill='x', padx=16, pady=(0, 10))
        self._preset_btns = []
        for label, rpm, accent in [('🔇 저속', 1200, BLUE),
                                    ('🔁 일반', 2500, GREEN),
                                    ('🚀 고성능', 4500, RED)]:
            b = FlatBtn(
                preset_row,
                text=f'{label}\n{rpm:,} rpm',
                bg=SURFACE, fg='#ffffff',
                font=('Helvetica Neue', 13, 'bold'),
                padx=0, pady=18,
                hover_bg=accent, hover_fg='#1e1e2e',
                state=s_fan,
                command=lambda r=rpm: self._apply_preset(r)
            )
            b.pack(side='left', expand=True, fill='x', padx=4)
            self._preset_btns.append(b)

        self._btn_fan_auto = FlatBtn(
            t2, text='🔄  자동 모드로 복구  (macOS 기본)',
            bg=SURFACE, fg='#ffffff',
            font=('Helvetica Neue', 12),
            padx=0, pady=10,
            hover_bg=BORDER, hover_fg='#ffffff',
            state=s_fan,
            command=self._reset_fan_auto
        )
        self._btn_fan_auto.pack(fill='x', padx=16, pady=(0, 14))

        tk.Frame(t2, bg=BORDER, height=1).pack(fill='x', padx=16)

        sl_hdr = tk.Frame(t2, bg=BG)
        sl_hdr.pack(fill='x', padx=16, pady=(14, 4))
        tk.Label(sl_hdr, text='커스텀 RPM', bg=BG, fg=SUBTEXT,
                 font=('Helvetica Neue', 10, 'bold')).pack(side='left')
        self._slider_val_lbl = tk.Label(sl_hdr, bg=BG, fg=BLUE,
                                         font=('Helvetica Neue', 17, 'bold'))
        self._slider_val_lbl.pack(side='right')

        self._slider_var = tk.IntVar(value=self._init_fan_rpm)
        self._slider = tk.Scale(
            t2, from_=1200, to=6000, resolution=100,
            orient='horizontal', variable=self._slider_var,
            bg=BG, fg=TEXT, troughcolor=SURFACE,
            highlightthickness=0, sliderrelief='flat',
            activebackground=BLUE, showvalue=False, state=s_fan,
            command=lambda v: self._slider_val_lbl.config(text=f'{int(v):,} rpm')
        )
        self._slider.pack(fill='x', padx=16, pady=4)
        self._slider_val_lbl.config(text=f'{self._init_fan_rpm:,} rpm')

        self._fan_apply_btn = FlatBtn(
            t2, text='  적용  ',
            bg=BLUE, fg='#1e1e2e',
            font=('Helvetica Neue', 14, 'bold'),
            padx=16, pady=10,
            hover_bg='#5a9af0', hover_fg='#1e1e2e',
            state=s_fan,
            command=self._apply_fan_custom
        )
        self._fan_apply_btn.pack(fill='x', padx=16, pady=(6, 0))

        if not SMC:
            tk.Label(t2, text='⚠  smcFanControl 앱이 설치되어 있어야 팬 제어가 가능합니다.',
                     bg=BG, fg=YELLOW, font=('Helvetica Neue', 10), wraplength=800
                     ).pack(padx=16, pady=(10, 0))

        # ── Tab 3: 배터리 ─────────────────────────────────────────────────────
        t3 = tk.Frame(nb, bg=BG)
        nb.add(t3, text='  🔋 배터리  ')

        bat_grid = tk.Frame(t3, bg=BG)
        bat_grid.pack(fill='x', padx=16, pady=18)
        for i in range(4):
            bat_grid.columnconfigure(i, weight=1, uniform='bg')

        bat_accents = [YELLOW, GREEN, BLUE, PEACH]
        bat_labels = ['충전 횟수', '최대 용량', '잔여 시간', '배터리 상태']
        bat_attrs  = ['_bat_cycle_lbl', '_bat_cap_lbl', '_bat_remain_lbl', '_bat_status_lbl']
        for i, (title, attr, accent) in enumerate(zip(bat_labels, bat_attrs, bat_accents)):
            card = tk.Frame(bat_grid, bg=SURFACE, padx=16, pady=16)
            card.grid(row=0, column=i, sticky='nsew', padx=(0 if i == 0 else 6, 0))
            tk.Label(card, text=title, bg=SURFACE, fg=accent,
                     font=('Helvetica Neue', 10, 'bold')).pack(anchor='w')
            lbl = tk.Label(card, text='—', bg=SURFACE, fg=TEXT,
                           font=('Helvetica Neue', 18, 'bold'))
            lbl.pack(anchor='w', pady=(8, 0))
            setattr(self, attr, lbl)

    # ── 위젯 헬퍼 ────────────────────────────────────────────────────────────

    def _mode_btn(self, parent, text, color, mode):
        return FlatBtn(
            parent, text=text,
            bg=SURFACE, fg='#ffffff',
            font=('Helvetica Neue', 12, 'bold'),
            padx=10, pady=9,
            hover_bg=color, hover_fg='#1e1e2e',
            command=lambda: self._apply_mode(mode)
        )

    # ── macOS 메뉴바 위젯 ──────────────────────────────────────────────────────

    def _setup_menubar(self):
        if not _APPKIT:
            return
        try:
            sb = NSStatusBar.systemStatusBar()
            self._mb_item = sb.statusItemWithLength_(-1)
            self._mb_item.setTitle_('🌡️ —')

            menu = NSMenu.alloc().init()
            menu.setAutoenablesItems_(False)

            # ── 앱 이름 ─────────────────────────────────────────────────────
            hd = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
                f'맥북 팬 관리  v{VERSION}', None, '')
            hd.setEnabled_(False)
            menu.addItem_(hd)
            menu.addItem_(NSMenuItem.separatorItem())

            # ── 실시간 상태 (읽기 전용) ──────────────────────────────────────
            self._mb_cpu_mi = self._mb_info_item(menu, 'CPU  ——')
            self._mb_gpu_mi = self._mb_info_item(menu, 'GPU  ——')
            self._mb_fan_mi = self._mb_info_item(menu, '팬    ——')
            self._mb_bat_mi = self._mb_info_item(menu, '배터리  ——')
            menu.addItem_(NSMenuItem.separatorItem())

            # ── 델리게이트 ───────────────────────────────────────────────────
            delegate = _MenuBarDelegate.alloc().init()
            delegate.set_callbacks(
                lambda: self.after(80, self._toggle_window),
                lambda: self._do_quit(),
                lambda v: self.after(80, self._on_toggle_temp, v),
                lambda v: self.after(80, self._on_toggle_fan,  v),
            )
            self._mb_delegate = delegate

            # ── 앱 열기/숨기기 ───────────────────────────────────────────────
            self._mb_show_win_mi = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
                '앱 숨기기', 'showApp:', '')
            self._mb_show_win_mi.setTarget_(delegate)
            self._mb_show_win_mi.setEnabled_(True)
            menu.addItem_(self._mb_show_win_mi)
            menu.addItem_(NSMenuItem.separatorItem())

            # ── 표시 설정 서브메뉴 ────────────────────────────────────────────
            sub_menu = NSMenu.alloc().init()
            sub_menu.setAutoenablesItems_(False)

            self._mb_temp_toggle = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
                'CPU 온도 표시', 'toggleTemp:', '')
            self._mb_temp_toggle.setTarget_(delegate)
            self._mb_temp_toggle.setEnabled_(True)
            self._mb_temp_toggle.setState_(1 if self._settings['mb_show_temp'] else 0)
            sub_menu.addItem_(self._mb_temp_toggle)

            self._mb_fan_toggle = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
                '팬 속도 표시', 'toggleFan:', '')
            self._mb_fan_toggle.setTarget_(delegate)
            self._mb_fan_toggle.setEnabled_(True)
            self._mb_fan_toggle.setState_(1 if self._settings['mb_show_fan'] else 0)
            sub_menu.addItem_(self._mb_fan_toggle)

            display_mi = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
                '메뉴바 표시 설정', None, '')
            display_mi.setEnabled_(True)
            display_mi.setSubmenu_(sub_menu)
            menu.addItem_(display_mi)
            menu.addItem_(NSMenuItem.separatorItem())

            # ── 종료 ────────────────────────────────────────────────────────
            quit_mi = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
                '종료', 'quitApp:', 'q')
            quit_mi.setTarget_(delegate)
            quit_mi.setEnabled_(True)
            menu.addItem_(quit_mi)

            self._mb_item.setMenu_(menu)
        except Exception as e:
            print(f'menubar setup error: {e}')

    def _mb_info_item(self, menu, text):
        mi = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(text, None, '')
        mi.setEnabled_(False)
        menu.addItem_(mi)
        return mi

    def _toggle_window(self):
        try:
            if self._window_visible:
                self.withdraw()
                self._window_visible = False
                if self._mb_show_win_mi:
                    self._mb_show_win_mi.setTitle_('앱 열기')
            else:
                self.deiconify()
                self.lift()
                self.focus_force()
                self._window_visible = True
                if self._mb_show_win_mi:
                    self._mb_show_win_mi.setTitle_('앱 숨기기')
        except Exception:
            pass

    def _hide_window(self):
        try:
            self.withdraw()
            self._window_visible = False
            if self._mb_show_win_mi:
                self._mb_show_win_mi.setTitle_('앱 열기')
        except Exception:
            pass

    def _bring_to_front(self):
        try:
            self.deiconify()
            self.lift()
            self.focus_force()
            self._window_visible = True
        except Exception:
            pass

    def _do_quit(self):
        """메뉴바 콜백에서 직접 호출 — os._exit으로 클린 종료."""
        try:
            if _APPKIT and self._mb_item:
                NSStatusBar.systemStatusBar().removeStatusItem_(self._mb_item)
        except Exception:
            pass
        os._exit(0)

    def _quit_app(self):
        self._do_quit()

    def _on_toggle_temp(self, val: bool):
        self._settings['mb_show_temp'] = val
        save_settings(self._settings)

    def _on_toggle_fan(self, val: bool):
        self._settings['mb_show_fan'] = val
        save_settings(self._settings)

    # ── 상태 업데이트 ─────────────────────────────────────────────────────────

    def _update_mode_ui(self):
        hints = {
            'low':    '🌙 절전 모드 활성 — CPU 성능 제한, 발열·팬소음 감소',
            'normal': '⚡ 기본 모드 활성 — macOS 기본 전원 관리',
        }
        is_low = self._mode == 'low'
        self._btn_low.set_colors(
            bg=BLUE if is_low else SURFACE,
            fg='#1e1e2e' if is_low else '#ffffff',
            hover_bg=BLUE, hover_fg='#1e1e2e')
        self._btn_normal.set_colors(
            bg=GREEN if not is_low else SURFACE,
            fg='#1e1e2e' if not is_low else '#ffffff',
            hover_bg=GREEN, hover_fg='#1e1e2e')
        mode_txt = '🌙 절전' if is_low else '⚡ 기본'
        self._mode_lbl.config(text=mode_txt,
                               fg=BLUE if is_low else GREEN)
        self._hint_lbl.config(text=hints.get(self._mode, ''))
        self._strip_labels['mode'].config(text=mode_txt,
                                          fg=BLUE if is_low else GREEN)

    def _refresh(self):
        cpu_temp, gpu_temp, battery_temp, fan_rpm, fan_min, fan_max, fan_manual = get_thermal()

        cpu_txt, cpu_col = temp_label(cpu_temp)
        self._temp_lbl.config(text=cpu_txt, fg=cpu_col)
        self._strip_labels['cpu'].config(text=cpu_txt, fg=cpu_col)

        gpu_txt, gpu_col = temp_label(gpu_temp)
        self._gpu_lbl.config(text=gpu_txt, fg=gpu_col)
        self._strip_labels['gpu'].config(text=gpu_txt, fg=gpu_col)

        bat_txt, bat_col = temp_label(battery_temp)
        self._bat_lbl.config(text=bat_txt, fg=bat_col)
        self._strip_labels['bat_t'].config(text=bat_txt, fg=bat_col)

        fan_txt, fan_col = fan_label(fan_rpm)
        self._fan_lbl.config(text=fan_txt, fg=fan_col)
        self._strip_labels['fan'].config(text=fan_txt, fg=fan_col)

        if fan_min is not None and fan_max is not None:
            self._fan_rng_lbl.config(text=f'{fan_min:,} ~ {fan_max:,} rpm', fg=SUBTEXT)
        else:
            self._fan_rng_lbl.config(text='N/A', fg=DIM)

        # 팬 모드 표시
        mode_txt = '🔧 수동' if fan_manual else '🔄 자동'
        mode_col = YELLOW if fan_manual else GREEN
        self._fan_mode_lbl.config(text=mode_txt, fg=mode_col)
        self._btn_fan_auto.set_colors(
            bg=BLUE if fan_manual else SURFACE,
            fg='#1e1e2e' if fan_manual else '#ffffff')

        # 메뉴바 위젯 업데이트
        if self._mb_item:
            cpu_short = cpu_txt.split()[0] if cpu_temp else '—'
            fan_short = fan_txt.split()[0] if fan_rpm else '—'
            show_t = self._settings.get('mb_show_temp', True)
            show_f = self._settings.get('mb_show_fan',  True)
            parts = []
            if show_t: parts.append(f'🌡️{cpu_short}')
            if show_f: parts.append(f'🌀{fan_short}')
            self._mb_item.setTitle_('  '.join(parts) if parts else '🖥️')
            self._mb_cpu_mi.setTitle_(f'CPU      {cpu_txt}')
            self._mb_gpu_mi.setTitle_(f'GPU      {gpu_txt}')
            self._mb_fan_mi.setTitle_(f'팬        {fan_txt}')
            bat_t_short = bat_txt.split()[0] if battery_temp else '—'
            self._mb_bat_mi.setTitle_(f'배터리   {bat_t_short}')

    def _setup_power_source_watcher(self):
        """IOPSNotificationCreateRunLoopSource: 충전 상태 변경 즉시 감지. 폴링 없음."""
        try:
            import ctypes
            _IOKit = ctypes.cdll.LoadLibrary(
                '/System/Library/Frameworks/IOKit.framework/IOKit')
            _CF = ctypes.cdll.LoadLibrary(
                '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')

            _CF.CFRunLoopGetCurrent.restype = ctypes.c_void_p
            _CF.CFRunLoopAddSource.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
            _CF.CFRunLoopRun.argtypes = []
            _IOKit.IOPSNotificationCreateRunLoopSource.restype = ctypes.c_void_p

            kCFRunLoopDefaultMode = ctypes.c_void_p.in_dll(_CF, 'kCFRunLoopDefaultMode')

            CALLBACK = ctypes.CFUNCTYPE(None, ctypes.c_void_p)

            def _on_power_change(info):
                self.after(0, self._refresh_battery)

            cb = CALLBACK(_on_power_change)
            self._ps_callback_ref = cb  # GC 방지

            source = _IOKit.IOPSNotificationCreateRunLoopSource(cb, None)

            def run_loop():
                loop = _CF.CFRunLoopGetCurrent()
                _CF.CFRunLoopAddSource(loop, ctypes.c_void_p(source), kCFRunLoopDefaultMode)
                _CF.CFRunLoopRun()

            threading.Thread(target=run_loop, daemon=True).start()
            return True
        except Exception as e:
            print(f'power watcher setup error: {e}')
            return False

    def _schedule_refresh(self):
        # 온도/팬: 5초마다 (SMC는 이벤트 API 없어 폴링 불가피)
        def thermal_loop():
            while True:
                time.sleep(5)
                self.after(0, self._refresh)
        threading.Thread(target=thermal_loop, daemon=True).start()

        # 충전 상태: IOKit 이벤트 기반 (USB 꽂는 즉시, 유휴 CPU 0)
        if not self._setup_power_source_watcher():
            # IOKit 실패 시 3초 폴링으로 폴백
            def battery_loop():
                while True:
                    time.sleep(3)
                    self.after(0, self._refresh_battery)
            threading.Thread(target=battery_loop, daemon=True).start()

        # 배터리 상세 정보: 60초마다 (충전 횟수·용량·상태는 자주 안 바뀜)
        def battery_full_loop():
            while True:
                time.sleep(60)
                self._refresh_battery_full()
        threading.Thread(target=battery_full_loop, daemon=True).start()

    # ── 전원 모드 액션 ───────────────────────────────────────────────────────

    def _apply_mode(self, mode):
        self._btn_low.config(state='disabled')
        self._btn_normal.config(state='disabled')
        def worker():
            ok = admin(f'pmset lowpowermode {"1" if mode=="low" else "0"}')
            self.after(0, self._on_mode_done, ok, mode)
        threading.Thread(target=worker, daemon=True).start()

    def _on_mode_done(self, ok, mode):
        self._btn_low.config(state='normal')
        self._btn_normal.config(state='normal')
        if ok:
            self._mode = mode
            self._update_mode_ui()
        else:
            messagebox.showerror('실패', '전원 모드 변경 실패 (암호 취소 또는 오류)')

    # ── 팬 액션 ──────────────────────────────────────────────────────────────

    def _apply_preset(self, rpm):
        # 슬라이더를 선택된 프리셋 RPM에 맞춤
        clamped = max(1200, min(6000, rpm))
        self._slider_var.set(clamped)
        self._slider_val_lbl.config(text=f'{clamped:,} rpm')
        self._set_fan_busy(True)
        def worker():
            ok = set_fan_speed(rpm)
            self.after(0, self._on_fan_set_done, ok, rpm)
        threading.Thread(target=worker, daemon=True).start()

    def _apply_fan_custom(self):
        rpm = self._slider_var.get()
        self._fan_apply_btn.config(state='disabled', text='적용 중…')
        def worker():
            ok = set_fan_speed(rpm)
            self.after(0, self._on_fan_set_done, ok, rpm)
            self.after(0, lambda: self._fan_apply_btn.config(state='normal', text='  적용  '))
        threading.Thread(target=worker, daemon=True).start()

    def _reset_fan_auto(self):
        self._btn_fan_auto.config(state='disabled', text='복구 중…')
        def worker():
            ok = reset_fan_to_auto()
            self.after(0, self._on_fan_auto_done, ok)
        threading.Thread(target=worker, daemon=True).start()

    def _on_fan_set_done(self, ok, rpm):
        self._set_fan_busy(False)
        if ok:
            self.after(1500, self._refresh)
        else:
            messagebox.showerror('실패', f'팬 설정 실패\nsmc 경로: {SMC or "없음"}')

    def _on_fan_auto_done(self, ok):
        self._btn_fan_auto.config(state='normal', text='🔄  자동 모드로 복구  (macOS 기본)')
        if ok:
            self.after(1500, self._refresh)
        else:
            messagebox.showerror('실패', '자동 복구 실패')

    def _set_fan_busy(self, busy):
        state = 'disabled' if busy else ('normal' if SMC else 'disabled')
        for b in self._preset_btns:
            b.config(state=state)

    def _refresh_battery(self):
        """충전 상태만 빠르게 갱신 (3초 주기). 무거운 정보는 30초마다."""
        out, _ = shell('pmset -g batt 2>/dev/null')
        m_status = re.search(r'\d+%;\s*([\w ]+?)\s*;', out)
        status_word = m_status.group(1).lower() if m_status else ''
        charging = status_word == 'charging'

        m_remain = re.search(r'(\d+:\d+)\s+remaining', out)
        remain = m_remain.group(1) if m_remain else None

        if remain:
            self._bat_remain_lbl.config(
                text=f'{remain}  {"⚡ 충전 중" if charging else "🔋 방전 중"}',
                fg=BLUE if charging else GREEN)
        else:
            charged = 'charged' in out.lower()
            if charged:
                self._bat_remain_lbl.config(text='⚡ 완충', fg=GREEN)
            elif charging:
                self._bat_remain_lbl.config(text='⚡ 충전 중', fg=BLUE)
            else:
                self._bat_remain_lbl.config(text='🔋 방전 중', fg=SUBTEXT)

    def _refresh_battery_full(self):
        """충전 횟수·용량·상태 갱신 (느림, 30초 주기)."""
        cycle, capacity, condition, _, _ = get_battery_info()
        self._bat_cycle_lbl.config(
            text=f'{cycle:,} 회' if cycle else 'N/A',
            fg=RED if cycle and cycle > 800 else YELLOW if cycle and cycle > 500 else GREEN if cycle else DIM)
        self._bat_cap_lbl.config(
            text=f'{capacity} %' if capacity else 'N/A',
            fg=RED if capacity and capacity < 60 else YELLOW if capacity and capacity < 80 else GREEN if capacity else DIM)
        cond_map = {
            'Normal': '정상', 'Good': '양호', 'Fair': '보통',
            'Poor': '나쁨', 'Replace Soon': '교체 권장',
            'Replace Now': '교체 필요', 'Service Recommended': '점검 권장',
        }
        cond_txt = cond_map.get(condition, condition) if condition else 'N/A'
        bad  = ('Replace Now', 'Replace Soon')
        warn = ('Poor', 'Fair', 'Service Recommended')
        cond_col = RED if condition in bad else YELLOW if condition in warn else GREEN if condition else DIM
        self._bat_status_lbl.config(text=cond_txt, fg=cond_col)

    # ── 업데이트 ─────────────────────────────────────────────────────────────

    def _auto_check_update(self):
        time.sleep(3)
        latest, url = fetch_release_info()
        if latest and _parse_version(latest) > _parse_version(VERSION):
            self.after(0, self._show_update_banner, latest, url)

    def _check_update_manual(self):
        self._update_btn.config(text='확인 중…', state='disabled')
        def worker():
            latest, url = fetch_release_info()
            self.after(0, self._on_manual_check, latest, url)
        threading.Thread(target=worker, daemon=True).start()

    def _on_manual_check(self, latest, url):
        self._update_btn.config(text='업데이트 확인', state='normal')
        if latest is None:
            messagebox.showinfo('업데이트 확인', '네트워크 오류 또는 확인 실패')
        elif _parse_version(latest) > _parse_version(VERSION):
            self._show_update_dialog(latest, url)
        else:
            messagebox.showinfo('업데이트 확인', f'최신 버전입니다 (v{VERSION})')

    def _show_update_banner(self, latest, url):
        banner = tk.Frame(self, bg=BLUE, cursor='hand2')
        banner.place(relx=0, rely=0, relwidth=1)
        tk.Label(banner, text=f'  🎉 새 버전 v{latest} 출시 — 클릭해서 업데이트',
                 bg=BLUE, fg=BG, font=('Helvetica Neue', 11, 'bold'),
                 anchor='w').pack(side='left', pady=6, padx=8)
        close = tk.Label(banner, text='✕', bg=BLUE, fg=BG,
                         font=('Helvetica Neue', 12, 'bold'), cursor='hand2')
        close.pack(side='right', padx=8)
        close.bind('<Button-1>', lambda e: (banner.destroy(), 'break'))
        banner.bind('<Button-1>', lambda e: self._show_update_dialog(latest, url))
        for w in banner.winfo_children():
            if w is not close:
                w.bind('<Button-1>', lambda e: self._show_update_dialog(latest, url))

    def _show_update_dialog(self, latest, dmg_url):
        app_path = get_app_path()
        can_auto = bool(app_path and dmg_url)

        win = tk.Toplevel(self)
        win.title('업데이트')
        win.configure(bg=BG)
        win.resizable(False, False)
        win.geometry('320x180')
        win.grab_set()

        tk.Label(win, text=f'🎉 새 버전 v{latest} 출시!',
                 bg=BG, fg=TEXT, font=('Helvetica Neue', 14, 'bold')
                 ).pack(pady=(20, 4))
        tk.Label(win, text=f'현재 v{VERSION}  →  최신 v{latest}',
                 bg=BG, fg=DIM, font=('Helvetica Neue', 11)).pack()

        if not can_auto:
            tk.Label(win, text='소스 실행 모드 — 브라우저로 이동합니다.',
                     bg=BG, fg=DIM, font=('Helvetica Neue', 10)).pack(pady=4)

        btns = tk.Frame(win, bg=BG)
        btns.pack(pady=16)

        update_text = '지금 업데이트' if can_auto else '다운로드'
        def on_update():
            win.destroy()
            if can_auto:
                self._run_auto_update(dmg_url, app_path)
            else:
                webbrowser.open(f'https://github.com/eondcom/mac-fan-control/releases/tag/v{latest}')

        tk.Button(btns, text=update_text,
                  bg=BLUE, fg=BG, font=('Helvetica Neue', 12, 'bold'),
                  bd=0, padx=16, pady=7, relief='flat', cursor='hand2',
                  command=on_update).pack(side='left', padx=(0, 8))
        tk.Button(btns, text='나중에',
                  bg=SURFACE, fg=SUBTEXT, font=('Helvetica Neue', 12),
                  bd=0, padx=16, pady=7, relief='flat', cursor='hand2',
                  command=win.destroy).pack(side='left')

    def _run_auto_update(self, dmg_url, app_path):
        """다운로드 진행창 표시 후 업데이트 실행."""
        win = tk.Toplevel(self)
        win.title('업데이트 중')
        win.configure(bg=BG)
        win.resizable(False, False)
        win.geometry('300x130')
        win.grab_set()
        win.protocol('WM_DELETE_WINDOW', lambda: None)  # 닫기 차단

        tk.Label(win, text='업데이트 다운로드 중…',
                 bg=BG, fg=TEXT, font=('Helvetica Neue', 13, 'bold')
                 ).pack(pady=(22, 8))

        bar_bg = tk.Frame(win, bg=SURFACE, height=8)
        bar_bg.pack(fill='x', padx=24)
        bar_fg = tk.Frame(bar_bg, bg=BLUE, height=8)
        bar_fg.place(relwidth=0, relheight=1)

        pct_lbl = tk.Label(win, text='0%', bg=BG, fg=DIM,
                           font=('Helvetica Neue', 10))
        pct_lbl.pack(pady=4)

        def set_progress(pct):
            bar_fg.place(relwidth=pct / 100, relheight=1)
            pct_lbl.config(text=f'{pct}%')
            win.update_idletasks()

        def worker():
            try:
                ok = do_auto_update(dmg_url, app_path,
                                    progress_cb=lambda p: self.after(0, set_progress, p))
                if ok:
                    self.after(0, lambda: (
                        win.destroy(),
                        messagebox.showinfo('업데이트', '업데이트 완료!\n앱을 재시작합니다.'),
                        self.destroy()
                    ))
                else:
                    self.after(0, lambda: (
                        win.destroy(),
                        messagebox.showerror('실패', 'DMG 마운트 실패\n수동으로 다운로드해 주세요.')
                    ))
            except Exception as e:
                self.after(0, lambda: (
                    win.destroy(),
                    messagebox.showerror('실패', f'업데이트 오류:\n{e}')
                ))

        threading.Thread(target=worker, daemon=True).start()


if __name__ == '__main__':
    app = FanApp()
    app.mainloop()
