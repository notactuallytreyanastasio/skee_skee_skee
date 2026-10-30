import Testing
import CoreGraphics
import SkeeCore
@testable import SkeeRender

@Suite("Art styles")
struct ArtStyleTests {
    @Test func everyTwoAntesTheStyleChanges() {
        #expect(ArtStyle.forAnte(1) == .pixel)
        #expect(ArtStyle.forAnte(2) == .pixel)
        #expect(ArtStyle.forAnte(3) == .cel)
        #expect(ArtStyle.forAnte(5) == .depth)
        #expect(ArtStyle.forAnte(7) == .neon)
        #expect(ArtStyle.forAnte(8) == .neon)
        #expect(Set((1...8).map(ArtStyle.forAnte)) == Set(ArtStyle.allCases))
    }
}

@Suite("Layout")
struct LayoutTests {
    let layout = Layout(size: CGSize(width: 669, height: 951))

    @Test func hingeSplitsTheScreenInHalf() {
        #expect(layout.hingeY == 475.5)
        #expect(layout.boardRect.maxY <= layout.hingeY)
        #expect(layout.laneRect.minY >= layout.hingeY)
    }

    @Test(arguments: ArtStyle.allCases)
    func laneAndBoardMeetAtTheHinge(style: ArtStyle) {
        let p = Projection(layout: layout, style: style)
        let laneEnd = p.lane(x: 0.2, s: Table.standard.lane.length)
        let boardStart = p.board(Vec2(0.2, 0))
        #expect(abs(laneEnd.x - boardStart.x) < 0.5)
        #expect(abs(laneEnd.y - layout.hingeY) < 0.5)
        #expect(abs(boardStart.y - layout.hingeY) < 0.5)
    }

    @Test(arguments: ArtStyle.allCases)
    func boardGoesUpAndLaneComesDown(style: ArtStyle) {
        let p = Projection(layout: layout, style: style)
        #expect(p.board(Vec2(0, 1)).y < p.board(Vec2(0, 0)).y)
        #expect(p.lane(x: 0, s: 0).y > p.lane(x: 0, s: 2.4).y)
        #expect(p.board(Vec2(0.3, 0.5)).x > p.board(Vec2(-0.3, 0.5)).x)
    }

    @Test func boardToScreenRoundTrips() {
        let p = Projection(layout: layout, style: .pixel)
        let w = Vec2(0.12, 0.7)
        let back = p.boardPoint(at: p.board(w))
        #expect(abs(back.x - w.x) < 1e-6 && abs(back.y - w.y) < 1e-6)
    }
}

@Suite("Swipe to launch")
struct SwipeTests {
    let layout = Layout(size: CGSize(width: 669, height: 951))

    @Test func fasterSwipeIsMorePower() {
        let slow = Swipe(start: CGPoint(x: 334, y: 900), end: CGPoint(x: 334, y: 700), velocity: CGVector(dx: 0, dy: -900))
        let fast = Swipe(start: CGPoint(x: 334, y: 900), end: CGPoint(x: 334, y: 700), velocity: CGVector(dx: 0, dy: -2200))
        #expect(slow.launch(in: layout, fold: 0)!.power < fast.launch(in: layout, fold: 0)!.power)
    }

    @Test func swipeRightAimsRight() {
        let s = Swipe(start: CGPoint(x: 334, y: 900), end: CGPoint(x: 400, y: 700), velocity: CGVector(dx: 300, dy: -1500))
        #expect(s.launch(in: layout, fold: 0)!.aim > 0)
    }

    @Test func releasePointSetsStart() {
        let s = Swipe(start: CGPoint(x: 100, y: 900), end: CGPoint(x: 100, y: 700), velocity: CGVector(dx: 0, dy: -1500))
        #expect(s.launch(in: layout, fold: 0)!.start < -0.5)
    }

    @Test func downwardSwipeIsNotAThrow() {
        let s = Swipe(start: CGPoint(x: 334, y: 700), end: CGPoint(x: 334, y: 900), velocity: CGVector(dx: 0, dy: 1500))
        #expect(s.launch(in: layout, fold: 0) == nil)
    }
}
