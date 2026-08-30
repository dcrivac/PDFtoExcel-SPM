//
//  GlassEffectModifiers.swift
//  PDFtoExcel
//
//  Created by David Kenji Crivac on 10/16/25.
//

import SwiftUI

// MARK: - Glass Effect Modifier

struct GlassEffect: ViewModifier {
    let material: Material
    let shape: AnyShape

    func body(content: Content) -> some View {
        if #available(iOS 15.0, macOS 12.0, *) {
            content
                .background(material, in: shape)
        } else {
            content
                .background(Color.black.opacity(0.1))
                .clipShape(shape)
        }
    }
}

extension View {
    func glassEffect(_ material: Material, in shape: some Shape) -> some View {
        self.modifier(GlassEffect(material: material, shape: AnyShape(shape)))
    }
}

// MARK: - Type-erased Shape

struct AnyShape: Shape, @unchecked Sendable {
    private let _path: @Sendable (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        _path = { (rect: CGRect) -> Path in
            shape.path(in: rect)
        }
    }

    func path(in rect: CGRect) -> Path {
        _path(rect)
    }
}

// MARK: - Glass Effect Container

struct GlassEffectContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        content
    }
}

// MARK: - Button Styles

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Group {
                    if #available(iOS 15.0, macOS 12.0, *) {
                        Color.clear.background(.ultraThinMaterial)
                    } else {
                        Color.black.opacity(0.08)
                    }
                }
            )
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct GlassProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [.blue, .blue.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
            .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static var glass: GlassButtonStyle { GlassButtonStyle() }
}

extension ButtonStyle where Self == GlassProminentButtonStyle {
    static var glassProminent: GlassProminentButtonStyle { GlassProminentButtonStyle() }
}

