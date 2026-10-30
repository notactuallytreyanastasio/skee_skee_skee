import Foundation
import Observation
import QuartzCore
import SceneKit
import SkeeCore
import SkeeHUD
import SkeeRender
import SkeeScene
import UIKit

/// The imperative shell. Holds current values, feeds input to the pure
/// functions, performs effects. Rules live in SkeeCore (`apply`,
/// `analyzeStroke`); timing in SkeeRender (`Presentation`); the 3D scene in
/// SkeeScene; the HUD in SkeeHUD.
/// Shared between the main thread (input, HUD) and SceneKit's render thread
/// (moving the scene). Every access goes through the lock.
final class Stage: @unchecked Sendable {
    private let lock = NSLock()
    private var presentation: Presentation
    private var finished: [Beat] = []
    private var held: SIMD3<Float>?
    private var lastRender: TimeInterval?

    init(_ p: Presentation) { presentation = p }

    func with<T>(_ f: (inout Presentation) -> T) -> T { lock.lock(); defer { lock.unlock() }; return f(&presentation) }
    var snapshot: Presentation { with { $0 } }
    func setHeld(_ h: SIMD3<Float>?) { lock.lock(); held = h; lock.unlock() }

    /// Render thread: advance by the render clock, return what to draw.
    func advance(to time: TimeInterval) -> (Presentation, SIMD3<Float>?, Double) {
        lock.lock(); defer { lock.unlock() }
        let dt = min(1.0 / 20, max(0, time - (lastRender ?? time)))
        lastRender = time
        presentation.advance(dt)
        finished += presentation.finished
        return (presentation, held, dt)
    }

    /// Main thread: beats finished since last asked, for haptics.
    func takeFinished() -> [Beat] { lock.lock(); defer { lock.unlock() }; let f = finished; finished = []; return f }
}

/// SceneKit calls this on its render thread before every frame. Moving the
/// ball here, by the render clock, is what makes the roll smooth: updating
/// from a separate display link raced the renderer and stuttered.
final class RenderDriver: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    let stage: Stage
    let presenter: ScenePresenter
    init(stage: Stage, presenter: ScenePresenter) { self.stage = stage; self.presenter = presenter }

    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let (p, held, dt) = stage.advance(to: time)
        presenter.update(p, held: held, dt: dt)
    }
}

/// The imperative shell. Holds current values, feeds input to the pure
/// functions, performs effects. Rules live in SkeeCore (`apply`,
/// `analyzeStroke`); timing in SkeeRender (`Presentation`); the 3D scene in
/// SkeeScene; the HUD in SkeeHUD.
@Observable
@MainActor
final class GameModel {
    private(set) var state: RunState
    private(set) var hud = HUDState()
    var screen: HUDState.Screen = .title
    var selectedOffer: Int?
    var selectedCharm: Int?
    var fold: Double = 0

    @ObservationIgnored let cabinet = Cabinet()
    @ObservationIgnored let presenter: ScenePresenter
    @ObservationIgnored let stage: Stage
    @ObservationIgnored let driver: RenderDriver
    @ObservationIgnored var viewSize = CGSize(width: 626, height: 890)
    @ObservationIgnored private var seed: UInt64
    @ObservationIgnored private var actions: [Action] = []
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private let haptics = Haptics()
    @ObservationIgnored private var autoplay: [Launch] = []
    @ObservationIgnored private var stroke: [StrokeSample] = []

    init() {
        let args = LaunchArguments()
        var seed = args.seed ?? UInt64(Date().timeIntervalSince1970)
        var s: RunState
        var actions: [Action] = []
        if let saved = RunStore.load(), !args.fresh {
            seed = saved.seed
            s = newRun(seed: saved.seed)
            for a in saved.actions {
                guard case .success(let step) = apply(a, to: s) else { break }
                s = step.state
                actions.append(a)
            }
        } else {
            s = newRun(seed: seed)
        }
        if let ante = args.ante { s.ante = ante; s.round.target = s.config.target(ante: ante, kind: .warmup) }
        self.seed = seed
        self.state = s
        self.actions = actions
        let presenter = ScenePresenter(cabinet: cabinet, aspect: 626.0 / 890.0)
        self.presenter = presenter
        let stage = Stage(Presentation(state: s))
        self.stage = stage
        self.driver = RenderDriver(stage: stage, presenter: presenter)
        self.screen = args.skipTitle || !actions.isEmpty || !args.autoplay.isEmpty ? .game : .title
        if let f = args.fold { fold = f }
        self.autoplay = args.autoplay
    }

