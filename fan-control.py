#!/usr/bin/env python3
"""맥북 팬 · 전원 관리 — Intel MacBook / macOS Sequoia"""

import tkinter as tk
from tkinter import messagebox
import subprocess, threading, re, time, shutil, os, sys, tempfile
import urllib.request, json, webbrowser

VERSION = "1.0.4"
GITHUB_API = "https://api.github.com/repos/eondcom/mac-fan-control/releases/latest"

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
    m = re.search(r'([\d]+\.[\d]+)\s*\(bytes', out)
    if m:
        try:
            return float(m.group(1))
        except Exception:
            pass
    return None

def get_thermal():
    cpu_temp = fan_rpm = None

    # CPU 온도 — 모델마다 키 다름
    for key in ('TC0P', 'TC0D', 'TC0H', 'TCXC', 'Ts0S'):
        val = _smc_read_decimal(key)
        if val and 0 < val < 120:
            cpu_temp = val
            break

    # 팬 속도 — F0Ac 직접 읽기
    fan_val = _smc_read_decimal('F0Ac')
    if fan_val and fan_val > 0:
        fan_rpm = int(fan_val)

    # 팬 속도 폴백 — smc -f (Current speed 라인)
    if fan_rpm is None and SMC:
        out, _ = shell(f'"{SMC}" -f 2>/dev/null')
        m = re.search(r'[Cc]urrent\s+[Ss]peed\s*:\s*(\d+)', out)
        if m:
            fan_rpm = int(m.group(1))

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

    return cpu_temp, fan_rpm

def get_fan_min_rpm():
    if not SMC:
        return None
    val = _smc_read_decimal('F0Mn')
    if val and val > 0:
        return int(val)
    return None

def set_fan_min_rpm(rpm):
    if not SMC:
        return False
    raw = rpm * 4
    return admin(f'"{SMC}" -k F0Mn -w {raw:08x}')

def reset_fan():
    if not SMC:
        return False
    return admin(f'"{SMC}" -k F0Mn -w 000012c0')

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

# ── GUI ──────────────────────────────────────────────────────────────────────

class FanApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title('맥북 팬 관리')
        self.resizable(False, False)
        self.configure(bg=BG)
        self._mode = get_power_mode()
        self._build()
        self._refresh()
        self._schedule_refresh()
        threading.Thread(target=self._auto_check_update, daemon=True).start()

    # ── 레이아웃 ─────────────────────────────────────────────────────────────

    def _build(self):
        self.geometry('380x570')

        # 제목
        tk.Label(self, text='맥북 팬 · 전원 관리',
                 bg=BG, fg=TEXT, font=('Helvetica Neue', 17, 'bold')
                 ).pack(pady=(20, 2))
        sub = tk.Frame(self, bg=BG)
        sub.pack(pady=(0, 14))
        tk.Label(sub, text='Intel MacBook · macOS Sequoia',
                 bg=BG, fg=DIM, font=('Helvetica Neue', 11)).pack(side='left')
        tk.Label(sub, text=f'  v{VERSION}',
                 bg=BG, fg=BORDER, font=('Helvetica Neue', 11)).pack(side='left')

        # 상태 카드
        card = self._card()
        card.pack(fill='x', padx=18, pady=4)
        self._mode_lbl = self._stat_row(card, '전원 모드')
        self._temp_lbl = self._stat_row(card, 'CPU 온도')
        self._fan_lbl  = self._stat_row(card, '팬 속도')

        # 전원 모드
        self._section('전원 모드').pack(fill='x', padx=18, pady=(12, 4))
        row = tk.Frame(self, bg=BG)
        row.pack(fill='x', padx=18)
        self._btn_low = self._mode_btn(row, '🌙 절전', BLUE, 'low')
        self._btn_low.pack(side='left', expand=True, fill='x', padx=(0, 4))
        self._btn_normal = self._mode_btn(row, '⚡ 기본', GREEN, 'normal')
        self._btn_normal.pack(side='left', expand=True, fill='x')
        self._hint_lbl = tk.Label(self, bg=BG, fg=DIM,
                                  font=('Helvetica Neue', 10), wraplength=340)
        self._hint_lbl.pack(anchor='w', padx=18, pady=(4, 0))
        self._update_mode_ui()

        # 팬 최소 속도
        tk.Frame(self, bg=BORDER, height=1).pack(fill='x', padx=18, pady=12)
        fan_hdr = tk.Frame(self, bg=BG)
        fan_hdr.pack(fill='x', padx=18)
        self._section('팬 최소 속도', parent=fan_hdr).pack(side='left')
        self._slider_val_lbl = tk.Label(fan_hdr, bg=BG, fg=BLUE,
                                        font=('Helvetica Neue', 12, 'bold'))
        self._slider_val_lbl.pack(side='right')

        self._slider_var = tk.IntVar(value=1200)
        state = 'normal' if SMC else 'disabled'
        self._slider = tk.Scale(
            self, from_=1200, to=6000, resolution=100,
            orient='horizontal', variable=self._slider_var,
            bg=BG, fg=TEXT, troughcolor=SURFACE,
            highlightthickness=0, sliderrelief='flat',
            activebackground=BLUE, showvalue=False, state=state,
            command=lambda v: self._slider_val_lbl.config(text=f'{int(v):,} rpm')
        )
        self._slider.pack(fill='x', padx=18, pady=4)
        self._slider_val_lbl.config(text=f'{self._slider_var.get():,} rpm')

        fan_btns = tk.Frame(self, bg=BG)
        fan_btns.pack(fill='x', padx=18, pady=4)
        self._fan_apply_btn = tk.Button(
            fan_btns, text='최소 속도 적용',
            bg=BLUE, fg=BG, font=('Helvetica Neue', 12, 'bold'),
            bd=0, padx=12, pady=7, cursor='hand2', relief='flat',
            state=state, command=self._apply_fan_min
        )
        self._fan_apply_btn.pack(side='left', expand=True, fill='x', padx=(0, 4))
        self._fan_reset_btn = tk.Button(
            fan_btns, text='초기화',
            bg=SURFACE, fg=SUBTEXT, font=('Helvetica Neue', 12),
            bd=0, padx=12, pady=7, cursor='hand2', relief='flat',
            state=state, command=self._reset_fan
        )
        self._fan_reset_btn.pack(side='left', expand=True, fill='x')

        if not SMC:
            tk.Label(self, text='⚠  smc 도구 필요 → smcFanControl 앱 설치 후 사용 가능',
                     bg=BG, fg=DIM, font=('Helvetica Neue', 10), wraplength=340
                     ).pack(padx=18, pady=(2, 0))

        # 하단
        bottom = tk.Frame(self, bg=BG)
        bottom.pack(fill='x', padx=18, pady=(14, 10))
        tk.Label(bottom, text='전원 모드 변경 시 시스템 암호가 필요합니다.',
                 bg=BG, fg=DIM, font=('Helvetica Neue', 10)).pack(side='left')
        self._update_btn = tk.Button(
            bottom, text='업데이트 확인',
            bg=BG, fg=DIM, font=('Helvetica Neue', 10),
            bd=0, relief='flat', cursor='hand2',
            command=self._check_update_manual
        )
        self._update_btn.pack(side='right')

    # ── 위젯 헬퍼 ────────────────────────────────────────────────────────────

    def _card(self):
        return tk.Frame(self, bg=SURFACE, bd=0, padx=14, pady=10)

    def _section(self, text, parent=None):
        p = parent or self
        return tk.Label(p, text=text, bg=p['bg'] if parent else BG,
                        fg=SUBTEXT, font=('Helvetica Neue', 10, 'bold'))

    def _stat_row(self, parent, label):
        row = tk.Frame(parent, bg=SURFACE)
        row.pack(fill='x', pady=2)
        tk.Label(row, text=f'{label}:', bg=SURFACE, fg=DIM,
                 font=('Helvetica Neue', 12), width=8, anchor='w').pack(side='left')
        lbl = tk.Label(row, text='—', bg=SURFACE, fg=TEXT,
                       font=('Helvetica Neue', 12, 'bold'), anchor='w')
        lbl.pack(side='left', fill='x')
        return lbl

    def _mode_btn(self, parent, text, color, mode):
        btn = tk.Button(
            parent, text=text, bg=SURFACE, fg=TEXT,
            font=('Helvetica Neue', 12, 'bold'),
            bd=0, padx=12, pady=8, cursor='hand2', relief='flat',
            command=lambda: self._apply_mode(mode)
        )
        btn.bind('<Enter>', lambda e: btn.config(bg=color, fg=BG))
        btn.bind('<Leave>', lambda e: self._update_mode_ui())
        return btn

    # ── 상태 업데이트 ─────────────────────────────────────────────────────────

    def _update_mode_ui(self):
        hints = {
            'low':    '🌙 절전 모드 활성 — CPU 성능 제한, 발열·팬소음 감소',
            'normal': '⚡ 기본 모드 활성 — macOS 기본 전원 관리',
        }
        self._btn_low.config(bg=BLUE if self._mode=='low' else SURFACE,
                             fg=BG   if self._mode=='low' else TEXT)
        self._btn_normal.config(bg=GREEN if self._mode=='normal' else SURFACE,
                                fg=BG    if self._mode=='normal' else TEXT)
        self._mode_lbl.config(
            text='절전 🌙' if self._mode=='low' else '기본 ⚡',
            fg=BLUE if self._mode=='low' else GREEN)
        self._hint_lbl.config(text=hints.get(self._mode, ''))

    def _refresh(self):
        cpu_temp, fan_rpm = get_thermal()

        txt, col = temp_label(cpu_temp)
        self._temp_lbl.config(text=txt, fg=col)

        txt, col = fan_label(fan_rpm)
        self._fan_lbl.config(text=txt, fg=col)

        if SMC:
            min_rpm = get_fan_min_rpm()
            if min_rpm:
                self._slider_var.set(min_rpm)
                self._slider_val_lbl.config(text=f'{min_rpm:,} rpm')

    def _schedule_refresh(self):
        def loop():
            while True:
                time.sleep(5)
                self.after(0, self._refresh)
        threading.Thread(target=loop, daemon=True).start()

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

    def _apply_fan_min(self):
        rpm = self._slider_var.get()
        self._fan_apply_btn.config(state='disabled', text='적용 중…')
        def worker():
            ok = set_fan_min_rpm(rpm)
            self.after(0, self._on_fan_done, ok, rpm)
        threading.Thread(target=worker, daemon=True).start()

    def _on_fan_done(self, ok, rpm):
        self._fan_apply_btn.config(state='normal', text='최소 속도 적용')
        if ok:
            self._slider_val_lbl.config(text=f'{rpm:,} rpm', fg=GREEN)
            self.after(2000, lambda: self._slider_val_lbl.config(fg=BLUE))
        else:
            messagebox.showerror('실패', f'팬 설정 실패\nsmc 경로: {SMC or "없음"}')

    def _reset_fan(self):
        self._fan_reset_btn.config(state='disabled', text='초기화 중…')
        def worker():
            ok = reset_fan()
            self.after(0, self._on_reset_done, ok)
        threading.Thread(target=worker, daemon=True).start()

    def _on_reset_done(self, ok):
        self._fan_reset_btn.config(state='normal', text='초기화')
        if ok:
            self._slider_var.set(1200)
            self._slider_val_lbl.config(text='1,200 rpm', fg=GREEN)
            self.after(2000, lambda: self._slider_val_lbl.config(fg=BLUE))

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
