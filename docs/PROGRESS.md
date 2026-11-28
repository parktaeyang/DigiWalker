# 1차 MVP 작업 기록

## 2026-11-23 개발 환경

- 지정된 v1.1 설계서와 CLI 지시문을 읽고 기존 iPhone 앱, 임베드된 Watch 앱, DigiWalkerCore 패키지, 워치 HealthKit entitlement를 확인했다.
- 이 작업 머신은 Apple M1 Pro, macOS 26.6.2, Xcode 26.5 (17F42), Swift 6.3.2다. 활성 개발 경로는 `/Applications/Xcode.app/Contents/Developer`다.
- 기존 최소 배포 버전은 iOS 18과 watchOS 11이다. 페어링된 iPhone 17 및 Apple Watch Ultra 3 시뮬레이터에 26.5 런타임이 있다. Xcode 장치 목록에 실제 iPhone 16 Pro Max가 표시됐고 실제 Watch는 표시되지 않았다.
- 작업 전부터 Git에서 삭제 상태였던 `docs/DESIGN.md`는 사용자가 지정한 두 로컬 원본과 별개다.

## 구현

| 항목 | 파일 및 동작 |
| --- | --- |
| 타깃 | 기존 두 앱과 Embed Watch Content 설정을 재사용했다. 두 앱에 로컬 DigiWalkerCore 패키지와 PartnerArt 카탈로그를 연결했다. |
| 도트 | 아구몬 항목의 공개 미리보기·규격·내보내기 접근 조건을 확인했다. 현재 두 앱은 오리지널 도토롱의 32×32 PNG를 사용한다. 워치에서는 원본 순서대로 대기 애니메이션을 재생한다. [에셋 출처](ASSET_SOURCES.md) |
| 워치 | `DigiWalker/DigiWalker Watch App/Services/`의 HealthService, WatchGameStore, WatchSyncService가 건강 조회, 저장, 발행을 담당한다. 화면에 몬스터·레벨·XP·오늘 걸음과 새로고침을 표시한다. |
| 성장 | `Packages/DigiWalkerCore/Sources/DigiWalkerCore/Growth/`에서 등록 시각, 고정 정산 시간대, 일별 원장, 누적 XP, 스냅샷 세대를 관리한다. 등록일의 전체 걸음은 표시하되 등록 이후의 활동만 보상한다. 마지막으로 걸음이 관측된 날의 전날부터 오늘까지 다시 읽어 미실행 기간을 정산한다. 더 오래된 날짜의 사후 수정은 자동 재조회 범위 밖이다. |
| 보존 | 중복 요청은 워치의 단일 MainActor 저장소에서 차단한다. 기록 감소 시 이미 지급한 XP를 유지한다. 몬스터와 원장을 Application Support의 같은 JSON 파일에 원자적으로 쓰고 저장 성공 후 최신 스냅샷을 보낸다. 손상·접근 오류 시 파일을 유지하고 화면에서 오류를 표시한다. |
| iPhone | `DigiWalker/DigiWalker/PhoneSyncService.swift`가 WatchConnectivity의 application context를 받아 최신 스키마·세대·revision을 검사하고 로컬 캐시를 저장한다. `ContentView.swift`는 파트너와 활동 기록, 마지막 수신 시각을 표시한다. |
| 권한 | 워치에서 사용자가 ‘건강 데이터 연결’을 누르면 걸음과 걷기·달리기 거리의 읽기 권한을 요청한다. 읽을 수 있는 걸음이 없을 때에는 별도로 안내한다. 거리에는 XP를 지급하지 않는다. |

## 검증

- `swift test --package-path Packages/DigiWalkerCore`에서 기존 스프라이트 검사와 성장 검사 총 41개가 통과했다. 150→200보 경계, 감소·반복 조회, 날짜 변경, 등록 전 제외, 서머타임을 포함한 미접속 기간, 파일 재로드, 오래된 스냅샷 거부를 검사했다.
- `xcodebuild -project DigiWalker/DigiWalker.xcodeproj -scheme DigiWalker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build` 성공. Watch 앱 임베드까지 검증했다.
- `xcodebuild -project DigiWalker/DigiWalker.xcodeproj -scheme 'DigiWalker Watch App' -configuration Debug -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm),OS=26.5' build` 성공.
- 두 앱을 페어링된 iPhone 17 / Watch Ultra 3 시뮬레이터에 설치·실행했다. 워치 화면에서 픽셀 파트너와 건강 연결 버튼을 확인했다. iPhone 캐시의 몬스터 ID·누적값·revision이 실제 WatchConnectivity로 전달된 워치 초기 상태와 일치했다.
- `xcodebuild ... -scheme 'DigiWalker Watch App' -parallel-testing-enabled NO -only-testing:'DigiWalker Watch AppUITests/DigiWalker_Watch_AppUITests/testPartnerAndHealthEntryPoint' test`에서 화면·연결 버튼 UI 테스트 1개가 통과했다. 시뮬레이터 healthd 로그에서 걸음 및 걷기·달리기 거리 읽기 요청과 권한 프롬프트 이벤트를 확인했다.
- `xcodebuild ... -scheme DigiWalker -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` 성공. 산출물에 Watch 앱과 양쪽 에셋 카탈로그가 포함되며 Release Watch Info.plist에 건강 데이터 읽기 목적 문구와 iPhone 번들 ID가 들어 있다. 빌드 로그에는 AppIntents 의존성이 없어 관련 메타데이터 추출을 생략했다는 Xcode 경고가 있다.
- iPhone을 끈 상태에서 다른 페어의 Watch Series 11 시뮬레이터를 단독 실행했다. 초기 게임 파일을 생성하고 앱 종료·재실행 후 파일 체크섬이 동일함을 확인했다.
- Series 11의 상대 iPhone 17 Pro Max 시뮬레이터는 최초 부팅 시 CoreLocationMigrator에서 지연돼 이 페어의 재수신 검증은 중단했다. iPhone 17 / Watch Ultra 3 페어에서는 iPhone을 끄고 워치를 실행한 뒤 iPhone을 다시 켰다. 페어 연결 복귀, WCSession의 reachability 변경 및 application context 재발행, 양쪽 몬스터와 revision 일치를 확인했다. 검증한 값은 초기 상태(revision 0)다.
- 마지막으로 열린 Xcode 프로젝트에서 Build를 실행해 성공과 오류 0건을 확인했다. 세 PNG는 StarterPack의 원본 픽셀과 알파 값을 대조했다.

## 남은 실기기 확인

- 실제 Apple Watch Ultra 2의 건강 읽기 권한 화면에서 동의한 뒤 걸음 수와 걷기·달리기 거리의 반영 지연을 확인한다. 등록 이후 100걸음 경계에서 XP가 10 증가하고 반복 갱신으로 추가 지급되지 않는지 점검한다.
- 실기기에서 iPhone 연결을 끊고 새 XP를 적립한 뒤 워치 앱을 재실행하고, 재연결 시 새 revision이 iPhone에 도착하는지 확인한다. 시뮬레이터에서 실제 보행이나 오프라인 신규 XP 전송을 검증한 것은 아니다.
- 아구몬 시트는 정상 내보내기 접근과 개별 이용 조건이 확보되면 대기 포즈·프레임 규격을 검증해 교체할 수 있다.

## 첫 파트너 부화 · 2026-11-23

- 워치에서 새 게임을 시작하면 디지타마를 받는다. 등록 이후 일별 원장에서 인정한 걸음의 합이 500 이상이 되는 정산에서 깜몬·푸니몬·포요몬 중 하나를 같은 확률로 뽑는다. **(2026-11-25 갱신: 이 규칙은 아래 "카드 기반 진화와 도감"으로 대체됐다. 포요몬은 더 이상 부화 후보가 아니다.)** 워치 앱이 활성화되거나 ‘활동량 갱신’을 누를 때 정산한다.
- 종과 이름만 바꾸고 같은 개체 ID, 원장, XP, 거리를 보존한다. 날짜 변경·재조회·재실행을 거쳐도 한 번 부화한 결과를 유지한다. 이전 기본 도토롱은 워치 앱 업데이트 후 처음 열 때 누적 걸음에 따라 알 또는 유년기 파트너로 전환된다.
- 워치와 iPhone에 500걸음 부화 진행률과 투명 도트를 표시한다. 워치는 알에서 파트너로 바뀌는 시점에 이름을 알려 준다. 사용한 도트 8장의 출처는 [에셋 기록](ASSET_SOURCES.md)에 정리했다.
- `swift test --package-path Packages/DigiWalkerCore`에서 44개 테스트가 통과했다. 부화 검사는 499→500보, 날짜 경계, 첫 조회가 803보인 경우, 저장·재조회 후 종 유지, 기존 도토롱 데이터 이전을 포함한다.
- 두 스킴의 Debug 시뮬레이터 빌드가 성공했다. iPhone 17과 Apple Watch Ultra 3 시뮬레이터에서 기존 도토롱이 디지타마로 전환됐으며, 양쪽에 같은 revision과 ‘부화 0 / 500걸음’이 표시되는 것을 확인했다. 500보 경계는 테스트 입력으로 검증했다. 실제 500보를 걸은 실기기 검증은 남아 있다.
- 워치 UI 테스트 1개가 통과했다. 부화 진행 표시와 건강 연결·갱신 진입점을 확인했다.

## 디지타마 앱 아이콘 · 2026-11-23

iPhone과 Apple Watch 앱 아이콘을 게임의 디지타마 도트로 교체했다. 두 카탈로그의 PNG가 동일한 1024×1024 RGB 이미지임을 확인했다. iPhone 17과 Apple Watch Ultra 3 시뮬레이터용 Debug 빌드가 성공했고 코어 테스트 44개가 통과했다.

