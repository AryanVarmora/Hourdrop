import SwiftUI

/// The popover that opens when you click the drop in the menu bar.
struct MenuBarView: View {
    @EnvironmentObject private var store: WaterStore
    @Environment(\.openSettings) private var openSettings
    @AppStorage(Prefs.bottleSizeML.key) private var bottleSizeML = Prefs.bottleSizeML.fallback
    @AppStorage(Prefs.dailyGoalML.key) private var dailyGoalML = Prefs.dailyGoalML.fallback
    @AppStorage(Prefs.wakeStartHour.key) private var wakeStartHour = Prefs.wakeStartHour.fallback
    @AppStorage(Prefs.wakeEndHour.key) private var wakeEndHour = Prefs.wakeEndHour.fallback
    @AppStorage(Prefs.filterCapacityL.key) private var filterCapacityL = Prefs.filterCapacityL.fallback
    @AppStorage(Prefs.filterStart.key) private var filterStart = Prefs.filterStart.fallback

    /// The drink whose size picker is open (tap Coffee, Chai or Smoothie to open it).
    @State private var openDrink: Drink?
    /// What you've typed in the "Other" size box.
    @State private var customText = ""

    private var progress: Double {
        guard dailyGoalML > 0 else { return 0 }
        return min(Double(store.todayTotal) / Double(dailyGoalML), 1)
    }

    /// How you're doing for this time of day, or nil outside your wake hours.
    private var pace: Pace? {
        let now = Date.now
        let window = WakeWindow.current(startHour: wakeStartHour, endHour: wakeEndHour, now: now)
        guard window.contains(now), dailyGoalML > 0 else { return nil }
        return Pace(drankML: store.total(since: window.start), goalML: dailyGoalML, window: window, now: now)
    }

    private var filter: FilterLife? {
        guard filterCapacityL > 0 else { return nil }
        let start = Date(timeIntervalSince1970: filterStart)
        return FilterLife(start: start, capacityL: filterCapacityL,
                          filteredML: store.total(since: start, drink: .water))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            todaySection
            waterSection
            drinksSection

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

            if let filter { filterLine(filter) }

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

    // MARK: - Sections

    /// Total, progress bar with a "where you should be by now" marker, pace, and caffeine.
    private var todaySection: some View {
        let pace = pace
        return VStack(alignment: .leading, spacing: 6) {
            Text("Today").font(.headline).foregroundStyle(.secondary)
            Text("\(Format.liters(store.todayTotal)) of \(Format.liters(dailyGoalML))")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            PaceBar(progress: progress,
                    marker: pace.map { Double($0.expectedML) / Double(dailyGoalML) },
                    color: progress >= 1 ? .green : .blue)
            if progress >= 1 {
                Text("Goal reached 🎉").font(.caption).foregroundStyle(.green)
            } else if let pace {
                Text(pace.summary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(pace.status == .behind ? .orange : .green)
            }
            // What the total is made of, once you've had more than water
            if store.todayByDrink.contains(where: { $0.drink != .water }) {
                Text(store.todayByDrink.map { "\($0.drink.emoji) \(Format.liters($0.ml))" }
                    .joined(separator: "   "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if store.todayCaffeineMg > 0 {
                let mg = store.todayCaffeineMg
                Text(mg > 400 ? "~\(mg) mg caffeine today, over the 400 mg daily limit"
                              : "~\(mg) mg caffeine today")
                    .font(.caption)
                    .foregroundStyle(mg > 400 ? .orange : .secondary)
            }
        }
    }

    /// Water: how much of your bottle you just drank.
    private var waterSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("💧 Water")
            HStack(spacing: 8) {
                logButton("¼", detail: "\(bottleSizeML / 4) ml") { log(.water, ml: bottleSizeML / 4) }
                logButton("½", detail: "\(bottleSizeML / 2) ml") { log(.water, ml: bottleSizeML / 2) }
                logButton("Full", detail: "\(bottleSizeML) ml") { log(.water, ml: bottleSizeML) }
            }
        }
    }

    /// Other drinks: tap one, then pick its size.
    private var drinksSection: some View {
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
    }

    /// "LARQ filter: 23% used · replace by Dec 18", orange from 90%, red when due.
    private func filterLine(_ filter: FilterLife) -> some View {
        let used = filter.used(now: .now)
        let text = used >= 1
            ? "LARQ filter: time to replace it"
            : "LARQ filter: \(Int(used * 100))% used · replace by \(filter.replaceBy.formatted(.dateTime.month(.abbreviated).day()))"
        return Text(text)
            .font(.caption)
            .foregroundStyle(used >= 1 ? .red : used >= 0.9 ? .orange : .secondary)
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

    // MARK: - Helpers

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

/// A progress bar with an optional marker showing where you'd be by now if you drank evenly.
struct PaceBar: View {
    let progress: Double     // 0...1
    let marker: Double?      // 0...1
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color)
                    .frame(width: progress > 0 ? max(geo.size.width * progress, 6) : 0)
                if let marker {
                    Capsule()
                        .fill(.primary.opacity(0.55))
                        .frame(width: 2, height: geo.size.height + 6)
                        .offset(x: min(max(geo.size.width * marker - 1, 0), geo.size.width - 2))
                }
            }
        }
        .frame(height: 6)
        .help("The line shows where you'd be by now if you drank evenly through your wake hours.")
    }
}