    // MARK: main-thread clock: HUD, haptics, autoplay

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: DisplayTarget(self), selector: #selector(DisplayTarget.step(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    func resized(_ size: CGSize) {
        guard size.width > 0, size != viewSize else { return }
        viewSize = size
        presenter.refit(aspect: Float(size.width / size.height))
    }

    fileprivate func tick() {
        for beat in stage.takeFinished() { haptics.play(beat) }
        let p = stage.snapshot
        refreshHUD(p)
        if !p.isBusy, case .throwing = state.phase, !autoplay.isEmpty {
            send(.throwBall(autoplay.removeFirst()))
        }
    }

    func refreshHUD(_ p: Presentation) {
        let size = viewSize
        let a = Float(size.width / size.height)
        let w = cabinet.world
        let rig = presenter.rig
        hud = HUDState.make(p, holeOnScreen: { hole in
            let f = rig.project(w.board(w.table.board.holeCenter(hole)), aspect: a)
            return CGPoint(x: CGFloat(f.x) * size.width, y: CGFloat(f.y) * size.height)
        }, center: CGPoint(x: size.width / 2, y: size.height * 0.2),
           selectedOffer: selectedOffer, selectedCharm: selectedCharm, screen: screen)
    }

    // MARK: thumb

    var geometry: StrokeGeometry { presenter.strokeGeometry(size: viewSize) }
    var busy: Bool { stage.with { $0.isBusy } }
    var canThrow: Bool {
        if screen != .game || busy { return false }
        if case .throwing = state.phase { return true }
        return false
    }

    /// A touch on the glass, mapped onto the lane. The ball sits just above
    /// the thumb so it stays visible.
    func sample(t: Double, x: Double, y: Double) -> StrokeSample? {
        let f = SIMD2(Float(x / viewSize.width), Float((y - 34) / viewSize.height))
        guard let p = presenter.lanePoint(screen: f, aspect: Float(viewSize.width / viewSize.height)) else { return nil }
        let lane = presenter.laneCoordinates(p)
        return StrokeSample(t: t, screenX: x, screenY: y, x: lane.x, s: lane.s)
    }

    func touchBegan(t: Double, x: Double, y: Double) {
        if busy { stage.with { $0.skip() }; return }
        guard canThrow, y > geometry.creaseY, let s = sample(t: t, x: x, y: y) else { return }
        stroke = [s]
        holdBall(s)
    }

    func touchMoved(_ touches: [(t: Double, x: Double, y: Double)]) {
        guard !stroke.isEmpty else { return }
        let samples = touches.compactMap { sample(t: $0.t, x: $0.x, y: $0.y) }
        stroke += samples
        if crossedCrease(samples, in: geometry) {
            // Well past the crease: foul, right now, like stepping over the line.
            stroke = []
            stage.setHeld(nil)
            haptics.foul()
            send(.foul)
            return
        }
        if let last = samples.last { holdBall(last) }
    }

    func touchEnded(_ touches: [(t: Double, x: Double, y: Double)]) {
        guard !stroke.isEmpty else { return }
        stroke += touches.compactMap { sample(t: $0.t, x: $0.x, y: $0.y) }
        let outcome = analyzeStroke(stroke, in: geometry, fold: fold)
        stroke = []
        stage.setHeld(nil)
        switch outcome {
        case .none: break
        case .foul: haptics.foul(); send(.foul)
        case .release(let l): send(.throwBall(l))
        }
    }

    func touchCancelled() { stroke = []; stage.setHeld(nil) }

    private func holdBall(_ s: StrokeSample) {
        let w = cabinet.world
        stage.setHeld(w.lane(x: s.x, s: s.s) + w.laneNormal * w.ballRadius)
    }

    /// A tap on the board while a stamp, gild or purge is selected.
    func tapBoard(at p: CGPoint) -> Bool {
        guard let sel = selectedOffer else { return false }
        let a = Float(viewSize.width / viewSize.height)
        let w = cabinet.world
        let hit = BoardSetup.reelHoles.map { hole -> (Hole, CGFloat) in
            let f = presenter.rig.project(w.board(w.table.board.holeCenter(hole)), aspect: a)
            return (hole, hypot(CGFloat(f.x) * viewSize.width - p.x, CGFloat(f.y) * viewSize.height - p.y))
        }.min { $0.1 < $1.1 }
        selectedOffer = nil
        if let hit, hit.1 < 44 { send(.buy(sel, target: hit.0)); return true }
        return false
    }

    // MARK: HUD actions

    var hudActions: HUDActions {
        var a = HUDActions()
        a.buy = { [weak self] i in self?.send(.buy(i, target: nil)) }
        a.selectOffer = { [weak self] i in self?.selectedOffer = i; self?.haptics.tap() }
        a.reroll = { [weak self] in self?.send(.reroll) }
        a.leave = { [weak self] in self?.selectedOffer = nil; self?.send(.leaveCounter) }
        a.tapCharm = { [weak self] i in
            guard let self else { return }
            if case .prizeCounter = state.phase, selectedCharm == i { selectedCharm = nil; send(.sell(i)) }
            else if case .prizeCounter = state.phase { selectedCharm = i; haptics.tap() }
        }
        a.arm = { [weak self] i in self?.send(.arm(i)) }
        a.start = { [weak self] in self?.screen = .game; self?.haptics.tap() }
        a.newRun = { [weak self] in self?.newGame() }
        return a
    }

    // MARK: effects

    func send(_ action: Action) {
        switch apply(action, to: state) {
        case .failure:
            haptics.reject()
        case .success(let step):
            state = step.state
            actions.append(action)
            stage.with { $0.enqueue(step) }
            RunStore.save(seed: seed, actions: actions)
            if case .throwBall = action { haptics.launch() } else { haptics.tap() }
        }
    }

    func newGame() {
        seed = UInt64(Date().timeIntervalSince1970)
        actions = []
        state = newRun(seed: seed)
        let fresh = Presentation(state: state)
        stage.with { $0 = fresh }
        selectedOffer = nil; selectedCharm = nil
        screen = .game
        RunStore.save(seed: seed, actions: actions)
    }
}

