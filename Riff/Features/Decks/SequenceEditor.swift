import SwiftUI

struct SequenceEditor: View {
    @Environment(RiffStore.self) private var store
    @Binding var steps: [ActionStep]
    let title: String
    var random = false
    private var totalDelay: Int { steps.reduce(0) { $0 + $1.delayMs } }

    var body: some View {
        Section {
            ForEach($steps) { $step in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(random ? "Choice" : "Step") \((steps.firstIndex(where: { $0.id == step.id }) ?? 0) + 1)")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        if let index = steps.firstIndex(where: { $0.id == step.id }) {
                            if index > 0 {
                                Button { steps.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up") }.accessibilityLabel("Move step earlier")
                            }
                            if index < steps.count - 1 {
                                Button { steps.swapAt(index, index + 1) } label: { Image(systemName: "arrow.down") }.accessibilityLabel("Move step later")
                            }
                            Button {
                                var copy = step
                                copy.id = UUID().uuidString
                                steps.insert(copy, at: index + 1)
                            } label: { Image(systemName: "plus.square.on.square") }
                                .accessibilityLabel("Duplicate step")
                                .disabled(steps.count >= 20 || totalDelay + step.delayMs > 30000)
                        }
                        Button(role: .destructive) { steps.removeAll { $0.id == step.id } } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Remove step")
                    }.buttonStyle(.borderless)
                    Picker("Action", selection: $step.kind) {
                        ForEach(ActionKind.allCases.filter(\.isStep)) { Text($0.label).tag($0.rawValue) }
                    }.onChange(of: step.kind) { _, kind in
                        step.value = defaultValue(for: kind)
                    }
                    ActionFields(kind: step.kind, value: $step.value)
                    Stepper("Wait before: \(step.delayMs) ms", value: $step.delayMs, in: 0...5000, step: 100).font(.subheadline)
                }.padding(.vertical, 8)
            }
            Menu {
                ForEach(ActionKind.allCases.filter(\.isStep)) { kind in
                    Button(kind.label, systemImage: kind.icon) {
                        steps.append(ActionStep(kind: kind.rawValue, value: defaultValue(for: kind.rawValue)))
                    }
                }
            } label: {
                Label(random ? "Add choice" : "Add step", systemImage: "plus")
            }.disabled(steps.count >= 20)
            if !random {
                Button("Add game chat message", systemImage: "text.bubble") {
                    steps.append(contentsOf: ActionStep.gameChatMessage)
                }.disabled(steps.count > 17 || totalDelay > 29600)
                Text("Optional starting point: K to open chat, GG as typed text, and Enter to send. Every step is editable. Increase the wait before the text if your game needs more time to open chat.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if steps.isEmpty { Text("Add at least one action.").foregroundStyle(.red) }
            if totalDelay > 30000 { Text("Reduce total delays to 30 seconds or less.").foregroundStyle(.red) }
        } header: { Text(title) } footer: {
            Text(random ? "Each tap chooses one of these actions with equal probability. Repeats are possible. Add up to 20 choices." : "Build your own sequence with Add step. Mix keys, text, sounds, websites, apps, and media controls in any order. Edit, duplicate, move, or remove each step and set its wait. Steps run in order; Stop all cancels remaining steps. Use up to 20 steps, 5 seconds per wait, and 30 seconds of total delays.")
        }
    }

    private func defaultValue(for kind: String) -> String {
        switch kind {
        case "sound": store.snapshot.clips.first?.id ?? ""
        case "app": store.snapshot.apps.first?.id ?? ""
        case "media": "playPause"
        case "url": "https://"
        default: ""
        }
    }
}