iPhone 17 시뮬레이터(iOS 26.5)에 기존 데이터를 유지하는 업데이트 설치를 진행했다. 설치된 아이콘 파일이 새 빌드와 일치하며, 홈 화면의 DigiWalker 아이콘에 연두색 배경의 디지타마가 표시되는 것을 확인했다.

## iPhone 16 Pro Max 실기기 설치 준비 · 2026-11-23

Xcode가 USB로 페어링된 iPhone 16 Pro Max를 확인했다. iOS 기기용 Debug 빌드와 코드 서명 검증은 성공했다. 대상 기기에서 개발자 모드가 비활성으로 확인된 후 Xcode 연결이 대기 상태로 전환되었다. 범용 빌드의 프로비저닝 프로파일에는 이 iPhone이 포함되지 않아, 기기가 준비되는 대로 기기 지정 자동 서명 빌드·설치·실행 검증이 필요하다.

## iPhone 16 Pro Max 실기기 설치 · 2026-11-23

사용자가 개발자 모드를 켠 뒤 iPhone 16 Pro Max (UDID `00008140-0009353C1462401C`, iOS 27.2.1)가 USB로 연결됐다. 기기 등록 및 서명 프로비저닝 빌드가 성공했고 프로파일에 해당 기기가 포함된 것을 확인했다. `devicectl`로 앱 설치 후 실기기에서 실행했다.

## 카드 기반 진화와 도감 · 2026-11-25

### 구현
- **무작위 진화:** (2026-11-25 갱신: 기준이 5,000걸음 단위로 바뀌었다. 아래 "진화 기준 5,000걸음 단위로 변경" 참고.) 500걸음에 디지타마가 Agumon EX, Gabumon EX, Guilmon EX 중 한 카드를 같은 확률로 골라 그 카드의 stage 0이 된다. 이후 500걸음(1000·1500·2000·2500·3000)마다 같은 카드의 다음 stage 후보 중 하나로 무작위 진화하고 stage 5에서 멈춘다. 한 번의 정산으로 여러 임계값을 넘으면 단계마다 따로 뽑는다. 원작 진화 경로가 아니라 앱 고유 규칙이다. 오메가몬은 무작위 후보에서 제외했다(조그레스는 설계만 했고 구현하지 않았다). 개체 ID·원장·XP·거리는 보존한다.
- **도감:** 워치 상태 파일(`game-state.json`)에 몬스터·원장과 함께 원자적으로 저장한다. 만난 종·처음 확인한 시각·그때의 누계를 기록한다(디지타마 포함). 깨진 도감(중복·빈 ID·음수 걸음, 카드가 있는데 비었거나 없음)은 손상 저장으로 보고 디코딩이 실패하며 기존 파일은 보존한다.
- **스냅샷 v2:** `dex`와 `monster.cardId`를 포함한다. iPhone은 v1과 v2를 받고 v3 이상, dex 검증에 실패한 v2, dex가 붙은 v1은 거부한다. v1 캐시에서는 도감 대신 현재 파트너 한 줄과 동기화 안내를 표시한다.
- **마이그레이션:** 워치 로드 경로에서 `migrateLegacyStarter()` 뒤에 `migrateToEvolutionCatalog()`를 호출하고 저장에 성공한 뒤에만 반영한다. 깜몬은 `agu_ex`, 푸니몬은 `gabu_ex`로 배정하고 누계에 맞게 진화한다. **포요몬은 새 알로 재배정**한다(카드를 무작위로 골라 stage 0부터 누계만큼 진화, 도감에는 디지타마·포요몬·새 종을 기록). 알 수 없는 종은 그대로 두고 도감에 현재 종만 넣는다.
- **도트 표시:** `PrivateAssets/dim/<speciesId>.png`의 DIM 시트를 실행 중에 잘라(`SheetSlicing`) 대기 프레임을 정수 배율·최근접 보간으로 그린다. 없으면 저장소 PNG(디지타마·깜몬·푸니몬·포요몬), 그것도 없으면 `?` 플레이스홀더다. iPhone 타깃에도 PrivateAssets 폴더 참조를 추가했다.
- **UI:** 워치는 부화·진화 알림과 "다음 진화까지 N걸음"·구간 진행바를 표시한다. iPhone은 `도감 · n / N`(2026-11-26부터 기본 184, 포요몬을 만났으면 185; 그 전에는 50/51) 화면을 제공하고 미발견 종은 `???`로 가린다.
- **사용자 결정:** 한국어 표시명은 "우선 가안 그대로" 쓴다. 표(`SpeciesCatalog.swift`)에서 `nameVerified=false`인 항목은 미확인이며 이후 한 곳에서 고칠 수 있다. 도감 섹션 제목은 "아구몬 카드", "파피몬 카드", "길몬 카드"로 정했다. 출처와 이용 조건은 [에셋 기록](ASSET_SOURCES.md)에 있다.

### 검증한 환경
- Xcode 27.2, macOS Mac 호스트. `swift test --package-path Packages/DigiWalkerCore` 95개 통과(카탈로그·진화·마이그레이션·스냅샷·시트 분할). 기존 상태 파일 검사용 JSON 픽스처 중 커밋 96819e2 코드로 실제 인코딩한 것은 디지타마 하나뿐이고, 깜몬·푸니몬·포요몬·미지의 종 픽스처는 같은 형식으로 구성했다. 이 픽스처들로 디코딩·이전·왕복을 검사했다.
- iPhone 17(iOS 27.2)과 Apple Watch Series 12 (46mm)(watchOS 27.2) 시뮬레이터에서 두 스킴 Debug 빌드가 성공했다. iPhone 17 시뮬레이터에서 `DigiWalkerTests` 12개(합성 시트 로더, 도감 모델)가 통과했다. 워치 UI 테스트 `testPartnerAndHealthEntryPoint`가 통과했다.
- iPhone 17 시뮬레이터에 임시 `watch-cache.json`(v2, 길몬)을 넣어 메인 화면의 카드 이름·단계·남은 걸음·진행바·`도감 · 4 / 50`을 눈으로 확인했다.
- 빌드된 두 앱의 `PrivateAssets/`에는 README와 `.gitkeep`만 있음을 확인했다.

### 미검증
- 실기기에서의 마이그레이션(디지타마 9걸음 상태 업데이트)과 실제 500걸음 이상 진화.
- 실제 DIM 시트의 렌더링, 시트 레이아웃·대기 프레임(0·1번) 가정, 공유 종의 두 카드 시트 일치 여부.
- 워치 진화·부화 alert 표시, iPhone 도감 화면의 육안 확인(도감 화면은 스크린샷을 찍지 못했다).
- 실제 WatchConnectivity로 v2 스냅샷이 iPhone에 도착하는 흐름(시뮬레이터 페어 재검증 없음).

## DIM BIN 추출 도구 · 2026-11-25

### 구현
- `Tools/dim-extract`(SwiftPM, macOS 15, 코어 패키지만 의존): BIN 형식 파서(`DIMCardImage`), RGB565 변환, PNG 인코더(`PNGWriter`), 시트 계획·검증(`SheetPlanner`), CLI `dim-extract`. 카드·슬롯·프레임 규격은 `DigiWalkerCore`(`SpeciesCatalog`, `EvolutionCard`, `SheetSlicing`)에서 가져온다. 앱·코어 코드는 바꾸지 않았다.
- BIN은 `PrivateSources/dim-bin/`(git 제외, 번들 비포함)에 둔다. 세 BIN으로 `PrivateAssets/dim/`에 49개 시트(768×56 또는 160×24)를 생성했고 git에는 추적되지 않는다.
- 형식 확인: 반전 후 포인터 테이블·크기 표·길이(w×h×2)가 세 BIN 모두 일관됐고 슬롯 17개의 단계·속성·프레임 규격이 카탈로그와 일치했다. Guilmon.bin은 카탈로그 해시와 다르지만(자세한 내용은 ASSET_SOURCES.md) 같은 구조였고 `--allow-hash-mismatch`로 변환했다. Guilmon.bin은 스프라이트가 포인터 순서와 다른 순서로 저장돼 있어(오프셋이 단조 증가하지 않음) 파서는 오프셋을 크기 표 인덱스로 조회한다.

### 검증한 환경
- `swift test --package-path Tools/dim-extract` 19개 통과(합성 데이터만 사용: 파서, 범위 검사, PNG 왕복, 시트 조립, 공유 종, 덮어쓰기, 드라이런, 해시 불일치). `swift test --package-path Packages/DigiWalkerCore` 95개 통과.
- 실제 BIN 추출 후 49개 파일의 PNG 크기가 코어 규격과 일치함을 `sips`로 확인했다(생성 시 `SheetSlicing` 검사도 통과).
- iPhone 17(iOS 27.2)과 Apple Watch Series 12 (46mm)(watchOS 27.2) 시뮬레이터에서 두 스킴 Debug 빌드가 성공했다. iPhone 17 시뮬레이터에 임시 캐시(그레이몬)를 넣어 메인 화면을 확인한 결과 실제 도트가 표시되고 배경이 투명했다. iPhone 번들의 `PrivateAssets/dim`에 PNG 49개가 들어 있다. 실기기 확인은 하지 않았다.

### 미검증
- 대기 프레임 0·1이 대기 포즈인지(Gist 순서는 Idle, Idle 2이며 한 종의 한 프레임만 육안으로 봤다). 도감 화면·워치 화면·유년기 크기의 육안 확인은 사용자가 해야 한다.
- 색 변환(비트 복제)이 DIM Modifier PNG 내보내기와 같은지, 카탈로그 `fingerprint` 재현(시도했으나 입력 방식을 알아내지 못함), 공유 종 두 카드(agu/gabu) 픽셀 동일 여부, Guilmon.bin 픽셀이 카탈로그 원본과 같은지.
- 빈 `PrivateAssets/dim-bin/` 디렉터리는 사용자가 제거했다. 리뷰 반영 후 BIN 헤더 dimId 검증, 출력 경로 검증, 비정규 대상 거부, 코어 `cardId` 디코딩 검증을 추가했다(자세한 시험은 위 테스트 수 갱신 참고).


