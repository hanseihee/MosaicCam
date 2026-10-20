import Foundation

#if DEBUG
private let debugLogFile = URL.documentsDirectory.appending(path: "debug.log")

/// 실기기 측정용. stderr(`devicectl ... --console`)와 앱 Documents/debug.log에 함께 남긴다.
/// stdout은 파이프에서 버퍼링되므로 쓰지 않는다.
func debugLog(_ message: String) {
    let time = Date().formatted(.dateTime.hour().minute().second())
    let data = Data("\(time) [MosaicCam] \(message)\n".utf8)
    FileHandle.standardError.write(data)
    if let handle = try? FileHandle(forWritingTo: debugLogFile) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: debugLogFile)
    }
}

func debugElapsed(since start: ContinuousClock.Instant) -> String {
    (ContinuousClock.now - start).formatted(.units(allowed: [.milliseconds], width: .narrow))
}
#endif
