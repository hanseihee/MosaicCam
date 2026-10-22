# 모자이크 (MosaicCam)

사진을 찍거나 앨범에서 고르면 **번호판과 얼굴을 찾아 상자로 표시**하고, 사용자가 **탭한 곳만 모자이크**하는 iOS 앱. 모든 처리는 기기 안에서 한다.

## 구성

```
MosaicCam/            앱 (SwiftUI, iOS 18+)
  HomeView            사진 찍기 / 앨범에서 고르기
  EditorView          상자 탭 → 모자이크, 직접 그리기, 되돌리기, 저장·공유
  EditorModel         찾은 영역·가린 영역·되돌리기 기록
  Theme               색·글꼴·유리 질감 부품 (흐릿한 사진 같은 바탕 + 반투명 알약)
  Ads                 저장 전에 보여 주는 전면 광고 (에드몹)
  Purchases           광고 제거 구매 (StoreKit 2, 한 번 사면 계속)
  RemoveAdsView       광고 제거 구매 시트
  Products.storekit   시험 결제 설정 (스킴에 연결, 앱에는 안 들어감)
  Localizable.xcstrings  화면 문구 번역 (소스 언어 한국어 + 33개 언어)
  InfoPlist.xcstrings    앱 이름·권한 문구 번역
Tools/render-icon.swift  앱 아이콘을 그려 PNG로 저장 (swift Tools/render-icon.swift)
MosaicCore/           탐지·모자이크 Swift 패키지 (맥에서 swift test 가능)
  RegionDetector      번호판 + 얼굴 탐지 (사진을 겹치는 조각으로 나눠 작은 것까지)
  Mosaic              Core Image 픽셀화 (흐림 → 칸 나누기, 되돌릴 수 없음)
  Models/             ONNX 모델 2개
```

## 모델

| 용도 | 파일 | 출처 · 라이선스 | 실행 |
|---|---|---|---|
| 번호판 | `plate-yolov9t-640.onnx` (7.8MB) | [ankandrew/open-image-models](https://github.com/ankandrew/open-image-models) `yolo-v9-t-640-license-plate-end2end`, 코드 MIT · **학습 데이터 출처 미공개** | CPU (모델 안의 NMS가 후보 0개일 때 CoreML 실행기에서 오류) |
| 얼굴 | `face-yunet-2023mar.onnx` (230KB) | [opencv_zoo YuNet](https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet), MIT | CoreML |

런타임은 [onnxruntime-swift-package-manager](https://github.com/microsoft/onnxruntime-swift-package-manager) (ORT 1.24.2 커밋 고정).

**출시 전 할 일:** 번호판 모델의 학습 데이터 라이선스를 확인하거나, Open Images의 "Vehicle registration plate"(CC BY 4.0) 등으로 직접 다시 학습한다.

## 탐지 설정 (맥 실측으로 정함)

- 번호판: 점수 0.4 이상, 전체 1회 + 긴 변 2등분 조각 → 멀리 있는 번호판까지
- 얼굴: 점수 0.7 이상(0.6이면 바퀴·전조등이 잡힘), 전체 1회 + 긴 변 3등분 조각 → 군중 속 작은 얼굴까지
- 조각 안쪽 경계에 걸린 결과는 버린다(근접 사진에서 잘린 번호판 중복 방지)

## 광고와 광고 제거

- 저장을 누르면 전면 광고가 먼저 나오고, 닫히면 저장한다. 광고를 받아 두지 못했으면(인터넷 없음 등) 그냥 저장한다.
- 광고 제거(`realmasse.mosaiccam.removeads`, 비소모성)는 홈 아래 "광고 없이 쓰기"에서 산다. 값(₩3,000)은 App Store Connect에서 정하고, 시험 결제 설정 `MosaicCam/Products.storekit`에도 3000원으로 넣어 두었다.
- 에드몹 앱 ID는 `project.yml`의 `GADApplicationIdentifier`, 전면 광고 단위("저장 전면 광고")는 `Ads.swift`의 `AdUnit.interstitial`에 있다. 디버그 빌드는 구글 시험 광고 단위를 써서 실기기에서도 시험 광고가 나온다(내 광고를 누르면 정책 위반이라 일부러 그렇게 둔다). **출시 전 할 일:** App Store Connect에 상품을 만든다. 유럽 등에 배포하면 동의 창(UMP)도 붙여야 한다.

## 다국어

문구는 코드에 한국어로 쓰고, `Localizable.xcstrings`에서 번역한다(영어·일본어·중국어 간체/번체·스페인어·프랑스어·독일어·이탈리아어·포르투갈어(브라질/포르투갈)·러시아어·우크라이나어·폴란드어·체코어·슬로바키아어·헝가리어·루마니아어·크로아티아어·그리스어·튀르키예어·아랍어·히브리어·힌디어·인도네시아어·말레이어·태국어·베트남어·네덜란드어·스웨덴어·덴마크어·핀란드어·노르웨이어·카탈루냐어). 새 문구를 넣으면 빌드할 때 카탈로그에 자동으로 추가되고, Xcode에서 번역을 채우면 된다.

- SwiftUI의 `Text("…")`·`Label`·`Button`은 그대로 번역된다. 코드에서 만든 String은 `String(localized:)`를 쓴다. 삼항식으로 고른 문구는 String이 되어 번역되지 않으니 `as LocalizedStringKey`나 if/else로 쓴다.
- 제목처럼 줄마다 굵기가 다른 문구는 번역문 안의 마크다운(`**…**`)으로 정한다.
- UI 테스트는 `-AppleLanguages (ko)`로 한국어를 고정한다.

## 개발

```sh
# 탐지·모자이크 시험 (맥)
cd MosaicCore && swift test

# Xcode 프로젝트 생성 (project.yml이 원본, 서명 팀도 여기 있음)
xcodegen generate && open MosaicCam.xcodeproj

# 앱 아이콘 다시 그리기 (색을 바꿨을 때)
swift Tools/render-icon.swift
```

시뮬레이터에는 카메라가 없다. 디버그 빌드는 사진 경로를 넘기면 바로 편집 화면을 연다.

```sh
# 환경 변수 앞에 SIMCTL_CHILD_를 붙이면 앱에 전달된다
SIMCTL_CHILD_MOSAIC_DEMO_IMAGE=/절대/경로/사진.jpg \
  xcrun simctl launch --terminate-running-process booted realmasse.mosaiccam
# SIMCTL_CHILD_MOSAIC_DEMO_MASK_ALL=1 을 더하면 찾은 곳을 모두 가린 상태로 연다
```
