import Flutter
import UIKit
import Foundation

/**
 * FlutterLlamaPlugin - плагин для работы с llama.cpp моделями на iOS
 * 
 * Поддерживает:
 * - Загрузку GGUF моделей
 * - GPU ускорение через Metal
 * - Потоковую и обычную генерацию
 */
@available(iOS 13.0, *)
public class FlutterLlamaPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var modelLoaded = false
    private var modelPath: String?
    private let queue = DispatchQueue(label: "net.nativemind.flutter_llama", qos: .userInitiated)
    private var eventSink: FlutterEventSink?
    private var shouldStop = false
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "flutter_llama",
            binaryMessenger: registrar.messenger()
        )
        
        let eventChannel = FlutterEventChannel(
            name: "flutter_llama/stream",
            binaryMessenger: registrar.messenger()
        )
        
        let instance = FlutterLlamaPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
        
        NSLog("[FlutterLlama] Plugin registered")
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "loadModel":
            loadModel(call: call, result: result)
        case "generate":
            generate(call: call, result: result)
        case "generateStream":
            generateStream(call: call, result: result)
        case "unloadModel":
            unloadModel(result: result)
        case "getModelInfo":
            getModelInfo(result: result)
        case "stopGeneration":
            stopGeneration(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - FlutterStreamHandler
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        shouldStop = true
        llama_stop_generation()
        return nil
    }
    
    // MARK: - Load Model
    
    private func loadModel(call: FlutterMethodCall, result: @escaping FlutterResult) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let args = call.arguments as? [String: Any],
                  let modelPath = args["modelPath"] as? String else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "INVALID_ARGS",
                        message: "Missing required arguments",
                        details: nil
                    ))
                }
                return
            }
            
            let nThreads = args["nThreads"] as? Int ?? 4
            let nGpuLayers = args["nGpuLayers"] as? Int ?? 0
            let contextSize = args["contextSize"] as? Int ?? 2048
            let batchSize = args["batchSize"] as? Int ?? 512
            let useGpu = args["useGpu"] as? Bool ?? true
            let verbose = args["verbose"] as? Bool ?? false
            
            // Check if model file exists
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: modelPath) else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "MODEL_NOT_FOUND",
                        message: "Model file not found: \(modelPath)",
                        details: nil
                    ))
                }
                return
            }
            self.prepareLargeModelFile(atPath: modelPath)
            
            self.modelPath = modelPath

            // Initialize model through llama.cpp C++ bridge
            let success = modelPath.withCString { cPath -> Bool in
                return llama_init_model(
                    cPath,
                    Int32(nThreads),
                    Int32(nGpuLayers),
                    Int32(contextSize),
                    Int32(batchSize),
                    useGpu,
                    verbose
                )
            }

            self.modelLoaded = success
            
            DispatchQueue.main.async {
                if success {
                    NSLog("[FlutterLlama] Model loaded: \(modelPath)")
                    NSLog("[FlutterLlama] GPU layers: \(nGpuLayers), threads: \(nThreads), context: \(contextSize)")
                    result(true)
                } else {
                    let nativeError = String(cString: llama_last_error()).trimmingCharacters(in: .whitespacesAndNewlines)
                    var details = self.modelLoadDetails(
                        path: modelPath,
                        nThreads: nThreads,
                        nGpuLayers: nGpuLayers,
                        contextSize: contextSize,
                        batchSize: batchSize,
                        useGpu: useGpu
                    )
                    if !nativeError.isEmpty {
                        details["nativeError"] = nativeError
                    }
                    result(FlutterError(
                        code: "INIT_FAILED",
                        message: nativeError.isEmpty ? "Failed to initialize model" : nativeError,
                        details: details
                    ))
                }
            }
        }
    }

    private func prepareLargeModelFile(atPath path: String) {
        let fileManager = FileManager.default

        do {
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.none],
                ofItemAtPath: path
            )
        } catch {
            NSLog("[FlutterLlama] Unable to disable file protection for model: \(error.localizedDescription)")
        }

        var url = URL(fileURLWithPath: path)
        do {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            NSLog("[FlutterLlama] Unable to exclude model from backup: \(error.localizedDescription)")
        }
    }

    private func modelLoadDetails(
        path: String,
        nThreads: Int,
        nGpuLayers: Int,
        contextSize: Int,
        batchSize: Int,
        useGpu: Bool
    ) -> [String: Any] {
        let fileManager = FileManager.default
        let attributes = try? fileManager.attributesOfItem(atPath: path)
        let size = attributes?[.size] as? NSNumber
        let protection = attributes?[.protectionKey] as? String

        return [
            "path": path,
            "fileSize": size?.int64Value ?? -1,
            "readable": fileManager.isReadableFile(atPath: path),
            "protection": protection ?? "unknown",
            "nThreads": nThreads,
            "nGpuLayers": nGpuLayers,
            "contextSize": contextSize,
            "batchSize": batchSize,
            "useGpu": useGpu
        ]
    }

    private func stopSequencesPayload(from args: [String: Any]) -> String {
        guard let stopSequences = args["stopSequences"] as? [String] else {
            return ""
        }

        return stopSequences
            .filter { !$0.isEmpty }
            .joined(separator: "\u{1F}")
    }
    
    // MARK: - Generate (blocking)
    
    private func generate(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard modelLoaded else {
            result(FlutterError(
                code: "MODEL_NOT_LOADED",
                message: "Model not loaded",
                details: nil
            ))
            return
        }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let args = call.arguments as? [String: Any],
                  let prompt = args["prompt"] as? String else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "INVALID_ARGS",
                        message: "Missing prompt",
                        details: nil
                    ))
                }
                return
            }
            
            let temperature = (args["temperature"] as? Double) ?? 0.8
            let topP = (args["topP"] as? Double) ?? 0.95
            let topK = (args["topK"] as? Int) ?? 40
            let maxTokens = (args["maxTokens"] as? Int) ?? 512
            let repeatPenalty = (args["repeatPenalty"] as? Double) ?? 1.1
            let stopSequences = self.stopSequencesPayload(from: args)
            
            self.shouldStop = false
            let startTime = Date()
            
            // Generate through llama.cpp C++ bridge
            var outputBuffer = [CChar](repeating: 0, count: 16384)
            var tokensGenerated: Int32 = 0

            let success = prompt.withCString { cPrompt -> Bool in
                stopSequences.withCString { cStopSequences -> Bool in
                    return llama_generate(
                        cPrompt,
                        Float(temperature),
                        Float(topP),
                        Int32(topK),
                        Int32(maxTokens),
                        Float(repeatPenalty),
                        cStopSequences,
                        &outputBuffer,
                        Int32(outputBuffer.count),
                        &tokensGenerated
                    )
                }
            }
            
            let generationTime = Int(Date().timeIntervalSince(startTime) * 1000)
            
            DispatchQueue.main.async {
                if success {
                    let responseText = String(cString: outputBuffer)
                    let response: [String: Any] = [
                        "text": responseText,
                        "tokensGenerated": Int(tokensGenerated),
                        "generationTimeMs": generationTime
                    ]
                    NSLog("[FlutterLlama] Generated: \(tokensGenerated) tokens in \(generationTime)ms")
                    result(response)
                } else {
                    result(FlutterError(
                        code: "GENERATION_FAILED",
                        message: "Failed to generate response",
                        details: nil
                    ))
                }
            }
        }
    }
    
    // MARK: - Generate Stream
    
    private func generateStream(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard modelLoaded else {
            result(FlutterError(
                code: "MODEL_NOT_LOADED",
                message: "Model not loaded",
                details: nil
            ))
            return
        }
        
        guard let eventSink = self.eventSink else {
            result(FlutterError(
                code: "NO_EVENT_SINK",
                message: "Event channel not initialized",
                details: nil
            ))
            return
        }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let args = call.arguments as? [String: Any],
                  let prompt = args["prompt"] as? String else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "INVALID_ARGS",
                        message: "Missing prompt",
                        details: nil
                    ))
                }
                return
            }
            
            let temperature = (args["temperature"] as? Double) ?? 0.8
            let topP = (args["topP"] as? Double) ?? 0.95
            let topK = (args["topK"] as? Int) ?? 40
            let maxTokens = (args["maxTokens"] as? Int) ?? 512
            let repeatPenalty = (args["repeatPenalty"] as? Double) ?? 1.1
            let stopSequences = self.stopSequencesPayload(from: args)
            
            self.shouldStop = false

            // Initialize streaming generation
            prompt.withCString { cPrompt in
                stopSequences.withCString { cStopSequences in
                    llama_generate_stream_init(
                        cPrompt,
                        Float(temperature),
                        Float(topP),
                        Int32(topK),
                        Int32(maxTokens),
                        Float(repeatPenalty),
                        cStopSequences
                    )
                }
            }
            
            // Stream tokens one by one
            var tokenBuffer = [CChar](repeating: 0, count: 256)
            while !self.shouldStop {
                let hasMore = llama_generate_stream_next(&tokenBuffer, Int32(tokenBuffer.count))
                
                if hasMore {
                    let token = String(cString: tokenBuffer)
                    DispatchQueue.main.async {
                        eventSink(token)
                    }
                } else {
                    break
                }
            }
            
            llama_generate_stream_end()
            
            DispatchQueue.main.async {
                eventSink(FlutterEndOfEventStream)
                result(nil)
            }
        }
    }
    
    // MARK: - Unload Model
    
    private func unloadModel(result: @escaping FlutterResult) {
        if modelLoaded {
            llama_cpp_bridge_free_model()
            modelLoaded = false
            modelPath = nil
            NSLog("[FlutterLlama] Model unloaded")
        }
        result(nil)
    }
    
    // MARK: - Get Model Info
    
    private func getModelInfo(result: @escaping FlutterResult) {
        guard modelLoaded, let modelPath = modelPath else {
            result(nil)
            return
        }
        
        var nParams: Int64 = 0
        var nLayers: Int32 = 0
        var contextSize: Int32 = 0
        
        llama_get_model_info(&nParams, &nLayers, &contextSize)
        
        let info: [String: Any] = [
            "modelPath": modelPath,
            "nParams": nParams,
            "nLayers": nLayers,
            "contextSize": contextSize
        ]
        
        result(info)
    }
    
    // MARK: - Stop Generation
    
    private func stopGeneration(result: @escaping FlutterResult) {
        shouldStop = true
        llama_stop_generation()
        result(nil)
    }
}

