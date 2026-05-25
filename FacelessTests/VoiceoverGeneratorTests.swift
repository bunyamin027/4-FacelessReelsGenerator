//
//  VoiceoverGeneratorTests.swift
//  FacelessTests
//
//  Unit tests for VoiceoverGenerator.
//
//  NOTE: AVSpeechSynthesizer.write() may only produce audio output on
//  physical devices. These tests are expected to pass on device but may
//  throw `noAudioBufferReceived` on the Simulator.
//

import XCTest
@testable import Faceless

final class VoiceoverGeneratorTests: XCTestCase {

    // MARK: - Properties

    private var sut: VoiceoverGenerator!

    // MARK: - Lifecycle

    override func setUp() {
        super.setUp()
        sut = VoiceoverGenerator()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - VoiceConfig Tests

    func testDefaultVoiceConfig() {
        let config = VoiceoverGenerator.VoiceConfig.default

        XCTAssertEqual(config.language, "tr-TR")
        XCTAssertEqual(config.pitch, 1.0)
        XCTAssertEqual(config.volume, 1.0)
        XCTAssertEqual(config.preUtteranceDelay, 0.0)
        XCTAssertEqual(config.postUtteranceDelay, 0.0)
    }

    func testCustomVoiceConfig() {
        let config = VoiceoverGenerator.VoiceConfig(
            rate: 0.3,
            pitch: 1.5,
            volume: 0.8,
            language: "en-US",
            preUtteranceDelay: 0.1,
            postUtteranceDelay: 0.2
        )

        let generator = VoiceoverGenerator(voiceConfig: config)
        XCTAssertEqual(generator.voiceConfig.language, "en-US")
        XCTAssertEqual(generator.voiceConfig.rate, 0.3)
        XCTAssertEqual(generator.voiceConfig.pitch, 1.5)
        XCTAssertEqual(generator.voiceConfig.volume, 0.8)
    }

    // MARK: - Error Cases

    func testSynthesizeSpeechWithEmptyTextThrows() async {
        do {
            _ = try await sut.synthesizeSpeech(text: "")
            XCTFail("Expected VoiceoverError.emptyText to be thrown")
        } catch let error as VoiceoverGenerator.VoiceoverError {
            XCTAssertEqual(
                error.errorDescription,
                "Cannot generate voiceover from empty text."
            )
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testSynthesizeSpeechWithWhitespaceOnlyThrows() async {
        do {
            _ = try await sut.synthesizeSpeech(text: "   \n\t  ")
            XCTFail("Expected VoiceoverError.emptyText to be thrown")
        } catch let error as VoiceoverGenerator.VoiceoverError {
            XCTAssertEqual(
                error.errorDescription,
                "Cannot generate voiceover from empty text."
            )
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testGenerateVoiceoverWithEmptyScenesThrows() async {
        let scenes: [Scene] = []

        do {
            _ = try await sut.generateVoiceover(for: scenes)
            XCTFail("Expected VoiceoverError.emptyText to be thrown")
        } catch let error as VoiceoverGenerator.VoiceoverError {
            XCTAssertEqual(
                error.errorDescription,
                "Cannot generate voiceover from empty text."
            )
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testGenerateVoiceoverWithEmptyScriptsThrows() async {
        let scenes = [
            Scene(duration: 3.0, onScreenText: "Visual only", voiceoverScript: "", videoSearchKeyword: "test"),
            Scene(duration: 2.0, onScreenText: "No narration", voiceoverScript: "   ", videoSearchKeyword: "test")
        ]

        do {
            _ = try await sut.generateVoiceover(for: scenes)
            XCTFail("Expected VoiceoverError.emptyText to be thrown")
        } catch let error as VoiceoverGenerator.VoiceoverError {
            XCTAssertEqual(
                error.errorDescription,
                "Cannot generate voiceover from empty text."
            )
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testCombineAudioFilesWithEmptyArrayThrows() async {
        do {
            _ = try await sut.combineAudioFiles([])
            XCTFail("Expected VoiceoverError.noAudioFiles to be thrown")
        } catch let error as VoiceoverGenerator.VoiceoverError {
            XCTAssertEqual(
                error.errorDescription,
                "No audio files to combine."
            )
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Error Description Coverage

    func testErrorDescriptions() {
        let errors: [(VoiceoverGenerator.VoiceoverError, String)] = [
            (.emptyText, "Cannot generate voiceover from empty text."),
            (.synthesisFailure("timeout"), "Speech synthesis failed: timeout"),
            (.noAudioBufferReceived, "No audio buffer was received from the speech synthesizer."),
            (.audioFileCreationFailed("disk full"), "Failed to create audio file: disk full"),
            (.exportFailed("codec error"), "Audio export failed: codec error"),
            (.exportCancelled, "Audio export was cancelled."),
            (.noAudioFiles, "No audio files to combine."),
        ]

        for (error, expected) in errors {
            XCTAssertEqual(error.errorDescription, expected)
        }
    }

    // MARK: - On-Device Tests (AVSpeechSynthesizer.write)

    /// Tests that a single speech synthesis produces a non-empty .caf file.
    ///
    /// ⚠️ This test requires a physical device. AVSpeechSynthesizer.write()
    /// may not produce audio output on the iOS Simulator.
    func testSingleSpeechSynthesisProducesFile() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("AVSpeechSynthesizer.write() does not reliably produce audio on Simulator.")
        #else
        let url = try await sut.synthesizeSpeech(text: "Merhaba dünya, bu bir test.")

        // Verify file exists and is non-empty
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        XCTAssertTrue(fileExists, "Generated audio file should exist")

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        XCTAssertGreaterThan(fileSize, 0, "Generated audio file should be non-empty")

        // Verify it's a .caf file
        XCTAssertEqual(url.pathExtension, "caf")

        // Clean up
        try? FileManager.default.removeItem(at: url)
        #endif
    }

    /// Tests generating voiceover for multiple scenes produces a combined .m4a file.
    ///
    /// ⚠️ Requires a physical device.
    func testMultipleSceneVoiceoverGeneration() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("AVSpeechSynthesizer.write() does not reliably produce audio on Simulator.")
        #else
        let scenes = [
            Scene(duration: 3.0, onScreenText: "Sahne 1", voiceoverScript: "Birinci sahne metni.", videoSearchKeyword: "test"),
            Scene(duration: 4.0, onScreenText: "Sahne 2", voiceoverScript: "İkinci sahne metni.", videoSearchKeyword: "test"),
            Scene(duration: 2.5, onScreenText: "Sahne 3", voiceoverScript: "Üçüncü sahne.", videoSearchKeyword: "test")
        ]

        let combinedURL = try await sut.generateVoiceover(for: scenes)

        // Verify the combined file
        let fileExists = FileManager.default.fileExists(atPath: combinedURL.path)
        XCTAssertTrue(fileExists, "Combined audio file should exist")

        let attributes = try FileManager.default.attributesOfItem(atPath: combinedURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        XCTAssertGreaterThan(fileSize, 0, "Combined file should be non-empty")

        // Should be .m4a
        XCTAssertEqual(combinedURL.pathExtension, "m4a")

        // Clean up
        try? FileManager.default.removeItem(at: combinedURL)
        #endif
    }

    /// Tests that scenes with empty scripts are filtered out.
    ///
    /// ⚠️ Requires a physical device.
    func testScenesWithMixedEmptyScriptsFilterCorrectly() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("AVSpeechSynthesizer.write() does not reliably produce audio on Simulator.")
        #else
        let scenes = [
            Scene(duration: 2.0, onScreenText: "Visual", voiceoverScript: "", videoSearchKeyword: "test"),
            Scene(duration: 3.0, onScreenText: "Narrated", voiceoverScript: "Bu sahne sesli.", videoSearchKeyword: "test"),
            Scene(duration: 2.0, onScreenText: "Silent", voiceoverScript: "   ", videoSearchKeyword: "test")
        ]

        // Should succeed — only the middle scene has valid text
        let url = try await sut.generateVoiceover(for: scenes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // Clean up
        try? FileManager.default.removeItem(at: url)
        #endif
    }

    /// Tests synthesis with a custom language (English).
    ///
    /// ⚠️ Requires a physical device.
    func testSynthesisWithCustomLanguage() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("AVSpeechSynthesizer.write() does not reliably produce audio on Simulator.")
        #else
        let url = try await sut.synthesizeSpeech(
            text: "Hello world, this is a test.",
            language: "en-US"
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        XCTAssertGreaterThan(fileSize, 0)

        // Clean up
        try? FileManager.default.removeItem(at: url)
        #endif
    }
}
