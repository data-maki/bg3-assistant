import Foundation

precondition(
    BackendProcessManager.processIDs(from: "101\n202\ninvalid\n", excluding: 202) == [101],
    "Port-listener parsing must exclude the current process and malformed output"
)

precondition(PermissionManager.authorizationAction(
    preflightGranted: false, verifiedThisLaunch: true, requestAttempted: false, promptIfMissing: true
) == .alreadyVerified, "Verified pixel access must never prompt again")
precondition(PermissionManager.authorizationAction(
    preflightGranted: true, verifiedThisLaunch: false, requestAttempted: false, promptIfMissing: true
) == .verifyPixels, "An existing macOS grant must be pixel-verified without prompting")
precondition(PermissionManager.authorizationAction(
    preflightGranted: false, verifiedThisLaunch: false, requestAttempted: false, promptIfMissing: true
) == .offerRequest, "A missing first-launch grant must offer a user-initiated TCC request")
precondition(PermissionManager.authorizationAction(
    preflightGranted: false, verifiedThisLaunch: false, requestAttempted: true, promptIfMissing: true
) == .wait, "An unresolved system request must not trigger repeated pixel probes")
precondition(PermissionManager.authorizationAction(
    preflightGranted: false, verifiedThisLaunch: false, requestAttempted: false, promptIfMissing: false
) == .wait, "Background refresh must never produce a permission prompt")

if ProcessInfo.processInfo.environment["BG3_DECODE_ROUTE"] == "1" {
    let payloadData = FileHandle.standardInput.readDataToEndOfFile()
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let payload = try decoder.decode(RoutePayload.self, from: payloadData)
    precondition(payload.checkpoints.count == 19)
    precondition(payload.walkthrough.count == 59)
    precondition(payload.walkthrough.contains(where: { $0.id == "walk-vlaakith-audience" && $0.incident != nil }))
    // Every checkpoint must be owned by a walkthrough step — setDisposition
    // routes checkpoint dispositions through the walkthrough ledger.
    let ownedCheckpointIds = Set(payload.walkthrough.compactMap(\.checkpointId))
    for checkpoint in payload.checkpoints {
        precondition(ownedCheckpointIds.contains(checkpoint.id), "Checkpoint \(checkpoint.id) has no owning walkthrough step")
    }
}

let restingPet = PetAnimationModel.frame(
    isHovered: false,
    hoverElapsed: 20,
    pointerLocation: CGPoint(x: 100, y: 0),
    viewSize: CGSize(width: 100, height: 100),
    reduceMotion: false
)
precondition(restingPet == PetSpriteFrame(row: 0, column: 0), "The pet must be perfectly still outside hover")
let hoverIntroPet = PetAnimationModel.frame(
    isHovered: true,
    hoverElapsed: 0.15,
    pointerLocation: CGPoint(x: 100, y: 50),
    viewSize: CGSize(width: 100, height: 100),
    reduceMotion: false
)
precondition(hoverIntroPet == PetSpriteFrame(row: 4, column: 1), "Hover must use the authored jump intro")
let petViewSize = CGSize(width: 100, height: 100)
precondition(PetAnimationModel.lookFrame(pointerLocation: CGPoint(x: 50, y: 0), viewSize: petViewSize) == PetSpriteFrame(row: 9, column: 0))
precondition(PetAnimationModel.lookFrame(pointerLocation: CGPoint(x: 100, y: 50), viewSize: petViewSize) == PetSpriteFrame(row: 9, column: 4))
precondition(PetAnimationModel.lookFrame(pointerLocation: CGPoint(x: 50, y: 100), viewSize: petViewSize) == PetSpriteFrame(row: 10, column: 0))
precondition(PetAnimationModel.lookFrame(pointerLocation: CGPoint(x: 0, y: 50), viewSize: petViewSize) == PetSpriteFrame(row: 10, column: 4))
precondition(PetAnimationModel.lookFrame(pointerLocation: CGPoint(x: 50, y: 50), viewSize: petViewSize) == nil)

