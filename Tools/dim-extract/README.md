# dim-extract

DIM 카드 이미지(4 MiB BIN)를 읽어 `PrivateAssets/dim/<speciesId>.png` 시트(프레임 가로 한 줄)로 쓰는 개발자용 macOS 도구다. 읽기 전용이며 BIN을 수정하거나 카드에 쓰지 않는다.

- BIN은 제3자 저작물이다. `PrivateSources/dim-bin/`(git 제외, 앱 번들 비포함)에 두고 커밋하지 않는다. 출력도 `PrivateAssets/`(git 제외)에만 쓴다.
- 지원 카드는 코어 `SpeciesCatalog.cards`(EX 카드 11장)이며 `--help`의 usage에 같은 목록이 나온다. 카드·슬롯·프레임 규격은 `DigiWalkerCore`(`SpeciesCatalog`, `EvolutionCard`)가 단일 출처다.
- 사용법과 정책은 `PrivateAssets/README.md`의 "BIN에서 시트 만들기"를 본다. 옵션: `--bin --card --out [--dry-run] [--force] [--allow-hash-mismatch] [--transparent-key 0x07E0] [--only <speciesId>]`.
- 테스트: `swift test --package-path Tools/dim-extract` (합성 데이터만 사용).
