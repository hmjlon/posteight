# Posteight

**맥을 위한 사적인 포스트잇 — 보이는 시점은 내가 정한다.**

Posteight 는 오늘 할 일을 바탕화면에 꺼내 둔다. 작업이 실제로 일어나는 자리마다
독립된 작은 창을 놓고, 누가 다가오면 감춘다.

[English](README.md) · 한국어

![바탕화면에 떠 있는 Posteight 메모들](docs/images/posteight-desktop-ko.png)

## 설치

### 요구 사항

| | |
| --- | --- |
| macOS | 14 (Sonoma) 이상 |
| Mac | Apple Silicon 전용 — `ARCHS` 가 `arm64` 로 고정되어 있어 Intel Mac 은 지원하지 않는다 |
| 인터페이스 언어 | 한국어 / 영어, 설정에서 전환 |

### 내려받기

[Releases](https://github.com/hmjlon/posteight/releases) 에서 최신 `.dmg` 를 내려받아 열고,
**Posteight** 를 **응용 프로그램** 으로 끌어다 놓는다.

### 처음 열 때

Posteight 는 아직 Apple 공증을 받지 않아서, macOS 가 첫 실행을 한 번 막는다.

1. Posteight 를 연다. 경고가 뜨고 실행이 거부된다.
2. **시스템 설정 → 개인정보 보호 및 보안** 을 연다.
3. 아래로 내려 **그래도 열기** 를 누른다.

설치당 한 번만 하면 된다. 터미널을 쓴다면 아래 한 줄로도 같다.

```bash
xattr -dr com.apple.quarantine /Applications/Posteight.app
```

공증에는 유료 Apple Developer Program 멤버십이 필요하다. 그전까지는 앱을 직접 빌드한
사람이 아닌 이상 이 단계를 피할 수 없다.

## 사용하기

### 메모 창

<img src="docs/images/posteight-note-ko.png" alt="탭 두 개와 완료된 항목에 그어진 펜 줄이 보이는 메모 창" width="300">

메모는 각자 떠 있는 창이고, 놓아둔 자리를 기억한다. 안쪽의 컴팩트한 탭 바는 메모 폭을
균등하게 나눠 쓰기 때문에 가로 스크롤이 없다. 창 하나에 목록 여러 개를 나란히 둘 수 있다.

- 독립적으로 떠 있고 크기를 조절할 수 있는 메모 창 여러 개
- 메모마다 붙는 탭. 활성 탭을 한 번 더 누르면 그 자리에서 이름을 고친다
- 완료할 때 펜으로 줄을 긋는 애니메이션 체크리스트
- 종이 색, 펜 색, 펜 종류, 분류 스티커
- 복원과 영구 삭제가 되는 휴지통
- 오늘 기록 미리보기와 Markdown 클립보드 내보내기

### 메뉴 막대

<img src="docs/images/posteight-menubar.png" alt="오늘의 개수가 적힌 접힌 카드 모양의 Posteight 상태 아이템" width="44">

Posteight 에는 메인 창이 없다. 상태 아이템이 유일한 상설 표면이다. 오늘의 개수가 적힌
접힌 카드 하나가 할 일이 끝날 때마다 아래에서부터 차오른다. 누르면 팝오버가 열리고,
거기서 빠른 입력, 메모 창 열기, 오늘 기록, 휴지통, 설정, 종료로 간다.

설정은 일부러 작게 유지한다. 상태 아이템이 무엇을 세는지, 메모를 다른 앱 위에 띄울지,
Dock 아이콘을 남길지. Dock 아이콘은 기본으로 켜져 있어서 실행 중인 Posteight 를 Dock 과
Command-Tab 으로 부를 수 있고, 누르면 메모 창이 다시 나온다. 끄면 메뉴 막대에만 사는 앱이 된다.

### 언어

<img src="docs/images/posteight-settings-ko.png" alt="언어 항목이 맨 위에 있는 Posteight 설정 창" width="380">

Posteight 는 한국어와 영어로 읽힌다. 고르기 전까지는 맥의 언어를 따른다.
**설정 → 언어** 를 바꾸면 앱이 직접 그리는 모든 문구가 재실행 없이 바뀐다. 팝오버, 메모의
조작 버튼, 휴지통, 오늘 기록까지 — 열려 있는 메모 창도 누르는 즉시 따라온다.
직접 적은 것은 적은 그대로 남는다. 메모 내용, 탭 이름, 제목은 번역하지 않는다.

macOS 가 직접 그리는 메뉴(파일, 편집, 윈도우)는 여전히 시스템 언어를 따른다.

### 메모가 저장되는 곳

메모는 `~/Library/Application Support/Posteight/` 에 로컬로 저장된다. 계정도, 동기화도,
사용 정보 수집도 없다. 내보내기는 명시적으로만 일어난다 — 오늘 기록을 Markdown 으로
클립보드에 복사하는 것이 전부다. Notion 동기화는 아직 구현되어 있지 않다.

이건 시각적 프라이버시이지 보안 금고가 아니다. 자리를 비우거나 화면을 공유할 때 우연한
노출을 줄여 주지만, 잠기지 않은 화면에 지금 보이는 내용을 옆사람이 읽는 것까지 막지는 못한다.

## 제품 방향

제품 방향, 경험 원칙, 디자인 방향, 우선순위의 원본은 영어 README 의
[Product Direction](README.md#product-direction) 이다. 제품 결정이 바뀌면 그쪽을 먼저 고친다.

요약하면 이렇다.

- 종이 포스트잇은 오늘 할 일을 계속 보이게 하지만, 공용 책상 위에서 내용까지 그대로 드러난다.
  일반적인 할 일 관리 앱은 사적이지만, 다음 행동이 다른 앱 안으로 사라진다.
  Posteight 는 두 쪽의 쓸모 있는 부분을 합친다.
- 대상은 개방형 사무실, 공유 업무 공간, 화면 공유가 잦은 환경에서 맥으로 일하는 사람이다.
- 원칙: 빠르게 놓고, 잊기 어렵게 두고, 쉽게 감추고, 기본은 사적이고, 끝내는 순간은
  기분 좋고, 안 쓸 때는 조용할 것.
- 우선순위: 로컬 저장과 창 위치 복원 → 전역 표시/숨김과 회의 모드 → 메뉴 막대 빠른 입력과
  키보드 중심 조작 → 하루 마감 흐름과 Markdown 내보내기.
- 협업, 계정, 클라우드 동기화, AI 기능, 깊은 서드파티 연동은 현재 범위 밖이다.

## Xcode 로 개발하기

앱 프로젝트를 연다.

```bash
xed Posteight.xcodeproj
```

Xcode 에서 `Posteight` 스킴과 `My Mac` 을 고르고 `Command-R` 로 빌드해 실행한다.

빠른 컴파일 확인만 할 때는 이렇게 한다.

```bash
swift build
```

단위 테스트를 돌린다.

```bash
swift test
```

빌드 경로, 저장 관련 주의사항, git 흐름, 커밋 메시지 규범은 [AGENTS.md](AGENTS.md) 에 있다.

## 릴리스

릴리스는 손이 아니라 CI 가 만든다. `v*` 태그를 밀면
[`release.yml`](.github/workflows/release.yml) 이 돌면서 태그에서 버전을 찍고, Release 구성으로
빌드하고, `.dmg` 를 만들고, 체크섬과 함께 GitHub Releases 에 게시한다.

```bash
git switch release
git tag v0.2.0
git push origin v0.2.0
```

버전의 유일한 출처는 태그다. `Packaging/Info.plist` 는 `$(MARKETING_VERSION)` 을 읽으므로
거기에 버전을 직접 박지 않는다.

평소 작업은 `dev` 에서 하고, `release` 는 `dev` 에서 오는 머지만 받는다. 태그는 `release`
에서 자른다. [`ci.yml`](.github/workflows/ci.yml) 은 `dev` 와 `release` 로의 모든 푸시와
`release` 로 향하는 모든 PR 에서 `swift test` 와 실제 `.app` 번들 `xcodebuild` 를 돌린다.
문서만 고친 커밋은 건너뛴다.

로컬에서 한 번 만들어 볼 때는 Xcode 의 `Product > Archive` 도 여전히 쓸 수 있다.

## 저장소 구조

- `Sources/Posteight/`: SwiftUI 뷰, 모델, 로컬 저장
- `Tests/PosteightTests/`: 스토어와 저장 경로 테스트
- `Posteight.xcodeproj`: Xcode 앱 타겟과 빌드 설정
- `Packaging/Info.plist`: macOS 번들 메타데이터
- `.github/workflows/`: CI 와 릴리스 자동화
- `docs/images/`: README 스크린샷

## 라이선스

독점 소프트웨어다. [LICENSE](LICENSE) 를 참고한다. 오픈소스가 아니다.