var run = HonorRun()
run.migrateLegacyPartySlots()
precondition(run.party.count == 4)
precondition(run.party.map(\.level) == [1, 1, 1, 1])
precondition(run.party.map(\.name) == ["Tav", "Shadowheart", "Lae'zel", "Astarion"])
precondition(run.progress.isEmpty)
precondition(run.guideVersion.isEmpty)
precondition(run.selectedAct == 1)
precondition(run.party.map(\.className) == [nil, "Cleric", "Fighter", "Rogue"])
precondition(run.roster?.count == 7)
precondition(run.activeParty.count == 4)
precondition(run.roster?.first(where: { $0.name == "Wyll" })?.rosterStatus == .camp)
precondition(run.equippedByMember?.isEmpty == true)
precondition(run.equipmentOwnershipKnown == false)
precondition(run.visualMemory?.isEmpty == true)
let firstMemory = VisualMemoryEntry(
    id: "one", capturedAt: Date(timeIntervalSince1970: 1), summary: "At the cove", likelyArea: "Secluded Cove",
    screenKind: "exploration", evidence: ["Harpy result visible"],
    candidates: [ScreenCandidate(checkpointId: "fight-harpies", confidence: 0.9, reason: "Cove")],
    completionCandidates: [VisualCompletionCandidate(stepId: "walk-harpies", confidence: 0.9, reason: "Result")],
    confidence: 0.9
)
let refreshedMemory = VisualMemoryEntry(
    id: "two", capturedAt: Date(timeIntervalSince1970: 2), summary: "Still at the cove", likelyArea: "Secluded Cove",
    screenKind: "exploration", evidence: ["Harpy result visible"],
    candidates: firstMemory.candidates, completionCandidates: firstMemory.completionCandidates, confidence: 0.92
)
let deduplicatedMemory = VisualMemoryLedger.recording(refreshedMemory, in: [firstMemory])
precondition(deduplicatedMemory.count == 1 && deduplicatedMemory[0].id == "two")
precondition(VisualMemoryLedger.recording(firstMemory, in: Array(repeating: refreshedMemory, count: 30)).count == 24)
var evidenceOnlyRun = HonorRun()
evidenceOnlyRun.walkthroughProgress = ["walk-harpies": .pending]
evidenceOnlyRun.visualMemory = VisualMemoryLedger.recording(firstMemory, in: [])
precondition(evidenceOnlyRun.walkthroughProgress?["walk-harpies"] == .pending)
var legacyRun = HonorRun()
legacyRun.party[1].name = "Companion 1"
legacyRun.party[1].className = nil
legacyRun.migrateLegacyPartySlots()
precondition(legacyRun.party[1].name == "Shadowheart" && legacyRun.party[1].className == "Cleric")
precondition(legacyRun.roster?.count == 7)
var rosterRun = legacyRun
let laezelIndex = rosterRun.roster!.firstIndex(where: { $0.name == "Lae'zel" })!
rosterRun.roster![laezelIndex].buildId = "MO-OH"
rosterRun.roster![laezelIndex].className = "Monk 4"
rosterRun.roster![laezelIndex].status = .camp
rosterRun.syncActivePartyProjection()
precondition(!rosterRun.activeParty.contains(where: { $0.name == "Lae'zel" }))
precondition(rosterRun.roster![laezelIndex].buildId == "MO-OH")
let wyllIndex = rosterRun.roster!.firstIndex(where: { $0.name == "Wyll" })!
rosterRun.roster![wyllIndex].status = .active
rosterRun.syncActivePartyProjection()
precondition(rosterRun.activeParty.count == 4 && rosterRun.activeParty.contains(where: { $0.name == "Wyll" }))
let karlachIndex = rosterRun.roster!.firstIndex(where: { $0.name == "Karlach" })!
rosterRun.roster![karlachIndex].status = .dead
rosterRun.storyOutcomes = ["karlach_killed_for_robe", "infernal_robe_obtained"]
rosterRun.syncActivePartyProjection()
precondition(!rosterRun.activeParty.contains(where: { $0.name == "Karlach" }))
precondition(rosterRun.storyOutcomes?.contains("infernal_robe_obtained") == true)
rosterRun.setStoryOutcome("infernal_robe_obtained", confirmed: false)
precondition(rosterRun.storyOutcomes?.contains("infernal_robe_obtained") == false)
rosterRun.setStoryOutcome("infernal_robe_obtained", confirmed: false)
precondition(rosterRun.storyOutcomes?.contains("infernal_robe_obtained") == false)
rosterRun.setStoryOutcome("infernal_robe_obtained", confirmed: true)
rosterRun.setStoryOutcome("infernal_robe_obtained", confirmed: true)
precondition(rosterRun.storyOutcomes?.contains("infernal_robe_obtained") == true)

