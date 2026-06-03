#!/usr/bin/env python3
"""맥북 팬 · 전원 관리 — Intel MacBook / macOS Sequoia"""

import tkinter as tk
from tkinter import messagebox
import subprocess, threading, re, time, shutil, os

# ── smc 바이너리 탐색 ────────────────────────────────────────────────────────
# smcFanControl 앱이 설치된 경우 /Applications/smcFanControl.app 안에 있음
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
    """macOS 관리자 암호 다이얼로그로 실행. 성공 여부 반환."""
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

def get_thermal():
    """CPU 온도(°C)와 팬 속도(rpm). 없으면 None."""
    cpu_temp = fan_rpm = None

    # smc 바이너리 우선
    if SMC:
        out, _ = shell(f'"{SMC}" -k TC0P -r 2>/dev/null')
        m = re.search(r'([\d.]+)\s*\(bytes', out)
        if m:
            # SMC raw 값 → °C 변환 (fp2e 포맷)
            try:
                raw = int(m.group(0).split('0x')[1].split(')')[0], 16) if '0x' in out else None
                if raw: cpu_temp = raw / 256.0
            except Exception:
                pass

        out, _ = shell(f'"{SMC}" -k F0Ac -r 2>/dev/null')
        m = re.search(r'([\d.]+)\s*\(bytes', out)
        if m:
            try:
                raw = int(m.group(0).split('0x')[1].split(')')[0], 16) if '0x' in out else None
                if raw: fan_rpm = int(raw / 4)  # fp2e 포맷
            except Exception:
                pass

    # ioreg로 팬 속도 보완
    if fan_rpm is None:
        out, _ = shell('ioreg -r -c AppleSMCFan 2>/dev/null')
        m = re.search(r'"CurrentSpeed"\s*=\s*(\d+)', out)
        if m:
            fan_rpm = int(m.group(1))

    # CPU 온도: IOPMrootDomain (sudo 불필요)
    if cpu_temp is None:
        out, _ = shell('ioreg -r -n "IOPMrootDomain" 2>/dev/null | grep -i temperature')
        m = re.search(r'temperature.*?(\d+)', out, re.IGNORECASE)
        if m:
            val = int(m.group(1))
            cpu_temp = val / 100.0 if val > 1000 else float(val)

    return cpu_temp, fan_rpm

def get_fan_min_rpm():
    if not SMC:
        return None
    out, _ = shell(f'"{SMC}" -k F0Mn -r 2>/dev/null')
    m = re.search(r'0x([0-9a-fA-F]+)', out)
    if m:
        try:
            return int(m.group(1), 16) // 4
        except Exception:
            pass
    return None

def set_fan_min_rpm(rpm):
    if not SMC:
        return False
    raw = rpm * 4
    return admin(f'"{SMC}" -k F0Mn -w {raw:08x}')

def reset_fan():
    """SMC 팬 최소값 초기화 (1200 rpm)"""
    if not SMC:
        return False
    return admin(f'"{SMC}" -k F0Mn -w 00001200')

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
RED     = '#f38ba8'
MAUVE   = '#cba6f7'

MODE_COLOR = {'low': BLUE, 'normal': GREEN}

# ── GUI ──────────────────────────────────────────────────────────────────────

class FanApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title('맥북 팬 관리')
        self.resizable(False, False)
        self.configure(bg=BG)
        self._mode = get_power_mode()
        self._build()
        self._refresh()  # 즉시 한 번
        self._schedule_refresh()

    # ── 레이아웃 ─────────────────────────────────────────────────────────────

    def _build(self):
        W = 380
        self.geometry(f'{W}x560')

        # 제목
        tk.Label(self, text='맥북 팬 · 전원 관리',
                 bg=BG, fg=TEXT, font=('Helvetica Neue', 17, 'bold')
                 ).pack(pady=(20, 2))
        tk.Label(self, text='Intel MacBook · macOS Sequoia',
                 bg=BG, fg=DIM, font=('Helvetica Neue', 11)
                 ).pack(pady=(0, 14))

        # ── 상태 카드 ────────────────────────────────────────────────────────
        card = self._card()
        card.pack(fill='x', padx=18, pady=4)

        self._mode_lbl  = self._stat_row(card, '전원 모드')
        self._temp_lbl  = self._stat_row(card, 'CPU 온도')
        self._fan_lbl   = self._stat_row(card, '팬 속도')

        # ── 전원 모드 ─────────────────────────────────────────────────────────
        self._section('전원 모드').pack(fill='x', padx=18, pady=(12, 4))

        row = tk.Frame(self, bg=BG)
        row.pack(fill='x', padx=18)

        self._btn_low = self._mode_btn(row, '🌙 절전', BLUE,  'low',
                                       '성능 제한 → 발열·팬소음 최소')
        self._btn_low.pack(side='left', expand=True, fill='x', padx=(0, 4))

        self._btn_normal = self._mode_btn(row, '⚡ 기본', GREEN, 'normal',
                                          'macOS 기본값')
        self._btn_normal.pack(side='left', expand=True, fill='x')

        self._hint_lbl = tk.Label(self, bg=BG, fg=DIM,
                                  font=('Helvetica Neue', 10), wraplength=340)
        self._hint_lbl.pack(anchor='w', padx=18, pady=(4, 0))
        self._update_mode_ui()

        # ── 팬 최소 속도 ──────────────────────────────────────────────────────
        sep = tk.Frame(self, bg=BORDER, height=1)
        sep.pack(fill='x', padx=18, pady=12)

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

        # 팬 버튼
        fan_btns = tk.Frame(self, bg=BG)
        fan_btns.pack(fill='x', padx=18, pady=4)

        apply_state = 'normal' if SMC else 'disabled'
        self._fan_apply_btn = tk.Button(
            fan_btns, text='최소 속도 적용',
            bg=BLUE, fg=BG, font=('Helvetica Neue', 12, 'bold'),
            bd=0, padx=12, pady=7, cursor='hand2', relief='flat',
            state=apply_state, command=self._apply_fan_min
        )
        self._fan_apply_btn.pack(side='left', expand=True, fill='x', padx=(0, 4))

        self._fan_reset_btn = tk.Button(
            fan_btns, text='초기화',
            bg=SURFACE, fg=SUBTEXT, font=('Helvetica Neue', 12),
            bd=0, padx=12, pady=7, cursor='hand2', relief='flat',
            state=apply_state, command=self._reset_fan
        )
        self._fan_reset_btn.pack(side='left', expand=True, fill='x')

        if not SMC:
            tk.Label(self,
                     text='⚠  smc 도구 필요 → smcFanControl 앱 설치 후 사용 가능',
                     bg=BG, fg=DIM, font=('Helvetica Neue', 10), wraplength=340
                     ).pack(padx=18, pady=(2, 0))

        # 하단
        tk.Label(self, text='전원 모드 변경 시 시스템 암호가 필요합니다.',
                 bg=BG, fg=DIM, font=('Helvetica Neue', 10)
                 ).pack(pady=(14, 10))

    # ── 위젯 헬퍼 ────────────────────────────────────────────────────────────

    def _card(self):
        f = tk.Frame(self, bg=SURFACE, bd=0, padx=14, pady=10)
        return f

    def _section(self, text, parent=None):
        p = parent or self
        return tk.Label(p, text=text, bg=BG if parent is None else parent['bg'],
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

    def _mode_btn(self, parent, text, color, mode, tip):
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
        colors = {'low': BLUE, 'normal': GREEN}
        c = colors.get(self._mode, TEXT)
        h = hints.get(self._mode, '')

        self._btn_low.config(
            bg=BLUE if self._mode == 'low' else SURFACE,
            fg=BG   if self._mode == 'low' else TEXT
        )
        self._btn_normal.config(
            bg=GREEN if self._mode == 'normal' else SURFACE,
            fg=BG    if self._mode == 'normal' else TEXT
        )
        self._mode_lbl.config(text=('절전 🌙' if self._mode == 'low' else '기본 ⚡'), fg=c)
        self._hint_lbl.config(text=h)

    def _refresh(self):
        cpu_temp, fan_rpm = get_thermal()

        temp_txt = f'{cpu_temp:.1f} °C' if cpu_temp else 'N/A'
        fan_txt  = f'{fan_rpm:,} rpm'   if fan_rpm  else 'N/A'

        temp_color = (RED if cpu_temp and cpu_temp > 85
                      else YELLOW if cpu_temp and cpu_temp > 70
                      else GREEN)
        fan_color  = (RED if fan_rpm and fan_rpm > 5000
                      else YELLOW if fan_rpm and fan_rpm > 3500
                      else GREEN)

        self._temp_lbl.config(text=temp_txt, fg=temp_color)
        self._fan_lbl.config(text=fan_txt,   fg=fan_color)

        # 슬라이더 초기값 = 현재 팬 최소 rpm
        if SMC and fan_rpm:
            min_rpm = get_fan_min_rpm()
            if min_rpm:
                self._slider_var.set(min_rpm)
                self._slider_val_lbl.config(text=f'{min_rpm:,} rpm')

    def _schedule_refresh(self):
        def loop():
            while True:
                time.sleep(5)
                cpu_temp, fan_rpm = get_thermal()
                self.after(0, self._refresh)
        threading.Thread(target=loop, daemon=True).start()

    # ── 액션 ─────────────────────────────────────────────────────────────────

    def _apply_mode(self, mode):
        self._btn_low.config(state='disabled')
        self._btn_normal.config(state='disabled')

        def worker():
            if mode == 'low':
                ok = admin('pmset lowpowermode 1')
            else:
                ok = admin('pmset lowpowermode 0')
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
            messagebox.showerror('실패', f'팬 설정 실패\nsmc 도구 경로: {SMC or "없음"}')

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


if __name__ == '__main__':
    app = FanApp()
    app.mainloop()
