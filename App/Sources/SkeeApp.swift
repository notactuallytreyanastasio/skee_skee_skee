import SceneKit
import SkeeCore
import SkeeHUD
import SkeeScene
import SwiftUI
import UIKit

@main
struct SkeeApp: App {
    @State private var model = GameModel()

    var body: some Scene {
        WindowGroup {
            GameView(model: model)
                .ignoresSafeArea()
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}

/// The 3D cabinet, a touch layer for the thumb, and the HUD on top. The HUD
/// only takes touches on its buttons; everywhere else falls through to the
/// throw pad.
struct GameView: View {
    let model: GameModel

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CabinetView(cabinet: model.cabinet, driver: model.driver)
                ThrowPadView(model: model)
                HUDView(state: model.hud, actions: model.hudActions)
            }
            .background(HingeReader { model.fold = $0 })
            .onAppear { model.resized(geo.size); model.start() }
            .onChange(of: geo.size) { _, s in model.resized(s) }
        }
    }
}

struct CabinetView: UIViewRepresentable {
    let cabinet: Cabinet
    let driver: RenderDriver

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero, options: nil)
        v.scene = cabinet.scene
        v.pointOfView = cabinet.camera
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 120
        v.rendersContinuously = true
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        v.delegate = driver
        v.isPlaying = true
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {}
}

/// Raw touches with their real timestamps, including coalesced samples, so
/// the stroke analyser sees the whole slide at the digitiser's rate.
struct ThrowPadView: UIViewRepresentable {
    let model: GameModel

    func makeUIView(context: Context) -> ThrowPad {
        let v = ThrowPad()
        v.model = model
        v.isMultipleTouchEnabled = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ v: ThrowPad, context: Context) { v.model = model }
}

final class ThrowPad: UIView {
    weak var model: GameModel?

    func samples(_ touch: UITouch, _ event: UIEvent?) -> [(t: Double, x: Double, y: Double)] {
        let all = event?.coalescedTouches(for: touch) ?? [touch]
        return all.map { t in
            let p = t.location(in: self)
            return (t.timestamp, Double(p.x), Double(p.y))
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let model else { return }
        let p = t.location(in: self)
        if model.tapBoard(at: p) { return }
        model.touchBegan(t: t.timestamp, x: Double(p.x), y: Double(p.y))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        model?.touchMoved(samples(t, event))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        model?.touchEnded(samples(t, event))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        model?.touchCancelled()
    }
}

/// Reports how far the device is folded, 0 (flat open) to 1 (folded to a
/// right angle or more), using UIHingeInteraction on iOS 27.1+.
struct HingeReader: UIViewRepresentable {
    let onFold: (Double) -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        if #available(iOS 27.1, *) {
            let interaction = UIHingeInteraction { _, update in
                // Closed means the player is on the outer display: no ramp to
                // bend. Reading the angle would give the steepest ramp.
                guard let hinge = update.hinge, hinge.status != .closed else { onFold(0); return }
                onFold(HingeReader.fold(angle: Double(hinge.angle)))
            }
            v.addInteraction(interaction)
        }
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func fold(angle: Double) -> Double {
        clamp((Double.pi - angle) / (Double.pi / 2), 0, 1)
    }
}