var rosterTransitionRun = legacyRun
let transitionAstarion = rosterTransitionRun.roster!.first(where: { $0.name == "Astarion" })!
precondition(rosterTransitionRun.applyRosterStatus(.camp, memberID: transitionAstarion.id))
let transitionWyll = rosterTransitionRun.roster!.first(where: { $0.name == "Wyll" })!
precondition(rosterTransitionRun.applyRosterStatus(.active, memberID: transitionWyll.id))
precondition(rosterTransitionRun.activeParty.count == 4)
precondition(rosterTransitionRun.applyRosterStatus(.dead, memberID: transitionWyll.id))
precondition(!rosterTransitionRun.applyRosterStatus(.active, memberID: transitionWyll.id), "Dead companions cannot be activated")
precondition(rosterTransitionRun.activeParty.count == 3)

var equipmentRun = legacyRun
let equipmentLaezelID = equipmentRun.roster!.first(where: { $0.name == "Lae'zel" })!.id
precondition(equipmentRun.toggleEquipment(itemKey: "ring-of-protection", for: "tav"))
precondition(equipmentRun.equipmentOwnerID(for: "ring-of-protection") == "tav")
precondition(equipmentRun.toggleEquipment(itemKey: "ring-of-protection", for: equipmentLaezelID))
precondition(equipmentRun.equipmentOwnerID(for: "ring-of-protection") == equipmentLaezelID, "Unique equipment transfers to one owner")
precondition(equipmentRun.equipmentOwnershipKnown == true)
precondition(equipmentRun.toggleEquipment(itemKey: "ring-of-protection", for: equipmentLaezelID))
precondition(equipmentRun.equipmentOwnerID(for: "ring-of-protection") == nil)

