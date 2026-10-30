import CoreGraphics
import Foundation
import Observation
import QuartzCore
import SkeeCore
import SkeeRender
import UIKit

/// The imperative shell. Holds the current values, feeds input to the pure
/// functions, and performs the effects (haptics, saving). No game rules here:
/// throws go through `apply`, taps through `intent`, swipes through `Swipe`.
@Observable
@MainActor
final class GameModel {
    private(set) var state: RunState
    private(set) var presentation: Presentation
    var ui = UIState()
    private var seed: UInt64
    private var actions: [Action] = []
    private var lastTick: CFTimeInterval?
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private let haptics = Haptics()
    @ObservationIgnored private var autoplay: [Launch] = []

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
        var ui = UIState()
        ui.screen = args.skipTitle || !actions.isEmpty || !args.autoplay.isEmpty ? .game : .title
        if let f = args.fold { ui.fold = f }
        self.ui = ui
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

    fileprivate func tick(_ now: CFTimeInterval) {
        let dt = min(1.0 / 20, now - (lastTick ?? now))
        lastTick = now
        presentation.advance(dt)
        for beat in presentation.finished { haptics.play(beat) }
        if !presentation.isBusy, case .throwing = state.phase, !autoplay.isEmpty {
            send(.throwBall(autoplay.removeFirst()))
        }
    }

    // MARK: input

    func dragChanged(start: CGPoint, now: CGPoint, layout: Layout) {
        guard ui.screen == .game, case .throwing = state.phase, !presentation.isBusy,
              start.y > layout.hingeY, start.y < layout.trayRect.minY else { return }
        ui.dragStart = start
        ui.dragNow = now
    }

    func dragEnded(start: CGPoint, end: CGPoint, velocity: CGSize, layout: Layout) {
        defer { ui.dragStart = nil; ui.dragNow = nil }
        let moved = hypot(end.x - start.x, end.y - start.y)
        if moved < 12 {
            tap(at: end, layout: layout)
            return
        }
        if presentation.isBusy { presentation.skip(); return }
        guard ui.screen == .game, case .throwing = state.phase, start.y > layout.hingeY else { return }
        let swipe = Swipe(start: start, end: end, velocity: CGVector(dx: velocity.width, dy: velocity.height))
        if let launch = swipe.launch(in: layout, fold: ui.fold) { send(.throwBall(launch)) }
    }

    func tap(at p: CGPoint, layout: Layout) {
        if presentation.isBusy {
            // Tapping during an animation hurries it along.
            presentation.skip()
            return
        }
        switch intent(at: p, layout: layout, state: state, ui: ui, busy: presentation.isBusy) {
        case .none: break
        case .startRun:
            if ui.screen == .title { ui.screen = .game; haptics.tap(); return }
            newGame()
        case .selectOffer(let i): ui.selectedOffer = i; haptics.tap()
        case .cancelSelection: ui.selectedOffer = nil; ui.selectedCharm = nil
        case .selectCharm(let i): ui.selectedCharm = i; haptics.tap()
        case .act(let a):
            ui.selectedOffer = nil; ui.selectedCharm = nil
            send(a)
        }
    }

    func setFold(_ f: Double) { ui.fold = f }

    // MARK: effects

    func send(_ action: Action) {
        switch apply(action, to: state) {
        case .failure(let e):
            haptics.reject()
            ui.message = "\(e)"
        case .success(let step):
            state = step.state
            actions.append(action)
            presentation.enqueue(step)
            RunStore.save(seed: seed, actions: actions)
            if case .throwBall = action { haptics.launch() } else { haptics.tap() }
        }
    }

    func newGame() {
        seed = UInt64(Date().timeIntervalSince1970)
        actions = []
        state = newRun(seed: seed)
        presentation = Presentation(state: state)
        ui = UIState()
        ui.screen = .game
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
///   -seed 42          fixed run seed
///   -fresh            ignore the saved run
///   -ante 5           start the run at this ante (to see a later art era)
///   -fold 0.6         pretend the hinge is half folded
///   -autoplay "0.62,0;0.55,0.1"   throw these launches (power,aim[,start])
///   -skipTitle
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

/// The run on disk is just the seed and the actions; replaying them
/// rebuilds the exact state.
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

/// Haptics keyed off what the presentation just finished showing.
@MainActor
final class Haptics {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let note = UINotificationFeedbackGenerator()

    func tap() { light.impactOccurred() }
    func launch() { rigid.impactOccurred(intensity: 0.6) }
    func reject() { note.notificationOccurred(.warning) }

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