## 실기기 설치·마이그레이션 확인 · 2026-11-25

- 환경: iPhone 16 Pro Max(iOS 27.2.1)와 Apple Watch Ultra 2(watchOS 27.2.1), Xcode 27.2, 무료 Personal Team 서명. `xcodebuild clean` 후 Xcode MCP로 iPhone 스킴을 실기기에서 실행했고, 빌드된 앱에 포함된 워치 앱을 `devicectl`로 Ultra 2에 설치·실행했다. 설치본에 BIN은 없고 `PrivateAssets/dim` PNG 49개가 들어 있다.
- 결과(사용자 사진으로 확인): 기존 디지타마 상태가 오류 없이 이전됐다. 워치와 iPhone 모두 디지타마 도트와 `부화 89 / 500걸음` 진행 막대를 표시했다. iPhone은 v2 스냅샷을 받아 `도감 · 1 / 50`을 표시했다(워치 앱 연결됨, 마지막 수신 2:23).
- 수정: iPhone의 날짜를 기기 지역 설정과 관계없이 한국어 형식(예: 2026년 11월 25일, 2026. 11. 25. 오전 2:23)으로, 누적 거리를 1km 미만은 `66m`, 이상은 `1.23km` 형식으로 표시하도록 바꿨다.
- 미검증: 실기기 부화·진화 alert, 유년기(32×24) DIM 도트 크기와 대기 애니메이션, iPhone 도감 화면 육안 확인, 날짜·거리 표시 수정분의 실기기 화면.
- 참고: Xcode MCP의 실행 대상 이름 `박태양의 Apple Watch`는 "Apple"과 "Watch" 사이가 줄바꿈 없는 공백(U+00A0)이라 MCP로 전환하지 못했다. 워치 실행은 `devicectl`로 했다.

## 실기기 부화 확인과 진화 기준 변경 · 2026-11-25

- 실기기 부화: 첫 부화 기준을 임시로 100걸음으로 낮춘 빌드(미커밋)를 iPhone 16 Pro Max와 Apple Watch Ultra 2에 설치했다. 사용자 보고로 걸음이 갱신되면서 디지타마가 푸니몬(Gabumon EX 카드)으로 부화한 것을 확인했다. 임시 변경은 되돌렸다.
- **진화 기준 5,000걸음 단위로 변경(사용자 결정):** 500걸음이 너무 빨리 채워져서 `EvolutionCard.stepsPerStage`를 500에서 5,000으로 바꿨다. 부화 5,000, 이후 10,000·15,000·20,000·25,000에 진화하고, 30,000에서 궁극체로 멈춘다. XP(100걸음당 10 XP)와 레벨(250 XP당 1) 규칙은 그대로다.
- 기존 저장 파일 영향: 저장 검증은 걸음 수와 단계를 대조하지 않는다. 이미 부화했거나 진화한 개체는 현재 종을 그대로 유지하고, 다음 진화는 새 기준을 따른다. 기존 도감 기록의 "N걸음에 부화/진화" 값은 기록 당시 값으로 남는다.
- 테스트: 임계값 관련 테스트와 레거시 픽스처(깜몬·포요몬의 걸음·XP 값)를 10배로 조정했다. `swift test --package-path Packages/DigiWalkerCore` 98개 통과.
- **부화만 500걸음으로 조정(사용자 결정, 같은 날):** 친구 요청으로 알 부화만 500걸음으로 되돌렸다(`EvolutionCard.hatchSteps`). 진화 기준은 그대로 10,000·15,000·20,000·25,000·30,000이다. 이미 부화한 개체에는 영향이 없다. `swift test --package-path Packages/DigiWalkerCore` 98개 통과.

## EX 카드 8장 추가(총 11장) · 2026-11-26

- **범위:** Terriermon·Renamon·Agnimon·Fairimon·Chackmon·Wolfmon·Blitzmon·Louwemon EX 카드를 코어 `SpeciesCatalog.cards`에 추가했다(기존 3장이 앞, `agu_ex`가 첫 카드). 디지타마는 500걸음에 11장 중 한 장을 균등하게 골라 그 카드의 유년기 I이 되고, 이후 같은 카드 안에서 기존 걸음 기준으로 무작위 진화한다. 스키마 v2는 그대로다. 걸음·XP·레벨 규칙은 바꾸지 않았다.
- **종:** 고유 종 183(기존 49 + 134), 공유 종 4(깜몬·알고몬·오메가몬·스사노오몬). 스사노오몬은 오메가몬처럼 무작위 후보에서 제외한다(조그레스 전용, 미구현). 원작 잠금 해제(`unlockRequired`) 종 6종은 후보에 포함한다(사용자 결정; 2026-11-26 진화 아이템 작업에서 아이템 보유 조건으로 대체, 아래 참고). 한국어 표시명 134개와 카드 제목 8개는 모두 가안(`nameVerified = false`)이다.
- **추출:** 8장 BIN은 `--allow-hash-mismatch`로 변환했다(해시는 모두 카탈로그와 다름, 헤더 dimId·스프라이트 233·슬롯 stage·프레임 규격 일치, 근거는 `docs/ASSET_SOURCES.md`). 결과 `PrivateAssets/dim` PNG 183개(2,176KB `du`, 합계 1,828,100바이트). 기존 49개 SHA-256은 변하지 않았고, 새 134개는 160×24 또는 768×56이며 `git status`에 BIN·PNG는 없다.
- **앱:** 도감 분모 184(포요몬을 만났으면 185), 섹션은 공통 + 카드 11개(+ 이전 파트너). 공유 종은 해당 카드 섹션마다 한 행씩 표시하고(발견하면 양쪽이 함께 열림) 분모·발견 수는 종 기준 한 번만 센다. 조그레스 안내("특별한 조건이 필요해요")는 어느 카드에서도 무작위 후보가 아닌 종(오메가몬·스사노오몬)에 표시한다. 카드 제목 11개는 `DexModel.cardTitles`다. 이전의 "…카드에도 등장" 주석은 없앴다.
- **테스트:** `swift test --package-path Packages/DigiWalkerCore` 108개 통과, `swift test --package-path Tools/dim-extract` 37개 통과. `DigiWalkerTests`(iPhone 17, iOS 27.2 시뮬레이터) 통과.
- **빌드·번들(시뮬레이터):** iPhone 17(iOS 27.2) `DigiWalker` 스킴과 Apple Watch Series 12 (46mm)(watchOS 27.2) 워치 스킴 Debug 빌드 성공. iPhone 앱 번들(`Debug-iphonesimulator/DigiWalker.app`) 10,540KB, 그중 `PrivateAssets/dim` PNG 183개 2,176KB. 워치 앱 번들(독립 빌드) 5,776KB, `PrivateAssets/dim` PNG 183개 2,176KB(iPhone 앱에 포함된 워치 앱도 183개). 두 번들 모두 `.bin` 없음.
- **미확인:** 가안 이름 134개, 새 BIN 8장 픽셀이 카탈로그 원본과 같은지, 새 카드의 대기 프레임(0·1번) 가정과 도트 육안 확인, 새 카드 개체의 시뮬레이터 화면 확인과 도감 스크롤 성능, 실기기 설치·동작(하지 않음). 동기화 때 잠금 해제 아이템을 지급하는 로직은 이 시점엔 범위 밖이었고 이후 "진화 아이템" 절에서 구현했다.

## 백그라운드 정산과 부화·진화 워치 알림 · 2026-11-26

