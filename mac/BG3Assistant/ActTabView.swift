import SwiftUI

struct ActTabView: View {
    @EnvironmentObject private var appState: AppState
    @State private var acceptsRouteConsequences = false
    @State private var confirmingAdvance = false
    @State private var confirmingFinal = false
    @State private var showsReviewedGear = false
    @State private var viewedAct: Int?

    var body: some View {
        VStack(spacing: 8) {
            actSwitcher
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    currentActCard
                    equipmentReview
                    routeReview
                    if ledgerAct == appState.selectedAct {
                        transitionCard
                    } else {
                        browsingCard
                    }
                }
                .padding(.trailing, 7)
            }
        }
        .onAppear { viewedAct = viewedAct ?? appState.selectedAct }
        .onChange(of: appState.selectedAct) { _, act in switchLedger(to: act) }
        .onChange(of: appState.run.id) { _, _ in switchLedger(to: appState.selectedAct) }
        .confirmationDialog(
            "Leave Act \(appState.selectedAct) permanently?",
            isPresented: $confirmingAdvance,
            titleVisibility: .visible
        ) {
            Button("Advance to Act \(appState.selectedAct + 1)", role: .destructive) {
                appState.advanceToNextAct(acceptingRouteConsequences: acceptsRouteConsequences)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The equipment review and unresolved consequences will be locked. This run cannot return to Act \(appState.selectedAct).")
        }
        .confirmationDialog(
            "Complete this Honor run?",
            isPresented: $confirmingFinal,
            titleVisibility: .visible
        ) {
            Button("Complete and lock Act 3", role: .destructive) {
                appState.finalizeActThree(acceptingRouteConsequences: acceptsRouteConsequences)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The final route and equipment ledger will become read-only.")
        }
    }

    private var ledgerAct: Int { viewedAct ?? appState.selectedAct }
    private var ledgerGuide: ActGuideSummary? { appState.actGuide(for: ledgerAct) }
    private var ledgerIsLocked: Bool { appState.run.actLedgerIsLocked(ledgerAct) }

    private var actSwitcher: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("ACT LEDGER").font(BG3Type.overline).foregroundStyle(BG3Theme.gold)
                Spacer()
                Text(ledgerAct == appState.selectedAct
                    ? "ACTIVE RUN"
                    : ledgerIsLocked ? "LOCKED HISTORY" : "PREVIEW")
                    .font(BG3Type.overline)
                    .foregroundStyle(ledgerAct == appState.selectedAct ? BG3Theme.success : BG3Theme.mutedParchment)
            }
            Picker("Act ledger", selection: Binding(
                get: { ledgerAct },
                set: { switchLedger(to: $0) }
            )) {
                ForEach(appState.acts.sorted(by: { $0.act < $1.act })) { guide in
                    Text("Act \(guide.act)").tag(guide.act)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
        .padding(8)
        .bg3InsetSurface(accent: BG3Theme.bronze)
    }

    private var currentActCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("ACT \(ledgerAct)")
                    .font(BG3Type.overline).foregroundStyle(BG3Theme.gold)
                Spacer()
                if let guide = ledgerGuide {
                    Text("\(guide.equipmentCount) equipment rows")
                        .font(BG3Type.captionBold).foregroundStyle(BG3Theme.mutedParchment)
                }
            }
            Text(ledgerGuide?.title ?? "Guide data unavailable")
                .font(BG3Type.pageTitle)
                .foregroundStyle(BG3Theme.parchment)
            if let guide = ledgerGuide {
                HStack(spacing: 7) {
                    Label(guide.routeAvailable ? "Route available" : "Route pending", systemImage: guide.routeAvailable ? "checkmark.circle.fill" : "clock")
                        .foregroundStyle(BG3Theme.mutedParchment)
                    Button { appState.openActMap(ledgerAct) } label: {
                        Label(guide.mapName, systemImage: "map")
                    }
                    .buttonStyle(.plain).foregroundStyle(BG3Theme.bronzeBright)
                }
                .font(BG3Type.caption)
            }
        }
        .padding(10).bg3InsetSurface(accent: BG3Theme.gold)
    }

    private var equipmentReview: some View {
        let gear = appState.actGear(for: ledgerAct)
        let pending = appState.unresolvedActGear(for: ledgerAct)
        let reviewed = appState.reviewedActGear(for: ledgerAct)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("EQUIPMENT REVIEW").font(BG3Type.overline).foregroundStyle(BG3Theme.gold)
                Spacer()
                Text("\(reviewed.count)/\(gear.count)")
                    .font(BG3Type.captionBold).foregroundStyle(BG3Theme.mutedParchment)
            }
            Text(equipmentReviewHelp)
                .font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment)
            if gear.isEmpty {
                Text("Assign reviewed builds on Party to create an equipment checklist.")
                    .font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(pending) { gear in
                    gearReviewRow(gear)
                }
                if pending.isEmpty {
                    Label("All equipment reviewed.", systemImage: "checkmark.seal.fill")
                        .font(BG3Type.captionBold).foregroundStyle(BG3Theme.success)
                        .padding(.vertical, 4)
                }
                if !reviewed.isEmpty {
                    BG3Disclosure(
                        title: "Reviewed (\(reviewed.count))", systemImage: "checkmark.circle.fill",
                        tint: BG3Theme.success, isExpanded: $showsReviewedGear
                    ) {
                        ForEach(reviewed) { gear in
                            gearReviewRow(gear)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(9).bg3InsetSurface(accent: BG3Theme.bronze)
    }

    private func gearReviewRow(_ gear: BuildGear) -> some View {
        let status = appState.actGearReviewStatus(for: gear, in: ledgerAct)
        let rarityColor = gear.rarityTint
        let locationColor = gear.regionTint
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                GearItemIcon(gear: gear, borderColor: rarityColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(gear.item)
                        .font(BG3Type.captionBold)
                        .foregroundStyle(rarityColor)
                    (Text(gear.region).foregroundColor(locationColor)
                        + Text(" · \(gear.acquisition)").foregroundColor(BG3Theme.mutedParchment))
                        .font(BG3Type.caption).lineLimit(2)
                }
                Spacer(minLength: 6)
                Button {
                    appState.setActGearReview(.obtained, for: gear, in: ledgerAct)
                } label: {
                    Image(systemName: status == .obtained ? "checkmark.circle.fill" : "checkmark.circle")
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).font(.system(size: 15, weight: .bold))
                .foregroundStyle(BG3Theme.success)
                .help("Mark as obtained")
                .accessibilityLabel("Mark \(gear.item) as obtained")
                .disabled(ledgerIsLocked)
                Button {
                    appState.setActGearReview(.missed, for: gear, in: ledgerAct)
                } label: {
                    Image(systemName: status == .missed ? "xmark.circle.fill" : "xmark.circle")
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).font(.system(size: 15, weight: .bold))
                .foregroundStyle(BG3Theme.danger)
                .help("Mark as missed")
                .accessibilityLabel("Mark \(gear.item) as missed")
                .disabled(ledgerIsLocked)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }

    @ViewBuilder private var routeReview: some View {
        let consequences = appState.actRouteConsequences(for: ledgerAct)
        let consequenceCount = appState.actRouteConsequenceCount(for: ledgerAct)
        if !consequences.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("UNRESOLVED CONSEQUENCES · \(consequenceCount)")
                    .font(BG3Type.overline).foregroundStyle(BG3Theme.warning)
                ForEach(consequences.prefix(4), id: \.self) { consequence in
                    Label(consequence, systemImage: "exclamationmark.triangle.fill")
                        .font(BG3Type.caption).foregroundStyle(BG3Theme.warning)
                }
                if consequenceCount > consequences.count {
                    Text("+ \(consequenceCount - consequences.count) additional consequence\(consequenceCount - consequences.count == 1 ? "" : "s") locked at transition")
                        .font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment)
                }
                if ledgerAct == appState.selectedAct && !ledgerIsLocked {
                    Toggle("I accept these unresolved Act \(ledgerAct) consequences", isOn: $acceptsRouteConsequences)
                        .font(BG3Type.captionBold)
                }
            }
            .padding(9).bg3InsetSurface(accent: BG3Theme.warning)
        }
    }

    private var transitionCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let next = appState.nextActGuide {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("NEXT · ACT \(next.act)").font(BG3Type.overline).foregroundStyle(BG3Theme.gold)
                        Text(next.title).font(BG3Type.rowTitle).foregroundStyle(BG3Theme.parchment)
                    }
                    Spacer()
                    Text("\(next.equipmentCount) gear rows")
                        .font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment)
                }
                if !next.routeAvailable {
                    Label("Equipment and map references are available; reviewed route instructions are not included yet.", systemImage: "info.circle")
                        .font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment)
                }
                if let blocker = appState.actTransitionBlockedReason {
                    Label(blocker, systemImage: "lock.fill").font(BG3Type.caption).foregroundStyle(BG3Theme.warning)
                }
                Button {
                    confirmingAdvance = true
                } label: {
                    Label("Advance to Act \(next.act)", systemImage: "arrow.right.circle.fill")
                        .font(BG3Type.captionBold).frame(maxWidth: .infinity)
                }
                .assistantActionButton(accent: BG3Theme.gold, prominent: true)
                .disabled(appState.actTransitionBlockedReason != nil || (!appState.currentActRouteConsequences.isEmpty && !acceptsRouteConsequences))
            } else if appState.run.finalActRecord != nil {
                Label("Honor run complete · Act 3 ledger locked", systemImage: "checkmark.seal.fill")
                    .font(BG3Type.captionBold).foregroundStyle(BG3Theme.success)
            } else {
                if let blocker = appState.finalActBlockedReason {
                    Label(blocker, systemImage: "lock.fill")
                        .font(BG3Type.caption).foregroundStyle(BG3Theme.warning)
                }
                Button {
                    confirmingFinal = true
                } label: {
                    Label("Complete Honor run", systemImage: "checkmark.seal.fill")
                        .font(BG3Type.captionBold).frame(maxWidth: .infinity)
                }
                .assistantActionButton(accent: BG3Theme.gold, prominent: true)
                .disabled(appState.finalActBlockedReason != nil || (!appState.currentActRouteConsequences.isEmpty && !acceptsRouteConsequences))
            }
        }
        .padding(10).bg3InsetSurface(accent: BG3Theme.gold)
    }

    private var browsingCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(
                ledgerIsLocked ? "Act \(ledgerAct) ledger is locked" : "Previewing Act \(ledgerAct)",
                systemImage: ledgerIsLocked ? "lock.fill" : "eye.fill"
            )
            .font(BG3Type.rowTitle)
            .foregroundStyle(ledgerIsLocked ? BG3Theme.mutedParchment : BG3Theme.gold)
            Text(ledgerIsLocked
                ? "This review remains available as history, but it was locked when the run advanced."
                : "Your run remains in Act \(appState.selectedAct). Reviewing this equipment does not advance the run or close the active ledger.")
                .font(BG3Type.caption).foregroundStyle(BG3Theme.mutedParchment)
            Button("Return to active Act \(appState.selectedAct)") {
                switchLedger(to: appState.selectedAct)
            }
            .assistantActionButton(accent: BG3Theme.gold)
        }
        .padding(10).bg3InsetSurface(accent: BG3Theme.bronze)
    }

    private var equipmentReviewHelp: String {
        if ledgerIsLocked { return "This completed act's equipment decisions are read-only." }
        if ledgerAct > appState.selectedAct {
            return "Preview and review this act's equipment without advancing the run."
        }
        return "Confirm the relevant items for the active party before leaving this act."
    }

    private func switchLedger(to act: Int) {
        viewedAct = act
        acceptsRouteConsequences = false
        showsReviewedGear = false
    }
}
