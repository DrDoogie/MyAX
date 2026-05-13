import SwiftUI

// MARK: - Obsidian-style Knowledge Graph

private struct GraphNode: Identifiable {
    let id: String        // topic title
    var position: CGPoint
    var velocity: CGPoint = .zero
    let meetings: [UUID]
    var radius: CGFloat   // bigger = more meetings
}

private struct ForceLayout: ObservableObject {
    @Published var nodes: [String: GraphNode] = [:]
    @Published var edges: [GraphEdge] = []

    private var timer: Timer?

    func build(nodes n: [String], edges e: [GraphEdge], meetings: StorageService) {
        var newNodes: [String: GraphNode] = [:]
        for name in n {
            let mids = meetings.meetings.filter { m in
                m.notes?.topicSummaries.contains { $0.title == name } ?? false
            }.map(\.id)
            let angle = Double.random(in: 0...(2 * .pi))
            let r = Double.random(in: 80...200)
            newNodes[name] = GraphNode(
                id: name,
                position: CGPoint(x: cos(angle) * r + 300, y: sin(angle) * r + 300),
                meetings: mids,
                radius: max(8, min(24, CGFloat(mids.count) * 6 + 8))
            )
        }
        Task { @MainActor in
            self.nodes = newNodes
            self.edges = e
        }
    }

    func step(canvasSize: CGSize) {
        let repulsion: CGFloat = 1200
        let attraction: CGFloat = 0.04
        let damping: CGFloat = 0.85
        let cx = canvasSize.width / 2
        let cy = canvasSize.height / 2

        var nodeArray = Array(nodes.values)

        // Repulsion between all pairs
        for i in 0..<nodeArray.count {
            var fx: CGFloat = 0; var fy: CGFloat = 0
            for j in 0..<nodeArray.count where i != j {
                let dx = nodeArray[i].position.x - nodeArray[j].position.x
                let dy = nodeArray[i].position.y - nodeArray[j].position.y
                let dist = max(1, sqrt(dx*dx + dy*dy))
                let force = repulsion / (dist * dist)
                fx += (dx / dist) * force
                fy += (dy / dist) * force
            }
            // Gravity toward center
            fx += (cx - nodeArray[i].position.x) * 0.01
            fy += (cy - nodeArray[i].position.y) * 0.01

            nodeArray[i].velocity.x = (nodeArray[i].velocity.x + fx) * damping
            nodeArray[i].velocity.y = (nodeArray[i].velocity.y + fy) * damping
        }

        // Attraction along edges
        for edge in edges {
            guard let a = nodeArray.firstIndex(where: { $0.id == edge.source }),
                  let b = nodeArray.firstIndex(where: { $0.id == edge.target }) else { continue }
            let dx = nodeArray[b].position.x - nodeArray[a].position.x
            let dy = nodeArray[b].position.y - nodeArray[a].position.y
            nodeArray[a].velocity.x += dx * attraction
            nodeArray[a].velocity.y += dy * attraction
            nodeArray[b].velocity.x -= dx * attraction
            nodeArray[b].velocity.y -= dy * attraction
        }

        // Apply velocities
        for i in 0..<nodeArray.count {
            nodeArray[i].position.x += nodeArray[i].velocity.x
            nodeArray[i].position.y += nodeArray[i].velocity.y
        }

        Task { @MainActor [self] in
            for node in nodeArray { self.nodes[node.id] = node }
        }
    }
}

