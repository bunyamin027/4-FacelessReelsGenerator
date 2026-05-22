import XCTest
import Combine
@testable import Faceless

@MainActor
final class ViewModelTests: XCTestCase {
    
    var viewModel: ReelGeneratorViewModel!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        viewModel = ReelGeneratorViewModel()
        cancellables = []
    }
    
    override func tearDown() {
        viewModel = nil
        cancellables = nil
        super.tearDown()
    }
    
    func testViewModel_InitialState() {
        XCTAssertEqual(viewModel.topicInput, "", "Initial topic should be empty")
        XCTAssertEqual(viewModel.currentPhase, .idle, "Initial phase should be idle")
        XCTAssertNil(viewModel.errorMessage, "Initial error message should be nil")
        XCTAssertNil(viewModel.generatedVideoURL, "Initial generated video URL should be nil")
        XCTAssertNil(viewModel.generatedAudioURL, "Initial generated audio URL should be nil")
        XCTAssertFalse(viewModel.isShowingPreview, "Initial isShowingPreview should be false")
        XCTAssertFalse(viewModel.isGenerating, "Initial isGenerating should be false")
        XCTAssertEqual(viewModel.progressValue, 0.0, "Initial progress value should be 0")
        XCTAssertNil(viewModel.currentBlueprint, "Initial blueprint should be nil")
    }
    
    func testViewModel_EmptyTopicValidation() {
        viewModel.topicInput = "   " // Just spaces
        viewModel.generateReel(isPro: false)
        
        XCTAssertEqual(viewModel.errorMessage, "Lütfen bir konu girin.", "Should show validation error for empty topic")
        XCTAssertFalse(viewModel.isGenerating, "Should not be generating after validation failure")
        XCTAssertEqual(viewModel.currentPhase, .idle, "Phase should remain idle")
    }
    
    func testViewModel_CancelGeneration() {
        // We set generating to true manually for the sake of the test
        viewModel.isGenerating = true
        viewModel.currentPhase = .fetchingVideo
        viewModel.progressValue = 0.5
        
        viewModel.cancelGeneration()
        
        XCTAssertFalse(viewModel.isGenerating, "isGenerating should be false after cancellation")
        XCTAssertEqual(viewModel.currentPhase, .idle, "Phase should revert to idle after cancellation")
        XCTAssertEqual(viewModel.progressValue, 0.0, "Progress should revert to 0 after cancellation")
    }
    
    func testViewModel_Reset() {
        // Set some dummy state
        viewModel.topicInput = "A great topic"
        viewModel.currentPhase = .completed
        viewModel.errorMessage = "Some error"
        viewModel.generatedVideoURL = URL(string: "https://example.com/video.mp4")
        viewModel.generatedAudioURL = URL(string: "https://example.com/audio.m4a")
        viewModel.isShowingPreview = true
        viewModel.isGenerating = true
        viewModel.progressValue = 1.0
        
        viewModel.reset()
        
        XCTAssertEqual(viewModel.topicInput, "", "Topic should be cleared after reset")
        XCTAssertEqual(viewModel.currentPhase, .idle, "Phase should be idle after reset")
        XCTAssertNil(viewModel.errorMessage, "Error message should be cleared after reset")
        XCTAssertNil(viewModel.generatedVideoURL, "Video URL should be cleared after reset")
        XCTAssertNil(viewModel.generatedAudioURL, "Audio URL should be cleared after reset")
        XCTAssertFalse(viewModel.isShowingPreview, "Preview should be hidden after reset")
        XCTAssertFalse(viewModel.isGenerating, "isGenerating should be false after reset")
        XCTAssertEqual(viewModel.progressValue, 0.0, "Progress should be 0 after reset")
        XCTAssertNil(viewModel.currentBlueprint, "Blueprint should be cleared after reset")
    }
    
    func testViewModel_PhaseChangesOnGenerate() async {
        let expectation = XCTestExpectation(description: "ViewModel transitions out of idle phase")
        
        viewModel.topicInput = "Test topic for phase changes"
        
        // Listen to phase changes
        viewModel.$currentPhase
            .dropFirst() // Ignore the initial '.idle' state
            .sink { phase in
                if phase == .creatingBlueprint {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        viewModel.generateReel(isPro: false)
        
        // Yield to allow the Task to begin executing
        try? await Task.sleep(nanoseconds: 10_000_000)
        
        XCTAssertTrue(viewModel.isGenerating, "ViewModel should mark generation as in progress")
        XCTAssertNil(viewModel.errorMessage, "Error message should be cleared upon new generation")
        
        await fulfillment(of: [expectation], timeout: 3.0)
        
        // Let's cancel it right after we confirm the state transition to prevent side effects
        viewModel.cancelGeneration()
    }
}