- **트리거(실시간 아님):** (1) 앱 새로고침 `WKApplicationRefreshBackgroundTask`, 정산마다 약 45분 뒤로 하나만 예약(시스템이 실제 시각을 정함), (2) `HKObserverQuery`(걸음) + `enableBackgroundDelivery(.hourly)`, `com.apple.developer.healthkit.background-delivery` 엔타이틀먼트, (3) 앱이 활성화될 때. 세 경로 모두 같은 직렬 정산 하나를 부른다(겹친 요청은 기다리고, 시작 전 대기 중인 일반 요청은 하나로 합친다). HealthKit 백그라운드 전달은 앱 새로고침과 같은 예산을 공유하고 watchOS 26 이후 불규칙하다는 보고가 많아서, 알림은 수십 분에서 1시간 이상 늦거나 오지 않을 수 있다. 앱을 열면 바로 정산한다. 운동 세션·위치·확장 런타임은 쓰지 않는다.
- **이벤트와 알림:** 부화·진화는 정산 저장(commit)이 성공한 뒤에만 만들어진다. 앱이 활성이면 햅틱(`.success`)과 alert, 아니면 로컬 알림을 등록한다. 이벤트는 commit 직후 `pending-growth-events.json`에 먼저 기록(write-ahead)하고 알림 등록이 성공하면 지운다. 알림을 못 보낸 이벤트(권한 없음, 등록 실패)만 다음 앱 실행 때 alert로 보여준다. 알림 등록이 진행 중인 이벤트는 alert에서 숨기고 ID로 하나씩 닫는다. 원장·몬스터 파일 스키마는 바꾸지 않았다. pending 파일 쓰기에 실패하면 다음 정산에서 다시 쓴다. 알림 권한은 건강 데이터 연결 뒤(앱이 활성일 때) 요청하고, 허용 상태에서 화면에 지연 안내를 보여준다.
- **스냅샷 전송:** `session.applicationContext`(마지막으로 제출에 성공한 값)를 디코딩해 monster.id와 revision이 같으면 `updateApplicationContext`를 생략한다. 제출이 실패하면 값이 바뀌지 않아 다시 보낸다. iPhone 수신 쪽 revision 비교는 그대로다.
- **무료 팀 서명 확인(1단계):** 무료 Personal Team에서 background-delivery 키를 넣은 워치 앱이 실기기용으로 서명됐다(codesign과 embedded.mobileprovision 양쪽에 키 있음, 설치하지 않음). 프로파일 만료 2026-12-02 09:36 KST.
- **검증한 환경:** `swift test --package-path Packages/DigiWalkerCore` 118개 통과. 워치 앱 테스트 36개 통과(Apple Watch Series 12 46mm, watchOS 27.2 시뮬레이터, build-for-testing + test-without-building), iPhone 17(iOS 27.2) 시뮬레이터 빌드 성공. 최종 코드로 워치 실기기용(arm64_32) 서명 빌드(`generic/platform=watchOS`, `-allowProvisioningUpdates -allowProvisioningDeviceRegistration`)를 다시 실행해 성공했다(설치 안 함).
- **전송 복구 경로:** `sessionCompanionAppInstalledDidChange`에서 iPhone 앱이 설치됨(true)이거나 `sessionReachabilityDidChange`에서 연결 가능(true)이 되면 같은 revision 생략을 건너뛰고 강제 전송한다(재설치·캐시 유실 복구). 평소 경로는 그대로 생략한다. 강제 플래그는 `SnapshotSendPolicy.shouldSend(force:)` 단위 테스트로 확인했다. `expirationHandler`는 메인 스레드에서 불리면 `MainActor.assumeIsolated`로 즉시 완료하고 아니면 `Task { @MainActor }`로 넘긴다.
- **미검증:** 실기기에서의 알림 도착과 진동, 도착까지의 지연, observer·앱 새로고침 실제 전달 빈도, 배터리 사용량, 손목에서 뺀 상태의 HealthKit 조회·파일 쓰기, `expirationHandler` 실동작(메인 밖 호출 포함), 알림이 워치와 iPhone에서 어떻게 중복·표시되는지, 시뮬레이터에서의 백그라운드 새로고침 실행.
- **미해결 위험:** 이벤트를 원장·몬스터 파일과 한 번에 원자적으로 저장하지는 않는다(스키마 변경이 필요해 보류). 정산 저장과 pending 쓰기 사이에 프로세스가 끝나거나 pending 쓰기가 실패한 직후 끝나면 그 이벤트의 알림이 사라질 수 있다.
- **추가 미해결 위험·미검증:** (a) 알림이 시스템에 등록된 직후 pending 삭제 전에 프로세스가 끝나면 다음 실행 때 같은 이벤트가 alert로 한 번 더 뜰 수 있다(write-ahead 선택의 대가). (b) HealthKit이 앱을 깨웠는데 게임 파일 읽기가 실패하면(재부팅 후 첫 잠금 해제 전 등) observer가 설치되지 않아 전달을 확인하지 못하고, 반복되면 HealthKit이 전달 빈도를 줄일 수 있다. (c) `expirationHandler` 호출 스레드와 완료 타이밍은 실기기에서 확인하지 못했다. (d) 비활성 상태에서 alert가 설정됐다가 시스템이 내리면 보지 못한 이벤트가 닫힘 처리될 가능성이 있다(실기기 확인 필요). (e) iPhone 재설치 시 워치 applicationContext 유지 여부는 미확인이다(강제 전송으로 대응). (f) 컴플리케이션이 없으면 watchOS가 백그라운드 새로고침 예산을 적게 줄 수 있어 실제 알림 빈도는 실기기 측정이 필요하다.

## 진화 기준 점증(사용자 결정, 2026-11-26)

- **변경:** 진화에 필요한 걸음이 단계마다 늘어난다. 부화는 500걸음 그대로, 이후 누적 5,000 / 15,000 / 30,000 / 50,000 / 75,000걸음(단계 사이 5,000·10,000·15,000·20,000·25,000, 부화→유년기 II 첫 구간만 4,500)에 진화하고 75,000에서 궁극체로 멈춘다. `EvolutionCard.requiredSteps(stage:)`는 `stage == 0 ? hatchSteps : stepsPerStage * stage * (stage + 1) / 2`다. XP·레벨 규칙은 그대로다.
- **기존 개체:** 퇴화하지 않는다. 이미 도달한 단계는 유지되고 다음 진화부터 새 표를 적용한다. 예: 15,000걸음 이상인 성장기는 다음 진화가 30,000걸음이다. 도감의 "N걸음에 진화" 기록은 기록 당시 값으로 남는다. 앱 PartnerGrowthView는 `requiredSteps`를 그대로 쓴다.
- **테스트:** 코어 테스트는 `EvolutionCard.requiredSteps(stage:)`를 쓰도록 바꾸고 기준표는 `[500, 5_000, 15_000, 30_000, 50_000, 75_000]`을 명시 검증한다. 포요몬 레거시 픽스처(800)는 4,010걸음으로 조정했다(첫 진화 전 단계 유지 의도).

## 워치 페이스 컴플리케이션(위젯 확장)과 진단 기록 · 2026-11-26

- **서명(1단계 결과):** 위젯 확장 `DigiWalker Widgets`(번들 ID `ty.park.DigiWalker.watchkitapp.widgets`)를 워치 앱에 내장했다. 무료 Personal Team에서 위젯 확장과 App Group(`group.ty.park.DigiWalker`)이 모두 실기기용으로 서명됐다(워치 앱·확장의 codesign과 embedded.mobileprovision 양쪽에 application-groups 확인, ProvisionedDevices 4대, 설치하지 않음). **프로파일 만료:** 워치 앱·위젯 확장 2026-12-03 20:06 KST, iPhone 앱 2026-12-02 09:35 KST(iPhone 앱은 App Group이 없고 프로파일이 바뀌지 않았다). 재설치 마감은 가장 이른 12-02 09:35 기준이다.
- **구조:** 육성 원본은 그대로 워치 앱 컨테이너의 `game-state.json`이고 스냅샷 스키마도 바꾸지 않았다. 워치 앱이 정산 commit 뒤(그리고 첫 로드 때) App Group에 표시용 사본 `widget-snapshot.json`을 원자적으로 쓰고, 위젯은 읽기만 한다. 사본 쓰기는 throw하지 않아 정산·알림에 영향이 없다. 리로드는 화면에 보이는 값(종·이름·단계·남은 걸음)이 바뀔 때만 요청하고, 걸음만 바뀐 경우 백그라운드에서는 마지막 리로드 후 30분이 지나야 한다(`WidgetReloadPolicy`). 궁극체 이후 쌓이는 걸음은 보이지 않으므로 리로드하지 않는다. 사본을 읽지 못한 위젯은 "앱을 열어 주세요"를 보이고 20분 뒤 다시 읽는다(읽을 수 있으면 갱신은 워치 앱이 주도). 알 수 없는 단계는 "최종 단계"로 표시하지 않고 최종 단계 문구는 `stage == stageCount - 1`일 때만 쓴다.
- **지원 칸:** 직사각형(도트·이름·남은 걸음), 원형(도트), 모서리(도트 + 곡선 라벨), 인라인(이름·남은 걸음 텍스트). 도트는 대기 프레임 0번만 기기 픽셀 기준 정수 배율과 최근접 보간으로 그린다.
- **진단 기록(`background-log.json`, 워치 홈 화면 맨 아래):** 백그라운드로 깨어난 경우만 기록한다. 앱이 활성(`.active`)이 아닐 때 도착한 앱 새로고침·HealthKit 콜백이 대상이고(활성 여부는 도착 시점에 확인, 이후 상태가 바뀌어도 도착 시점 기준), 앱이 열려 있을 때의 정산과 HealthKit 콜백은 기록하지 않는다. 최근 20건 링과 별개로 날짜별 횟수(최근 7일)와 마지막 시각을 저장해 "오늘 N회"가 20건에 묶이지 않는다. 깨어남은 도착 시각을 먼저 기록하고 정산이 끝나면 결과를 갱신한다(타임아웃·만료로 끊겨도 "도착 (결과 없음)"이 남는다). 기록 파일을 읽지 못하면 덮어쓰지 않고 메모리에만 두었다가 읽을 수 있게 되면 합친다. 정산은 자기 결과를 반환하며(공유 `lastOutcome` 제거) 합류한 호출자도 자기 결과를 받는다.
- **검증한 환경:** `swift test --package-path Packages/DigiWalkerCore` 136개 통과. 워치 앱 테스트 71개 통과(Apple Watch Series 12 46mm, watchOS 27.2 시뮬레이터, build-for-testing + test-without-building). `DigiWalker` 스킴 iOS 시뮬레이터(generic) Debug 빌드 성공, 워치 실기기용 서명 빌드(본인 워치 지정, `-allowProvisioningUpdates -allowProvisioningDeviceRegistration`) 성공. 설치는 하지 않았다.
- **미검증(실기기·페이스 확인 필요):** 페이스에서의 실제 렌더링, 틴트(accented) 페이스에서 도트가 단색이 되는지(`widgetAccentedRenderingMode(.fullColor)`는 컴파일만 확인), 작은 칸(원형·모서리)에서 도트 크기와 넘침, 컴플리케이션이 실제로 백그라운드 실행 예산을 늘리는지(진단 기록의 전후 비교로만 확인 가능), 위젯 확장 프로세스의 런타임과 Swift 6 격리(`PartnerEntry`·`PartnerProvider`를 `nonisolated`로 둠), 위젯 확장 메모리 한도, 잠금 상태에서의 App Group 파일 읽기·쓰기, 정산 뒤 컴플리케이션 갱신 지연, `.inactive`(손목 내림) 상태에서 도착한 콜백도 백그라운드로 집계되는 점.

### 컴플리케이션 넣는 방법

