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
