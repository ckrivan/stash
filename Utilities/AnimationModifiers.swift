import SwiftUI

// MARK: - Entrance Animation Modifiers

/// Slide in animation from a direction
struct SlideIn: ViewModifier {
    let direction: Edge
    let delay: Double
    let duration: Double
    @State private var isActive = false
    
    init(direction: Edge, delay: Double = 0, duration: Double = 0.3) {
        self.direction = direction
        self.delay = delay
        self.duration = duration
    }
    
    func body(content: Content) -> some View {
        content
            .offset(
                x: offsetX,
                y: offsetY
            )
            .opacity(isActive ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: duration).delay(delay)) {
                    isActive = true
                }
            }
    }
    
    private var offsetX: CGFloat {
        guard !isActive else { return 0 }
        
        switch direction {
        case .leading: return -50
        case .trailing: return 50
        default: return 0
        }
    }
    
    private var offsetY: CGFloat {
        guard !isActive else { return 0 }
        
        switch direction {
        case .top: return -50
        case .bottom: return 50
        default: return 0
        }
    }
}

/// Fade in animation
struct FadeIn: ViewModifier {
    let delay: Double
    let duration: Double
    @State private var isActive = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0)
            .onAppear {
                withAnimation(.easeIn(duration: duration).delay(delay)) {
                    isActive = true
                }
            }
    }
}

/// Scale animation
struct ScaleIn: ViewModifier {
    let scale: CGFloat
    let delay: Double
    let duration: Double
    @State private var isActive = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive ? 1.0 : scale)
            .opacity(isActive ? 1.0 : 0.0)
            .onAppear {
                withAnimation(.spring(response: duration, dampingFraction: 0.6).delay(delay)) {
                    isActive = true
                }
            }
    }
}

// MARK: - Hover Effect Modifiers

/// Hover effect for iPadOS
struct HoverEffect: ViewModifier {
    let scale: CGFloat
    let shadowRadius: CGFloat
    @State private var isHovering = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering ? scale : 1.0)
            .shadow(radius: isHovering ? shadowRadius : 0)
            .shadow(color: .blue.opacity(UIDevice.current.userInterfaceIdiom == .pad ? 0.3 : 0.1), 
                    radius: isHovering ? shadowRadius * 1.5 : 0, 
                    x: 0, 
                    y: 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

// MARK: - Loading Animation Modifiers

/// Shimmer loading effect
struct ShimmerEffect: ViewModifier {
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    ZStack {
                        Color.white.opacity(0.1)
                        
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.clear,
                                        Color.white.opacity(0.3),
                                        Color.clear
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .rotationEffect(.degrees(45))
                            .offset(x: isAnimating ? geometry.size.width : -geometry.size.width)
                            .animation(
                                Animation.linear(duration: 1.5)
                                    .repeatForever(autoreverses: false),
                                value: isAnimating
                            )
                    }
                }
                .mask(content)
                .onAppear {
                    isAnimating = true
                }
            )
    }
}

// MARK: - Pulse Animation Modifier

/// Pulsating animation
struct PulseEffect: ViewModifier {
    let duration: Double
    let minScale: CGFloat
    let maxScale: CGFloat
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isAnimating ? maxScale : minScale)
            .animation(
                Animation.easeInOut(duration: duration)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - SlideInModifier (used in MarkerView)
struct SlideInModifier: ViewModifier {
    let edge: Edge
    let delay: Double
    let duration: Double
    
    @State private var isActive = false
    
    func body(content: Content) -> some View {
        content
            .offset(x: edge == .leading ? (isActive ? 0 : -30) : (edge == .trailing ? (isActive ? 0 : 30) : 0),
                   y: edge == .top ? (isActive ? 0 : -30) : (edge == .bottom ? (isActive ? 0 : 30) : 0))
            .opacity(isActive ? 1 : 0)
            .animation(.easeOut(duration: duration).delay(delay), value: isActive)
            .onAppear {
                withAnimation {
                    isActive = true
                }
            }
    }
}

// MARK: - ScaleButtonStyle (used in MarkerView and MarkerRow)
public struct ScaleButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - View Extensions

extension View {
    /// Apply slide in animation
    func slideIn(from edge: Edge, delay: Double = 0, duration: Double = 0.3) -> some View {
        modifier(SlideIn(direction: edge, delay: delay, duration: duration))
    }
    
    /// Apply fade in animation
    func fadeIn(delay: Double = 0, duration: Double = 0.3) -> some View {
        modifier(FadeIn(delay: delay, duration: duration))
    }
    
    /// Apply hover effect using ScaleButtonStyle
    func applyHoverEffect() -> some View {
        self.buttonStyle(ScaleButtonStyle())
    }
    
    /// Apply scale in animation
    func scaleIn(from scale: CGFloat = 0.8, delay: Double = 0, duration: Double = 0.5) -> some View {
        modifier(ScaleIn(scale: scale, delay: delay, duration: duration))
    }
    
    /// Apply hover effect for iPadOS
    func applyHoverEffect(scale: CGFloat = 0, shadowRadius: CGFloat = 5) -> some View {
        let deviceScale = UIDevice.current.userInterfaceIdiom == .pad ? 1.08 : 1.05
        let actualScale = scale > 0 ? scale : deviceScale
        return modifier(HoverEffect(scale: actualScale, shadowRadius: shadowRadius))
    }
    
    /// Apply shimmer loading effect
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
    
    /// Apply pulse animation
    func pulse(duration: Double = 1.0, minScale: CGFloat = 0.95, maxScale: CGFloat = 1.05) -> some View {
        modifier(PulseEffect(duration: duration, minScale: minScale, maxScale: maxScale))
    }
}