let safetyCheckpoint = RouteCheckpoint(
    id: "major", routeOrder: 1, name: "Major fight", area: "Area", region: "Wilderness", x: 1, y: 2,
    minimumLevel: 4, importance: "major", danger: "high", enemies: "Boss", advice: "Prepare",
    legendaryAction: "Retaliates", failureConditions: ["Wipe"], preparation: ["Silence"],
    completionChecks: ["NPC survived"], irreversibleWarnings: ["Timed"], prerequisites: [], notes: [], honorDecisions: [],
    source: GuideSource(sheet: "Act 1", row: 1, url: "https://example.com")
)
let safetyReasons = RunSafety.completionConfirmationReasons(checkpoint: safetyCheckpoint, progress: CheckpointProgress(), readinessStatus: "blocked")
precondition(safetyReasons.count == 3)
let skippedDispositions: [String: CheckpointDisposition] = ["major": .skipped]
precondition(RunSafety.actTwoBlockers(route: [safetyCheckpoint], dispositions: skippedDispositions).first?.hasPrefix("Skipped") == true)
let secondCheckpoint = RouteCheckpoint(
    id: "next", routeOrder: 2, name: "Next fight", area: "Next area", region: "Wilderness", x: 3, y: 4,
    minimumLevel: 2, importance: "minor", danger: "medium", enemies: "Enemies", advice: "Advice",
    legendaryAction: nil, failureConditions: ["Wipe"], preparation: ["Prepare"], completionChecks: ["Done"],
    irreversibleWarnings: [], prerequisites: [], notes: [], honorDecisions: [], source: GuideSource(sheet: "Act 1", row: 2, url: "https://example.com")
)
let completedFirst: [String: CheckpointDisposition] = ["major": .completed]
precondition(RunSafety.nextCheckpoint(route: [safetyCheckpoint, secondCheckpoint], dispositions: completedFirst, selectedId: nil, partyLevel: 1)?.id == "next")
let underdarkCheckpoint = RouteCheckpoint(
    id: "underdark", routeOrder: 3, name: "Underdark fight", area: "Cavern", region: "Underdark", x: 5, y: 6,
    minimumLevel: 5, importance: "major", danger: "high", enemies: "Enemies", advice: "Advice",
    legendaryAction: nil, failureConditions: ["Wipe"], preparation: ["Prepare"], completionChecks: ["Done"],
    irreversibleWarnings: [], prerequisites: [], notes: [], honorDecisions: [], source: GuideSource(sheet: "Act 1", row: 3, url: "https://example.com")
)
precondition(
    RunSafety.nextCheckpoint(
        route: [secondCheckpoint, safetyCheckpoint, underdarkCheckpoint], dispositions: [:], selectedId: nil, partyLevel: 5
    )?.id == "major"
)
let activityPlan = RunSafety.activityPlan(
    route: [secondCheckpoint, safetyCheckpoint, underdarkCheckpoint], dispositions: [:], selectedId: nil, partyLevel: 3
)
precondition(activityPlan?.activityLabel == "SAFE XP")
precondition(activityPlan?.safeXP.map(\.id) == ["next"])
precondition(activityPlan?.coreChallenge?.id == "major")

func walkthroughStep(
    id: String, order: Int, kind: String, minimumLevel: Int = 2,
    prerequisites: [String] = [], dependencies: [WalkthroughDependency]? = nil, checkpointId: String? = nil
) -> WalkthroughStep {
    let typedDependencies = dependencies ?? prerequisites.map {
        WalkthroughDependency(stepId: $0, kind: "resolution_required", reason: "Resolve \($0)", requiredOutcome: nil)
    }
    return WalkthroughStep(
        id: id, order: order, phase: "Surface", phaseOrder: 1, title: id, kind: kind,
        importance: "required", region: "Wilderness", area: "Area", minimumLevel: minimumLevel,
        summary: "Do it", avoid: "Do not fail", why: "Safety", rewards: [], completionChecks: ["Confirmed"],
        prerequisites: prerequisites, dependencies: typedDependencies, checkpointId: checkpointId, markerId: checkpointId,
        decision: nil, incident: nil, riskReward: nil, authority: "assistant_suggestion",
        sourceLabel: "Test", sourceUrl: "https://example.com"
    )
}
let walkthrough = [
    walkthroughStep(id: "explore", order: 1, kind: "exploration"),
    walkthroughStep(id: "talk", order: 2, kind: "dialogue", prerequisites: ["explore"]),
    walkthroughStep(id: "fight", order: 3, kind: "major_fight", minimumLevel: 4, prerequisites: ["talk"], checkpointId: "major"),
]

