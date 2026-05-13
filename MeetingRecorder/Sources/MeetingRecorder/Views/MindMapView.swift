import SwiftUI

// MARK: - Mind Map Layout Engine

private struct LayoutNode: Identifiable {
    let id: UUID
    let label: String
    let detail: String
    let color: Color
    let nodeType: MindMapNode.NodeType
    var position: CGPoint
    let depth: Int
    let childIds: [UUID]
}

private struct LayoutEdge: Identifiable {
    let id = UUID()
    let from: UUID
    let to: UUID
}

private class MindMapLayout {
    private(set) var nodes: [UUID: LayoutNode] = [:]
    private(set) var edges: [LayoutEdge] = []

    func build(from roots: [MindMapNode], in size: CGSize) {
        nodes = [:]
        edges = []
        let cx = size.width / 2
        let cy = size.height / 2

        for (i, root) in roots.enumerated() {
            let angle = (2 * .pi / Double(max(roots.count, 1))) * Double(i)
            let offset = CGPoint(x: cos(angle) * 20, y: sin(angle) * 20)
            place(node: root, at: CGPoint(x: cx + offset.x, y: cy + offset.y), depth: 0, parentId: nil)
        }
    }

    private func place(node: MindMapNode, at point: CGPoint, depth: Int, parentId: UUID?) {
        let childIds = node.children.map { $0.id }
        let layout = LayoutNode(
            id: node.id,
            label: node.label,
            detail: node.detail,
            color: Color(hex: node.color) ?? .accentColor,
            nodeType: node.nodeType,
            position: point,
            depth: depth,
            childIds: childIds
        )
        nodes[node.id] = layout

        if let parentId {
            edges.append(LayoutEdge(from: parentId, to: node.id))
        }

        guard !node.children.isEmpty else { return }

        let radialStep: CGFloat = [180, 140, 110, 90][min(depth, 3)]
        let spreadAngle: CGFloat = depth == 0 ? 2 * .pi : .pi * 0.9
        let baseAngle: CGFloat = parentId == nil ? 0 : atan2(point.y - (nodes[parentId!]?.position.y ?? 0),
                                                               point.x - (nodes[parentId!]?.position.x ?? 0))
        let startAngle = baseAngle - spreadAngle / 2

        for (i, child) in node.children.enumerated() {
            let angle = startAngle + (spreadAngle / CGFloat(max(node.children.count - 1, 1))) * CGFloat(i)
            let childPos = CGPoint(
                x: point.x + cos(angle) * radialStep,
                y: point.y + sin(angle) * radialStep
            )
            place(node: child, at: childPos, depth: depth + 1, parentId: node.id)
        }
    }
}

// MARK: - MindMapView

struct MindMapView: View {
    let rootNodes: [MindMapNode]

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var selectedNode: LayoutNode?
    @State private var layout = MindMapLayout()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                Color(.systemBackground)

                Canvas { ctx, size in
                    layout.build(from: rootNodes, in: size)
                    drawEdges(ctx: ctx)
                    drawNodes(ctx: ctx)
                }
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { scale = max(0.3, min(3, $0)) },
                        DragGesture()
                            .onChanged { offset = $0.translation }
                    )
                )
                .onTapGesture { tap in
                    // Find nearest node
                    let adjusted = CGPoint(
                        x: (tap.x - geo.size.width/2 - offset.width) / scale + geo.size.width/2,
                        y: (tap.y - geo.size.height/2 - offset.height) / scale + geo.size.height/2
                    )
                    selectedNode = layout.nodes.values.min(by: {
                        distance($0.position, adjusted) < distance($1.position, adjusted)
                    })
                }

                // Detail popover
                if let node = selectedNode {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(node.label).font(.headline)
                            Spacer()
                            Button { selectedNode = nil } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                        if !node.detail.isEmpty {
                            Text(node.detail).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding()
                    .frame(maxWidth: 320)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation { scale = 1; offset = .zero }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
            }
        }
    }

    private func drawEdges(ctx: GraphicsContext) {
        for edge in layout.edges {
            guard let from = layout.nodes[edge.from], let to = layout.nodes[edge.to] else { continue }
            var path = Path()
            path.move(to: from.position)
            // Bezier curve for smooth connections
            let cp1 = CGPoint(x: (from.position.x + to.position.x) / 2, y: from.position.y)
            let cp2 = CGPoint(x: (from.position.x + to.position.x) / 2, y: to.position.y)
            path.addCurve(to: to.position, control1: cp1, control2: cp2)
            ctx.stroke(path, with: .color(.secondary.opacity(0.4)), style: StrokeStyle(lineWidth: 1.5))
        }
    }

    private func drawNodes(ctx: GraphicsContext) {
        for node in layout.nodes.values {
            let r = nodeRadius(for: node.nodeType)
            let rect = CGRect(x: node.position.x - r, y: node.position.y - r, width: r*2, height: r*2)

            // Shadow
            ctx.fill(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)), with: .color(.black.opacity(0.06)))

            // Fill
            ctx.fill(Path(ellipseIn: rect), with: .color(node.color))

            // Label
            let text = Text(node.label)
                .font(.system(size: fontSize(for: node.nodeType), weight: .medium))
                .foregroundStyle(.white)
            ctx.draw(text, at: node.position)
        }
    }

    private func nodeRadius(for type: MindMapNode.NodeType) -> CGFloat {
        switch type {
        case .root: return 44
        case .topic: return 36
        case .subtopic: return 28
        case .action, .decision: return 22
        }
    }

    private func fontSize(for type: MindMapNode.NodeType) -> CGFloat {
        switch type {
        case .root: return 13
        case .topic: return 11
        case .subtopic: return 10
        case .action, .decision: return 9
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
    }
}

// MARK: - Color hex extension

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red: Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8) & 0xFF) / 255,
            blue: Double(val & 0xFF) / 255
        )
    }
}
