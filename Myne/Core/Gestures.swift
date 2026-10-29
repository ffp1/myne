import SwiftUI
import UIKit

/// 縦スクロールを邪魔しない横方向専用のパン
struct HorizontalPanGesture: UIGestureRecognizerRepresentable {
    enum Direction { case left, right }

    var direction: Direction
    var edgeExclusion: CGFloat = 0
    var onChanged: (CGFloat) -> Void = { _ in }
    var onEnded: (CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(direction: direction, edgeExclusion: edgeExclusion)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let x = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .changed: onChanged(x)
        case .ended: onEnded(x)
        case .cancelled, .failed: onEnded(0)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let direction: Direction
        let edgeExclusion: CGFloat

        init(direction: Direction, edgeExclusion: CGFloat) {
            self.direction = direction
            self.edgeExclusion = edgeExclusion
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view else { return false }
            if edgeExclusion > 0, pan.location(in: view.window).x < edgeExclusion { return false }
            let v = pan.velocity(in: view)
            guard abs(v.x) > abs(v.y) * 1.4 else { return false }
            return direction == .left ? v.x < 0 : v.x > 0
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }
    }
}

/// 戻るボタンを独自にした画面でも端スワイプで戻れるようにする
struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let nav = navigationController else { return }
            nav.interactivePopGestureRecognizer?.isEnabled = true
            nav.interactivePopGestureRecognizer?.delegate = self
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}
