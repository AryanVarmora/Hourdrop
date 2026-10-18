import SwiftUI

/// The popover that opens when you click the drop in the menu bar.
struct MenuBarView: View {
    @EnvironmentObject private var store: WaterStore
    @Environment(\.openSettings) private var openSettings
    @AppStorage("bottleSizeML") private var bottleSizeML = 750
    @AppStorage("dailyGoalML") private var dailyGoalML = 3000

    /// The drink whose size picker is open (tap Coffee, Chai or Smoothie to open it).
    @State private var openDrink: Drink?
    /// What you've typed in the "Other" size box.
    @State private var customText = ""

    private var progress: Double {
        guard dailyGoalML > 0 else { return 0 }
        return min(Double(store.todayTotal) / Double(dailyGoalML), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Today's progress
            VStack(alignment: .leading, spacing: 6) {
                Text("Today").font(.headline).foregroundStyle(.secondary)
                Text("\(Format.liters(store.todayTotal)) of \(Format.liters(dailyGoalML))")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                ProgressView(value: progress)
                    .tint(progress >= 1 ? .green : .blue)
                // What the total is made of, once you've had more than water
                if store.todayByDrink.contains(where: { $0.drink != .water }) {
                    Text(store.todayByDrink.map { "\($0.drink.emoji) \(Format.liters($0.ml))" }
                        .joined(separator: "   "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if progress >= 1 {
                    Text("Goal reached 🎉").font(.caption).foregroundStyle(.green)
                }
            }

            // Water: how much of your bottle you just drank
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("💧 Water")
                HStack(spacing: 8) {
                    logButton("¼", detail: "\(bottleSizeML / 4) ml") { log(.water, ml: bottleSizeML / 4) }
                    logButton("½", detail: "\(bottleSizeML / 2) ml") { log(.water, ml: bottleSizeML / 2) }
                    logButton("Full", detail: "\(bottleSizeML) ml") { log(.water, ml: bottleSizeML) }
                }
            }

            // Other drinks: tap one, then pick its size
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Other drinks")
                HStack(spacing: 8) {
                    ForEach(Drink.others, id: \.self) { drink in
                        logButton("\(drink.emoji) \(drink.name)", detail: "pick size",
                                  highlighted: openDrink == drink) {
                            openDrink = (openDrink == drink) ? nil : drink
                            customText = ""
                        }
                    }
                }
                if let drink = openDrink {
                    sizePicker(for: drink)
                }
            }

            // Today's log
            if !store.todayEntries.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.todayEntries.suffix(5).reversed()) { entry in
                        HStack {
                            Text(entry.timestamp, style: .time)
                            Text("\(entry.kind.emoji) \(entry.kind.name)")
                            Spacer()
                            Text("\(entry.ml) ml")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                Button("Undo last") { store.undoLast() }
                    .disabled(store.todayEntries.isEmpty)
                Spacer()
                Button("Settings…") {
                    NSApp.activate()
                    openSettings()
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(16)
        .frame(width: 290)
        .onAppear {
            store.refresh()
            openDrink = nil
            customText = ""
        }
    }

    /// Size choices for one drink: quick sizes in oz, or type any amount.
    private func sizePicker(for drink: Drink) -> some View {
        let customML = Drink.ml(fromTyped: customText)
        return VStack(alignment: .leading, spacing: 8) {
            Text("How much \(drink.name.lowercased())?")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(Drink.sizesOz, id: \.self) { oz in
                    logButton("\(Int(oz)) oz", detail: "\(Drink.ml(oz: oz)) ml") {
                        log(drink, ml: Drink.ml(oz: oz))
                    }
                }
            }
            HStack(spacing: 6) {
                Text("Other:")
                TextField("e.g. 18", text: $customText)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                    .onSubmit { if let ml = customML { log(drink, ml: ml) } }
                Text("oz")
                Spacer()
                Button("Log") { if let ml = customML { log(drink, ml: ml) } }
                    .disabled(customML == nil)
            }
            .font(.callout)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func log(_ drink: Drink, ml: Int) {
        store.add(ml: ml, drink: drink)
        openDrink = nil
        customText = ""
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
    }

    /// A two-line button: a title, and a small detail line (ml, or "pick size").
    @ViewBuilder
    private func logButton(_ title: String, detail: String, highlighted: Bool = false,
                           action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail).font(.caption2).opacity(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        if highlighted {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}
