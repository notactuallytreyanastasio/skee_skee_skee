import SkeeCore
import SkeeRender
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

/// One Canvas, drawn by the shared renderer; one drag gesture for swipes
/// and taps; a hidden view that listens to the hinge.
struct GameView: View {
    let model: GameModel

    var body: some View {
        GeometryReader { geo in
            let layout = Layout(size: geo.size)
            Canvas { ctx, _ in
                ctx.withCGContext { cg in
                    Renderer.draw(model.presentation, ui: model.ui, layout: layout, in: cg)
                }
            }
            .background(HingeReader { model.setFold($0) })
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in model.dragChanged(start: v.startLocation, now: v.location, layout: layout) }
                    .onEnded { v in
                        model.dragEnded(start: v.startLocation, end: v.location, velocity: v.velocity, layout: layout)
                    }
            )
        }
        .onAppear { model.start() }
    }
}

/// Reports how far the device is folded, 0 (flat open) to 1 (folded to a
/// right angle or more), using UIHingeInteraction on iOS 27.1+. Earlier
/// systems and unfolding devices never call back, and the ramp stays flat.
struct HingeReader: UIViewRepresentable {
    let onFold: (Double) -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        if #available(iOS 27.1, *) {
            let interaction = UIHingeInteraction { _, update in
                // Closed means the player is on the outer display: there is
                // no ramp to bend, so no loft. Reading the angle here would
                // give the steepest ramp to anyone playing folded.
                guard let hinge = update.hinge, hinge.status != .closed else { onFold(0); return }
                onFold(HingeReader.fold(angle: Double(hinge.angle)))
            }
            v.addInteraction(interaction)
        }
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    /// The API reports the opening angle; pi is flat. Halfway to closed (a
    /// right angle, like a little skee-ball cabinet) is full fold.
    static func fold(angle: Double) -> Double {
        clamp((Double.pi - angle) / (Double.pi / 2), 0, 1)
    }
}