실기기(본인 Ultra 2, 2026-11-26 21:40경, `c31a0c6`)에서 확인했다.
- 시계 페이스를 길게 누름 → 편집 → 컴플리케이션 칸에서 DigiWalker 선택. 도트는 칸 안에 잘리지 않고 표시된다.
- 페이스 색상이 한 가지 색일 때는 도트가 흰색 단색 실루엣으로 나온다(`widgetAccentedRenderingMode(.fullColor)`가 적용되지 않음). 편집의 색상 단계에서 **멀티컬러**로 바꾸면 원래 색으로 나온다.
- 미확인: 백그라운드 깨어남 횟수 변화(진단 기록), 앱을 닫은 상태의 부화·진화 알림.

## 진화 아이템(문장·디지멘탈·X항체) · 2026-11-26

계획서: `local-notes/plans/20261126-evolution-items.md`(사용자 결정 반영). 코어·워치·iPhone을 구현했고 실기기 확인은 아직 하지 않았다.

### 규칙
- **지급:** 파트너의 누적 인정 걸음 기준으로 새 5,000걸음 구간(`걸음 / 5,000`)마다 정확히 한 번 20% 확률로 아이템 1개를 지급한다. 거리·감소한 측정값·같은 구간 재조회는 새 구간을 만들지 않는다. 구간은 부화·진화 판정보다 먼저 추첨하므로 그 구간에서 얻은 아이템이 같은 정산의 진화에 쓰일 수 있다.
- **종류:** 25종(문장 11, 디지멘탈 11, X항체·디지코어·디지코드 3). 이름은 모두 가안(`nameVerified = false`)이고 `ItemCatalog` 한 곳에 있다. 출처는 [에셋 기록](ASSET_SOURCES.md) "진화 아이템 이름 출처".
- **분포:** 당첨되면 50%는 현재 카드의 미보유 잠금 아이템, 50%는 25종 균등이다. 우선 후보가 없으면 25종 균등이다.
- **소모하지 않음:** 중복 허용(개수 증가), 다음 개체에도 유지한다. 인벤토리는 `Monster`가 아니라 `GameState`에 있다.
- **진화 연결:** 원작 잠금 해제 7종(돈데블몬·래피드몬(아머)·사쿠야몬 X·로드나이트몬·다이나스몬·무르무쿠스몬·루체몬 폴다운모드)은 해당 아이템(디지코어·운명의 디지멘탈·X항체·디지코드)을 보유해야 무작위 후보가 된다. 보유하면 일반 후보 중 하나라 확정은 아니다. 이미 그 종인 개체는 되돌리지 않는다. 모든 단계에서 아이템 없이도 후보가 1종 이상 남는다.

### 결정성과 중복 방지
- 추첨은 `ItemDrop.roll`(개체 UUID + 구간 번호로 시드한 SplitMix64, `Hasher` 미사용)이라 진화용 난수 생성기를 쓰지 않는다. 기존 `draws` 소비 개수와 진화 결과는 그대로다. 같은 상태·같은 구간은 항상 같은 결과다.
- `GameState.itemSegmentsRolled`(마지막으로 추첨한 구간)와 `items`(`(monsterId, segment)`가 키인 append-only 원장)를 원장·몬스터·도감과 같은 `game-state.json`에 원자 저장한다. 저장 실패 후 재시도, 재실행, 재조회에서 구간은 한 번만 추첨된다.
- **소급 없음:** 아이템 키(`items`, `itemSegmentsRolled`)가 둘 다 없는 옛 파일은 읽을 때 `itemSegmentsRolled = 총 걸음 / 5,000`, `items = []`로 시작하고 revision을 바꾸지 않는다. 둘 중 하나만 있거나 null이거나, 체크포인트가 `총 걸음 / 5,000`과 다르거나, 같은 `(monsterId, segment)`가 겹치거나 현재 개체의 구간이 체크포인트를 넘으면 손상 저장으로 보고 디코딩이 실패하며 파일은 보존한다.
- **알 상태에서의 일괄 정산은 균등:** 한 정산에서 부화 전에 여러 구간이 열리면 카드가 없어 25종 균등이다.
- **다일 재조회 재시도(2026-11-26 리뷰 반영):** `GrowthService.reconcile`은 하루씩 정산하므로, 같은 reconcile 안에서 1일차에 부화한 카드(무작위)가 2일차 우선 분포를 바꾸면 저장 실패 후 재시도 때 아이템이 달라질 수 있다. 그래서 우선 분포는 reconcile 시작 시 입력 상태(커밋된 상태)에 이미 있던 카드에만 쓴다(`settle(…committedCardId:)`; 벽시계 비교는 쓰지 않아 시계 역행에도 같다). 같은 reconcile에서 부화한 카드의 구간은 25종 균등이다. 시드가 다른 재시도에서 구간과 아이템 ID가 모두 같음, 시계 역행에도 우선 분포가 유지됨을 테스트로 확인했다.
- **획득 시각(`grantedAt`)은 재시도마다 다를 수 있다.** 정산 시각을 쓰므로 ID·구간은 같아도 시각은 재시도 때의 정산 시각이다.

### 스냅샷 v3와 알림
- **스냅샷 v3:** 전체 원장은 워치 상태 파일에만 두고 스냅샷에는 아이템별 요약(`itemId`, `count`, `firstGrantedAt`, `currentPartnerCount`)만 보낸다(5,000건 원장에서도 8KB 미만을 테스트로 확인). v3는 `items` 필수(빈 배열 허용), 이전 버전은 `items`가 없어야 한다. 요약 검증: id 중복·빈 id 거부, `count >= 1`, `0 <= currentPartnerCount <= count`, 현재 개체 합계가 `총 걸음 / 5,000`을 넘으면 거부.
- **같은 revision에서 v2 → v3:** iPhone `supersedes`와 워치 `SnapshotSendPolicy.shouldSend`는 같은 개체·같은 revision이면 스키마가 더 높은 쪽만 받아들인다(하향·낮은 revision 거부). 워치 앱만 업데이트해도 revision이 안 오르면 v3가 막히던 문제를 막는다.
- **알림:** `GrowthEvent.itemFound`를 기존 pending 큐·알림·alert 경로로 보낸다. 아이템마다 알림 1개, 같은 정산에서는 아이템(구간 순) 먼저, 부화·진화가 그다음이다. 식별자는 `item-<monsterId>-<segment>`(진화는 `growth-...`). 앱이 활성이면 정산당 진동 한 번(`.success`)이고 나머지 이벤트는 alert로 차례로 보인다. 문구는 "○○을(를) 얻었어요!" / "누적 N걸음을 넘겨 찾았어요"로, 획득 이후 종이 바뀔 수 있어 종 이름은 쓰지 않는다. 숫자 구분 기호는 로케일과 무관하게 고정했다.
- **화면:** 워치 홈에서 "아이템 N개" 버튼 → 시트(이름·개수·처음 얻은 날), 없으면 "5,000걸음마다 아이템을 찾을 수 있어요". iPhone은 파트너 섹션의 "아이템 · 보유 종류 n / 25"(문장/디지멘탈/기타, 미보유는 회색 "미보유")와 도감에서 잠금 종 행의 "필요: ○○ · 보유/미보유"를 표시한다. v1·v2 캐시에서는 "워치 앱을 업데이트하면 아이템이 동기화돼요"를 보인다. 아이템 그림은 쓰지 않았다.
- **워치와 iPhone을 함께 설치해야 한다.** 워치만 먼저 v3로 올리면 옛 iPhone 앱은 v3를 거부해 화면이 갱신되지 않는다. 앱 삭제 없이 덮어쓰기 설치한다(12-02 재설치 때도 두 앱 동시).

### 검증한 환경
- `swift test --package-path Packages/DigiWalkerCore` 174개 통과(10회 반복 모두 통과, Xcode 27.2, macOS Mac 호스트). 워치 앱 테스트 75개를 `-test-iterations 15`로 반복해 1,125건 모두 통과(Apple Watch Series 11 46mm, watchOS 27.2 시뮬레이터, build-for-testing + test-without-building `-only-testing:"DigiWalker Watch AppTests"`). iPhone `DigiWalkerTests` 23개 통과(iPhone 17, iOS 27.2 시뮬레이터). 워치 실기기용 서명 빌드(본인 워치 지정, `-allowProvisioningUpdates`) 성공, 설치하지 않았다. 무작위 UUID 때문에 20% 확률로 아이템 이벤트가 끼어들던 간헐 실패는 테스트의 파트너 ID를 고정해 없앴다.
- **미검증:** 실기기에서의 획득 알림·진동(20%라 바로 못 볼 수 있어 시뮬레이터 테스트로 대신), 소급 없이 기존 실기기 파일이 읽히는지, 워치·iPhone 화면 육안 확인(스크린샷 미촬영), 5,000걸음 경계를 넘긴 뒤 실제 추첨, 25종 가안 이름의 공식 한국어명, v3 전송 실기기 확인.

## 새 알 키우기(환생)·레벨 제거·아이템 소모 · 2026-11-27

계획서: `local-notes/plans/20261127-rebirth-new-egg.md`, 요구사항: `local-notes/기능/새알키우기-환생.md`. 코어·워치·iPhone을 구현했고 실기기 확인은 아직 하지 않았다.

