import SwiftUI
import AppKit

/// SwiftUI wrapper around NSVisualEffectView for macOS Vibrancy glass effects
public struct VisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

/// Custom modifier that ensures scrollbars use modern macOS overlay style (no border, no background track, autohiding)
public struct ModernOverlayScrollViewModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .background(ScrollViewConfigurator())
    }
}

private final class ConfiguratorNSView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            ScrollViewConfigurator.configure(view: self)
        }
    }
    
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview != nil {
            ScrollViewConfigurator.configure(view: self)
        }
    }
    
    override func layout() {
        super.layout()
        ScrollViewConfigurator.configure(view: self)
    }
}

private struct ScrollViewConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = ConfiguratorNSView()
        context.coordinator.targetView = view
        context.coordinator.setupObserver()
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            Self.configure(view: view)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.targetView = nsView
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView else { return }
            Self.configure(view: nsView)
        }
    }
    
    final class Coordinator: NSObject {
        weak var targetView: NSView?
        private var observerToken: Any?
        
        func setupObserver() {
            observerToken = NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let view = self?.targetView else { return }
                ScrollViewConfigurator.configure(view: view)
            }
        }
        
        deinit {
            if let observerToken {
                NotificationCenter.default.removeObserver(observerToken)
            }
        }
    }
    
    static func configure(view: NSView) {
        guard let scrollView = findScrollView(from: view) else { return }
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        if let scroller = scrollView.verticalScroller {
            scroller.scrollerStyle = .overlay
            scroller.controlSize = .small
            scroller.knobStyle = .default
        }
    }
    
    static func findScrollView(from view: NSView) -> NSScrollView? {
        if let scrollView = view.enclosingScrollView {
            return scrollView
        }
        func searchDescendants(_ v: NSView) -> NSScrollView? {
            if let sv = v as? NSScrollView { return sv }
            for sub in v.subviews {
                if let found = searchDescendants(sub) { return found }
            }
            return nil
        }
        var current: NSView? = view
        while let c = current {
            if let sv = searchDescendants(c) {
                return sv
            }
            current = c.superview
        }
        return nil
    }
}

public extension View {
    func thinScrollbar() -> some View {
        self.modifier(ModernOverlayScrollViewModifier())
    }
}
