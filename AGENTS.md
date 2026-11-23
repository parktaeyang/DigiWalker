# DigiWalker 개발 규칙

- 개인용 iPhone + Apple Watch 프로토타입이다. v1.1 설계와 단계별 범위는 `local-notes/docs/Digital_Monster_Walker_Design_v1.1.md`와 `local-notes/docs/Codex_CLI_Instruction_v1.1.md`를 기준으로 한다. 실제 구현 결과와 미검증 사항은 `docs/PROGRESS.md`에 기록한다.
- Xcode 프로젝트는 `DigiWalker/DigiWalker.xcodeproj`다. SwiftUI 타깃은 iOS 18 및 watchOS 11 이상을 지원한다. 플랫폼 독립 모델과 성장 규칙은 두 타깃이 참조하는 `Packages/DigiWalkerCore`에 둔다.
- 워치가 육성 원본을 소유한다. 사용자 요청 시 걸음 수 및 걷기·달리기 거리 읽기 권한을 요청한다. 건강 데이터를 쓰거나 다른 출처의 걸음 수를 직접 합산하지 않는다. 읽기 거부와 기록 부재는 구분할 수 없으므로 안내 문구에 반영한다.
- 등록 시각 이후의 걸음만 지급한다. 등록 당시의 정산 시간대와 일별 최고 인정량을 보존한다. 100걸음마다 10 XP, 누적 250 XP마다 1레벨이다. 거리·감소한 측정값·같은 구간 재조회는 추가 XP를 만들지 않는다.
- 첫 파트너는 디지타마로 시작한다. 날짜별 인정 걸음의 누계가 500 이상인 첫 정산에서 유년기 I 한 종을 무작위로 선택한다. 개체 ID, 원장, XP와 부화 결과를 함께 유지한다.
- 워치 정산은 직렬화하고 후보 원장과 몬스터를 한 파일에 원자적으로 저장한 뒤 최신 스냅샷을 발행한다. 읽기·쓰기 실패 시 기존 파일을 보존한다. iPhone은 스키마·개체 세대·revision을 확인한 뒤 캐시와 수신 시각을 표시한다.
- 스프라이트는 DIM Modifier에서 개별 자료의 다운로드 방법과 이용 조건을 확인하고 `docs/ASSET_SOURCES.md`에 기록한다. 제3자 개인용 자료는 git에서 제외되는 `PrivateAssets/`로 관리한다. 프로젝트에 포함하는 기본 PNG는 저장소 오리지널 에셋을 사용한다. 픽셀 크기·알파·프레임 순서를 유지하고 정수 배율과 최근접 보간으로 표시한다.
- 변경 후 `swift test --package-path Packages/DigiWalkerCore`와 해당 앱 스킴의 시뮬레이터 빌드를 실행한다. HealthKit 실측, 페어링 복귀, 재실행 결과는 실제로 검증한 환경을 명시한다.