### 구현
- **레벨·경험치 제거:** `ExperienceCalculator`·`Monster.experience/level`·`DailyActivityLedger.creditedXP`를 없앴다. 옛 상태 파일·캐시·pending 파일의 `experience`·`creditedXP` 키는 읽을 때 무시한다. 화면에는 "다음 진화까지 N걸음" 진행 바(궁극체 뒤에는 "새 알까지 N걸음", 85,000 이후 "새 알을 키울 수 있어요")를 둔다.
- **아이템 자동 소모:** 잠금 종이 무작위 진화로 선택되면 필요한 아이템 1개를 소모하고 `itemUses`(append-only)에 기록한다. 보유 수는 획득 − 사용이며 요약(`ItemSummary.count`)도 현재 개수다. 기존 보유량은 그대로이고 소급 소모는 없다. 다음 개체에도 유지한다.
- **새 알:** 궁극체 개체가 누적 85,000걸음(`Monster.stepsForNewEgg`)이 되면 워치가 알림을 한 번만 보낸다(정산에서 경계를 넘는 순간만; 기능 설치 전에 넘긴 개체는 알림 없이 버튼만). 워치·iPhone 디지몬 아래 '새 알 키우기' 버튼 → "정말 새 알을 키울까요? ○○몬은 도감에 남습니다" 확인 → 실행. 새 개체는 새 UUID의 디지타마, 0걸음, 아이템 구간 0부터. 부화 카드는 직전 카드를 뺀 10장 중 개체 ID 시드로 결정적으로 고른다(2세대부터, 첫 세대는 기존 방식). 도감·아이템·사용 기록·정산 원장은 유지하고, 환생 시각 이후 걸음만 새 개체에 지급한다(환생 날의 이전 원장은 `priorPartnerLedgers`로 옮겨 재지급 방지).
- **iPhone → 워치 요청:** iPhone이 `NewEggRequest`를 `pending-new-egg.json`에 먼저 저장하고 `WCSession.transferUserInfo`로 보낸다. 워치는 정산과 같은 직렬 체인에서 대상 개체 ID가 현재 개체일 때만 적용하므로 중복·늦은 요청은 무시된다. iPhone은 "워치에 연결되면 시작됩니다"(큐 대기) / "워치에서 새 알을 준비하고 있어요"(전달됨)를 표시하고, 다른 개체 ID의 스냅샷을 받으면 대기를 해제한다. 대기 중(queued)에서만 "요청 취소"가 큐의 전송을 취소하고 대기를 지운다. 이미 전달된 뒤(delivered)·실패 뒤에는 "대기 표시 지우기"로 바뀌며 iPhone의 표시만 지운다: 전달된 요청은 취소되지 않아 워치에서 새 알이 시작될 수 있고, 화면에 그렇게 안내한다. 워치와 활성화·페어링·앱 설치가 확인되지 않으면 요청을 저장하거나 보내지 않고 "워치와 연결을 확인해 주세요"를 보인다. 같은 요청의 전달 후 실패 보고(delivered→failed)도 반영한다. 기록 파일을 지우지 못하면 `null`로 덮어쓰고, 그것도 실패하면 메모리 상태를 유지한다. v3 이하 캐시(옛 워치)에서는 버튼을 숨기고 "워치 앱을 업데이트해 주세요"를 보인다.
- **스냅샷 v4:** `generation` 추가, 개체 교체는 `(createdAt, generation)`으로 판정(환생은 같은 `createdAt`, 높은 세대). 아이템 요약은 현재 개수. **iPhone과 워치 앱을 함께 설치해야 한다**(워치만 올리면 옛 iPhone이 v4를 거부하고, iPhone만 올리면 v3 캐시가 보이며 버튼은 숨겨진다).
- 환생하면 이전 개체의 "새 알" 안내(pending 큐·알림 센터)만 지우고 부화·진화·아이템 기록은 남긴다. 위젯 사본은 개체 ID가 바뀌어 즉시 다시 쓴다. 컴플리케이션은 "새 알까지 N걸음"/"새 알 준비"를 보인다.

### 검증한 환경
- 검증 일시: 2026-11-27, Xcode 27.2, macOS Mac 호스트. `swift test --package-path Packages/DigiWalkerCore` 225개 통과. iPhone `DigiWalkerTests` 30개 통과(이번에 7개 추가). 워치 앱 테스트 100개 통과(3회 실행 중 1회 `mergeAfterUnreadablePendingFileIsSaved`가 간헐 실패했다. 원인: 테스트의 `donor`와 `rig`가 같은 고정 개체 ID를 써서, 첫 부화가 시스템 난수로 같은 종을 고르면(약 10.7%) 두 알림 이벤트가 같아져 병합되어 개수가 1이 됐다. 수정: `donor`에 다른 개체 ID를 써서 이벤트가 항상 달라지게 했다. 테스트만 바뀌었다).
- iPhone `DigiWalkerTests`(iPhone 17, iOS 27.2 시뮬레이터)에 새 알 요청 상태 판정(대기·전달됨·실패·해제, v3 캐시 버튼 숨김, 현재 개수 표시, `experience` 키 무시) 테스트를 추가했다.
- 워치 앱 테스트는 Apple Watch Series 12 46mm 시뮬레이터에서 build-for-testing + test-without-building으로 실행했다. `generic/platform=watchOS`와 `generic/platform=iOS` 빌드는 `CODE_SIGNING_ALLOWED=NO`로 확인했다(arm64_32 컴파일 포함, 설치 안 함).

### 알려진 제약
- **저장 실패 후 iPhone 요청 재시도 없음:** `transferUserInfo`는 한 번만 전달된다. 워치가 커밋에 실패하면 요청은 워치 메모리에서만 사라지고 iPhone은 다른 개체 ID를 받을 때까지 대기를 표시한다. "대기 표시 지우기" 후 다시 요청한다.
- **환생 기준점과 시계 역행:** 환생 시각은 `max(요청 시각, creditedThrough, partnerSince, enrolledAt)`(+옛 파일 폴백으로 `observedAt`)이다. `creditedThrough`는 걸음을 정산한 조회 구간의 가장 늦은 끝으로 줄지 않으며(옛 파일은 nil), 시계를 되돌려 `observedAt`이 내려가도 이미 지급한 구간을 새 개체에 다시 주지 않는다.
- **카드 없는 레거시 개체 버튼 없음:** 카드가 없거나 모르는 종(stage 없음)의 개체는 85,000걸음을 넘어도 새 알 버튼이 없다(`canStartNewEgg == false`).
- **v4라 iPhone·워치 동시 설치 필수**(앱 삭제 없이 덮어쓰기. 12-02 무료 계정 재설치와 친구 기기 2대 포함).
- **iPhone의 "전달됨" 판정:** 앱이 꺼진 사이 전송이 끝나 완료 콜백을 놓치면, 앱 시작 때 큐에 없다는 이유로 "전달됨"으로 본다. 실제로 워치가 받았는지는 새 개체 스냅샷으로만 확정된다.
- **85,000 알림 pending 기록:** 알림은 게임 파일 커밋 뒤 별도 pending 파일에 쓰므로 그 사이 앱이 종료되면 알림이 빠질 수 있다(버튼은 항상 표시되어 기능은 유지; 사용자 결정(2026-11-27): 현행 유지). 환생 후 pending 제거에 실패하면 이전 개체의 offer가 다시 뜰 수 있으나 대상 ID가 일치하지 않아 무시된다.
- **iPhone 취소와 재전송:** 취소는 시스템 큐에서 해당 전송을 찾아 실제로 취소했을 때만 기록을 지운다. 찾지 못하거나 세션이 활성이 아니면 이미 워치로 갔을 수 있어 "전달됨"으로 남기고 "대기 표시 지우기"만 가능하다. 전송 직전 `preparing`으로 저장하므로 그 사이 종료되면 다음 활성화 때 같은 요청 ID·대상으로 다시 보낸다(워치는 대상 ID 기준 멱등).

### 미검증(실기기 필요)
- 85,000걸음 도달 시 워치 알림과 알림 동작 버튼("새 알 키우기"/"궁극체 유지")이 long-look에서 실제로 보이는지, `.foreground` 동작으로 앱이 열려 확인 창이 뜨는지.
- 환생 실행, iPhone 요청 → 워치 적용, 연결 끊김 중 대기 표시와 재연결 후 전달, `transferUserInfo`로 워치 앱이 백그라운드에서 깨어나는 시점과 빈도(`WKWatchConnectivityRefreshBackgroundTask` 처리).
- 기존 실기기 파일(경험치 포함, `itemUses`·`generation` 없음)이 손상 판정 없이 읽히는지, 화면에서 Lv/XP가 사라졌는지, 컴플리케이션 문구와 개체 교체 시 갱신.
- iPhone 화면(버튼·확인창·대기 문구) 육안 확인(스크린샷 미촬영). 85,000걸음은 시뮬레이터 단위 테스트로 대신했다.

## iPhone 위젯(홈 화면 small·잠금 화면 3종) · 2026-11-28

계획서 `local-notes/plans/20261127-iphone-widget.md`의 1~7단계. 7단계 실기기 확인은 아래 "실기기 확인 (2026-11-28)"에 적었다.

