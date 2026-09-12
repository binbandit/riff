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
                        if let index = steps.firstIndex(where: { $0.id == step.id }), index > 0 {
                            Button { steps.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up") }.accessibilityLabel("Move step earlier")
                        }
                        Button(role: .destructive) { steps.removeAll { $0.id == step.id } } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Remove step")
                    }.buttonStyle(.borderless)
                    Picker("Action", selection: $step.kind) {
                        ForEach(ActionKind.allCases.filter(\.isStep)) { Text($0.label).tag($0.rawValue) }
                    }.onChange(of: step.kind) { _, kind in
                        switch kind {
                        case "sound": step.value = store.snapshot.clips.first?.id ?? ""
                        case "app": step.value = store.snapshot.apps.first?.id ?? ""
                        case "media": step.value = "playPause"
                        case "hotkey": step.value = "Ctrl+Shift+M"
                        case "url": step.value = "https://"
                        default: step.value = ""
                        }
                    }
                    ActionFields(kind: step.kind, value: $step.value)
                    Stepper("Wait before: \(step.delayMs) ms", value: $step.delayMs, in: 0...5000, step: 100).font(.subheadline)
                }.padding(.vertical, 8)
            }
            Button(random ? "Add choice" : "Add step", systemImage: "plus") { steps.append(ActionStep()) }.disabled(steps.count >= 20)
            if steps.isEmpty { Text("Add at least one action.").foregroundStyle(.red) }
            if totalDelay > 30000 { Text("Reduce total delays to 30 seconds or less.").foregroundStyle(.red) }
        } header: { Text(title) } footer: {
            Text(random ? "Each tap chooses one of these actions with equal probability. Repeats are possible. Add up to 20 choices." : "Steps run in order. Stop all cancels remaining steps. Use up to 20 steps and 30 seconds of total delays.")
        }
    }
}
