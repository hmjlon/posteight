# Posteight 기여자 가이드

Posteight 는 macOS 메뉴 막대 포스트잇 체크리스트 앱이다. 노트는 전부 로컬에 저장되고,
계정도 네트워크도 텔레메트리도 없다.

제품 방향은 [docs/PRODUCT.md](docs/PRODUCT.md) 가 담지만 지금은 비어 있는 상태다. 다시 채워지기
전까지는 현재 동작 자체가 명세다. 제품 동작을 바꾸기 전에 물어본다.

## 스택

| | |
| --- | --- |
| 언어 | Swift 6 (`swift-tools-version: 6.0`) |
| UI | SwiftUI. SwiftUI 로 닿지 않는 곳은 AppKit (`NSWindow`, `NSViewRepresentable`) 으로 내려간다 |
| 테스트 | swift-testing (`import Testing`). XCTest 가 아니다 |
| 최소 버전 | macOS 14 (Sonoma) |
| 아키텍처 | Apple silicon 전용. `ARCHS` 가 `arm64` 로 고정되어 있다 |
| 의존성 | 없음 |

## 빌드와 실행

빌드 경로가 두 개다. 번들이 소유한 것(`Info.plist`, entitlements, 서명, 앱 아이콘)을 건드릴
때는 Xcode 를 쓰고, 빠른 컴파일 확인에는 SwiftPM 을 쓴다.

```bash
xed Posteight.xcodeproj
```

```bash
xcodebuild -project Posteight.xcodeproj -scheme Posteight -configuration Debug build
```

```bash
swift build
```

```bash
swift test
```

빌드 설정은 전부 `Posteight.xcodeproj` 안에 둔다. 실제 앱을 만드는 것은 이것뿐이고, 빌드 경로가
둘로 갈리면 설정이 어긋난다. `Sources/Posteight` 는 file system synchronized group 이라 Swift
파일을 추가하거나 지워도 `project.pbxproj` 를 고칠 필요가 없다.

`swift run` 도 되지만 번들 없는 바이너리가 뜬다. `Bundle.main.bundleIdentifier` 가 `nil` 이라
macOS 가 `linkd` / Process Instance Registry XPC 실패를 로그에 남기고, 창 위치도 따로 저장된다.
그 메시지는 잡음이지 앱 버그가 아니다. 번들이 중요한 작업이면 Xcode 타깃으로 실행한다.

## 진입점과 씬 구성

`@main struct PosteightApp: App` 이 [`Sources/Posteight/PosteightApp.swift`](Sources/Posteight/PosteightApp.swift)
에 있다. 메인 창은 없다. 씬 구성은 이렇다.

- **`MenuBarExtra`** (`.menuBarExtraStyle(.window)`) — 상태 아이템에 `MenuBarLabel`, 팝오버에
  `MenuBarPanelView`. 유일한 상설 표면이다.
- **`WindowGroup("Posteight", for: UUID.self)`** — 노트 ID 하나당 메모 창 하나. 타이틀 바는 숨긴다.
- **`Window(id:)`** — `WindowID.dailyLog` 와 `WindowID.trash`. `openWindow` 로 여는 단일 창이다.
- **설정은 씬이 아니다.** 앱에 시트를 붙일 창이 없어서 `SettingsModal.present` 가 자기
  `NSWindow` 를 띄운다. `NSApp.runModal` 은 일부러 피했다. 모달 세션이 `terminate` 를 삼켜서
  설정이 열려 있는 동안 Command-Q 가 통째로 먹통이 됐다.

`AppDelegate.applicationWillFinishLaunching` 은 SwiftUI 가 `MenuBarExtra` 를 설치하기 **전에**
activation policy 를 정한다. 나중에 바꾸면 씬이 다시 만들어지면서 한 프로세스에 상태 아이템이
둘 살아남을 수 있다.

### 창 라우팅

`WindowGroup` 은 같은 값으로 `openWindow` 를 불러도 매번 새 창을 만든다. 그래서 메모 창은
`NoteWindowCoordinator.shared` 를 거친다.

- `present(_:openWindow:)` — 몇 번을 불러도 결과가 같은 표시 경로. 살아 있는 창을 재사용하고,
  최소화된 창은 되돌리고, 화면 밖으로 밀려난 창에는 `moveOnScreenIfNeeded()` 를 부른다.
- `register(_:for:)` — 각 `StickyNoteWindowView` 가 뜰 때 자기 `NSWindow` 를 넘겨준다.
- `hideAll()` — 모든 메모 창을 내린다. 만들어지는 중이던 창도 숨김으로 기록해서, 숨기기 직후에
  생성이 끝난 창이 도로 튀어나오지 못하게 한다.

