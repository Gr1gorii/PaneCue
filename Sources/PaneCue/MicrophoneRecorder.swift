@preconcurrency import AVFoundation
import Foundation

enum MicrophoneRecorderError: LocalizedError {
    case unavailable
    case conversionUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "PaneCue could not start the microphone."
        case .conversionUnavailable:
            return "PaneCue could not prepare microphone audio for the voice model."
        }
    }
}

final class MicrophoneRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var capturedPCM16 = Data()
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var isTapInstalled = false

    func start() throws {
        if engine.isRunning {
            _ = stop()
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw MicrophoneRecorderError.unavailable
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24_000,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(
            from: inputFormat,
            to: outputFormat
        ) else {
            throw MicrophoneRecorderError.conversionUnavailable
        }

        lock.withLock {
            capturedPCM16.removeAll(keepingCapacity: true)
        }
        self.converter = converter
        self.outputFormat = outputFormat

        inputNode.installTap(
            onBus: 0,
            bufferSize: 2_048,
            format: inputFormat
        ) { [weak self] buffer, _ in
            self?.appendConverted(buffer)
        }
        isTapInstalled = true

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            isTapInstalled = false
            self.converter = nil
            self.outputFormat = nil
            throw error
        }
    }

    func stop() -> Data {
        if engine.isRunning {
            engine.stop()
        }

        if isTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }

        converter = nil
        outputFormat = nil

        return lock.withLock {
            let result = capturedPCM16
            capturedPCM16.removeAll(keepingCapacity: false)
            return result
        }
    }

    private func appendConverted(_ inputBuffer: AVAudioPCMBuffer) {
        guard let converter, let outputFormat else {
            return
        }

        let sampleRateRatio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(
            ceil(Double(inputBuffer.frameLength) * sampleRateRatio)
        ) + 1

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputCapacity
        ) else {
            return
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(
            to: outputBuffer,
            error: &conversionError
        ) { _, outputStatus in
            if suppliedInput {
                outputStatus.pointee = .noDataNow
                return nil
            }

            suppliedInput = true
            outputStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error,
              conversionError == nil,
              outputBuffer.frameLength > 0,
              let samples = outputBuffer.int16ChannelData?[0]
        else {
            return
        }

        let data = Data(
            bytes: samples,
            count: Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
        )
        lock.withLock {
            capturedPCM16.append(data)
        }
    }
}