### 구조
- **확장 타깃:** `DigiWalker Phone Widgets`(번들 ID `ty.park.DigiWalker.widgets`, iOS 18.0). 지원 크기는 systemSmall, accessoryCircular, accessoryRectangular, accessoryInline이고 kind는 `WidgetSnapshot.widgetKind`다. 위젯은 사본을 읽기만 하고 걸음을 계산하지 않는다.
- **`DigiWalker/WidgetShared/`:** 워치 위젯과 iPhone 위젯 두 확장만 컴파일하는 공용 코드(`PartnerEntry`, `PartnerProvider`, 문구 extension, `PartnerSprite`). 워치 위젯에서 옮겼고 동작은 같다.
- **코어:** `WidgetSnapshot(snapshot:receivedAt:)`로 iPhone 캐시에서 사본을 만든다(`updatedAt` = 수신 시각). 선택 필드 `offersNewEgg`가 false(스냅샷 v3 이하 캐시)이고 궁극체이면 새 알 카운트다운 대신 "최종 단계"(`Progress.finalStage`)를 보인다. 워치가 쓰는 사본에는 이 키가 없다.
- **publisher:** `PhoneWidgetPublisher`가 캐시 저장에 성공한 뒤(`PhoneSyncService.receive`)와 앱이 활성화될 때(`scenePhase == .active`, `refreshWidget()`) iPhone의 App Group 컨테이너에 `widget-snapshot.json`을 원자적으로 쓴다. 쓰기 실패는 `NSLog`만 남기고 캐시·상태·새 알 요청에 영향이 없다. 캐시 저장이 실패하거나 스냅샷이 거부되면 사본을 건드리지 않는다. 단위 테스트 실행 중에는 `InertPhoneWidgetPublisher`를 쓴다.
- **리로드 규칙:** 사본이 기존과 완전히 같으면(수신 시각 포함) 쓰지 않는다. 리로드 여부는 사본을 쓰지 않았더라도 마지막 리로드 기록(`phone-widget-reload.json`)과 비교해 판단한다. 포그라운드: 마지막 리로드 이후 바뀐 것이 있으면 항상 리로드. 백그라운드: `WidgetReloadPolicy`(종·단계·개체 변경은 즉시, 걸음만 바뀌면 30분 간격)에 더해, 수신 시각이 더 새로워졌고 30분이 지났으면 리로드. 기록 시각이 현재보다 미래(시계를 되돌림)이면 기록을 기준으로 보지 않고 한 번 리로드한 뒤 기준을 새로 잡는다. 기록 저장에 실패하면 중복 리로드 쪽으로 기운다(의도). 이 규칙은 iPhone publisher 안에만 있고 워치 `WidgetReloadPolicy`는 바뀌지 않았다.
- **개인정보:** 걸음에서 나온 문구(rectangular·small의 진행 문구, inline은 이름을 포함한 문구 전체)에 `.privacySensitive()`를 지정했다(시스템이 가림을 요청할 때 가려진다). 도트는 가리지 않고, rectangular·small의 이름도 가리지 않는다. circular의 접근성 라벨은 이름만 쓴다. 실기기 확인 뒤 현행 유지(2026-11-28).

### 갱신 한계
- 위젯은 **iPhone 앱이 워치 스냅샷을 받았을 때만** 바뀐다. 워치는 `updateApplicationContext`로 보내고, 꺼진 iPhone 앱이 이것으로 백그라운드 실행되지는 않는다고 알고 있다(실기기 미확인). 그래서 실제로는 앱을 열었을 때나 앱이 메모리에 있을 때 갱신되고 워치의 최신 걸음보다 늦을 수 있다. 위젯 설명에도 이 한계를 적었다. 동기화 방식 변경은 이번 범위 밖이다.
- small 위젯은 수신 시각을 항상 **"M/d HH:mm 수신"**(고정 24시간제)으로 보인다. 계획 F의 "오늘이 아니면 날짜"에서 바꾼 이유: 타임라인이 `.never`라 위젯이 스스로 다시 그려지지 않으므로 "오늘인지" 판정이 어제 값으로 굳는다. 12시간제 기기에서는 시각 서식이 06시와 18시를 구분하지 못할 수도 있어 `en_US_POSIX` 24시간 서식으로 고정했다.

### 서명 요구사항 (이전 기록과 달라진 점)
- 위 "워치 페이스 컴플리케이션" 절의 "iPhone 앱에는 App Group이 없다" 기록은 **이제 맞지 않는다.** iPhone 앱(`DigiWalker.entitlements`)과 위젯 확장(`DigiWalker Phone Widgets.entitlements`) 모두에 App Group `group.ty.park.DigiWalker`가 새로 생겼다. iPhone 컨테이너와 워치 컨테이너는 기기마다 따로라 같은 식별자를 써도 파일이 섞이지 않는다.
- 새 App ID `ty.park.DigiWalker.widgets`가 필요하다(무료 팀은 7일에 10개 한도). iPhone 앱 프로파일도 새로 만들어졌다.
- **프로파일 만료(서명 빌드 기준, 설치 전):** iPhone 앱 2026-12-04 23:48 KST, iPhone 위젯 확장 2026-12-04 23:48 KST(앱 14:48:34Z, 확장 14:48:30Z). 두 프로파일 모두 application-groups `group.ty.park.DigiWalker`와 ProvisionedDevices 4대가 있다. 설치 전이므로 설치 후 기기에 실제 적용된 만료일은 다시 기록해야 한다. 워치 쪽 만료(2026-12-03 20:06 KST)는 그대로다. 이 iPhone 빌드를 설치하기 전까지 기기의 iPhone 앱 만료는 2026-12-02 09:35 KST(이전 기록)다.

### 위젯 넣는 방법
- 홈 화면을 길게 눌러 + → DigiWalker → small. 잠금 화면은 길게 눌러 사용자화 → 위젯 칸에서 DigiWalker(원형·직사각형·한 줄).

### 검증한 환경
- 코어 `swift test` 238개 통과.
- iPhone 17 시뮬레이터 `DigiWalkerTests` 통과(`PhoneWidgetPublisherTests` 13개 포함: 첫 쓰기, 동일 캐시 생략, 포그라운드 수신 시각 변경, 백그라운드 30분 간격, 보류된 리로드의 포그라운드 실행, 수신 시각만 바뀐 경우, 종 변경 즉시 리로드, 손상된 사본, 컨테이너 없음, 쓰기 실패, 미래 기록, 기록 파일 없음 등).
- 워치 시뮬레이터(Series 11 46mm) `DigiWalker Watch AppTests` 통과(회귀).
- `generic/platform=iOS -allowProvisioningUpdates` 서명 빌드 성공. 앱과 확장 양쪽의 엔타이틀먼트에 App Group이 있고 확장 번들에 `PrivateAssets`가 들어 있다. 설치하지 않았다.

### 실기기 확인 (2026-11-28)
- 본인 iPhone 16 Pro Max(`618c5f0` 설치, 프로파일 만료 2026-12-04 23:48 KST)와 본인 Apple Watch Ultra 2(`07f6c48`)에서 사용자가 확인했다: 홈 화면 small과 잠금 화면 3종 추가, 도트 크기·잘림 없음, 이름·진행 문구, "M/d HH:mm 수신", 워치에서 걸은 뒤 iPhone 앱을 열면 위젯 갱신, 잠금 화면 표시. 사용자 평가: "잘됩니다. 확인사항 모두 만족합니다."
- 잠금 화면 `privacySensitive` 가림: 실기기 확인 뒤 현행 유지(사용자가 확인 사항 모두 만족).
- 아직 측정하지 않은 것: 앱을 열지 않았을 때의 갱신 지연, 친구 기기.

### 미검증 (실기기 확인 뒤 남은 것)
- 사용자가 확인한 것(위 절): 정상 상태의 도트 크기·잘림, 이름·진행 문구, 수신 시각, 앱을 열 때 갱신, 잠금 화면 표시와 가림 동작 수용.
- 확인하지 않은 상태와 모드: 사본 없음·v3 캐시 "최종 단계" 문구, 다크·틴트·클리어 홈 화면.
- **포그라운드 리로드 예산:** "포그라운드 앱의 리로드 요청은 예산에 들어가지 않는다"는 Apple 문서 기반이며 원문을 다시 확인하지 않았다.
- **백그라운드 전달 지연:** 앱을 열지 않았을 때 위젯이 얼마나 늦는지.
- 잠금 상태(재부팅 후 첫 잠금 해제 전)에서 App Group 파일 읽기, 위젯 확장 메모리 한도.
- 친구 기기.

## QR 친선 배틀(iPhone) · 2026-11-28
친구와 QR로 하는 친선전이다. 보상·전적·횟수 제한이 없고 디지몬·걸음·도감·아이템·캐시를 바꾸지 않는다. 요구사항은 `local-notes/기능/배틀.md`, 계획은 `local-notes/plans/20261128-friendly-battle.md`다. 워치 코드와 스냅샷 v4는 바꾸지 않았다.

### 구조
- **코어 `Packages/DigiWalkerCore/Sources/DigiWalkerCore/Battle/`**(플랫폼 독립, 난수 주입 가능)
  - `BattleCard.swift`: `SpeciesCatalog.battleStage(of:)`, QR 페이로드 `BattleCard`(인코드·디코드·검증).
  - `BattleRules.swift`: `BattleMove`, `BattleRules.judge`, 난수 함수, `BattleSession`.
  - `BattleRoster.swift`: 도감과 현재 파트너에서 배틀 가능한 디지몬 목록(`BattleRoster`), 단계 맞추기(`BattleMatch`).
- **앱 `DigiWalker/DigiWalker/`**: `BattleFlow.swift`(상태 모델: 스캔 처리, 매칭, 세 판 수집, 다시 하기, 캐시 갱신), `BattleView.swift`(배틀하기 화면, 내 QR, 도감에서 바꾸기, 같은 단계 고르기), `BattleArenaView.swift`(마주 보는 도트, 고르기, 결과), `BattleQRImage.swift`(CoreImage, payload별 캐시), `BattleScannerView.swift`(VisionKit `DataScannerViewController`, 권한·지원 판단 `BattleCameraAccess`).
- **진입점:** `ContentView.swift`의 "아이템 · 보유 종류" 바로 아래 "배틀하기"(식별자 `battleLink`).
- **카메라 권한:** iPhone 앱 Debug·Release에 `INFOPLIST_KEY_NSCameraUsageDescription = "친구의 배틀 QR 코드를 읽을 때 카메라를 사용합니다."`. 워치 타깃에는 없다.
- **엔타이틀먼트·프로파일 변경 없음:** 서명 빌드의 앱 엔타이틀먼트는 App Group `group.ty.park.DigiWalker`와 `get-task-allow`뿐이고 새 App ID도 필요 없었다. 프로파일 만료는 위젯 절의 기록과 같다(iPhone 앱 2026-12-04 23:48 KST).
- **DEBUG 전용:** QR 문자열 입력칸 + "붙여넣기로 입력", 내 QR 문자열 표시 + "복사". Release 시뮬레이터 빌드의 실행 파일에 이 문구가 없음을 확인했다(Debug에는 있음).

