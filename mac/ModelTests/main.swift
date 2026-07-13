import Foundation

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

let run = HonorRun()
precondition(run.party.count == 4)
precondition(run.party.map(\.level) == [1, 1, 1, 1])
precondition(run.party.map(\.name) == ["Tav", "Shadowheart", "Lae'zel", "Astarion"])
precondition(run.progress.isEmpty)
precondition(run.guideVersion.isEmpty)
precondition(run.selectedAct == 1)
precondition(run.party.map(\.className) == [nil, "Cleric", "Fighter", "Rogue"])
var legacyRun = run
legacyRun.party[1].name = "Companion 1"
legacyRun.party[1].className = nil
legacyRun.migrateLegacyPartySlots()
precondition(legacyRun.party[1].name == "Shadowheart" && legacyRun.party[1].className == "Cleric")

let safetyCheckpoint = RouteCheckpoint(
    id: "major", routeOrder: 1, name: "Major fight", area: "Area", region: "Wilderness", x: 1, y: 2,
    minimumLevel: 4, importance: "major", danger: "high", enemies: "Boss", advice: "Prepare",
    legendaryAction: "Retaliates", failureConditions: ["Wipe"], preparation: ["Silence"],
    completionChecks: ["NPC survived"], irreversibleWarnings: ["Timed"], prerequisites: [], notes: [], honorDecisions: [],
    source: GuideSource(sheet: "Act 1", row: 1, url: "https://example.com")
)
let safetyReasons = RunSafety.completionConfirmationReasons(checkpoint: safetyCheckpoint, progress: CheckpointProgress(), readinessStatus: "blocked")
precondition(safetyReasons.count == 3)
let skippedProgress = ["major": CheckpointProgress(disposition: .skipped, checkedPreparation: [], checkedCompletion: [], skipNote: "intentional", updatedAt: .now)]
precondition(RunSafety.actTwoBlockers(route: [safetyCheckpoint], progress: skippedProgress).first?.hasPrefix("Skipped") == true)
let secondCheckpoint = RouteCheckpoint(
    id: "next", routeOrder: 2, name: "Next fight", area: "Next area", region: "Wilderness", x: 3, y: 4,
    minimumLevel: 2, importance: "minor", danger: "medium", enemies: "Enemies", advice: "Advice",
    legendaryAction: nil, failureConditions: ["Wipe"], preparation: ["Prepare"], completionChecks: ["Done"],
    irreversibleWarnings: [], prerequisites: [], notes: [], honorDecisions: [], source: GuideSource(sheet: "Act 1", row: 2, url: "https://example.com")
)
let completedFirst = ["major": CheckpointProgress(disposition: .completed, checkedPreparation: [], checkedCompletion: [], skipNote: "", updatedAt: .now)]
precondition(RunSafety.nextCheckpoint(route: [safetyCheckpoint, secondCheckpoint], progress: completedFirst, selectedId: nil, partyLevel: 1)?.id == "next")
let underdarkCheckpoint = RouteCheckpoint(
    id: "underdark", routeOrder: 3, name: "Underdark fight", area: "Cavern", region: "Underdark", x: 5, y: 6,
    minimumLevel: 5, importance: "major", danger: "high", enemies: "Enemies", advice: "Advice",
    legendaryAction: nil, failureConditions: ["Wipe"], preparation: ["Prepare"], completionChecks: ["Done"],
    irreversibleWarnings: [], prerequisites: [], notes: [], honorDecisions: [], source: GuideSource(sheet: "Act 1", row: 3, url: "https://example.com")
)
precondition(
    RunSafety.nextCheckpoint(
        route: [secondCheckpoint, safetyCheckpoint, underdarkCheckpoint], progress: [:], selectedId: nil, partyLevel: 5
    )?.id == "major"
)
let activityPlan = RunSafety.activityPlan(
    route: [secondCheckpoint, safetyCheckpoint, underdarkCheckpoint], progress: [:], selectedId: nil, partyLevel: 3
)
precondition(activityPlan?.activityLabel == "SAFE XP")
precondition(activityPlan?.safeXP.map(\.id) == ["next"])
precondition(activityPlan?.coreChallenge?.id == "major")

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
var persistedRun = HonorRun()
persistedRun.guideVersion = "test-guide"
try store.save(persistedRun)
let loadedRun = store.load()
precondition(loadedRun.id == persistedRun.id)
precondition(loadedRun.guideVersion == "test-guide")
precondition(loadedRun.selectedAct == 1)
precondition(FileManager.default.fileExists(atPath: temporaryDirectory.appending(path: "runs/\(persistedRun.id).json").path))
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
    let expanded = OverlayMetrics.expandedSize(for: frame)
    let partyExpanded = OverlayMetrics.expandedSize(for: frame, tab: .party)
    precondition(collapsed.width > collapsed.height * 2, "\(name): collapsed tooltip must stay horizontal")
    precondition(collapsed.width >= 288 && collapsed.width <= 336, "\(name): collapsed width out of range")
    precondition(collapsed.height >= 142 && collapsed.height <= 158, "\(name): collapsed height out of range")
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
