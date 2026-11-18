# moa

> moment of a lifetime, gathered.

사진을 기기 안에서 분석해 여행, 인물, 반려동물, 장소, 분류 앨범으로 자동 정리하는 iOS 앱입니다.
사진과 분석 결과는 기기 밖으로 나가지 않습니다.

![Swift](https://img.shields.io/badge/Swift-F05138?logo=swift&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-17.0%2B-000000?logo=apple&logoColor=white)
![Tuist](https://img.shields.io/badge/Tuist-4.x-6236FF)

## 주요 기능

- **자동 앨범** — 여행, 인물, 반려동물, 분류(8종), 장소, 시간, 비슷한 사진, 영상
- **여행 앨범** — 자주가는 동네는 빼고 여행 구간만 묶기, 동행자 자동 연결, 날짜순/분류순 보기, 부분 공유
- **앨범 편집** — 이름·대표 사진 변경, 합치기·분리, 사진 직접 추가, 사진 앱 앨범 가져오기
- **분석** — 새 사진만 이어서 분석, 앨범 종류별 재생성, 진행률 표시(시트 → 미니 → 배지)
- **사진첩과 뷰어** — 월별 그리드, 영상 재생, 위치 정보
- 한국어 / 영어

## 기술 스택

- Swift, UIKit, Combine, SwiftData
- Vision, CoreML(AdaFace, DINOv2), Photos, MapKit
- SnapKit, Moya, Firebase
- Tuist

## 아키텍처

Tuist 멀티 모듈 + Clean Architecture, 화면은 MVVM + Coordinator입니다.

```
Projects/
├── App/            앱 진입점, DI 조립
├── Presentation/   화면(ViewController / ViewModel / Coordinator), 공통 UI
├── Domain/         UseCase, Repository 프로토콜, 모델
└── Data/           Repository 구현, SwiftData, Vision·CoreML·Photos 서비스
```

의존 방향: `App → Presentation → Domain ← Data`

분석은 주소 트랙(지오코딩 → 여행·지역 앨범)과 라벨 트랙(이미지 분류·임베딩 → 인물·분류·비슷한 사진 앨범)이 동시에 진행되고, 데이터가 준비되는 대로 앨범이 만들어집니다.

## 시작하기

요구 사항: Xcode 최신 버전, [Tuist](https://tuist.dev) 4.x(`mise`로 설치)

```bash
mise exec -- tuist install
mise exec -- tuist generate
open Projects.xcworkspace
```

`.xcodeproj`/`.xcworkspace`는 커밋하지 않습니다. 파일을 추가하거나 `Project.swift`를 바꾸면 `tuist generate`를 다시 실행합니다.
