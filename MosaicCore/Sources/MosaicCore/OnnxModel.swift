import Foundation
import OnnxRuntimeBindings

enum OnnxModelError: Error {
    case missingModel(String)
    case missingOutput(String)
}

/// ONNX 모델 하나를 감싼다. 입력은 [1, 3, 640, 640] float 하나로 고정.
final class OnnxModel {
    private static let env = Result { try ORTEnv(loggingLevel: .warning) }

    private let session: ORTSession
    private let inputName: String

    init(resource name: String, inputName: String, coreML: Bool) throws {
        guard let url = Bundle.module.url(forResource: name, withExtension: "onnx", subdirectory: "Models") else {
            throw OnnxModelError.missingModel(name)
        }
        let env = try Self.env.get()
        self.inputName = inputName
        do {
            session = try ORTSession(env: env, modelPath: url.path, sessionOptions: Self.options(coreML: coreML))
        } catch {
            // CoreML 실행기를 못 쓰는 환경(시뮬레이터 등)이면 CPU로
            session = try ORTSession(env: env, modelPath: url.path, sessionOptions: Self.options(coreML: false))
        }
    }

    private static func options(coreML: Bool) throws -> ORTSessionOptions {
        let options = try ORTSessionOptions()
        try options.setLogSeverityLevel(.warning)
        #if !targetEnvironment(simulator)
        if coreML && ORTIsCoreMLExecutionProviderAvailable() {
            try options.appendCoreMLExecutionProvider(with: ORTCoreMLExecutionProviderOptions())
        }
        #endif
        return options
    }

    func run(_ tensor: [Float], outputs: [String]) throws -> [String: [Float]] {
        let side = NSNumber(value: Tensor.side)
        let data = tensor.withUnsafeBufferPointer {
            NSMutableData(bytes: $0.baseAddress, length: $0.count * MemoryLayout<Float>.size)
        }
        let input = try ORTValue(tensorData: data, elementType: .float, shape: [1, 3, side, side])
        let values = try session.run(withInputs: [inputName: input], outputNames: Set(outputs), runOptions: nil)
        var result: [String: [Float]] = [:]
        for name in outputs {
            guard let value = values[name] else { throw OnnxModelError.missingOutput(name) }
            let raw = try value.tensorData() as Data
            result[name] = raw.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
        return result
    }
}
