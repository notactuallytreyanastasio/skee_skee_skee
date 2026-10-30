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
@Observable
@MainActor
final class GameModel {
    private(set) var state: RunState
    private(set) var presentation: Presentation
    private(set) var hud = HUDState()
    var screen: HUDState.Screen = .title
    var selectedOffer: Int?
    var selectedCharm: Int?
    var fold: Double = 0

    @ObservationIgnored let cabinet = Cabinet()
    @ObservationIgnored private(set) var presenter: ScenePresenter
    @ObservationIgnored var viewSize = CGSize(width: 626, height: 890)
    @ObservationIgnored private var seed: UInt64
    @ObservationIgnored private var actions: [Action] = []
    @ObservationIgnored private var lastTick: CFTimeInterval?
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private let haptics = Haptics()
    @ObservationIgnored private var autoplay: [Launch] = []
    /// The stroke in progress, if the thumb is down on the lane.
    @ObservationIgnored private var stroke: [TouchSample] = []
    @ObservationIgnored private var held: SIMD3<Float>?

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
        self.presentation = Presentation(state: s)
        self.presenter = ScenePresenter(cabinet: cabinet, aspect: 626.0 / 890.0)
        self.screen = args.skipTitle || !actions.isEmpty || !args.autoplay.isEmpty ? .game : .title
        if let f = args.fold { fold = f }
        self.autoplay = args.autoplay
    }

    // MARK: clock

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

    fileprivate func tick(_ now: CFTimeInterval) {
        let dt = min(1.0 / 20, now - (lastTick ?? now))
        lastTick = now
        presentation.advance(dt)
        for beat in presentation.finished { haptics.play(beat) }
        presenter.update(presentation, held: held, dt: dt)
        refreshHUD()
        if !presentation.isBusy, case .throwing = state.phase, !autoplay.isEmpty {
            send(.throwBall(autoplay.removeFirst()))
        }
    }

    func refreshHUD() {
        let size = viewSize
        let a = Float(size.width / size.height)
        let w = cabinet.world
        hud = HUDState.make(presentation, holeOnScreen: { [presenter] hole in
            let f = presenter.rig.project(w.board(w.table.board.holeCenter(hole)), aspect: a)
            return CGPoint(x: CGFloat(f.x) * size.width, y: CGFloat(f.y) * size.height)
        }, center: CGPoint(x: size.width / 2, y: size.height * 0.2),
           selectedOffer: selectedOffer, selectedCharm: selectedCharm, screen: screen)
    }

    // MARK: thumb

    var geometry: StrokeGeometry { presenter.strokeGeometry(size: viewSize) }
    var canThrow: Bool {
        if screen != .game || presentation.isBusy { return false }
        if case .throwing = state.phase { return true }
        return false
    }

    func touchBegan(_ s: TouchSample) {
        if presentation.isBusy { presentation.skip(); return }
        guard canThrow, s.y > geometry.creaseY else { return }
        stroke = [s]
        hold(at: s)
    }

    func touchMoved(_ samples: [TouchSample]) {
        guard !stroke.isEmpty else { return }
        stroke += samples
        if crossedCrease(samples, in: geometry) {
            // Past the crease: foul, right now, like stepping over the line.
            stroke = []
            held = nil
            haptics.foul()
            send(.foul)
            return
        }
        if let last = samples.last { hold(at: last) }
    }

    func touchEnded(_ samples: [TouchSample]) {
        guard !stroke.isEmpty else { return }
        stroke += samples
        let outcome = analyzeStroke(stroke, in: geometry, fold: fold)
        let releaseAlong = held.map(alongLane) ?? 0
        stroke = []
        held = nil
        switch outcome {
        case .none: break
        case .foul: haptics.foul(); send(.foul)
        case .release(let l): send(.throwBall(l), releaseAlong: releaseAlong)
        }
    }

    func touchCancelled() { stroke = []; held = nil }

    /// The ball sits just above the thumb so it stays visible.
    private func hold(at s: TouchSample) {
        let f = SIMD2(Float(s.x / viewSize.width), Float((s.y - 34) / viewSize.height))
        held = presenter.lanePoint(screen: f, aspect: Float(viewSize.width / viewSize.height))
    }

    private func alongLane(_ p: SIMD3<Float>) -> Double {
        let w = cabinet.world
        return Double(max(0, simd_dot(p - w.lane(x: 0, s: 0), w.laneForward) / w.laneScale))
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

    func send(_ action: Action, releaseAlong: Double = 0) {
        switch apply(action, to: state) {
        case .failure:
            haptics.reject()
        case .success(let step):
            state = step.state
            actions.append(action)
            presentation.enqueue(step, releaseAlong: releaseAlong)
            RunStore.save(seed: seed, actions: actions)
            if case .throwBall = action { haptics.launch() } else { haptics.tap() }
        }
    }

    func newGame() {
        seed = UInt64(Date().timeIntervalSince1970)
        actions = []
        state = newRun(seed: seed)
        presentation = Presentation(state: state)
        selectedOffer = nil; selectedCharm = nil
        screen = .game
        RunStore.save(seed: seed, actions: actions)
    }
}

/// CADisplayLink retains its target; this breaks the cycle.
private final class DisplayTarget {
    weak var model: GameModel?
    init(_ m: GameModel) { model = m }
    @MainActor @objc func step(_ link: CADisplayLink) { model?.tick(link.timestamp) }
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
