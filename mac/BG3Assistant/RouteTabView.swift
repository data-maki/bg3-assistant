import SwiftUI

/// The planner's Route tab: one flat, phase-grouped checklist of the active
/// route with build-gear pickups woven in. Rows push a full-panel detail page
/// instead of expanding inline, so the list stays scannable and every row is
/// a single click target.
struct RouteTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var page = RoutePage.list
    @State private var expandedPickupPhases: Set<Int> = []
    @State private var showsDone = false
    @State private var showsSkipped = false
    @State private var showsOtherPickups = false
    @State private var showsGateDetail = false
    @State private var showsDeadlines = false

    enum RoutePage: Equatable {
        case list
        case step(String)
        case gear(memberId: String, itemKey: String)
    }

    var body: some View {
        Group {
            if !appState.activeGuideLoaded {
                loadingCard
            } else if !appState.activeRouteAvailable {
                laterActCard
            } else {
                ZStack {
                    switch page {
                    case .list:
                        stepList
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    case .step(let stepId):
                        StepDetailView(stepId: stepId) { page = .list }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    case .gear(let memberId, let itemKey):
                        gearPage(memberId: memberId, itemKey: itemKey)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.18), value: page)
            }
        }
        .onChange(of: appState.loadedGuideAct) { _, _ in resetNavigation() }
        .onChange(of: appState.run.id) { _, _ in resetNavigation() }
    }

    private func resetNavigation() {
        page = .list
        expandedPickupPhases = []
        showsDone = false
        showsSkipped = false
        showsOtherPickups = false
        showsGateDetail = false
        showsDeadlines = false
    }

    // MARK: - List

    private var stepList: some View {
        let pickups = GearLogic.pickupsByPhase(appState.routePickups, walkthrough: appState.walkthrough)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 5, pinnedViews: [.sectionHeaders]) {
                    progressHeader
                    ForEach(routePhases, id: \.order) { phase in
                        Section {
                            ForEach(phase.steps) { step in
                                stepRow(step).id(step.id)
                            }
                            pickupsRow(phase.order, pickups: pickups.byPhase[phase.order] ?? [])
                        } header: {
                            phaseHeader(phase.name, count: phase.steps.count)
                        }
                    }
                    if appState.activeWalkthroughSteps.isEmpty { routeCompleteCard }
                    bottomSummaries(otherPickups: pickups.other)
                }
                .padding(.trailing, 8)
            }
            .onAppear { scrollToCurrent(proxy) }
            .onChange(of: appState.focusedWalkthroughStepId) { _, _ in scrollToCurrent(proxy) }
        }
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        guard let id = appState.currentWalkthroughStep?.id else { return }
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text("Route · Act \(appState.selectedAct)")
                    .font(BG3Type.overline)
                    .foregroundStyle(BG3Theme.gold)
                    .textCase(.uppercase)
                Spacer()
                Text("Party L\(appState.lowestPartyLevel)")
                    .font(BG3Type.captionBold)
                    .foregroundStyle(BG3Theme.mutedParchment)
                Button {
                    appState.followRecommendedRoute()
                } label: {
                    Image(systemName: "location.fill").frame(width: 16, height: 16)
                }
                .assistantActionButton()
                .controlSize(.mini)
                .help("Jump back to the recommended route")
            }
            HStack(spacing: 7) {
                ProgressView(value: Double(appState.archivedCount), total: Double(max(appState.walkthrough.count, 1)))
                    .tint(BG3Theme.gold)
                Text("\(appState.archivedCount)/\(appState.walkthrough.count) done")
                    .font(BG3Type.captionBold)
                    .foregroundStyle(BG3Theme.mutedParchment)
                    .fixedSize()
            }
            gateLine
            deadlinesLine
        }
        .padding(8)
        .bg3InsetSurface(accent: BG3Theme.gold)
    }

    @ViewBuilder private var gateLine: some View {
        if appState.selectedAct == 3 {
            Label("Final act · no next-act gate", systemImage: "flag.checkered")
                .font(BG3Type.captionBold)
                .foregroundStyle(BG3Theme.mutedParchment)
        } else if appState.currentActRouteConsequences.isEmpty {
            Label("Act \(appState.selectedAct + 1) gate: ready", systemImage: "checkmark.seal.fill")
                .font(BG3Type.captionBold)
                .foregroundStyle(BG3Theme.success)
        } else {
            let blockers = appState.currentActRouteConsequences
            BG3Disclosure(
                title: blockers.count == 1
                    ? "Act \(appState.selectedAct + 1) gate: 1 step remains"
                    : "Act \(appState.selectedAct + 1) gate: \(blockers.count) steps remain",
                systemImage: "exclamationmark.triangle.fill",
                tint: BG3Theme.warning, titleTint: BG3Theme.warning,
                isExpanded: $showsGateDetail
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(blockers, id: \.self) { blocker in
                        FactRow(glyph: "⚠", tint: BG3Theme.warning, text: blocker, secondary: true)
                    }
                }
            }
        }
    }

    @ViewBuilder private var deadlinesLine: some View {
        if !appState.timedEvents.isEmpty {
            BG3Disclosure(
                title: "Deadlines & lockouts (\(appState.timedEvents.count))",
                systemImage: "clock.badge.exclamationmark",
                tint: BG3Theme.warning,
                titleTint: BG3Theme.warning,
                isExpanded: $showsDeadlines
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(appState.timedEvents) { event in
                        FactRow(
                            glyph: event.severity == "critical" ? "!" : "◷",
                            tint: event.severity == "critical" ? BG3Theme.danger : BG3Theme.warning,
                            text: "\(event.name): \(event.deadline). \(event.consequence)",
                            secondary: true
                        )
                    }
                }
            }
        }
    }

    private func phaseHeader(_ name: String, count: Int) -> some View {
        HStack {
            Text(name.uppercased())
            Spacer()
            Text(count == 1 ? "1 left" : "\(count) left")
        }
        .font(BG3Type.overline)
        .foregroundStyle(BG3Theme.gold)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(BG3Theme.ink.opacity(0.94))
    }

    private var routePhases: [(order: Int, name: String, steps: [WalkthroughStep])] {
        Dictionary(grouping: appState.activeWalkthroughSteps, by: \.phaseOrder)
            .sorted { $0.key < $1.key }
            .map { order, steps in
                (order, steps.first?.phase ?? "", steps.sorted { $0.order < $1.order })
            }
    }

    private func stepRow(_ step: WalkthroughStep) -> some View {
        let encounter = StepEncounter.classify(step)
        let isNow = step.id == appState.currentWalkthroughStep?.id
        let presentation = appState.routeDependencyPresentation(for: step)
        return Button {
            page = .step(step.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: encounter.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(encounter.tint)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(step.title)
                        .font(BG3Type.rowTitle)
                        .foregroundStyle(BG3Theme.parchment)
                        .lineLimit(1)
                    Text(presentation.note ?? step.area)
                        .font(BG3Type.caption)
                        .foregroundStyle(presentation.requiresAttention ? BG3Theme.warning : BG3Theme.mutedParchment)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                statusChip(for: step, isNow: isNow, presentation: presentation)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(BG3Theme.mutedParchment.opacity(0.7))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 8).fill(isNow ? BG3Theme.bronze.opacity(0.2) : BG3Theme.ink.opacity(0.24)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isNow ? BG3Theme.gold.opacity(0.55) : BG3Theme.bronze.opacity(0.3), lineWidth: 0.7))
        .accessibilityLabel("\(step.title), \(accessibilityStatus(for: step, isNow: isNow, presentation: presentation))")
    }

    private func statusChip(for step: WalkthroughStep, isNow: Bool, presentation: RouteDependencyPresentation) -> StatusChip {
        if isNow { return StatusChip(text: "now", tint: BG3Theme.gold, filled: true) }
        if presentation.requiresAttention { return StatusChip(text: "revisit", tint: BG3Theme.warning) }
        if presentation.note != nil { return StatusChip(text: "later", tint: BG3Theme.mutedParchment) }
        if step.minimumLevel > appState.lowestPartyLevel {
            return StatusChip(text: "L\(step.minimumLevel)", tint: BG3Theme.caution)
        }
        return StatusChip(text: "ready", tint: BG3Theme.success)
    }

    private func accessibilityStatus(for step: WalkthroughStep, isNow: Bool, presentation: RouteDependencyPresentation) -> String {
        if isNow { return "current objective" }
        if presentation.requiresAttention { return "needs a revisit" }
        if let note = presentation.note { return note }
        if step.minimumLevel > appState.lowestPartyLevel { return "preparation recommended, needs level \(step.minimumLevel)" }
        return "ready"
    }

    // MARK: - Pickups

    @ViewBuilder private func pickupsRow(_ phaseOrder: Int, pickups: [GearLogic.Pickup]) -> some View {
        if !pickups.isEmpty {
            BG3Disclosure(
                title: pickups.count == 1 ? "1 pickup here" : "\(pickups.count) pickups here",
                glyph: "◈", tint: BG3Theme.gold, titleTint: BG3Theme.mutedParchment,
                isExpanded: Binding(
                    get: { expandedPickupPhases.contains(phaseOrder) },
                    set: { expanded in
                        if expanded { expandedPickupPhases.insert(phaseOrder) } else { expandedPickupPhases.remove(phaseOrder) }
                    }
                )
            ) {
                ForEach(pickups) { pickupRow($0) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .accessibilityLabel("\(pickups.count) gear pickups in this phase")
        }
    }

    private func pickupRow(_ pickup: GearLogic.Pickup) -> some View {
        Button {
            page = .gear(memberId: pickup.memberId, itemKey: pickup.gear.itemKey)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: appState.gearTargetContext?.matches(gearId: pickup.gear.id, memberId: pickup.memberId) == true ? "scope" : "circle")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(BG3Theme.gold)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pickup.gear.item)
                        .font(BG3Type.body)
                        .foregroundStyle(BG3Theme.parchment)
                        .lineLimit(1)
                    Text("for \(pickup.memberName) · \(pickup.gear.region)")
                        .font(BG3Type.caption)
                        .foregroundStyle(BG3Theme.mutedParchment)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(BG3Theme.mutedParchment.opacity(0.7))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 7).fill(BG3Theme.ink.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(BG3Theme.bronze.opacity(0.22), lineWidth: 0.7))
    }

    private func gearPage(memberId: String, itemKey: String) -> some View {
        // Resolve member and item live so the page never shows a stale copy
        // after a build or catalog refresh while pushed.
        let member = appState.activeParty.first { $0.id == memberId }
        let gear = member.flatMap { member in
            appState.builds.first { $0.id == member.buildId }?.gear.first { $0.itemKey == itemKey }
        }
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                page = .list
            } label: {
                Label("Route", systemImage: "chevron.left").font(BG3Type.captionBold)
            }
            .assistantActionButton()
            .controlSize(.small)
            if let member, let gear {
                ScrollView {
                    GearDetailView(gear: gear, member: member)
                        .padding(9)
                        .bg3InsetSurface(accent: BG3Theme.bronze)
                        .padding(.trailing, 8)
                }
            } else {
                Text("This pickup is no longer part of the active party's plan.")
                    .font(BG3Type.caption)
                    .foregroundStyle(BG3Theme.mutedParchment)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Bottom summaries

    @ViewBuilder private func bottomSummaries(otherPickups: [GearLogic.Pickup]) -> some View {
        let done = appState.archivedWalkthroughSteps.filter { appState.walkthroughDisposition($0) == .completed }
        let skipped = appState.archivedWalkthroughSteps.filter { appState.walkthroughDisposition($0) == .skipped }
        VStack(spacing: 5) {
            if !skipped.isEmpty {
                BG3Disclosure(
                    title: "Skipped (\(skipped.count))", systemImage: "forward.circle.fill",
                    tint: BG3Theme.warning, inset: true, isExpanded: $showsSkipped
                ) {
                    ForEach(skipped.sorted { $0.order < $1.order }) { archivedRow($0) }
                }
            }
            if !done.isEmpty {
                BG3Disclosure(
                    title: "Done (\(done.count))", systemImage: "checkmark.circle.fill",
                    tint: BG3Theme.success, inset: true, isExpanded: $showsDone
                ) {
                    ForEach(done.sorted { $0.order > $1.order }) { archivedRow($0) }
                }
            }
            if !otherPickups.isEmpty {
                BG3Disclosure(
                    title: "Other pickups (\(otherPickups.count))", systemImage: "bag.fill",
                    tint: BG3Theme.gold, inset: true, isExpanded: $showsOtherPickups
                ) {
                    ForEach(otherPickups) { pickupRow($0) }
                }
            }
        }
        .padding(.top, 4)
    }

    private func archivedRow(_ step: WalkthroughStep) -> some View {
        let completed = appState.walkthroughDisposition(step) == .completed
        return HStack(spacing: 7) {
            Image(systemName: completed ? "checkmark.circle.fill" : "forward.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(completed ? BG3Theme.success : BG3Theme.warning)
            VStack(alignment: .leading, spacing: 0) {
                Text(step.title).font(BG3Type.body).foregroundStyle(BG3Theme.parchment).lineLimit(1)
                Text(step.area).font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment).lineLimit(1)
            }
            Spacer()
            Button("Revisit") { appState.setWalkthroughDisposition(step, .pending) }
                .assistantActionButton()
                .controlSize(.mini)
        }
        .padding(.vertical, 2)
    }

    // MARK: - States

    private var routeCompleteCard: some View {
        let hasSkips = appState.routeHasConsequentialSkips
        return VStack(alignment: .leading, spacing: 5) {
            Label(
                hasSkips ? "Act \(appState.selectedAct) route resolved with skips" : "Act \(appState.selectedAct) route complete",
                systemImage: hasSkips ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"
            )
                .font(BG3Type.rowTitle)
                .foregroundStyle(hasSkips ? BG3Theme.warning : BG3Theme.success)
            Text(routeCompleteMessage)
                .font(BG3Type.caption)
                .foregroundStyle(BG3Theme.mutedParchment)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bg3InsetSurface(accent: hasSkips ? BG3Theme.warning : BG3Theme.success)
    }

    private var routeCompleteMessage: String {
        if appState.routeHasConsequentialSkips { return "Revisit required or recommended skipped steps before treating this route as complete." }
        if appState.selectedAct == 3 { return "The final reviewed route is complete." }
        return appState.currentActRouteConsequences.isEmpty
            ? "No Act \(appState.selectedAct) requirements remain."
            : "Review the remaining Act \(appState.selectedAct + 1) requirements before advancing."
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            ProgressView()
            Text(appState.statusMessage)
                .font(BG3Type.rowTitle)
                .foregroundStyle(BG3Theme.parchment)
            Text("The active route stays hidden until the matching act guide is loaded.")
                .font(BG3Type.caption)
                .foregroundStyle(BG3Theme.mutedParchment)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bg3InsetSurface(accent: BG3Theme.gold)
    }

    private var laterActCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Act \(appState.selectedAct) route")
                .font(BG3Type.overline)
                .textCase(.uppercase)
                .foregroundStyle(BG3Theme.gold)
            Label("Step-by-step route guidance is not available for this act yet.", systemImage: "clock")
                .foregroundStyle(BG3Theme.warning)
            Text(appState.selectedAct < 3
                ? "Equipment and map references are available in Loadout. The next act gate stays locked until this route is ready."
                : "Equipment and map references remain available in Loadout.")
                .font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment)
            HStack(spacing: 6) {
                Button("Open loadout") { appState.plannerTab = .loadout }
                Button("Open map") { appState.openCurrentActMap() }
            }
            .assistantActionButton()
        }
        .padding(10)
        .bg3InsetSurface(accent: BG3Theme.gold)
    }

}