// Encounter classification: fight vs talk vs "starts as talk, can turn hostile".
let sampleDecision = WalkthroughDecision(
    prompt: "Choose", recommended: DecisionOption(label: "A", benefits: [], costs: []),
    alternatives: [], reversible: false, authority: "guide_fact"
)
let sampleIncident = IncidentProtocol(
    trigger: "Hostility", safeActions: [], never: "Panic", escape: "Run", honorDelta: "",
    postFight: [], authority: "guide_fact", sourceUrl: ""
)
func encounterStep(_ kind: String, decision: WalkthroughDecision? = nil, incident: IncidentProtocol? = nil) -> WalkthroughStep {
    WalkthroughStep(
        id: "enc-\(kind)", order: 9, phase: "Surface", phaseOrder: 1, title: "t", kind: kind,
        importance: "required", region: "Wilderness", area: "Area", minimumLevel: 2,
        summary: "s", avoid: "", why: "", rewards: [], completionChecks: [], prerequisites: [], dependencies: [],
        checkpointId: nil, markerId: nil, decision: decision, incident: incident,
        riskReward: nil, authority: "guide_fact", sourceLabel: "T", sourceUrl: ""
    )
}
precondition(StepEncounter.classify(encounterStep("major_fight")) == .fight)
precondition(StepEncounter.classify(encounterStep("mini_fight")) == .fight)
precondition(StepEncounter.classify(encounterStep("dialogue")) == .talk)
precondition(StepEncounter.classify(encounterStep("dialogue", incident: sampleIncident)) == .fightAndTalk)
precondition(StepEncounter.classify(encounterStep("major_fight", decision: sampleDecision)) == .fightAndTalk)
precondition(StepEncounter.classify(encounterStep("exploration", decision: sampleDecision)) == .explore)
precondition(StepEncounter.classify(encounterStep("exploration")) == .explore)
precondition(StepEncounter.classify(encounterStep("pickup")) == .pickup)
precondition(StepEncounter.classify(encounterStep("pickup", decision: sampleDecision)) == .pickup)
precondition(StepEncounter.fightAndTalk.hint != nil && StepEncounter.fight.hint == nil)
precondition(RunSafety.nextWalkthroughStep(
    walkthrough: walkthrough, walkthroughProgress: [:], selectedCheckpointId: nil, partyLevel: 3
)?.id == "explore")
precondition(RunSafety.nextDialogueStep(
    walkthrough: walkthrough, walkthroughProgress: [:], selectedCheckpointId: nil, partyLevel: 3
)?.id == "talk")
let explored: [String: CheckpointDisposition] = ["explore": .completed]
precondition(RunSafety.nextWalkthroughStep(
    walkthrough: walkthrough, walkthroughProgress: explored, selectedCheckpointId: nil, partyLevel: 3
)?.id == "talk")
let talked: [String: CheckpointDisposition] = ["explore": .completed, "talk": .completed]
precondition(RunSafety.nextWalkthroughStep(
    walkthrough: walkthrough, walkthroughProgress: talked, selectedCheckpointId: nil, partyLevel: 3
)?.id == "fight")
let hardEvidence = walkthroughStep(
    id: "evidence", order: 4, kind: "mini_fight",
    prerequisites: ["fight"], checkpointId: "evidence"
)
let exposeKagha = walkthroughStep(
    id: "expose", order: 5, kind: "dialogue", prerequisites: ["evidence"],
    dependencies: [WalkthroughDependency(
        stepId: "evidence", kind: "completion_required",
        reason: "Collect the Shadow Druid letter.", requiredOutcome: nil
    )]
)
let kaghaRoute = walkthrough + [hardEvidence, exposeKagha]
let skippedEvidence: [String: CheckpointDisposition] = [
    "explore": .completed, "talk": .completed, "fight": .completed, "evidence": .skipped,
]
precondition(RunSafety.nextWalkthroughStep(
    walkthrough: kaghaRoute, walkthroughProgress: skippedEvidence,
    selectedCheckpointId: "major", partyLevel: 4
) == nil)
precondition(RunSafety.dependencyBlockers(
    for: exposeKagha, walkthrough: kaghaRoute, walkthroughProgress: skippedEvidence
).first?.contains("Revisit evidence") == true)
let completedEvidence = skippedEvidence.merging(["evidence": .completed]) { _, new in new }
precondition(RunSafety.nextWalkthroughStep(
    walkthrough: kaghaRoute, walkthroughProgress: completedEvidence,
    selectedCheckpointId: "major", partyLevel: 4
)?.id == "expose")
// Single ledger: only walkthroughProgress determines a step's disposition.
precondition(RunSafety.walkthroughDisposition(walkthrough[2], walkthroughProgress: talked) == .pending)
precondition(RunSafety.walkthroughDisposition(
    walkthrough[2], walkthroughProgress: ["fight": .completed]
) == .completed)

