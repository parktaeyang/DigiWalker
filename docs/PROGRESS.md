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
- **무작위 진화:** 500걸음에 디지타마가 Agumon EX, Gabumon EX, Guilmon EX 중 한 카드를 같은 확률로 골라 그 카드의 stage 0이 된다. 이후 500걸음(1000·1500·2000·2500·3000)마다 같은 카드의 다음 stage 후보 중 하나로 무작위 진화하고 stage 5에서 멈춘다. 한 번의 정산으로 여러 임계값을 넘으면 단계마다 따로 뽑는다. 원작 진화 경로가 아니라 앱 고유 규칙이다. 오메가몬은 무작위 후보에서 제외했다(조그레스는 설계만 했고 구현하지 않았다). 개체 ID·원장·XP·거리는 보존한다.
- **도감:** 워치 상태 파일(`game-state.json`)에 몬스터·원장과 함께 원자적으로 저장한다. 만난 종·처음 확인한 시각·그때의 누계를 기록한다(디지타마 포함). 깨진 도감(중복·빈 ID·음수 걸음, 카드가 있는데 비었거나 없음)은 손상 저장으로 보고 디코딩이 실패하며 기존 파일은 보존한다.
- **스냅샷 v2:** `dex`와 `monster.cardId`를 포함한다. iPhone은 v1과 v2를 받고 v3 이상, dex 검증에 실패한 v2, dex가 붙은 v1은 거부한다. v1 캐시에서는 도감 대신 현재 파트너 한 줄과 동기화 안내를 표시한다.
- **마이그레이션:** 워치 로드 경로에서 `migrateLegacyStarter()` 뒤에 `migrateToEvolutionCatalog()`를 호출하고 저장에 성공한 뒤에만 반영한다. 깜몬은 `agu_ex`, 푸니몬은 `gabu_ex`로 배정하고 누계에 맞게 진화한다. **포요몬은 새 알로 재배정**한다(카드를 무작위로 골라 stage 0부터 누계만큼 진화, 도감에는 디지타마·포요몬·새 종을 기록). 알 수 없는 종은 그대로 두고 도감에 현재 종만 넣는다.
- **도트 표시:** `PrivateAssets/dim/<speciesId>.png`의 DIM 시트를 실행 중에 잘라(`SheetSlicing`) 대기 프레임을 정수 배율·최근접 보간으로 그린다. 없으면 저장소 PNG(디지타마·깜몬·푸니몬·포요몬), 그것도 없으면 `?` 플레이스홀더다. iPhone 타깃에도 PrivateAssets 폴더 참조를 추가했다.
- **UI:** 워치는 부화·진화 알림과 "다음 진화까지 N걸음"·구간 진행바를 표시한다. iPhone은 `도감 · n / N`(기본 50, 포요몬을 만났으면 51) 화면을 제공하고 미발견 종은 `???`로 가린다.
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

