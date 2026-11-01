import CoreHaptics
import Foundation
import Observation
import QuartzCore
import SceneKit
import SkeeCore
import SkeeHUD
import SkeeNet
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
    private var cues: [Cue] = []
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
        cues += presentation.cues
        return (presentation, held, dt)
    }

    /// Main thread: beats finished since last asked, for haptics.
    func takeFinished() -> [Beat] { lock.lock(); defer { lock.unlock() }; let f = finished; finished = []; return f }
    func takeCues() -> [Cue] { lock.lock(); defer { lock.unlock() }; let c = cues; cues = []; return c }
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
    /// Winnings and the prize shelf, across runs.
    var wallet: Wallet
    var shopOpen = false
    /// The coached practice warm-up, while it runs. The real run waits in
    /// `parked` and comes back when the walkthrough ends or is skipped.
    var walkthrough: Walkthrough?
    @ObservationIgnored private var parked: (seed: UInt64, actions: [Action], state: RunState)?

    @ObservationIgnored let cabinet: Cabinet
    /// The comp negotiation, while the host is at the table.
    var haggle: Haggle?
    var hostThinking = false
    var hostError: String?
    @ObservationIgnored private let deepseek = DeepSeek(key: GameModel.deepseekKey)
    /// The app swaps in a fresh model (new cabinet, new room) through this.
    @ObservationIgnored var rebuild: (_ toGame: Bool) -> Void = { _ in }
    @ObservationIgnored private var extraTickets = 0

    /// Baked into Info.plist from App/Secrets.xcconfig at build time. An
    /// unexpanded "$(...)" means the build had no key.
    static var deepseekKey: String {
        let k = Bundle.main.object(forInfoDictionaryKey: "DeepSeekAPIKey") as? String ?? ""
        return k.hasPrefix("$(") ? "" : k
    }
    @ObservationIgnored let presenter: ScenePresenter
    @ObservationIgnored let stage: Stage
    @ObservationIgnored let driver: RenderDriver
    @ObservationIgnored var viewSize = CGSize(width: 626, height: 890)
    @ObservationIgnored private var seed: UInt64
    @ObservationIgnored private var actions: [Action] = []
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private let haptics = Haptics()
    @ObservationIgnored private let sound = SoundEngine()
    @ObservationIgnored private var lastBall: (along: Double, x: Double, t: CFTimeInterval)?
    @ObservationIgnored private var autoplay: [Launch] = []

    /// - Parameter fresh: start a new run in the wallet's room, ignoring
    ///   the save (after changing rooms).
    init(fresh: Bool = false, toGame: Bool = false) {
        let args = LaunchArguments()
        var seed = args.seed ?? UInt64(Date().timeIntervalSince1970)
        var s: RunState
        var actions: [Action] = []
        var wallet = WalletStore.load()
        let room = wallet.room
        cabinet = Cabinet(table: room.table, palette: .of(room))
        if let saved = RunStore.load(), !args.fresh, !fresh, saved.room ?? .boardwalk == room {
            seed = saved.seed
            extraTickets = saved.extraTickets ?? 0
            s = newRun(seed: saved.seed, room: room, extraTickets: extraTickets)
            for a in saved.actions {
                guard case .success(let step) = apply(a, to: s) else { break }
                s = step.state
                actions.append(a)
            }
        } else {
            extraTickets = wallet.checkIn()
            WalletStore.save(wallet)
            s = newRun(seed: seed, room: room, extraTickets: extraTickets)
            RunStore.save(seed: seed, room: room, extraTickets: extraTickets, actions: [])
        }
        self.wallet = wallet
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
        // First time in this version: show the title, whose TAP TO PLAY
        // starts the walkthrough.
        if !WalkthroughStore.done && args.autoplay.isEmpty && !args.skipTitle { self.screen = .title }
        if toGame { self.screen = .game }
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
        for cue in stage.takeCues() { sound.play(cue); haptics.cue(cue) }
        let p = stage.snapshot
        // Rumble follows the ball while it rolls; silent in the air.
        let now = CACurrentMediaTime()
        if let b = p.ball, b.phase != .air || b.height < 0.003 {
            if let l = lastBall, now > l.t {
                // Screen speed is slowed by the roll's pace; undo that.
                let speed = abs(b.along - l.along) / (now - l.t) * Presentation.rollSpeed
                let level = min(1, speed / 4) * (p.isBusy ? 1 : 0)
                sound.setRumble(Float(level))
                haptics.rumble(b.phase == .lane ? level : b.phase == .board ? level * 0.5 : 0)
            }
            lastBall = (b.along, b.x, now)
        } else { sound.setRumble(0); haptics.rumble(0); lastBall = nil }
        sound.setDrumRoll(p.anticipation > 0)
        refreshHUD(p)
        if !p.isBusy, case .throwing = state.phase, !autoplay.isEmpty {
            if state.round.pull == nil { send(.pull(.one)) } else { send(.throwBall(autoplay.removeFirst())) }
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
           selectedOffer: selectedOffer, selectedCharm: selectedCharm, screen: screen, bet: affordableBet)
        hud.machine?.progressive = wallet.progressive
        hud.trail = trail
        hud.host = haggle.map { HostState(haggle: $0, thinking: hostThinking, error: hostError) }
        hud.guide = canThrow ? presenter.guide(line: line, size: viewSize) : []
        hud.aiming = aiming
        hud.wallet = wallet
        hud.shopOpen = shopOpen
        if let w = walkthrough, !w.finished {
            hud.coach = w.card
            hud.over = nil   // the last card says it instead
        }
    }

    // MARK: thumb

    @ObservationIgnored private var flickSamples: [FlickSample] = []
    @ObservationIgnored private var trailPoints: [(CGPoint, CFTimeInterval)] = []
    /// The waiting ball's release line, -1...1. Kept between throws, so a
    /// line that worked is still there for the next ball.
    @ObservationIgnored private var line = 0.0
    @ObservationIgnored private var aiming = false

    var geometry: FlickGeometry { presenter.flickGeometry(size: viewSize) }
    var busy: Bool { stage.with { $0.isBusy } }
    var canThrow: Bool {
        if screen != .game || busy || shopOpen { return false }
        if case .throwing = state.phase { return state.round.pull != nil }
        return false
    }

    /// The ball slides under the thumb as it lands: that is the line. The
    /// flick is read whole after lift-off.
    func touchBegan(t: Double, x: Double, y: Double) {
        if busy { stage.with { $0.skip() }; return }
        guard canThrow, y > geometry.creaseY else { return }
        line = laneStart(touchX: x, in: geometry)
        aiming = true
        placeBall()
        flickSamples = [FlickSample(t: t, x: x, y: y)]
        trailPoints = [(CGPoint(x: x, y: y), CACurrentMediaTime())]
    }

    func touchMoved(_ touches: [(t: Double, x: Double, y: Double)]) {
        guard !flickSamples.isEmpty else { return }
        let new = touches.map { FlickSample(t: $0.t, x: $0.x, y: $0.y) }
        flickSamples += new
        let now = CACurrentMediaTime()
        trailPoints += new.map { (CGPoint(x: $0.x, y: $0.y), now) }
        if crossedFoulLine(new, in: geometry) {
            // Dragged well past the crease: foul.
            flickSamples = []
            aiming = false
            haptics.foul()
            send(.foul)
        }
    }

    func touchEnded(_ touches: [(t: Double, x: Double, y: Double)]) {
        guard !flickSamples.isEmpty else { return }
        flickSamples += touches.map { FlickSample(t: $0.t, x: $0.x, y: $0.y) }
        let outcome = analyzeFlick(flickSamples, in: geometry, fold: fold)
        flickSamples = []
        aiming = false
        switch outcome {
        case .none: break
        case .foul: haptics.foul(); send(.foul)
        case .release(let l): send(.throwBall(l))
        }
    }

    func touchCancelled() { flickSamples = []; aiming = false }

    func placeBall() { stage.setHeld(presenter.waitingBall(line: line)) }

    var trail: [(CGPoint, Double)] {
        let now = CACurrentMediaTime()
        trailPoints.removeAll { now - $0.1 > 0.35 }
        return trailPoints.map { ($0.0, (now - $0.1) / 0.35) }
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
        a.start = { [weak self] in
            guard let self else { return }
            if WalkthroughStore.done { screen = .game } else { startWalkthrough() }
            haptics.tap()
        }
        a.howToPlay = { [weak self] in self?.startWalkthrough(); self?.haptics.tap() }
        a.pull = { [weak self] in
            guard let self, !busy, state.round.pull == nil else { return }
            send(.pull(affordableBet))
        }
        a.setBet = { [weak self] b in self?.bet = b; self?.haptics.tap() }
        a.pickRoom = { [weak self] r in self?.pickRoom(r) }
        a.openHost = { [weak self] in self?.openHost(); self?.haptics.tap() }
        a.hostSay = { [weak self] t in self?.hostSay(t) }
        a.hostRetry = { [weak self] in self?.askHost() }
        a.hostDeal = { [weak self] in self?.hostDeal() }
        a.closeHost = { [weak self] in self?.closeHost() }
        a.skipWalkthrough = { [weak self] in self?.endWalkthrough(); self?.haptics.tap() }
        a.gotIt = { [weak self] in
            guard let self else { return }
            walkthrough?.gotIt()
            if walkthrough?.finished == true { endWalkthrough() }
            haptics.tap()
        }
        a.newRun = { [weak self] in self?.newGame() }
        a.openShop = { [weak self] in self?.shopOpen = true; self?.haptics.tap() }
        a.closeShop = { [weak self] in self?.shopOpen = false; self?.haptics.tap() }
        a.buyPrize = { [weak self] p in
            guard let self else { return }
            switch wallet.buy(p) {
            case .success(let w): wallet = w; WalletStore.save(w); haptics.prize()
            case .failure: haptics.reject()
            }
        }
        return a
    }

    // MARK: effects

    /// The bet on the machine, kept between pulls; never more than the
    /// tickets cover.
    @ObservationIgnored var bet: Bet = .one
    var affordableBet: Bet { Bet.allCases.last { $0 <= bet && $0.cost <= state.tickets } ?? .one }

    func send(_ action: Action) {
        switch apply(action, to: state) {
        case .failure:
            haptics.reject()
        case .success(let step):
            state = step.state
            actions.append(action)
            stage.with { $0.enqueue(step) }
            if walkthrough != nil {
                // Practice: no save, no winnings, just the coach.
                walkthrough?.observe(step.events)
                if case .throwBall = action { haptics.launch() } else { haptics.tap() }
                return
            }
            RunStore.save(seed: seed, room: state.room, extraTickets: extraTickets, actions: actions)
            // A finished run pays its winnings to the shelf, once.
            for e in step.events {
                switch e {
                case .pulled(let p): wallet.pulled(p); WalletStore.save(wallet)
                case .roundFailed: wallet.credit(winnings(stats: state.stats, won: false)); WalletStore.save(wallet)
                case .runWon: wallet.credit(winnings(stats: state.stats, won: true)); WalletStore.save(wallet)
                default: break
                }
            }
            if case .throwBall = action { haptics.launch() } else { haptics.tap() }
        }
    }

    /// Park the real run and play the coached practice warm-up.
    func startWalkthrough() {
        if walkthrough == nil { parked = (seed, actions, state) }
        walkthrough = Walkthrough()
        state = practiceRun(room: wallet.room)
        actions = []
        let fresh = Presentation(state: state)
        stage.with { $0 = fresh }
        selectedOffer = nil; selectedCharm = nil; shopOpen = false
        screen = .game
    }

    /// Done or skipped: never shown again unless asked for, and the real
    /// run comes back as it was (a fresh one if it had ended).
    func endWalkthrough() {
        walkthrough = nil
        WalkthroughStore.done = true
        guard let p = parked else { newGame(); return }
        parked = nil
        switch p.state.phase {
        case .lost, .won: newGame()
        default:
            seed = p.seed; actions = p.actions; state = p.state
            let fresh = Presentation(state: state)
            stage.with { $0 = fresh }
            selectedOffer = nil; selectedCharm = nil
            screen = .game
        }
    }

    func newGame() {
        seed = UInt64(Date().timeIntervalSince1970)
        actions = []
        extraTickets = wallet.checkIn()
        WalletStore.save(wallet)
        state = newRun(seed: seed, room: wallet.room, extraTickets: extraTickets)
        let fresh = Presentation(state: state)
        stage.with { $0 = fresh }
        selectedOffer = nil; selectedCharm = nil
        screen = .game
        RunStore.save(seed: seed, room: wallet.room, extraTickets: extraTickets, actions: actions)
    }

    // MARK: rooms and the host

    /// Play in another room you own. The cabinet is rebuilt for it.
    func pickRoom(_ r: Room) {
        guard wallet.rooms.contains(r), r != wallet.room else { return }
        wallet.room = r
        WalletStore.save(wallet)
        stop()
        rebuild(false)
    }

    func openHost() {
        guard let room = wallet.compDue else { return }
        haggle = Haggle(room: room, seed: UInt64(Date().timeIntervalSince1970))
        hostError = deepseek.key.isEmpty ? "The host can't be reached: this build has no DeepSeek key (run scripts/secrets.sh, then rebuild)." : nil
    }

    func hostSay(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !hostThinking, haggle?.status == .open else { return }
        haggle?.say(t)
        askHost()
    }

    /// Ask for the host's reply to the last thing said. Also the retry
    /// after a failed call: the player's line is already on the table.
    func askHost() {
        guard let h = haggle, h.status == .open, h.lines.last?.speaker == .player else { return }
        hostThinking = true
        hostError = nil
        let client = deepseek
        Task {
            do {
                let reply = try await client.reply(in: h)
                haggle?.hear(reply)
                haptics.tap()
                if let h = haggle, h.status != .open { settle(h) }
            } catch {
                hostError = "\(error)"
                haptics.reject()
            }
            hostThinking = false
        }
    }

    func hostDeal() {
        guard haggle?.status == .open, !hostThinking else { return }
        haggle?.accept()
        haptics.prize()
        if let h = haggle { settle(h) }
    }

    private func settle(_ h: Haggle) {
        wallet.close(h)
        WalletStore.save(wallet)
    }

    /// Leave the table. A finished deal checks you into the new room.
    func closeHost() {
        guard let h = haggle else { return }
        haggle = nil
        if h.status != .open { stop(); rebuild(true) }
    }

    func stop() { link?.invalidate(); link = nil }
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