// Migration: a legacy run whose fight completion lives only in run.progress
// reads completed after migrateLegacyFightDispositions — and stays stable
// (idempotent, never overwrites an explicit ledger entry).
var legacyFightRun = HonorRun()
legacyFightRun.progress["major"] = CheckpointProgress(
    disposition: .completed, checkedPreparation: [], checkedCompletion: [], skipNote: "", updatedAt: .now
)
precondition(RunSafety.walkthroughDisposition(walkthrough[2], walkthroughProgress: legacyFightRun.walkthroughProgress ?? [:]) == .pending)
legacyFightRun.migrateLegacyFightDispositions(walkthrough: walkthrough)
precondition(RunSafety.walkthroughDisposition(walkthrough[2], walkthroughProgress: legacyFightRun.walkthroughProgress ?? [:]) == .completed)
legacyFightRun.walkthroughProgress?["fight"] = .skipped
legacyFightRun.migrateLegacyFightDispositions(walkthrough: walkthrough)
precondition(legacyFightRun.walkthroughProgress == ["fight": .skipped])

let progress = CheckpointProgress(
    disposition: .completed,
    checkedPreparation: ["Elixirs"],
    checkedCompletion: ["Looted"],
    skipNote: "",
    updatedAt: Date(timeIntervalSince1970: 42)
)
let data = try JSONEncoder().encode(progress)
let decoded = try JSONDecoder().decode(CheckpointProgress.self, from: data)
precondition(decoded == progress)

let map = MapOpenDetector.score(recognizedText: ["WAYPOINTS", "Journal", "Place Marker"])
precondition(map.isOpen)
precondition(map.confidence >= 0.9)
let game = MapOpenDetector.score(recognizedText: ["End Turn", "Actions"])
precondition(!game.isOpen)
precondition(BG3Detector.matchesIdentity(applicationName: "Baldur's Gate 3", bundleIdentifier: "com.larian.bg3"))
precondition(!BG3Detector.matchesIdentity(applicationName: "BG3 Honor Mode Assistant", bundleIdentifier: "com.local.BG3HonorAssistant"))
precondition(BG3Detector.largestFrameIndex([
    CGRect(x: 0, y: 0, width: 2560, height: 44),
    CGRect(x: 0, y: 0, width: 2560, height: 1440),
]) == 1)
let captureSize = BG3Detector.capturePixelSize(for: CGRect(x: 0, y: 0, width: 2560, height: 1440))
precondition(captureSize.width == 2560 && captureSize.height == 1440)

