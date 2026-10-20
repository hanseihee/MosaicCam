# 모자이크 (MosaicCam)

사진을 찍거나 앨범에서 고르면 **번호판과 얼굴을 찾아 상자로 표시**하고, 사용자가 **탭한 곳만 모자이크**하는 iOS 앱. 모든 처리는 기기 안에서 한다.

## 구성

```
MosaicCam/            앱 (SwiftUI, iOS 18+)
  HomeView            사진 찍기 / 앨범에서 고르기
  EditorView          상자 탭 → 모자이크, 직접 그리기, 되돌리기, 저장·공유
  EditorModel         찾은 영역·가린 영역·되돌리기 기록
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

## 개발

```sh
# 탐지·모자이크 시험 (맥)
cd MosaicCore && swift test

# Xcode 프로젝트 생성 (project.yml이 원본, 서명 팀도 여기 있음)
xcodegen generate && open MosaicCam.xcodeproj
```

시뮬레이터에는 카메라가 없다. 디버그 빌드는 사진 경로를 넘기면 바로 편집 화면을 연다.

```sh
# 환경 변수 앞에 SIMCTL_CHILD_를 붙이면 앱에 전달된다
SIMCTL_CHILD_MOSAIC_DEMO_IMAGE=/절대/경로/사진.jpg \
  xcrun simctl launch --terminate-running-process booted realmasse.mosaiccam
# SIMCTL_CHILD_MOSAIC_DEMO_MASK_ALL=1 을 더하면 찾은 곳을 모두 가린 상태로 연다
```