/// Whether the walkthrough has been seen (finished or skipped).
enum WalkthroughStore {
    static var done: Bool {
        get { UserDefaults.standard.bool(forKey: "walkthroughDone") }
        set { UserDefaults.standard.set(newValue, forKey: "walkthroughDone") }
    }
}

/// Winnings and prizes, outside any run.
enum WalletStore {
    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("wallet.json")
    }
    static func save(_ w: Wallet) {
        if let data = try? JSONEncoder().encode(w) { try? data.write(to: url) }
    }
    static func load() -> Wallet {
        guard let data = try? Data(contentsOf: url), let w = try? JSONDecoder().decode(Wallet.self, from: data) else { return Wallet() }
        return w
    }
}

/// The run on disk is the seed and the actions; replaying rebuilds it.
enum RunStore {
    /// Room and comped tickets are optional so saves from before rooms
    /// still load (as Boardwalk runs).
    struct File: Codable { var seed: UInt64; var room: Room?; var extraTickets: Int?; var actions: [Action] }
    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("run.json")
    }
    static func save(seed: UInt64, room: Room, extraTickets: Int, actions: [Action]) {
        if let data = try? JSONEncoder().encode(File(seed: seed, room: room, extraTickets: extraTickets, actions: actions)) { try? data.write(to: url) }
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

    /// A continuous buzz that follows the ball while it rolls: the alley
    /// under your hand. Impact taps alone left the roll silent in the hand.
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var level = 0.0

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.resetHandler = { [weak self] in self?.player = nil; try? self?.engine?.start() }
        engine?.stoppedHandler = { [weak self] _ in self?.player = nil }
        try? engine?.start()
    }

    /// 0 stops; 0...1 sets how hard the ball is rumbling.
    func rumble(_ to: Double) {
        guard let engine else { return }
        if to < 0.05 {
            if player != nil { try? player?.stop(atTime: CHHapticTimeImmediate); player = nil }
            level = 0
            return
        }
        if player == nil {
            let buzz = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.12),
            ], relativeTime: 0, duration: 20)
            guard let pattern = try? CHHapticPattern(events: [buzz], parameters: []) else { return }
            try? engine.start()
            player = try? engine.makeAdvancedPlayer(with: pattern)
            try? player?.start(atTime: CHHapticTimeImmediate)
            level = -1
        }
        guard abs(to - level) > 0.03 else { return }
        level = to
        try? player?.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: Float(0.2 + 0.55 * to), relativeTime: 0)],
                                    atTime: CHHapticTimeImmediate)
    }

    func tap() { light.impactOccurred() }
    func launch() { rigid.impactOccurred(intensity: 0.7) }
    func reject() { note.notificationOccurred(.warning) }
    func foul() { note.notificationOccurred(.error) }
    func prize() { note.notificationOccurred(.success) }

    /// Light taps timed to the ball: the hump, rattles, the drop.
    func cue(_ c: Cue) {
        switch c {
        // The hop: the one hard knock in the throw, then silence in the air.
        case .hump: rumble(0); heavy.impactOccurred(intensity: 1)
        case .landed: heavy.impactOccurred(intensity: 0.6)
        case .lip: light.impactOccurred(intensity: 0.8)
        case .drop(let h): heavy.impactOccurred(intensity: min(1, 0.45 + CGFloat(h.faceValue) / 110))
        case .reelStop: light.impactOccurred(intensity: 0.4)
        case .lever: heavy.impactOccurred(intensity: 0.8)
        case .pullWin: rigid.impactOccurred(intensity: 0.9)
        case .combo(let n): rigid.impactOccurred(intensity: min(1, 0.5 + CGFloat(n) * 0.1))
        default: break
        }
    }

    func play(_ beat: Beat) {
        switch beat {
        case .roll(_, let b):
            if b.hole == .gutter { note.notificationOccurred(.error) }
        case .tally(let f):
            if f.isJackpot { note.notificationOccurred(.success) } else { light.impactOccurred() }
        case .banner(let t, _, _) where t == "CLEARED":
            note.notificationOccurred(.success)
        default: break
        }
    }
}