let temporaryDirectory = FileManager.default.temporaryDirectory.appending(path: "bg3-run-store-\(UUID().uuidString)")
let store = RunStore(baseDirectory: temporaryDirectory)
let isolatedDirectory = FileManager.default.temporaryDirectory.appending(path: "bg3-isolated-run-store-\(UUID().uuidString)")
setenv("BG3_ASSISTANT_STATE_DIR", isolatedDirectory.path, 1)
precondition(RunStore().databaseURL.path == isolatedDirectory.appending(path: "state.sqlite3").path)
unsetenv("BG3_ASSISTANT_STATE_DIR")
var persistedRun = HonorRun()
persistedRun.migrateLegacyPartySlots()
persistedRun.guideVersion = "test-guide"
persistedRun.walkthroughProgress = [
    "walk-nautiloid-zhalk": .completed,
    "walk-grove-entrance": .completed,
    "walk-dialogue": .skipped,
]
for index in persistedRun.roster!.indices where persistedRun.roster![index].rosterStatus == .active {
    persistedRun.roster![index].level = 5
}
persistedRun.syncActivePartyProjection()
try store.save(persistedRun)
let loadedRun = RunStore(baseDirectory: temporaryDirectory).load()
precondition(loadedRun.id == persistedRun.id)
precondition(loadedRun.party.allSatisfy { $0.level == 5 })
precondition(loadedRun.walkthroughProgress?.count == 3)
persistedRun.walkthroughOutcomes = ["walk-rolan": "Rolan punched Zevlor and his group left"]
persistedRun.focusedWalkthroughStepId = "walk-dialogue"
_ = persistedRun.toggleEquipment(itemKey: "sparkle-hands", for: "tav")
try store.save(persistedRun)
let restartedStore = RunStore(baseDirectory: temporaryDirectory)
precondition(restartedStore.load().walkthroughOutcomes?["walk-rolan"] == "Rolan punched Zevlor and his group left")
precondition(restartedStore.load().equipmentOwnerID(for: "sparkle-hands") == "tav")
precondition(restartedStore.load().focusedWalkthroughStepId == "walk-dialogue")
precondition(restartedStore.load().roster?.count == 7)
precondition(loadedRun.guideVersion == "test-guide")
precondition(loadedRun.walkthroughProgress?["walk-dialogue"] == .skipped)
precondition(loadedRun.selectedAct == 1)
let settings = AssistantSettings(telemetryEnabled: true, visualMemoryEnabled: true, mapOverlayCaptureEnabled: false, overlayDensity: OverlayDensity.minimal.rawValue)
try store.saveSettings(settings)
precondition(RunStore(baseDirectory: temporaryDirectory).loadSettings() == settings)
precondition(FileManager.default.fileExists(atPath: store.databaseURL.path))