// MARK: - C++ Bridge Function Declarations

// These functions will be implemented in llama_cpp_bridge.cpp
@_silgen_name("llama_init_model")
func llama_init_model(
    _ modelPath: UnsafePointer<CChar>,
    _ nThreads: Int32,
    _ nGpuLayers: Int32,
    _ contextSize: Int32,
    _ batchSize: Int32,
    _ useGpu: Bool,
    _ verbose: Bool
) -> Bool

@_silgen_name("llama_generate")
func llama_generate(
    _ prompt: UnsafePointer<CChar>,
    _ temperature: Float,
    _ topP: Float,
    _ topK: Int32,
    _ maxTokens: Int32,
    _ repeatPenalty: Float,
    _ stopSequences: UnsafePointer<CChar>,
    _ output: UnsafeMutablePointer<CChar>,
    _ outputSize: Int32,
    _ tokensGenerated: UnsafeMutablePointer<Int32>
) -> Bool

@_silgen_name("llama_generate_stream_init")
func llama_generate_stream_init(
    _ prompt: UnsafePointer<CChar>,
    _ temperature: Float,
    _ topP: Float,
    _ topK: Int32,
    _ maxTokens: Int32,
    _ repeatPenalty: Float,
    _ stopSequences: UnsafePointer<CChar>
)

@_silgen_name("llama_generate_stream_next")
func llama_generate_stream_next(
    _ output: UnsafeMutablePointer<CChar>,
    _ outputSize: Int32
) -> Bool

@_silgen_name("llama_generate_stream_end")
func llama_generate_stream_end()

@_silgen_name("llama_get_model_info")
func llama_get_model_info(
    _ nParams: UnsafeMutablePointer<Int64>,
    _ nLayers: UnsafeMutablePointer<Int32>,
    _ contextSize: UnsafeMutablePointer<Int32>
)

@_silgen_name("llama_cpp_bridge_free_model")
func llama_cpp_bridge_free_model()

@_silgen_name("llama_stop_generation")
func llama_stop_generation()

@_silgen_name("llama_last_error")
func llama_last_error() -> UnsafePointer<CChar>