### QR 형식과 검증
- 형식(ASCII만): `digiwalker-battle:1?s=<종 ID>&t=<단계>&n=<퍼센트 인코딩 이름>`. 형식 버전·종·이름·단계만 담고 걸음·거리·개체 ID는 없다.
- 검증 순서: 길이 512바이트 이하(`tooLong`) → 접두사(`notBattleCode`) → **버전**(`unsupportedVersion`) → 구조(`?` 뒤 키가 s·t·n뿐이고 중복·누락 없음, `malformed`) → 종 ID 형식·카탈로그(`unknownSpecies`) → 디지타마(`egg`) → 카드 단계 없는 종(포요몬, `notEligible`) → 단계가 한 자리 숫자이고 카탈로그와 같음(`stageMismatch`) → 이름(`malformed`).
- **버전을 구조보다 먼저 읽는다.** 계획서 순서와 다르다. 앞으로 형식이 바뀌어 키·구분자가 달라져도 "구조가 깨짐"이 아니라 "앱을 최신으로"로 안내하기 위해서다. 버전은 `digiwalker-battle:` 뒤의 앞쪽 숫자만 읽으므로 `2/...`·`2:...`·`2`(물음표 없음)도 `unsupportedVersion`이다. 버전 1인데 `?`가 없으면 `malformed`.
- 이름: 인코더가 쓰는 문자(알파벳·숫자·`-._~`)와 올바른 `%HH`만 받는다. 원문에 비ASCII·공백·`#`·깨진 이스케이프가 있으면 거부한다. 디코딩한 이름은 앞뒤 공백을 다듬고, 비었거나 32자 초과, 제어·서식(Cf)·줄/문단 구분(Zl, Zp) 문자가 있으면 거부한다. 이름이 카탈로그 이름과 달라도 받아들이고 화면에는 내 기기 이름을 쓴다.
- `BattleCard.init?`은 인코딩 결과가 512바이트를 넘는 이름이면 nil이다(만들 수 있는 카드는 항상 디코딩된다).

### 판정과 진행
- 공격 대 공격: 수치가 큰 쪽 승. 방어 대 방어: 수치와 상관없이 무승부. 공격 대 방어: 공격 수치가 크면 "크리티컬"로 공격 승, 방어 수치가 크면 "반격"으로 방어 승. 수치가 같으면 QR을 찍은 쪽(이 기기의 사용자) 승이고, 문구는 이긴 내 행동을 따른다(공격이면 크리티컬, 방어면 반격, 공격끼리는 문구 없음).
- 상대 패턴(공/방 + 0~100 세 개)은 이 기기가 배틀을 시작할 때 난수로 만든다. 같은 QR로 다시 하면 새 배틀이다. 내 수치는 공격·방어를 고르는 순간 0~100으로 뽑는다.
- **세 판 수집:** 처음 세 판의 선택을 모두 받은 뒤에 차례로 판정한다(결정 7). 그 전에는 결과가 나오지 않는다. 2:0이 되어도 셋째 선택은 받는다. 승부가 이미 난 뒤의 판은 판정에 넣지 않고, 결과 요약에 "3판 — (승부 결정 후)"와 내가 고른 행동·수치만 보인다.
- 세 판이 끝나도 승부가 나지 않으면(예: 1:1) "아직 승부가 나지 않았어요 — 한 판 더!"와 현재 전적을 보이고 한 판씩 추가로 고른다. 상대 패턴은 처음부터 다시 쓴다. 판 수 제한은 없고, 방어끼리 비기면 공격을 권하는 힌트를 보인다.
- 결과 화면: 승패, 판별 요약(예: "1판 크리티컬! 승", "3판 반격… 패"), 작은 글씨로 두 쪽 수치. 버튼은 "다시 하기"(같은 상대·같은 내 디지몬, 새 패턴)와 "끝내기". 막힌 상태(알)이거나 고른 디지몬이 로스터에서 사라졌으면 "다시 하기"는 새 배틀 대신 로비로 돌아간다.
- **단계 맞추기:** 같은 단계면 바로 배틀, 내가 낮으면 도감의 같은 단계 디지몬을 고르고(없으면 "같은 단계의 디지몬이 없어요"), 내가 높으면 "상대가 같은 단계의 디지몬으로 QR을 다시 만들어야 해요". 고른 디지몬은 이번 배틀에만 쓴다.
- **로스터 선택:** 사용자가 직접 고르기 전에는 "내 디지몬"이 현재 파트너를 따라간다(진화하면 QR도 바뀐다). 직접 고르면 도감에 있는 한 유지한다. 화면을 연 채로 새 캐시가 오면 로스터를 다시 계산하고, 이미 시작한 배틀은 그대로 둔다.

### 계획 검토 결정
- Q1 상대 패턴은 스캔하는 기기가 만든다. Q2 추가 판은 한 판씩. Q3 결과 화면에 수치를 작게 보임(고르는 동안은 숨김). Q4 판 수 상한 없음 + 힌트. Q5 동점 문구는 이긴 내 행동을 따름. Q6 포요몬은 배틀에서 뺌. Q8 이름 불일치는 허용하고 내 기기 이름을 씀.
- **Q7(사용자 변경):** 지금 키우는 디지몬이 디지타마이면 배틀 화면 전체를 "부화한 뒤에 배틀할 수 있어요"로 막는다(내 QR·상대 QR 찍기 모두). 코어에서는 `BattleRoster.isBlockedByEgg`와 `BattleMatch.eggBlocked`다.

### 검증한 환경 (시뮬레이터·macOS, 2026-11-28)
- 코어 `swift test` 289개 통과(새 `BattleCardTests`·`BattleRulesTests`·`BattleRosterTests` 포함).
- iPhone 17 시뮬레이터 `DigiWalkerTests` 통과(Battle 관련 새 테스트 `BattleFlowTests`·`BattleQRImageTests` 포함, 전체 통과 케이스 74개). QR 이미지를 만든 뒤 `CIDetector`로 읽어 payload와 같은지 확인했다(가장 긴 페이로드 포함, 시뮬레이터에서 동작).
- 워치 시뮬레이터 빌드 성공(회귀). `generic/platform=iOS -allowProvisioningUpdates` 서명 빌드 성공(설치하지 않음). 빌드된 `Info.plist`에 `NSCameraUsageDescription`이 있다.
- Release 시뮬레이터 빌드 성공, 실행 파일에 DEBUG 입력 문구가 없음.
- 화면 단위 렌더링 스크린샷(앱 호스트 안에서 UIWindow를 그려 저장, 실행 중인 앱 전체 흐름이 아님)으로 배틀 화면·결과·2:0 뒤 셋째 판 표시·추가 판을 확인했다. DIM 도트는 원래 왼쪽을 보므로 왼쪽의 내 도트만 좌우 반전해 서로 마주 본다(PrivateAssets가 있는 이 기기 기준).

### 실기기 확인 (2026-11-28)
- 기기: 본인 iPhone 16 Pro Max(`7a9a041` Debug 설치, 워치 연동 실데이터)와 본인 테스트폰 iPhone 15 Plus(워치 없음, `DEMO_DEX` 테스트 빌드: 도감이 가득 찬 가짜 파트너를 메모리에만 둠).
- 사용자 확인: 두 iPhone 사이 QR 서로 찍기와 배틀 진행, 내 디지몬 단계가 낮을 때 도감에서 같은 단계 고르기, "그 외 구상했던 기능들이 모두 동작". 사용자 평가: "배틀 기능은 완성입니다!"
- **테스트 빌드(`DEMO_DEX`):** `DigiWalker/DemoDex.swift`(`#if DEMO_DEX`)와 `PhoneSyncService.init`의 몇 줄. `SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG DEMO_DEX'`로 빌드할 때만 들어간다. 워치 캐시가 없을 때만 아구몬(성장기, 20,000걸음)과 카드 전 종 도감(183/184)을 메모리에 만든다. 일반 Debug·Release 빌드에는 없다.

### 알려진 제약 (사용자 결정 2026-11-28: 현행 커밋)
- **고르기 창이 열린 동안 진화:** 상대 QR을 찍고 도감 고르기 창이 열려 있는 사이 내 디지몬이 상대보다 높은 단계로 진화해도 창이 그대로 남아, 원래라면 "상대가 QR을 다시 만들어야 해요"로 막혀야 할 배틀을 시작할 수 있다.
- **스캐너가 열린 동안 새 알:** 카메라 시트는 닫히지 않는다. 다만 찍어도 `handleScanned`가 막아 배틀은 시작되지 않는다.
- **카메라 제한(`.restricted`):** 스크린 타임 등으로 제한된 경우에도 "설정 열기"를 안내한다(앱 권한 스위치로는 풀 수 없음).
- **PrivateAssets가 없는 빌드:** 내 쪽 도트를 좌우 반전하므로 물음표 대체 아이콘도 뒤집혀 보인다.
- 모두 보상 없는 친선전이라 육성 데이터에는 영향이 없다. 실기기에서 보고 필요하면 고친다.

### 미검증
- **실기기 카메라 스캔**과 VisionKit `payloadStringValue`가 ASCII QR을 그대로 돌려주는지.
- **두 기기 간 QR 교환**(서로 찍기, 친구 기기). 친구 기기 설치 때 한 번에 확인한다.
- **실행 중인 앱에서의 전체 흐름:** 스캔 시트가 닫힌 뒤 고르기 시트·아레나 push가 이어지는 동작, push된 상태에서 새 캐시가 올 때의 `onChange`. 이 흐름은 상태 모델(`BattleFlowTests`)로만 검증했다.
- **저장소 PNG 폴백 도트의 방향**(PrivateAssets가 없는 기기).
- **스캐너 실패·복구:** 시작 실패, 실행 중 카메라 불가, 설정에서 돌아온 뒤 재확인, "다시 시도". 시뮬레이터에는 카메라가 없다.
- iOS 18 런타임(설치된 시뮬레이터는 27.x).
