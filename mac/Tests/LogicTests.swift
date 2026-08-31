import XCTest
@testable import LensTransLogic

final class LogicTests: XCTestCase {
    func testPresentDecide() {
        XCTAssertEqual(PresentLogic.decide(bgVariance: 5, contrast: false, lock: "auto"), .immersive)
        XCTAssertEqual(PresentLogic.decide(bgVariance: 40, contrast: false, lock: "auto"), .sticker)
        XCTAssertEqual(PresentLogic.decide(bgVariance: 40, contrast: true, lock: "auto"), .stickerContrast)
        XCTAssertEqual(PresentLogic.decide(bgVariance: 5, contrast: false, lock: "sticker"), .sticker)
        XCTAssertEqual(PresentLogic.decide(bgVariance: 40, contrast: false, lock: "immersive"), .immersive)
    }

    func testFadeAlpha() {
        XCTAssertEqual(PresentLogic.fadeAlpha(hasText: true, emptyMs: 0), 1)
        XCTAssertEqual(PresentLogic.fadeAlpha(hasText: false, emptyMs: 0), 1)
        XCTAssertEqual(PresentLogic.fadeAlpha(hasText: false, emptyMs: 200), 0)
        let mid = PresentLogic.fadeAlpha(hasText: false, emptyMs: 100)
        XCTAssertGreaterThan(mid, 0.4)
        XCTAssertLessThan(mid, 0.6)
    }

    func testEnsureAa() {
        var tr = 200, tg = 200, tb = 200
        PresentLogic.ensureAaColor(tr: &tr, tg: &tg, tb: &tb, br: 220, bg: 220, bb: 220)
        XCTAssertEqual(tr, 35)
        XCTAssertEqual(tg, 35)
        XCTAssertEqual(tb, 35)
    }

    func testCloudParseJSON() {
        let body = #"{"choices":[{"message":{"content":"你好"}}]}"#
        XCTAssertEqual(CloudParseLogic.parseChatCompletion(body), "你好")
    }

    func testCloudParseSSE() {
        let sse = """
        data: {"choices":[{"delta":{"content":"你"}}]}
        data: {"choices":[{"delta":{"content":"好"}}]}
        data: [DONE]
        """
        XCTAssertEqual(CloudParseLogic.parseChatCompletion(sse), "你好")
    }

    func testRoute() {
        XCTAssertEqual(EngineRouteLogic.route(pref: "auto", privacy: false, chars: 10, localOk: true, cloudOk: true), .local)
        XCTAssertEqual(EngineRouteLogic.route(pref: "auto", privacy: false, chars: 201, localOk: true, cloudOk: true), .cloud)
        XCTAssertEqual(EngineRouteLogic.route(pref: "cloud", privacy: false, chars: 10, localOk: false, cloudOk: true), .cloud)
        XCTAssertEqual(EngineRouteLogic.route(pref: "auto", privacy: true, chars: 10, localOk: false, cloudOk: true), .none)
    }

    func testModelMeta() {
        XCTAssertEqual(ModelMetaLogic.ggufBytes, 1117320736)
        XCTAssertTrue(ModelMetaLogic.sha256Matches(ModelMetaLogic.ggufSha256))
        XCTAssertTrue(ModelMetaLogic.sha256Matches(ModelMetaLogic.ggufSha256.uppercased()))
        XCTAssertFalse(ModelMetaLogic.sha256Matches("deadbeef"))
        XCTAssertEqual(ModelMetaLogic.idleUnloadMs, 10 * 60 * 1000)
    }

    func testLocalPromptAndStrip() {
        let p = LocalPromptLogic.buildTranslatePrompt(text: "hello", tgtLang: "zh")
        XCTAssertTrue(p.contains("英译简体中文"))
        XCTAssertTrue(p.contains("hello"))
        XCTAssertTrue(p.contains("<|im_start|>assistant"))
        XCTAssertEqual(LocalPromptLogic.stripThink("  \"hi\"\n"), "hi")
        XCTAssertEqual(LocalPromptLogic.stripThink("a<think>x</think>b"), "ab")
        XCTAssertEqual(LocalPromptLogic.stripThink("一块蛋糕 [end of text]"), "一块蛋糕")
    }
}