이걸 굴리는 쪽은 `MenuBarLabel` 이다. 실행할 때 모든 노트를 복원하고, 새로 생긴 노트를 열고,
`AppSettings.showAllNotesRequests`(Dock 아이콘 클릭이 올린다) 변화에 반응한다.

## 코드 구조

```
Sources/Posteight/
  PosteightApp.swift         @main, 씬, NoteWindowCoordinator, AppDelegate, MenuBarLabel
  PosteightStore.swift       @MainActor ObservableObject — 모든 변경, 저장, 마이그레이션,
                             오늘 기록 Markdown
  Models.swift               StickyNote, MemoTab, TodoItem, 휴지통 타입, PenStyle,
                             ColorOption, StickerOption, DesignTokens
  AppSettings.swift          설정 싱글턴(UserDefaults 기반), activation policy
  Strings.swift              AppLanguage, L(), Lf(), englishStrings 테이블
  MenuBarPanelView.swift     팝오버 내용
  FoldedCardSurface.swift    종이 도형과 질감, 상태 아이템 글리프 MenuBarProgressCard
  StickyNoteWindowView.swift 메모 창 껍데기: 탭 바, NSWindow 설정, 프레임 저장과 복원
  StickyNoteView.swift       메모 본문
  TodoItemRow.swift          체크리스트 행과 펜 줄 긋기
  TrashView.swift, DailyLogPreviewView.swift, SettingsView.swift, SettingsModal.swift,
  PencilCaseView.swift       보조 화면들
  PlainEditableTextField.swift, WindowMoveHandle.swift   NSViewRepresentable 브리지
  Color+Hex.swift
  Assets.xcassets/           앱 아이콘. SwiftPM 타깃에서는 제외된다

Tests/PosteightTests/        스토어 로직, 저장, 창 표시 상태, 메뉴 막대 글리프, 로컬라이제이션
Packaging/Info.plist         두 빌드 경로가 공유하는 번들 메타데이터
.github/workflows/           ci.yml, release.yml
docs/                        PRODUCT.md, README 이미지
```

`README.md` / `README.ko.md` 는 앱을 설치하는 사람을 위한 문서지 빌드하는 사람을 위한 문서가 아니다.

## UI 규약

- 뷰는 얇게 유지한다. 테스트할 수 있는 것 — 개수, 정렬, 마이그레이션, Markdown — 은
  `PosteightStore` 나 모델 타입에 순수 함수나 `nonisolated` 코드로 둔다.
