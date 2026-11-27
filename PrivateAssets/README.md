# PrivateAssets

개인용 에셋을 두는 폴더입니다. 이 README와 `.gitkeep`을 제외한 모든 파일은 gitignore 대상입니다.

**타사 IP의 이미지나 도트 데이터를 이 폴더 밖으로 옮기거나 커밋하지 마세요.**

## JSON 스프라이트 팩 (기존)

개인용 에셋 팩(JSON 스프라이트 데이터)은 `pack.json`으로 둡니다. 포맷은 `docs/DESIGN.md` §8을 참고하세요. 팩 파일이 없으면 앱은 `Assets/StarterPack/`을 사용합니다.

## DIM 시트 (`dim/<speciesId>.png`)

DIM Modifier에서 정상적으로 내려받은 시트를 `PrivateAssets/dim/<speciesId>.png`로 넣으면 두 앱(iPhone, Apple Watch)과 두 위젯 확장(워치 컴플리케이션, iPhone 위젯 — 각 번들에 복사됨)이 해당 종을 그 도트로 그립니다. 없는 종은 저장소 PNG(디지타마·깜몬·푸니몬·포요몬) 또는 `?` 플레이스홀더로 표시됩니다. 일부만 넣어도 됩니다.

- **원본 그대로** 넣으세요. 다시 저장하거나 리사이즈하거나 배경을 지우지 마세요. 앱이 실행 중에 프레임을 잘라 씁니다. DIM 카드 BIN에서 `Tools/dim-extract`로 변환한 시트도 됩니다(픽셀 크기·프레임 순서 보존, 투명 키 색만 알파 0).
- 파일을 추가하거나 바꾼 뒤에는 **앱을 다시 빌드해 설치**해야 합니다(폴더가 앱 번들에 복사됩니다. 워치 컴플리케이션 위젯과 iPhone 위젯 확장 번들에도 복사됩니다).
- 분할 규칙: 이미지 크기가 프레임 크기로 나누어떨어져야 하고, 프레임은 왼쪽에서 오른쪽, 위에서 아래(행 우선) 순서입니다. 칸이 모자라거나 크기가 맞지 않으면 그 종은 플레이스홀더로 떨어집니다(크래시 없음). 프레임 수의 2배를 넘는 칸이 있는 시트도 거부합니다.
- 대기(idle) 프레임은 0번과 1번이라고 **가정**합니다(실제 시트로 확인하지 못했습니다). 0.5초 간격으로 번갈아 표시합니다.
- 두 카드에 모두 나오는 `algomon_adult`, `omegamon`, `botamon`, `susanoomon`은 파일 하나만 두며, 기준 출처는 카드 순서상 먼저인 카드(앞 셋은 `agu_ex`, `susanoomon`은 `agni_ex`) 시트입니다.
- 출처와 이용 조건은 `docs/ASSET_SOURCES.md`를 참고하세요.

### BIN에서 시트 만들기

BIN(DIM Modifier 카드 템플릿 페이지의 "Download 4 MiB BIN")은 `PrivateSources/dim-bin/`에 둡니다. 이 폴더는 `PrivateAssets/` 밖이라 앱 번들에 들어가지 않고 git에서도 제외됩니다. **BIN을 `PrivateAssets/` 아래에 두지 마세요**(폴더 전체가 두 앱에 복사됩니다).

```
swift build -c release --package-path Tools/dim-extract
X="$(swift build -c release --package-path Tools/dim-extract --show-bin-path)/dim-extract"
"$X" --bin "PrivateSources/dim-bin/Agumon · Variant 1.bin" --card agu_ex --out PrivateAssets/dim --dry-run
```

- `--dry-run`을 빼면 파일을 씁니다. 이미 있는 파일은 건너뛰며 `--force`일 때만 덮어씁니다.
- 카드는 11장(`agu_ex`, `gabu_ex`, `guil_ex`, `terrier_ex`, `rena_ex`, `agni_ex`, `fairi_ex`, `chack_ex`, `wolf_ex`, `blitz_ex`, `louwe_ex`; 또는 카탈로그 카드 id)입니다. 공유 종은 기준 카드에서만 쓰고 다른 카드에서는 건너뜁니다(`wolf_ex`는 `botamon`, `susanoomon` 2개 건너뜀).
- BIN의 SHA-256 앞 16자가 카드 id와 다르면 중단합니다. 내용을 확인한 뒤에만 `--allow-hash-mismatch`를 쓰세요. `guil_ex`와 새 8장(`terrier_ex`~`louwe_ex`)의 BIN은 모두 카탈로그 id와 해시가 달라 이 옵션이 필요했습니다(헤더 dimId·구조는 일치, 근거는 `docs/ASSET_SOURCES.md`).
- 규격이 코어와 다르면 아무것도 쓰지 않고 실패합니다.

