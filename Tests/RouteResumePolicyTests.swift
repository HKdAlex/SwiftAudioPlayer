import XCTest
@testable import SwiftAudioPlayer

final class RouteResumePolicyTests: XCTestCase {
    private func playing() -> RouteResumePolicy {
        var policy = RouteResumePolicy()
        policy.externalRouteLost(wasPlaying: true, now: Date(timeIntervalSince1970: 1_000))
        return policy
    }

    func testCarBluetoothReturnWithinGraceResumes() {
        var policy = playing()
        let resume = policy.externalRouteReturned(
            now: Date(timeIntervalSince1970: 1_003),
            outputIsExternal: true
        )
        XCTAssertTrue(resume)
    }

    func testReturnAfterGraceStaysPaused() {
        var policy = playing()
        let resume = policy.externalRouteReturned(
            now: Date(timeIntervalSince1970: 1_030),
            outputIsExternal: true
        )
        XCTAssertFalse(resume)
    }

    func testPhoneSpeakerDoesNotResume() {
        var policy = playing()
        let resume = policy.externalRouteReturned(
            now: Date(timeIntervalSince1970: 1_002),
            outputIsExternal: false
        )
        XCTAssertFalse(resume)
        XCTAssertNotNil(policy.resumeUntil)
    }

    func testUserPauseCancelsResume() {
        var policy = playing()
        policy.userPaused()
        let resume = policy.externalRouteReturned(
            now: Date(timeIntervalSince1970: 1_002),
            outputIsExternal: true
        )
        XCTAssertFalse(resume)
    }

    func testIdleRouteLossDoesNotArmResume() {
        var policy = RouteResumePolicy()
        policy.externalRouteLost(wasPlaying: false, now: Date(timeIntervalSince1970: 1_000))
        let resume = policy.externalRouteReturned(
            now: Date(timeIntervalSince1970: 1_001),
            outputIsExternal: true
        )
        XCTAssertFalse(resume)
    }

    func testCarAndSpeakerPortTypes() {
        XCTAssertTrue(RouteResumePolicy.isExternalOutput(portType: "BluetoothA2DPOutput"))
        XCTAssertTrue(RouteResumePolicy.isExternalOutput(portType: "CarAudio"))
        XCTAssertFalse(RouteResumePolicy.isExternalOutput(portType: "Speaker"))
    }
}
