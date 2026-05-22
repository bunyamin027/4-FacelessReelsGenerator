import XCTest
@testable import Faceless

final class ReelsBlueprintTests: XCTestCase {

    // MARK: - Mock Blueprint Decoding

    func testMockBlueprintDecoding() throws {
        guard let url = Bundle.main.url(forResource: "mock_blueprint", withExtension: "json") else {
            XCTFail("mock_blueprint.json not found in bundle")
            return
        }

        let data = try Data(contentsOf: url)
        let blueprint = try JSONDecoder().decode(ReelsBlueprint.self, from: data)

        XCTAssertEqual(blueprint.format, "Listicle")
        XCTAssertEqual(blueprint.videoSearchKeyword, "city night aerial")
        XCTAssertEqual(blueprint.audioMood, "energetic")
        XCTAssertEqual(blueprint.textAnimationStyle, "typewriter")
        XCTAssertEqual(blueprint.scenes.count, 3)
        XCTAssertEqual(blueprint.scenes.first?.duration, 5.0)
    }

    // MARK: - Scene Model

    func testSceneCodingKeys() throws {
        let json = """
        {
            "duration": 3.5,
            "on_screen_text": "Test text",
            "voiceover_script": "Test voiceover"
        }
        """
        let data = Data(json.utf8)
        let scene = try JSONDecoder().decode(Scene.self, from: data)

        XCTAssertEqual(scene.duration, 3.5)
        XCTAssertEqual(scene.onScreenText, "Test text")
        XCTAssertEqual(scene.voiceoverScript, "Test voiceover")
    }
}