struct GraphView: View {
    @ObservedObject private var storage = StorageService.shared
    @StateObject private var forceLayout = ForceLayout()
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var selectedNode: String?
    @State private var animating = false
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                GeometryReader { geo in
                    ZStack {
                        // Edges
                        Canvas { ctx, _ in
                            for edge in forceLayout.edges {
                                guard let a = forceLayout.nodes[edge.source],
                                      let b = forceLayout.nodes[edge.target] else { continue }
                                var path = Path()
                                path.move(to: a.position)
                                path.addLine(to: b.position)
                                ctx.stroke(path, with: .color(.secondary.opacity(0.25)), lineWidth: 1)

                                // Edge label midpoint
                                if !edge.relationship.isEmpty {
                                    let mid = CGPoint(x: (a.position.x + b.position.x)/2,
                                                      y: (a.position.y + b.position.y)/2)
                                    ctx.draw(
                                        Text(edge.relationship).font(.system(size: 9)).foregroundStyle(.secondary),
                                        at: mid
                                    )
                                }
                            }
                        }

                        // Nodes
                        ForEach(Array(forceLayout.nodes.values)) { node in
                            NodeCircle(
                                node: node,
                                isSelected: selectedNode == node.id
                            )
                            .position(node.position)
                            .onTapGesture {
                                withAnimation(.spring) {
                                    selectedNode = selectedNode == node.id ? nil : node.id
                                }
                            }
                        }
                    }
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture().onChanged { scale = max(0.2, min(4, $0)) },
                            DragGesture().onChanged { offset = $0.translation }
                        )
                    )
                    .onAppear {
                        canvasSize = geo.size
                        rebuildGraph(size: geo.size)
                        startSimulation()
                    }
                    .onChange(of: storage.meetings) { _, _ in
                        rebuildGraph(size: canvasSize)
                    }
                }

                // Info panel for selected node
                if let name = selectedNode {
                    selectedPanel(for: name)
                }
            }
            .navigationTitle("지식 그래프")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { withAnimation { scale = 1; offset = .zero } } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(animating ? "시뮬레이션 중지" : "시뮬레이션 시작") {
                        animating ? stopSimulation() : startSimulation()
                    }
                    .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func selectedPanel(for name: String) -> some View {
        let meetings = storage.meetings.filter { m in
            m.notes?.topicSummaries.contains { $0.title == name } ?? false
        }

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(name).font(.headline)
                Spacer()
                Button { selectedNode = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }

            if !meetings.isEmpty {
                Text("관련 회의 (\(meetings.count)건)").font(.caption).foregroundStyle(.secondary)
                ForEach(meetings) { m in
                    NavigationLink(destination: MeetingDetailView(meeting: m)) {
                        HStack {
                            Image(systemName: "doc.text")
                            Text(m.title).font(.callout).lineLimit(1)
                        }
                        .foregroundStyle(.accentColor)
                    }
                }
            }

            // Connected topics
            let connected = forceLayout.edges.compactMap { edge -> String? in
                if edge.source == name { return edge.target }
                if edge.target == name { return edge.source }
                return nil
            }
            if !connected.isEmpty {
                Text("연결된 주제").font(.caption).foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(Array(Set(connected)), id: \.self) { t in
                        Button { selectedNode = t } label: {
                            Text(t)
                                .font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                                .foregroundStyle(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func rebuildGraph(size: CGSize) {
        let (nodes, edges) = storage.buildGlobalGraph()
        forceLayout.build(nodes: nodes, edges: edges, meetings: storage)
    }

    private func startSimulation() {
        guard !animating else { return }
        animating = true
        Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { t in
            guard self.animating else { t.invalidate(); return }
            self.forceLayout.step(canvasSize: self.canvasSize)
        }
    }

    private func stopSimulation() {
        animating = false
    }
}

struct NodeCircle: View {
    let node: GraphNode
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : nodeColor(count: node.meetings.count))
                .frame(width: node.radius * 2, height: node.radius * 2)
                .shadow(color: isSelected ? .accentColor.opacity(0.5) : .clear, radius: 8)

            if node.radius >= 14 {
                Text(node.id)
                    .font(.system(size: min(10, node.radius * 0.5)))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: node.radius * 1.6)
            }
        }
    }

    private func nodeColor(count: Int) -> Color {
        switch count {
        case 0: return .gray.opacity(0.6)
        case 1: return Color(hex: "#4A90D9") ?? .blue
        case 2: return Color(hex: "#5BA85A") ?? .green
        default: return Color(hex: "#E8A838") ?? .orange
        }
    }
}