/// CADisplayLink retains its target; this breaks the cycle.
private final class DisplayTarget {
    weak var model: GameModel?
    init(_ m: GameModel) { model = m }
    @MainActor @objc func step(_ link: CADisplayLink) { model?.tick() }
}

/// Debug and screenshot hooks, read from the launch arguments.
///   -seed 42   -fresh   -ante 5   -fold 0.6   -skipTitle
///   -autoplay "0.62,0;0.55,0.1"   throw these launches (power,aim[,start])
struct LaunchArguments {
    var seed: UInt64?
    var fresh = false
    var ante: Int?
    var fold: Double?
    var autoplay: [Launch] = []
    var skipTitle = false

    init(_ argv: [String] = ProcessInfo.processInfo.arguments) {
        func value(_ k: String) -> String? {
            guard let i = argv.firstIndex(of: k), i + 1 < argv.count else { return nil }
            return argv[i + 1]
        }
        seed = value("-seed").flatMap(UInt64.init)
        fresh = argv.contains("-fresh") || seed != nil
        ante = value("-ante").flatMap(Int.init)
        fold = value("-fold").flatMap(Double.init)
        skipTitle = argv.contains("-skipTitle")
        autoplay = (value("-autoplay") ?? "").split(separator: ";").compactMap { item in
            let n = item.split(separator: ",").compactMap { Double($0) }
            guard n.count >= 2 else { return nil }
            return Launch(power: n[0], aim: n[1], start: n.count > 2 ? n[2] : 0)
        }
    }
}

/// The run on disk is the seed and the actions; replaying rebuilds it.
enum RunStore {
    struct File: Codable { var seed: UInt64; var actions: [Action] }
    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("run.json")
    }
    static func save(seed: UInt64, actions: [Action]) {
        if let data = try? JSONEncoder().encode(File(seed: seed, actions: actions)) { try? data.write(to: url) }
    }
    static func load() -> File? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data)
    }
}

@MainActor
final class Haptics {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let note = UINotificationFeedbackGenerator()

    func tap() { light.impactOccurred() }
    func launch() { rigid.impactOccurred(intensity: 0.7) }
    func reject() { note.notificationOccurred(.warning) }
    func foul() { note.notificationOccurred(.error) }

    func play(_ beat: Beat) {
        switch beat {
        case .roll(let r, let b):
            if b.hole == .gutter { note.notificationOccurred(.error) }
            else { heavy.impactOccurred(intensity: min(1, 0.4 + CGFloat(b.hole.faceValue) / 120)) }
            if r.rattles > 0 { rigid.impactOccurred() }
        case .tally(let f):
            if f.isJackpot { note.notificationOccurred(.success) } else { light.impactOccurred() }
        case .banner(let t, _, _) where t == "CLEARED":
            note.notificationOccurred(.success)
        default: break
        }
    }
}