- 사용자에게 보이는 문자열은 전부 `L()` / `Lf()` 를 거친다. [언어](#언어) 를 본다.
- 메모 표면은 `FoldedCardSurface`(`MemoCardShape`, `MemoTabShape`, `MemoCardSurface`,
  `PaperGrain`) 에서 가져온다. 뷰 안에서 종이 도형이나 색을 다시 만들지 않는다.
- 크기, 프레임 한계, 종이·펜 팔레트, 스티커는 `Models.swift` 의 `DesignTokens` 에 있다.
  `minimumNoteSize` 는 건드리면 파장이 크다. 값을 올리면 저장된 모든 노트가 `clamped` 를 지나며
  넓어져서, 사용자가 직접 잡아 둔 배치를 덮어쓴다.
- 상태 아이템 글리프는 단일 template `NSImage` 로 래스터화한다(`MenuBarProgressCard`). 메뉴 막대
  렌더러가 여러 뷰로 조립한 그림의 일부를 떨어뜨리기 때문이다. `MenuBarGlyphTests` 가 지킨다.
- AppKit 은 `NSViewRepresentable` 을 통해 만진다. SwiftUI 의 리치 텍스트 동작 없이 순수 텍스트를
  편집하려면 `PlainEditableTextField`, 타이틀 바 없는 창을 끌려면 `WindowMoveHandle`. 뷰 여기저기에
  `NSWindow` 접근을 흩뿌리지 않는다.

## 데이터와 환경

- 노트는 `~/Library/Application Support/Posteight/` 에 `notes.json`, `trash.json`,
  `trashed-tabs.json` 으로 저장된다(`PosteightStore.storeDirectory`). 테스트는 자기 `directory` 를
  넘기기 때문에 실제 노트를 건드리지 않는다.
- 설정은 `UserDefaults` 의 `posteight.*` 키에 있다.
- 네트워크 호출도, 계정도, API 키도, entitlement 가 필요한 권한도 없다. 밖으로 나가는 경로는
  오늘 기록을 Markdown 으로 클립보드에 복사하는 것 하나뿐이고, 그것도 명시적인 동작이다.
- 환경변수는 `POSTEIGHT_SYSTEM_LANGUAGE` 하나뿐이고 테스트 전용이다.

## 작업 시 주의할 점

### 저장

- 저장은 500ms 디바운스된다. **새로 만드는 종료·절전 경로는 반드시 `PosteightStore.flush()` 를
  불러야 한다.** 안 그러면 마지막 0.5초의 편집이 날아간다. `willTerminate` 옵저버는 이미 부르고 있다.
- 스토어는 아직 예전 `UserDefaults` 도메인과 그보다 더 오래된 `Posteat` 키를 읽는다. 기존 설치가
  첫 실행에 넘어오게 하는 경로다. 마이그레이션 계획 없이 걷어내지 않는다.
- 제목 마이그레이션은 사용자가 직접 쓴 글자를 고쳐 쓰는 동작이라 테스트로 덮여 있다.
  `legacyTitleDate` 를 바꿀 때는 지금 형식의 제목이 그대로 남는다는 걸 증명하는 테스트를 같이 넣는다.
- 저장된 데이터와 비교되는 문자열은 절대 번역하지 않는다. `PosteightStore.compacted` 의
  `"새 포스트잇"` 은 예전 빌드가 실제로 디스크에 쓴 값이라, 번역하면 마이그레이션이 깨진다. 노트
  본문, 탭 이름, 제목은 사용자의 말이므로 입력한 그대로 둔다.

### 언어

Posteight 는 자기가 그리는 UI 를 한국어나 영어로 보여 주고, 설정에서 바꾸면 재시작 없이 바뀐다.
한국어가 원본 언어이고, 한국어 문자열 자체가 조회 키다.

- 사용자에게 보이는 문자열은 전부 `L("한국어")` 를 거치고, 자리 표시자가 있으면
  `Lf("메모 %d", n)` 을 쓴다. 그냥 둔 리터럴은 번역되지 않은 채 나간다.
- 영어 항목은 `Sources/Posteight/Strings.swift` 의 `englishStrings` 에 **같은 변경 안에서** 넣는다.
  키가 없으면 한국어로 조용히 대체된다. 빌드가 깨지지도, 크래시가 나지도, 티가 나지도 않는다.
- `LocalizationTests` 는 모든 항목이 비어 있지 않고, 키와 다르고, `%d`/`%@` 개수가 양쪽에서 같은지
  검사한다. 테이블에 아예 넣지 않은 문자열은 이 테스트가 볼 수 없다.
- 순수 함수와 `nonisolated` 코드 — `PosteightStore`, 모델 타입, static 인 것 전부 — 는
  `language: AppLanguage` 를 파라미터로 받고 기본값은 `.korean` 이다. `AppSettings.shared` 를
  절대 직접 읽지 않는다. 그것 때문에 `addNote` 가 앱 설정이 아니라 기기의 시스템 언어로 새 탭
  이름을 지었다.
- 뷰는 `@MainActor` 인 `L(_:)` 를 불러도 된다. 이건 실제로 `AppSettings.shared` 를 읽는다. 그런데도
  동작하는 이유는 **모든 창의 루트 뷰가 `@ObservedObject var settings = AppSettings.shared` 를
  들고 있기 때문**이다 — `MenuBarPanelView`, `StickyNoteWindowView`, `TrashView`,
  `DailyLogPreviewView`, `PencilCaseView`, `SettingsView`, `MenuBarLabel`. 이걸 빠뜨린 새 루트는
  처음 그려진 언어에 그대로 멈춘다. 자식 뷰는 루트가 다시 그려질 때 따라오므로 아무것도 필요 없다.
- SwiftUI 가 값을 비교해야 하는 자리 — `Picker` 옵션 라벨, `ForEach` 안의 것 — 는 언어를 명시적으로
  넘긴다. `PenStyle`, `MenuBarCountStyle`, `StickerOption`, `AppLanguage` 의 `title(in:)` 을 쓴다.
  거기서 싱글턴을 읽으면 SwiftUI 눈에 보이지 않아서, 라벨이 처음 만들어진 값에 그대로 붙어 버린다.
- macOS 가 직접 그리는 메뉴(File, Edit, Window) 는 AppKit 것이다. `Packaging/Info.plist` 의
  `CFBundleLocalizations`(`en`, `ko`) 를 기준으로 시스템 언어를 따른다. AppKit 이 실행 시점에 한 번
  정하기 때문에 앱 안의 설정을 따를 수 없다.

#### 로컬에서 초록불이 났다고 통과가 아니다

이 프로젝트는 한국어 Mac 에서 개발하고 CI 는 영어 러너에서 돈다. 그래서 로케일 버그는 로컬에서
멀쩡히 통과하고 푸시한 뒤에야 터진다. `addNote` 가 러너에서는 새 탭을 `Memo 1` 로, 여기서는
`메모 1` 로 짓던 게 정확히 이 경우였다. 언어에 닿는 변경을 푸시하기 전에 러너를 재현한다.

```bash
POSTEIGHT_SYSTEM_LANGUAGE=en swift test
```

`AppLanguage.resolved` 가 `Locale.preferredLanguages` 대신 이 변수를 보기 때문에, 기기가 영어인
것처럼 전체 스위트가 돈다. 그냥도 한 번 돌린다. 둘 다 통과해야 한다.

이 변수는 재현 수단이지 해결책이 아니다. 해결책은 뷰 바깥의 어떤 코드도 현재 언어를 읽지 않는 것이다.

### 테스트

- 커밋 전마다 `swift test` 를 돌린다.
- 텍스트 편집, 체크리스트 완료, 노트 이동, 크기 조절, 휴지통, 저장을 건드렸다면 그 영역을 테스트한다.
- 여러 디스플레이·Space·절전 복귀에서의 창 배치는 테스트로 덮이지 않는다. 릴리스 전에 손으로 확인한다.

## 릴리스

릴리스는 손이 아니라 CI 가 만든다. `v*` 태그를 푸시하면 [`release.yml`](.github/workflows/release.yml)
이 돌면서 태그에서 버전을 찍고, Release 구성으로 빌드하고, `.dmg` 로 묶어 체크섬과 함께 GitHub
Releases 에 올린다.

```bash
git switch release
git tag v0.2.0
git push origin v0.2.0
```

버전의 유일한 원본은 태그다. `Packaging/Info.plist` 는 `$(MARKETING_VERSION)` 을 읽으므로 거기에
버전을 박아 넣지 않는다. dmg 는 서명도 공증도 되어 있지 않아서, 설치하는 사람마다 Gatekeeper 를
손으로 넘어야 한다.

[`ci.yml`](.github/workflows/ci.yml) 은 `dev` 나 `release` 로 푸시할 때마다, 그리고 `release` 로
들어오는 모든 PR 에서 `swift test` 와 실제 `.app` 번들의 `xcodebuild` 를 돌린다. 문서만 바뀐
커밋은 건너뛴다.

한 번짜리 로컬 빌드는 Xcode 의 `Product > Archive` 로도 된다.

## Git 작업 방식

- `dev` 에 바로 커밋한다. 기능별 브랜치는 쓰지 않는다.
- `release` 는 `dev` 에서 오는 머지만 받는다. 버전 태그는 `release` 에서 자른다.
- 커밋 하나에는 기능이나 변경 하나만 담는다.
- `.build/` 와 `dist/` 는 커밋하지 않는다. 둘 다 로컬에서 생성되고 Git 이 무시한다.

## 커밋 메시지

Conventional Commit 접두사만 영어고 나머지는 한국어다.

```
type(scope): 무엇을 바꿨는지 한 줄

왜 그랬는지, 무엇이 어긋나 있었는지, 어떻게 확인했는지.
```

- 제목: `type(scope):` 뒤에 한국어 요약. 타입은 `feat`, `fix`, `docs`, `test`, `chore`,
  `refactor`, `ci`. scope 는 선택이고 소문자로 쓴다(`fix(menubar):`). 한 줄, 마침표 없음.
  `~한다` 보다 명사형(`... 수정`, `... 추가`) 을 쓰고, 두 가지 변경은 뭉뚱그리지 말고 `+` 나 `—`
  로 잇는다.
- 본문: 제목과 빈 줄로 띄우고 한국어 산문으로 쓴다. 결함이나 동기와 그 파장으로 연다 — 무엇이
  잘못됐고, 어느 경로에서, 사용자에게 무엇이 보였는지. 그다음 무엇을 바꿨는지, 두 개 이상이면
  `-` 불릿으로. 마지막은 근거다. 이 변경 없이는 실패하는 테스트, `swift test` 결과, 관련 커밋
  해시와 날짜.
- 본문은 파일별 diff 요약이 아니라 이유를 적는 자리다. 함정과 가지 않은 길(SwiftUI 렌더링 한계,
  순서 제약)을 남겨서 다음 변경이 같은 자리로 되돌아가지 않게 한다.
- 에이전트가 작성한 변경이면 `Co-Authored-By:` 트레일러를 남긴다.