// A pre-SQLite run.json is imported once and remains recoverable in SQLite.
let legacyStoreDirectory = FileManager.default.temporaryDirectory.appending(path: "bg3-legacy-run-store-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: legacyStoreDirectory, withIntermediateDirectories: true)
let legacyStore = RunStore(baseDirectory: legacyStoreDirectory)
try JSONEncoder().encode(persistedRun).write(to: legacyStore.runURL)
precondition(legacyStore.load().walkthroughProgress?.count == 3)
precondition(FileManager.default.fileExists(atPath: legacyStore.databaseURL.path))
// Runs saved before the ORB-alignment era carry manual-calibration keys; they
// must still decode after the calibration fields were deleted.
let legacyJSON = try JSONSerialization.data(withJSONObject: [
    "id": "legacy", "guideVersion": "old", "party": [], "progress": [:],
    "mapRegion": "Wilderness", "mapZoom": 1.4, "mapPanX": 12, "mapPanY": -3,
    "mapCalibrations": ["Wilderness": ["zoom": 1.2, "panX": 4, "panY": -3]],
])
let legacyDecoded = try JSONDecoder().decode(HonorRun.self, from: legacyJSON)
precondition(legacyDecoded.id == "legacy" && legacyDecoded.mapRegion == "Wilderness")
var migratedLegacy = legacyDecoded
migratedLegacy.migrateLegacyPartySlots()
precondition(migratedLegacy.selectedAct == 1)
try FileManager.default.removeItem(at: temporaryDirectory)
try FileManager.default.removeItem(at: legacyStoreDirectory)

// Overlay metrics: responsive sizing + HUD-aware default placement across
// representative displays (13"/14"/16" MacBooks, 27" QHD, XL 6K-ish).
for (name, frame) in [
    ("13-inch", CGRect(x: 0, y: 0, width: 1470, height: 956)),
    ("14-inch", CGRect(x: 0, y: 0, width: 1512, height: 982)),
    ("16-inch", CGRect(x: 0, y: 0, width: 1728, height: 1117)),
    ("27-inch", CGRect(x: 0, y: 0, width: 2560, height: 1440)),
    ("XL", CGRect(x: 100, y: 50, width: 3008, height: 1692)),
] {
    let collapsed = OverlayMetrics.collapsedSize(for: frame)
    let minimal = OverlayMetrics.collapsedSize(for: frame, density: .minimal)
    let reference = OverlayMetrics.collapsedSize(for: frame, density: .reference)
    let expanded = OverlayMetrics.expandedSize(for: frame)
    let partyExpanded = OverlayMetrics.expandedSize(for: frame, tab: .party)
    precondition(collapsed.width > collapsed.height * 2, "\(name): collapsed tooltip must stay horizontal")
    precondition(collapsed.width >= 288 && collapsed.width <= 336, "\(name): collapsed width out of range")
    precondition(collapsed.height >= 142 && collapsed.height <= 158, "\(name): collapsed height out of range")
    precondition(minimal.width < collapsed.width && minimal.height < collapsed.height, "\(name): minimal density must materially reduce obstruction")
    precondition(reference.height > collapsed.height, "\(name): reference density must expose more context")
    precondition(expanded.width >= 420 && expanded.width <= 560, "\(name): expanded width out of range (\(expanded.width))")
    precondition(expanded.height <= frame.height * 0.70, "\(name): expanded overlay too tall for the window")
    precondition(partyExpanded.height > expanded.height, "\(name): party setup should receive a taller content envelope")
    precondition(partyExpanded.height <= frame.height * 0.70, "\(name): party overlay too tall for the window")

    for size in [collapsed, expanded, partyExpanded] {
        let origin = OverlayMetrics.defaultOrigin(panelSize: size, reference: frame)
        precondition(origin.x + size.width <= frame.maxX, "\(name): overlay must stay inside the game window")
        precondition(origin.x >= frame.midX, "\(name): overlay should hug the right side")
        precondition(origin.y >= frame.minY + frame.height * OverlayMetrics.hotbarBand - 0.5, "\(name): overlay must sit above the hotbar band")
        precondition(origin.y + size.height <= frame.maxY, "\(name): overlay must not overflow the top")
        precondition(abs(origin.y + size.height / 2 - frame.midY) < 1, "\(name): overlay should default to middle-right")
    }
    let clamped = OverlayMetrics.clampedOrigin(CGPoint(x: -5000, y: 5000), panelSize: collapsed, reference: frame)
    precondition(frame.contains(CGRect(origin: clamped, size: CGSize(width: 1, height: 1))), "\(name): clamp must land inside the window")
    let centeredAnchor = CGPoint(x: 1, y: 0.5)
    for size in [collapsed, expanded] {
        let anchored = OverlayMetrics.origin(fromNormalizedAnchor: centeredAnchor, panelSize: size, reference: frame)
        precondition(abs(anchored.x + size.width - frame.maxX) < 1, "\(name): normalized anchor must preserve right edge")
        precondition(abs(anchored.y + size.height / 2 - frame.midY) < 1, "\(name): normalized anchor must preserve vertical center")
    }
    let customAnchor = CGPoint(x: 0.23, y: 0.77)
    for size in [collapsed, expanded, partyExpanded] {
        let customOrigin = OverlayMetrics.origin(fromNormalizedAnchor: customAnchor, panelSize: size, reference: frame)
        let roundTrip = OverlayMetrics.normalizedAnchor(for: customOrigin, panelSize: size, reference: frame)
        precondition(abs(roundTrip.x - customAnchor.x) < 0.0001, "\(name): custom horizontal position must survive resizing")
        precondition(abs(roundTrip.y - customAnchor.y) < 0.0001, "\(name): custom vertical position must survive resizing")
    }
}

print("BG3HonorAssistant model checks passed")