카드 id는 DIM 카탈로그의 카드 id입니다. 아래 표는 기존 3장입니다. 새 8장은 카드 단위로만 요약하고, 종·index 목록은 코어 `Packages/DigiWalkerCore/Sources/DigiWalkerCore/Growth/EvolutionCard.swift`를 보세요. 규격은 `프레임 너비×높이×프레임 수`입니다.

| 파일 | 종 (표시명 가안) | 단계 | 카드 / index | 규격 |
| --- | --- | --- | --- | --- |
| `botamon.png` | 깜몬 (Botamon) | 0 | `agu_ex` / 0 | 32×24×5 |
| `koromon.png` | 코로몬 (Koromon) | 1 | `agu_ex` / 1 | 32×24×5 |
| `agumon.png` | 아구몬 (Agumon) | 2 | `agu_ex` / 2 | 64×56×12 |
| `greymon.png` | 그레이몬 (Greymon) | 3 | `agu_ex` / 3 | 64×56×12 |
| `coelamon.png` | 실라몬 (Coelamon) | 3 | `agu_ex` / 4 | 64×56×12 |
| `ogremon.png` | 오거몬 (Ogremon) | 3 | `agu_ex` / 5 | 64×56×12 |
| `algomon_adult.png` | 알고몬(성숙기) (Algomon (Adult)) | 3 | `agu_ex` / 6 | 64×56×12 |
| `metalgreymon_vaccine.png` | 메탈그레이몬(백신) (Metal Greymon (Vaccine)) | 4 | `agu_ex` / 7 | 64×56×12 |
| `andromon.png` | 안드로몬 (Andromon) | 4 | `agu_ex` / 8 | 64×56×12 |
| `anomalocarimon.png` | 아노말로카리몬 (Anomalocarimon) | 4 | `agu_ex` / 9 | 64×56×12 |
| `mamemon.png` | 마메몬 (Mamemon) | 4 | `agu_ex` / 10 | 64×56×12 |
| `neodevimon.png` | 네오데블몬 (Neo Devimon) | 4 | `agu_ex` / 11 | 64×56×12 |
| `metaltyranomon.png` | 메탈티라노몬 (Metal Tyranomon) | 4 | `agu_ex` / 12 | 64×56×12 |
| `wargreymon.png` | 워그레이몬 (War Greymon) | 5 | `agu_ex` / 13 | 64×56×12 |
| `omegamon.png` | 오메가몬 (Omegamon) | 5 | `agu_ex` / 14 | 64×56×12 |
| `blitzgreymon.png` | 블리츠그레이몬 (Blitz Greymon) | 5 | `agu_ex` / 15 | 64×56×12 |
| `donedevimon.png` | 돈데블몬 (Done Devimon) | 5 | `agu_ex` / 16 | 64×56×12 |
| `punimon.png` | 푸니몬 (Punimon) | 0 | `gabu_ex` / 0 | 32×24×5 |
| `tsunomon.png` | 쯔노몬 (Tsunomon) | 1 | `gabu_ex` / 1 | 32×24×5 |
| `gabumon.png` | 파피몬 (Gabumon) | 2 | `gabu_ex` / 2 | 64×56×12 |
| `garurumon.png` | 가루몬 (Garurumon) | 3 | `gabu_ex` / 3 | 64×56×12 |
| `gorimon.png` | 고리몬 (Gorimon) | 3 | `gabu_ex` / 4 | 64×56×12 |
| `dokugumon.png` | 도쿠구몬 (Dokugumon) | 3 | `gabu_ex` / 5 | 64×56×12 |
| `weregarurumon.png` | 워가루몬 (Were Garurumon) | 4 | `gabu_ex` / 7 | 64×56×12 |
| `parrotmon.png` | 패럿몬 (Parrotmon) | 4 | `gabu_ex` / 8 | 64×56×12 |
| `valvemon.png` | 밸브몬 (Valvemon) | 4 | `gabu_ex` / 9 | 64×56×12 |
| `bigmamemon.png` | 빅마메몬 (Big Mamemon) | 4 | `gabu_ex` / 10 | 64×56×12 |
| `orochimon.png` | 오로치몬 (Orochimon) | 4 | `gabu_ex` / 11 | 64×56×12 |
| `waruseadramon.png` | 와루시드라몬 (Waru Seadramon) | 4 | `gabu_ex` / 12 | 64×56×12 |
| `metalgarurumon.png` | 메탈가루몬 (Metal Garurumon) | 5 | `gabu_ex` / 13 | 64×56×12 |
| `cresgarurumon.png` | 크레스가루몬 (Cres Garurumon) | 5 | `gabu_ex` / 15 | 64×56×12 |
| `nidhoggmon.png` | 니드호그몬 (Nidhoggmon) | 5 | `gabu_ex` / 16 | 64×56×12 |
| `jyarimon.png` | 쟈리몬 (Jyarimon) | 0 | `guil_ex` / 0 | 32×24×5 |
| `gigimon.png` | 지지몬 (Gigimon) | 1 | `guil_ex` / 1 | 32×24×5 |
| `guilmon.png` | 길몬 (Guilmon) | 2 | `guil_ex` / 2 | 64×56×12 |
| `siesamon.png` | 시사몬 (Siesamon) | 3 | `guil_ex` / 3 | 64×56×12 |
| `growmon_orange.png` | 그라우몬(오렌지) (Growmon (Orange)) | 3 | `guil_ex` / 4 | 64×56×12 |
| `growmon.png` | 그라우몬 (Growmon) | 3 | `guil_ex` / 5 | 64×56×12 |
| `devidramon.png` | 데블드라몬 (Devidramon) | 3 | `guil_ex` / 6 | 64×56×12 |
| `vajramon.png` | 바즈라몬 (Vajramon) | 4 | `guil_ex` / 7 | 64×56×12 |
| `majiramon.png` | 마지라몬 (Majiramon) | 4 | `guil_ex` / 8 | 64×56×12 |
| `mihiramon.png` | 미히라몬 (Mihiramon) | 4 | `guil_ex` / 9 | 64×56×12 |
| `megalogrowmon_orange.png` | 메가로그라우몬(오렌지) (Megalo Growmon (Orange)) | 4 | `guil_ex` / 10 | 64×56×12 |
| `megalogrowmon.png` | 메가로그라우몬 (Megalo Growmon) | 4 | `guil_ex` / 11 | 64×56×12 |
| `sandiramon.png` | 산디라몬 (Sandiramon) | 4 | `guil_ex` / 12 | 64×56×12 |
| `dukemon.png` | 듀크몬 (Dukemon) | 5 | `guil_ex` / 13 | 64×56×12 |
| `dukemon_x.png` | 듀크몬 X (Dukemon X) | 5 | `guil_ex` / 14 | 64×56×12 |
| `megidramon.png` | 메기드라몬 (Megidramon) | 5 | `guil_ex` / 15 | 64×56×12 |
| `dukemon_crimson.png` | 듀크몬 크림슨모드 (Dukemon: Crimson Mode) | 5 | `guil_ex` / 16 | 64×56×12 |

