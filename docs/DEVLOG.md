# 개발 기록

맥북 팬 관리(MacFanControl) 개발 세션 기록. 제품 소개는 [README](../README.md). 현재 최신 릴리스는 **v2.2.1**(2026-10-04).

## 구조 (이번에 추가·바뀐 곳)
| 경로 | 내용 |
|---|---|
| `App/System/Displays.swift` | 내장 화면 끄기·절전 복구(`CGDisplayIsAsleep` 구분, 깨어나면 내장 화면을 잠깐 켜서 외장 신호 재연결), ⌃⌥⌘B(Carbon 단축키), 로그 `subsystem com.eond.macfancontrol` |
| `App/System/Performance.swift` | CPU·메모리 측정(`CPULoadMeter`, `host_statistics64`), 화면 볼 때만 2초 측정, 원인 앱 `PRIO_DARWIN_BG` |
| `App/AppState.swift` | 스로틀 전 자동 절전(`guardStep`), 선제 팬(`FanCurve.leadTemp`), 앱 안 업데이트(`installUpdate`) |
| `App/Updater/UpdateInstaller.swift` | DMG 받기 → 번들 ID·버전·CPU 확인 → `.new` 로 복사 후 교체 → 재실행 |
| `Helper/main.swift` | 도우미 v2 — `lowpower <0|1>` 추가 (`setuid(0)` 후 pmset) |
| `App/Resources/ja.lproj` | 일본어 319개 |
| `.github/workflows/build.yml` | 유니버설(`ARCHS="arm64 x86_64"`) 빌드 + `lipo -verify_arch` 검사, 릴리스 노트 |

## 왜 이렇게 했는가
- **모니터 절전 복구**: `CGDisplayIsActive` 는 잠든 화면도 0 을 준다 → 절전 중 외장 모니터를 "꺼짐"으로 보고 내장 화면을 켰다 껐다 했다. 그러나 이걸 고친 뒤에도 PA329CRV 는 깨어난 뒤 macOS 상으론 "켜짐·안 잠듦"인데 실제로는 검은 화면이었다(로그로 확인). ⌃⌥⌘B 로 내장 화면을 켜자 외장도 돌아와서, 깨어날 때 자동으로 내장을 잠깐 켰다 끄는 방식으로 감. **이 마지막 방식은 아직 실제 절전 테스트 안 함.**
- **클럭 상한 직접 제한(MSR·kext)은 버림**: 최신 macOS 에서 kext 승인·보안 낮춤 필요. 저전력 모드(`pmset lowpowermode`)가 인텔에서 터보를 억제하므로 그걸 온도로 자동화.
- **원인 앱 낮추기는 `renice` 대신 `PRIO_DARWIN_BG`**: 일반 사용자는 nice 를 올릴 수만 있고 되돌릴 수 없다. Darwin BG 는 같은 계정이면 켜고 끌 수 있음(테스트: 우선순위 31→4→31).
- **릴리스가 arm64 전용이었다**: GitHub `macos-15` 러너가 Apple Silicon 이라 v2.1.x 와 첫 v2.2.0 DMG 가 인텔 맥에서 "bad CPU type". ARCHS 명시 + 검사 단계 추가.
- **앱 안 업데이트는 v2.2.1 부터**: v2.2.0 이하 버튼은 다운로드 페이지만 연다(그 실행 파일엔 코드가 없음). 2.1.9(새 코드) → 2.2.0 교체·재실행은 사용자 확인.

## 다음 세션에서 할 일
1. 내장 화면 끄고 모니터 절전 복구 실제 테스트 — `pmset displaysleepnow` → 10초 뒤 마우스. 로그:
   ```bash
   /usr/bin/log stream --predicate 'subsystem == "com.eond.macfancontrol"'
   ```
2. 자동 절전 실제 동작 확인(도우미 v2 재설치 후, 부하를 걸어 85°C 30초). 선제 팬 소리가 과한지 사용감 확인.
3. v2.2.1 → 다음 버전 앱 안 업데이트 끝까지 확인(다음 릴리스 때).
4. `feat/secondary-display` 워크트리(`../mac-fan-control-secondary-display`)는 `Displays.swift` 충돌 예상 — main 에 맞춰 리베이스 필요.
5. `docs/screenshots` 는 v2.1.1 기준 — 대시보드 CPU·메모리, 자동 절전 카드로 교체.

## 세션 로그
- **2026-10-02~04**: 모니터 절전 복구 + ⌃⌥⌘B, 대시보드 CPU·메모리, 스로틀 전 자동 절전·선제 팬·원인 앱 낮추기, 앱 안 업데이트, 일본어, 유니버설 빌드 수정. v2.2.0·v2.2.1 릴리스. 홍보 영상(국문·영문·쇼츠)을 유튜브·인스타·스레드·커뮤니티·링크드인에 게시(작업 폴더 `~/Videos/macfancontrol-promo/v3-update/`).

&nbsp;

관련 세션

```
claude --resume a4be99bb-a5b4-4f5f-9547-3513fde28329
```
