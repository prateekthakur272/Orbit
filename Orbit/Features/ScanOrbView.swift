//
//  ScanOrbView.swift
//  Orbit
//

import SwiftUI

/// An animated solar system, shown while a scan runs. Holds still when Reduce Motion is on.
struct ScanOrbView: View {
    let count: Int
    let detail: String
    let startedAt: Date

    var size: CGFloat = 340
    private struct Star { let x: CGFloat; let y: CGFloat; let layer: Int; let phase: Double }
    private static let stars: [Star] = {
        var list: [Star] = []
        for i in 0..<70 {
            let x = (Double(i) * 0.6180339887).truncatingRemainder(dividingBy: 1)
            let y = (Double(i) * 0.7548776662).truncatingRemainder(dividingBy: 1)
            list.append(Star(x: CGFloat(x), y: CGFloat(y), layer: i % 3, phase: Double(i) * 1.7))
        }
        return list
    }()
    @State private var hover: CGPoint?

    var body: some View {
        VStack(spacing: 18) {
            TimelineView(.animation(paused: Motion.reduce)) { context in
                orb(t: Motion.reduce ? 0 : context.date.timeIntervalSinceReferenceDate)
            }
            .frame(width: size, height: size * 0.62)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Scanning")
            .accessibilityValue("\(count) items found")

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("Scanning · \(Int(context.date.timeIntervalSince(startedAt)))s · \(count) found")
                    .font(.title3.weight(.semibold)).monospacedDigit()
                    .contentTransition(.numericText())
            }
            VStack(spacing: 2) {
                Text("Looking at").font(.caption).foregroundStyle(.tertiary)
                Text(detail.isEmpty ? "Starting…" : detail)
                    .font(.callout.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: 520)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private struct Planet { let name: String; let radius: CGFloat; let size: CGFloat; let period: Double; let phase: Double; let color: Color; var ring = false }
    private static let planets: [Planet] = [
        Planet(name: "Mercury", radius: 0.20, size: 5,  period: 4,  phase: 0.3, color: .gray),
        Planet(name: "Venus", radius: 0.29, size: 8,  period: 7,  phase: 2.1, color: .orange),
        Planet(name: "Earth", radius: 0.39, size: 9,  period: 11, phase: 4.0, color: .blue),
        Planet(name: "Mars", radius: 0.49, size: 7,  period: 15, phase: 1.2, color: .red),
        Planet(name: "Jupiter", radius: 0.62, size: 14, period: 24, phase: 5.0, color: .brown),
        Planet(name: "Saturn", radius: 0.76, size: 12, period: 34, phase: 3.3, color: .yellow, ring: true),
        Planet(name: "Neptune", radius: 0.89, size: 9,  period: 46, phase: 0.8, color: .cyan),
    ]

    private func orb(t: TimeInterval) -> some View {
        Canvas { ctx, canvas in
            let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let r = canvas.width / 2
            let scale = canvas.width / 300
            let tilt: CGFloat = 0.5   // viewing angle: orbits become ellipses, near side lower on screen

            func point(_ a: Double, _ rx: CGFloat, around o: CGPoint) -> CGPoint {
                CGPoint(x: o.x + rx * CGFloat(cos(a)), y: o.y + rx * tilt * CGFloat(sin(a)))
            }
            func disc(_ pos: CGPoint, _ rad: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: pos.x - rad, y: pos.y - rad, width: rad * 2, height: rad * 2))
            }
            func sphere(_ pos: CGPoint, _ rad: CGFloat, _ color: Color) {
                ctx.fill(Path(ellipseIn: CGRect(x: pos.x - rad * 0.9, y: pos.y + rad * 0.9, width: rad * 1.8, height: rad * 0.5)),
                         with: .color(.black.opacity(0.12)))
                ctx.fill(disc(pos, rad),
                         with: .radialGradient(Gradient(colors: [.white.opacity(0.85), color, color.opacity(0.55)]),
                                               center: CGPoint(x: pos.x - rad * 0.35, y: pos.y - rad * 0.4), startRadius: 0, endRadius: rad * 1.5))
            }

            // Starfield: twinkles, and drifts slightly against the pointer for parallax.
            let look = hover.map { CGPoint(x: ($0.x - c.x) / r, y: ($0.y - c.y) / r) } ?? .zero
            for st in Self.stars {
                let layer = 1 + CGFloat(st.layer)
                let x = (st.x * canvas.width + look.x * -4 * layer).truncatingRemainder(dividingBy: canvas.width)
                let y = st.y * canvas.height + look.y * -4 * layer
                let a = 0.25 + 0.5 * (0.5 + 0.5 * sin(t * (0.8 + Double(st.layer)) + st.phase))
                ctx.fill(disc(CGPoint(x: x, y: y), 0.6 + CGFloat(st.layer) * 0.35), with: .color(.secondary.opacity(a)))
            }

            // A shooting star every few seconds.
            let cycle = t / 7, k = floor(cycle), f = cycle - k
            if f < 0.1 {
                let sx = canvas.width * (0.15 + 0.5 * CGFloat((k * 0.618).truncatingRemainder(dividingBy: 1)))
                let head = CGPoint(x: sx + CGFloat(f) * 900, y: 10 + CGFloat(f) * 500)
                let tail = CGPoint(x: head.x - 50, y: head.y - 28)
                var streak = Path(); streak.move(to: tail); streak.addLine(to: head)
                ctx.stroke(streak, with: .linearGradient(Gradient(colors: [.clear, .secondary.opacity(0.8)]), startPoint: tail, endPoint: head),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }

            struct Body { let planet: Planet; let pos: CGPoint; let depth: CGFloat; let a: Double }
            let bodies: [Body] = Self.planets.map { p in
                let a = t * 2 * .pi / p.period + p.phase
                return Body(planet: p, pos: point(a, r * p.radius, around: c), depth: 0.78 + 0.22 * CGFloat(sin(a)), a: a)
            }
            let hit: String? = hover.flatMap { h in
                bodies.min { hypot($0.pos.x - h.x, $0.pos.y - h.y) < hypot($1.pos.x - h.x, $1.pos.y - h.y) }
                    .flatMap { hypot($0.pos.x - h.x, $0.pos.y - h.y) < 28 ? $0.planet.name : nil }
            }

            // Orbit paths, then a fading comet-style trail behind each planet.
            for b in bodies {
                let rx = r * b.planet.radius, on = b.planet.name == hit
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - rx * tilt, width: rx * 2, height: rx * 2 * tilt)),
                           with: .color(on ? b.planet.color.opacity(0.8) : .secondary.opacity(0.35)), lineWidth: on ? 1.5 : 0.5)
                let steps = 18
                for i in 0..<steps {
                    var seg = Path()
                    seg.move(to: point(b.a - 0.7 * Double(i + 1) / Double(steps), rx, around: c))
                    seg.addLine(to: point(b.a - 0.7 * Double(i) / Double(steps), rx, around: c))
                    ctx.stroke(seg, with: .color(b.planet.color.opacity(0.7 * (1 - Double(i) / Double(steps)))),
                               style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
            }

            // Asteroid belt between Mars and Jupiter, slowly turning.
            for i in 0..<48 {
                let a = Double(i) * 0.1309 + t * 0.05
                let jitter = CGFloat((i * 37) % 11 - 5) * 0.9
                let pos = point(a, r * 0.555 + jitter, around: c)
                ctx.fill(disc(pos, (0.7 + CGFloat(i % 3) * 0.3) * scale), with: .color(.secondary.opacity(0.7)))
            }

            func draw(_ list: [Body]) {
                for b in list {
                    let p = b.planet, on = p.name == hit
                    let rad = p.size * scale * b.depth * (on ? 1.4 : 1)
                    if p.ring {
                        ctx.stroke(Path(ellipseIn: CGRect(x: b.pos.x - rad * 2, y: b.pos.y - rad * 0.7, width: rad * 4, height: rad * 1.4)),
                                   with: .color(p.color.opacity(0.75)), lineWidth: 1.8 * scale)
                    }
                    sphere(b.pos, rad, p.color)
                    if p.ring {   // front (lower) half of the ring crosses over the planet
                        var arc = Path()
                        for i in 0...24 {
                            let q = Double(i) / 24 * .pi
                            let pt = CGPoint(x: b.pos.x + rad * 2 * CGFloat(cos(q)), y: b.pos.y + rad * 0.7 * CGFloat(sin(q)))
                            if i == 0 { arc.move(to: pt) } else { arc.addLine(to: pt) }
                        }
                        ctx.stroke(arc, with: .color(p.color.opacity(0.9)), lineWidth: 1.8 * scale)
                    }
                    if p.name == "Earth" {
                        let m = point(t * 3.2, rad * 2.4, around: b.pos)
                        sphere(m, rad * 0.32, .gray)
                    }
                    if on { ctx.draw(Text(p.name).font(.caption.weight(.semibold)), at: CGPoint(x: b.pos.x, y: b.pos.y - rad - 12)) }
                }
            }

            let far = bodies.filter { $0.pos.y < c.y }.sorted { $0.pos.y < $1.pos.y }
            let near = bodies.filter { $0.pos.y >= c.y }.sorted { $0.pos.y < $1.pos.y }
            draw(far)

            // Sun with a breathing corona.
            let sun = r * 0.11, breathe = 1 + 0.12 * CGFloat(sin(t * 1.6))
            ctx.fill(disc(c, sun * 3.2 * breathe),
                     with: .radialGradient(Gradient(colors: [.orange.opacity(0.4), .yellow.opacity(0.1), .clear]), center: c, startRadius: sun * 0.8, endRadius: sun * 3.2 * breathe))
            sphere(c, sun, .yellow)
            draw(near)
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): hover = point
            case .ended: hover = nil
            }
        }
    }
}
