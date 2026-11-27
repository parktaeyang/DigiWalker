# 몬스터 도트 출처

## 아구몬 후보 · 2026-11-23 확인

- DIM Modifier 공개 카탈로그의 **25th Anniversary** BEM 카드, 슬롯 인덱스 2, Agumon. 카탈로그의 작성자 표기는 `Official`이며 개별 도트 작가 이름은 표시되지 않는다. [갤러리](https://dim.digitallink.games/resources?category=digimon) · [카탈로그](https://dim.digitallink.games/catalog/card-catalog.json)
- 카탈로그는 원본 12프레임, 프레임당 64×56을 명시한다. 카탈로그에 연결된 PNG 미리보기 한 장이 실제로 열리며 크기가 일치한다. 공개 웹 앱에서 `Download spritesheet` 버튼은 로그인한 관리자 또는 기여자에게만 표시된다. 공개 미리보기는 단일 프레임이다. [아구몬 미리보기](https://dim.digitallink.games/catalog/sprites/843b04f90bb09dbd/02.png)
- 사이트 약관 6항은 제3자 아트의 권리가 해당 소유자에게 있다고 설명한다. 이 항목에서 별도 게임에 포함할 수 있는 개별 이용 조건을 확인하지 못해 시트 내보내기·프레임 추출·프로젝트 편입은 보류했다. [사이트 약관](https://dim.digitallink.games/terms)

## 이전 기본 파트너 도토롱

저장소 오리지널 에셋 `Assets/StarterPack/pack.json`의 `starter_acorn.animations.idle.frames`를 서로 다른 포즈가 처음 등장하는 순서대로 RGBA PNG로 변환했다. 원본 32×32, 재생 순서 0·1·0·2(서로 다른 PNG 3장), 프레임당 0.5초다. 배경 알파와 팔레트 값을 유지했다. 두 앱이 함께 사용하는 `DigiWalker/PartnerArt/Assets.xcassets/monster_idle_{0,1,2}.imageset`에 등록했다.

## 디지타마와 첫 부화 후보

디지타마, 깜몬, 푸니몬, 포요몬에 사용할 프로토타입 도트를 직접 그렸다. 각 도트는 투명 배경의 32×32 PNG 2장으로, 공유 카탈로그 `DigiWalker/PartnerArt/Assets.xcassets`에 `digitama`, `botamon`, `punimon`, `poyomon` 이름으로 등록했다. DIM Modifier 시트나 공식 도감 이미지는 복제하지 않았다. 세 종의 유년기 I 분류는 공식 도감을 참고했다. [깜몬](https://digimon.net/reference_en/detail.php?directory_name=botamon) · [푸니몬](https://digimon.net/reference_en/detail.php?directory_name=punimon) · [포요몬](https://digimon.net/reference_en/detail.php?directory_name=poyomon)

iPhone과 Apple Watch의 `AppIcon.appiconset/AppIcon.png`는 디지타마의 첫 대기 프레임(`digitama_idle_0`)을 사용한다. 원본 도트를 32배 정수 배율로 확대해 기존 연두색 배경의 1024×1024 불투명 PNG 중앙에 배치했다.

## EX 카드 11장 DIM 시트 · 2026-11-25~26 확인

카드 기반 무작위 진화(EX 카드 11장: 기존 Agumon·Gabumon·Guilmon EX와 2026-11-26에 추가한 8장)에 쓰는 도트의 출처와 취급 방침이다. 저장소에는 포함하지 않는다.

- 출처(2026-11-25 builder가 scratchpad의 `card-catalog.json`을 읽어 확인): DIM Modifier 공개 카탈로그. [카탈로그](https://dim.digitallink.games/catalog/card-catalog.json) · [갤러리](https://dim.digitallink.games/resources?category=digimon). 카탈로그에는 진화 연결 필드가 없다. 카드별 캐릭터의 `index`, `name`, `stage`(0~5), `frameWidth/frameHeight/frameCount`, `previewUrl`, `selectable`만 있다.
- 카드

| 카드 | chartId | 카드 id (동일 구성 변형 id) | dimId | 캐릭터 수 |
| --- | --- | --- | --- | --- |
| Agumon EX | `agu_ex` | `04c5dc576a34887b` (`96178a42ceefc1ce`, variant 2) | 12 | 17 |
| Gabumon EX | `gabu_ex` | `5e133fc75fc90377` (`ff890c9b22d23cc5`, variant 2) | 13 | 17 |
| Guilmon EX | `guil_ex` | `23d5bc7093090fc5` (변형 없음) | 17 | 17 |
| Terriermon EX | `terrier_ex` | `b8a262b73a584fa2` (변형 없음) | 18 | 17 |
| Renamon EX | `rena_ex` | `ebec1fb5584f9ccc` (변형 없음) | 32 | 17 |
| Agnimon | `agni_ex` | `ffffde3475e68d8e` (변형 없음) | 6 | 17 |
| Fairimon | `fairi_ex` | `ad95fda80f528ee8` (변형 없음) | 10 | 17 |
| Chackmon | `chack_ex` | `8160a04f17b7e759` (변형 없음) | 16 | 17 |
| Wolfmon | `wolf_ex` | `2661974b34f571f5` (변형 없음) | 36 | 17 |
| Blitzmon | `blitz_ex` | `a5735c0f13f86ae3` (변형 없음) | 37 | 17 |
| Louwemon | `louwe_ex` | `10ab04bac23563d0` (변형 없음) | 33 | 17 |

- 규격: 11장 모두 stage 0·1은 프레임 32×24×5, stage 2~5는 64×56×12다(index 0~16, 모두 `selectable: true`). 기존 3장의 index별 종과 파일명은 [`PrivateAssets/README.md`](../PrivateAssets/README.md)의 표에, 새 8장은 코어 `EvolutionCard.swift`에 있다. 새 8장은 Frontier 계열이라 stage 2에 종이 2개인 카드가 6장이다(스프라이트 수는 카드마다 233).
- 미리보기 URL 형식: `/catalog/sprites/<카드 id>/NN.png`. 공개 웹은 단일 프레임 미리보기만 제공한다.
- 공유 종 4개: `algomon_adult`(index 6)와 `omegamon`(index 14)은 agu_ex와 gabu_ex에, `botamon`(index 0)은 agu_ex와 wolf_ex에, `susanoomon`(index 16)은 agni_ex와 wolf_ex에 모두 있다(카탈로그 fingerprint 앞 12자가 같음). 앱은 종 ID당 파일 하나만 쓰고 기준 출처는 카드 순서상 먼저인 카드(깜몬·알고몬·오메가몬은 agu_ex, 스사노오몬은 agni_ex)의 시트다. 두 카드의 실제 시트 픽셀이 같은지는 확인하지 못했다.
- 다운로드 조건: 전체 시트의 `Download spritesheet`는 로그인한 관리자 또는 기여자에게만 보인다. 사이트 약관 6항은 제3자 아트의 권리가 해당 소유자에게 있다고 설명한다. [사이트 약관](https://dim.digitallink.games/terms)
- Humulos(`humulosUrl`의 참조 사이트): 진화표는 화살표와 조건이 그려진 안내 페이지로 다운로드 기능이 없다. 배포처가 아니며 All rights reserved 고지가 있다는 내용은 요약을 바탕으로 한 것으로 **직접 확인하지 못했다(미확인)**.
- 2026-11-25 Chrome으로 확인한 사실(위 카탈로그 조회와 별개): DIM Modifier 공식 카드 템플릿 페이지(`template/<카드 id>`)에는 로그인 없이 "Download 4 MiB BIN"(카드 전체 이미지) 버튼이 있다. 개별 스프라이트 페이지에는 프레임 미리보기만 있고 다운로드가 없다. 위의 "관리자·기여자 전용"은 `Download spritesheet`(PNG 시트) 버튼에 대한 기록이며, BIN 다운로드와는 별개다.
- 사용자가 DIM Modifier 공식 카드 템플릿 페이지의 "Download 4 MiB BIN"으로 2026-11-25에 받은 BIN 3개와 2026-11-25 23:44~23:49(KST)에 받은 BIN 8개를 `PrivateSources/dim-bin/`(git 제외, 앱 번들 비포함)에 개인용으로 보관한다. 이용 조건은 위 사이트 약관 6항(제3자 아트 권리)을 따르며 개인용·git 제외·외부 전송 금지로 취급한다.

  | 파일 | 크기 | SHA-256 앞 16자 | 카탈로그 카드 id | 일치 |
  | --- | --- | --- | --- | --- |
  | `Agumon · Variant 1.bin` | 4,194,304 | `04c5dc576a34887b` | `04c5dc576a34887b` (agu_ex) | 일치 |
  | `Gabumon · Variant 1.bin` | 4,194,304 | `5e133fc75fc90377` | `5e133fc75fc90377` (gabu_ex) | 일치 |
  | `Guilmon.bin` | 4,194,304 | `b7e5b62b8319bbd5` | `23d5bc7093090fc5` (guil_ex) | **불일치** |

  | 파일 | 수신(KST) | 크기 | 전체 SHA-256 | 카탈로그 카드 id | 일치 |
  | --- | --- | --- | --- | --- | --- |
  | `Terriermon.bin` | 11-25 23:44 | 4,194,304 | `73bdb36a06f00a3f61330622651e41eb047f2eedfef422b8d8d64e8c44017b5b` | `b8a262b73a584fa2` (terrier_ex) | **불일치** |
  | `Renamon.bin` | 11-25 23:48 | 4,194,304 | `5dd9b8fd227986729b0369b1af5e36a9b67c76a74f9621acb7031419da908653` | `ebec1fb5584f9ccc` (rena_ex) | **불일치** |
  | `Agnimon.bin` | 11-25 23:48 | 4,194,304 | `c6d1b5623392ef39545e6659f3fd98c23cd145b9c0ed3a7f7fef7d0d51bcf39e` | `ffffde3475e68d8e` (agni_ex) | **불일치** |
  | `Fairimon.bin` | 11-25 23:49 | 4,194,304 | `152e95e88fb7ba53942012e6db4b76b15413e764914745dc7429cb7282cc3fd7` | `ad95fda80f528ee8` (fairi_ex) | **불일치** |
  | `Chackmon.bin` | 11-25 23:49 | 4,194,304 | `1955688c57f8d7cd49c8560a4e1d5dac5b79047006fcd029dc1f237925eeab0f` | `8160a04f17b7e759` (chack_ex) | **불일치** |
  | `Wolfmon.bin` | 11-25 23:49 | 4,194,304 | `c312a19794fe4e9be60674739ede315a2f8da0bfb2cd2bf21438cb757f0088ea` | `2661974b34f571f5` (wolf_ex) | **불일치** |
  | `Blitzmon.bin` | 11-25 23:49 | 4,194,304 | `7e74389195cbb053cbd6c1cfff22ea613d9f30ccd4a58932d1ef4a64cd3c2494` | `a5735c0f13f86ae3` (blitz_ex) | **불일치** |
  | `Louwemon.bin` | 11-25 23:48 | 4,194,304 | `d91c16ba0794cb52c4e25e07b27a3a895ba0e9380951318cbacf793d64555793` | `10ab04bac23563d0` (louwe_ex) | **불일치** |

  - 새 8장 불일치(2026-11-26 사용자 결정으로 진행): 8장 모두 SHA-256 앞 16자가 카탈로그 카드 id와 다르고, 카탈로그 전체의 `hash` 검색에서도 맞는 카드가 없다(Guilmon과 같은 현상). 헤더 dimId(18·32·6·10·16·36·37·33), 스프라이트 수(233), 17슬롯의 stage, 프레임 규격은 코어·카탈로그와 모두 일치했다. 픽셀이 카탈로그 원본과 같은지, 원인(템플릿 페이지가 파일을 다시 만드는지)은 **확인하지 못했다.** `--allow-hash-mismatch`로 변환했다(도구는 이때도 dimId와 구조를 검사하고 하나라도 어긋나면 아무것도 쓰지 않는다). 8장의 드라이런은 기대 요약(쓰기 17, 공유 건너뜀 0, wolf_ex만 15와 2)과 일치했고, 실행 전후 기존 49개 PNG의 SHA-256은 모두 같았다.
  - Guilmon 불일치: 사이트에서 다시 받아도 같은 파일이었다(`Guilmon-2.bin`은 동일 해시). 로컬 BIN과 카탈로그 guil_ex를 대조한 결과 스프라이트 233장, 슬롯 17개의 단계·속성, 프레임 규격이 모두 일치했다. 스프라이트가 포인터 테이블 순서와 다른 순서로 저장돼 있어(오프셋이 단조 증가하지 않음) 다시 저장된 파일로 보이지만 **원인은 확인하지 못했다.** 픽셀이 카탈로그 원본과 같은지는 검증하지 못했다. 사용자가 사이트에서 다시 받는 쪽을 택했고 같은 해시의 파일이었다. 구조 대조 후 사용하기로 한 사실을 오케스트레이터가 사용자에게 알렸다. BIN 헤더 dimId(17)는 `--allow-hash-mismatch`에서도 도구가 확인한다. `--allow-hash-mismatch`로 변환했다.
- BIN→PNG 변환: `Tools/dim-extract`(저장소 추적, macOS SwiftPM)가 BIN을 읽어 `PrivateAssets/dim/<speciesId>.png`(프레임 가로 한 줄)로 쓴다. 183종을 생성했다(기존 49 = agu 17 + gabu 15 + guil 17, 새 134 = 8장 136슬롯에서 wolf_ex의 깜몬(기존 파일)과 스사노오몬(agni_ex가 기준)을 뺀 값; 공유 종은 기준 카드에서만 씀). 새 134개는 `--force` 없이 새 파일로만 썼다. 방법은 `PrivateAssets/README.md`와 `Tools/dim-extract/README.md`에 있다. 변환은 투명 키 색을 알파 0으로 바꾸는 것 외에는 픽셀을 바꾸지 않는다. RGB565→8비트는 비트 복제이며 DIM Modifier PNG 내보내기와 하위 비트가 같은지는 확인하지 못했다.
- 형식 참고(코드는 복사하지 않고 형식 정보만 사용): cfogrady, "VB DIM Format" [Gist](https://gist.github.com/cfogrady/65606fa1a58d5d3dd5c6c0411edabb38). 라이선스 표기는 확인하지 못했다. 로컬 BIN 3개와 대조해 이미지 전체 비트 NOT, 0x100040 포인터 테이블, 0x60000 크기 표, R5G6B5, 슬롯당 스프라이트 구성(이름 + 프레임 + 1단계 이상은 전체 이미지)이 맞음을 확인했다. 투명 키는 순녹색 `0x07E0`으로, 세 BIN의 모든 프레임(각 190개)에서 테두리 최빈값이었다(문서에 없는 값을 실측으로 정함).
- 취급: 사용자가 받은 카드 BIN을 `Tools/dim-extract`로 `PrivateAssets/dim/<speciesId>.png`로 변환해 둔다(위 BIN 항목 참고). 변환은 투명 키 색(`0x07E0`)을 알파 0으로 바꾸는 것 외에 픽셀 크기·순서·색을 바꾸지 않는다. 파일은 git에서 제외되며 커밋하지 않는다. 앱은 실행 중에 프레임을 잘라 쓰며 픽셀·알파를 다시 변환하지 않는다. 사용자가 직접 받은 PNG 시트를 넣는 방식도 같은 위치로 허용한다.
- **앱 고유 규칙:** 원작의 진화 경로가 아니라, 디지타마가 500걸음에 카드 11장 중 하나를 무작위로 골라 그 카드의 stage 0이 되고, 누적 5,000·15,000·30,000·50,000·75,000걸음에 같은 카드의 다음 stage 후보 중 하나로 무작위 진화한다. 오메가몬과 스사노오몬은 무작위 후보에서 제외한다(조그레스 전용, 미구현). 원작의 잠금 해제 종(`unlockRequired`: 래피드몬(아머), 사쿠야몬 X, 로드나이트몬, 다이나스몬, 무르무쿠스몬, 루체몬 폴다운모드, 기존 돈데블몬)은 원작 조건이 아니라 앱 규칙의 진화 아이템 보유를 조건으로 후보에 넣는다(2026-11-26 사용자 결정, "진화 아이템 이름 출처" 참고). 새 134종의 한국어 표시명은 가안(`nameVerified = false`)이다.
- 대기 프레임을 0·1번으로 가정했으나 실제 시트에서 **확인하지 못했다(미확인)**.
- 포요몬과 토코몬은 이 11장에 없다. 그래서 포요몬은 신규 부화 후보에서 제외했다(기존 포요몬 상태는 새 카드로 재배정). 저장소 PNG `poyomon`은 이전 파트너 표시용으로만 남는다.
- **위젯 확장 번들(2026-11-26):** 워치 페이스 컴플리케이션용 위젯 확장 `DigiWalker Widgets`의 Copy Bundle Resources에도 `PrivateAssets` 폴더 참조가 들어가서, 변환한 DIM PNG(183개, 약 2.1MB)가 워치 앱 번들 안의 확장에도 복사된다. 앱 본체의 복사본과 별개로 한 벌이 더 생기며 친구 기기에 설치하는 빌드에도 포함된다(친구 기기 포함은 2026-11-25 사용자 결정). git 제외 규칙은 바뀌지 않았다. 위젯 갤러리·플레이스홀더 미리보기는 저장소 오리지널 그림(디지타마 등 `PartnerArt/Assets.xcassets`)만 쓴다. 위젯 갤러리 미리보기에 DIM 그림이 노출되지는 않지만, 실제 컴플리케이션에는 현재 종의 대기 프레임 0번이 표시된다.
- **iPhone 위젯 확장 번들(2026-11-28):** iPhone 위젯 확장 `DigiWalker Phone Widgets`의 Copy Bundle Resources에도 같은 `PrivateAssets` 폴더 참조가 들어가서, 변환한 DIM PNG(183개, 약 2.1MB)가 iPhone 앱 번들 안의 확장에도 복사된다. 앱 본체·워치 쪽 복사본과 별개로 한 벌이 더 생기며 친구 기기에 설치하는 빌드에도 포함된다. git 제외 규칙은 바뀌지 않았다. 위젯 갤러리·플레이스홀더 미리보기는 저장소 오리지널 그림만 쓰고, 실제 위젯에는 현재 종의 대기 프레임 0번이 표시된다.

## 진화 아이템 이름 출처 · 2026-11-26

아이템 25종(문장 11, 디지멘탈 11, X항체·디지코어·디지코드)은 이름만 쓰고 그림·설명문은 쓰지 않는다(텍스트와 SF Symbol만). 한국어 이름은 모두 가안(`nameVerified = false`, `ItemCatalog` 한 곳)이고 공식 한국어명을 직접 확인한 항목은 없다. 일본어·영어 이름은 Wikimon 기준(영어는 일본어 원제 직역)이다.
- 문장: [Wikimon — Crest](https://wikimon.net/Crest), [Digimon Wiki — Crests](https://digimon.fandom.com/wiki/Crests). 용기·우정·지식·성실의 한국어 표기는 2차 자료(팬 게시글)에서만 봤고 나머지는 가안이다.
- 디지멘탈: [Wikimon — Digimental](https://wikimon.net/Digimental). "디지멘탈"이라는 용어는 국내 극장판 제목 "황금의 디지멘탈"에서 확인(나무위키 미러 요약). 개별 이름은 가안.
- X항체: [Wikimon — X Antibody](https://wikimon.net/X_Antibody). 디지코어: [Wikimon — Digicore](https://wikimon.net/Digicore)(원작에서 획득하는 아이템이 아닌 설정 용어). 디지코드: [Wikimon — Digicode](https://wikimon.net/Digicode)(프론티어).
- 잠금 종과 아이템의 연결은 래피드몬(아머)↔운명의 디지멘탈(원작: 테리어몬 아머 진화)과 사쿠야몬 X↔X항체만 원작 근거가 있고, 돈데블몬·로드나이트몬·다이나스몬(디지코어), 무르무쿠스몬·루체몬 폴다운모드(디지코드)는 앱 규칙이다. VB/DIM의 실제 잠금 해제는 아이템이 아니라 수치 조건이다(팬 사이트 [humulos VBDM EX](https://humulos.com/digimon/vbdm/ex), 공식 미확인).