카드: `agu_ex` = Agumon EX (`04c5dc576a34887b`), `gabu_ex` = Gabumon EX (`5e133fc75fc90377`), `guil_ex` = Guilmon EX (`23d5bc7093090fc5`).

새 8장 요약(2026-11-26 추가, 모두 DIM 카탈로그 `variant` 없음, 슬롯 17개, stage 0·1은 32×24×5, stage 2~5는 64×56×12). 기존 `botamon.png`와 `susanoomon.png`를 재사용하므로 파일은 카드마다 17개, `wolf_ex`는 15개입니다. 합계 `PrivateAssets/dim/*.png` 183개입니다.

| 카드 | chartId | 카탈로그 id | 새 파일 수 | 공유 종 |
| --- | --- | --- | --- | --- |
| Terriermon EX | `terrier_ex` | `b8a262b73a584fa2` | 17 | 없음 |
| Renamon EX | `rena_ex` | `ebec1fb5584f9ccc` | 17 | 없음 |
| Agnimon | `agni_ex` | `ffffde3475e68d8e` | 17 | `susanoomon`(기준 카드, wolf_ex와 공유) |
| Fairimon | `fairi_ex` | `ad95fda80f528ee8` | 17 | 없음 |
| Chackmon | `chack_ex` | `8160a04f17b7e759` | 17 | 없음 |
| Wolfmon | `wolf_ex` | `2661974b34f571f5` | 15 | `botamon`(agu_ex 기준), `susanoomon`(agni_ex 기준) |
| Blitzmon | `blitz_ex` | `a5735c0f13f86ae3` | 17 | 없음 |
| Louwemon | `louwe_ex` | `10ab04bac23563d0` | 17 | 없음 |
