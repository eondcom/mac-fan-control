# MacFanControl

Intel MacBook용 팬 소음·전원 관리 GUI 앱. macOS Sequoia(15.x) 지원.

![Python](https://img.shields.io/badge/Python-3.12-blue)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

## 기능

| 기능 | 설명 |
|------|------|
| **전원 모드** | 절전 / 기본 전환 (`pmset lowpowermode`) |
| **실시간 온도·팬속도** | CPU 온도(°C), 현재 팬 RPM 표시 |
| **팬 최소 속도 조절** | 슬라이더로 1,200–6,000 rpm 설정 |

## 설치 (배포판)

[Releases](../../releases) 페이지에서 DMG 다운로드 후 설치.

| Mac 종류 | 파일 |
|----------|------|
| Intel Mac | `MacFanControl-intel.dmg` |
| Apple Silicon (M1/M2/M3) | `MacFanControl-arm.dmg` |

> **처음 실행 시**: 우클릭 → **열기** (Apple 미서명 앱 Gatekeeper 우회)

### 팬 속도 조절 요구사항

팬 최소 속도 슬라이더는 [smcFanControl](https://github.com/hholtmann/smcFanControl)의 `smc` 바이너리가 필요합니다.  
smcFanControl 앱을 먼저 설치하면 자동으로 감지합니다. 전원 모드 전환은 별도 설치 없이 동작합니다.

## 소스에서 직접 실행

```bash
python3 fan-control.py
```

Python 3.10+ 필요. 추가 패키지 없음 (표준 라이브러리 tkinter 사용).

## 직접 빌드

```bash
pip install pyinstaller
pyinstaller --windowed --onefile --name MacFanControl fan-control.py
# dist/MacFanControl.app 생성
```

## 라이선스

MIT
