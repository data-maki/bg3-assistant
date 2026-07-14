from typing import Literal

from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel


class CamelModel(BaseModel):
    """Base for models serialized to the web map as camelCase.

    Fields keep snake_case names in Python (and on the Mac payload, which is
    dumped with by_alias=False); dumping with by_alias=True yields the
    camelCase contract the web frontend consumes. One model, one vocabulary.
    """

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


class GuideSource(BaseModel):
    sheet: str
    row: int
    url: str


class HonorDecision(BaseModel):
    text: str
    kind: str = "guide_fact"


class RouteCheckpoint(CamelModel):
    id: str
    route_order: int
    name: str
    area: str
    region: str
    x: int
    y: int
    minimum_level: int
    importance: str
    danger: str
    enemies: str
    advice: str
    legendary_action: str | None = None
    failure_conditions: list[str] = Field(default_factory=list)
    preparation: list[str] = Field(default_factory=list)
    completion_checks: list[str] = Field(default_factory=list)
    irreversible_warnings: list[str] = Field(default_factory=list)
    prerequisites: list[str] = Field(default_factory=list)
    notes: list[str] = Field(default_factory=list)
    honor_decisions: list[HonorDecision] = Field(default_factory=list)
    source: GuideSource


class BuildLevel(CamelModel):
    level: int
    take: str
    subclass_choice: str
    choices: str
    tactics: str
    confidence: str


class BuildGear(CamelModel):
    item: str
    slot: str
    priority: str
    act: int
    region: str
    acquisition: str
    why: str
    source: str
    build_ids: list[str] = Field(default_factory=list)
    minimum_level: int = 1
    maximum_level: int | None = None
    requirement: str = ""
    map_objective: bool = True
    alternative: str = ""
    effect: str = ""  # what the item does (bg3.wiki lead)
    acquire: str = ""  # wiki "where to find" specifics
    wiki: str = ""  # canonical bg3.wiki page URL
    icon: str = ""  # servable URL under /map-assets/icons/


class BuildSummary(CamelModel):
    id: str
    name: str
    honor_status: str
    role: str
    final_split: str
    class_progression: str
    starting_abilities: str
    play_pattern: str
    caveat: str
    source: str
    levels: list[BuildLevel] = Field(default_factory=list)
    gear: list[BuildGear] = Field(default_factory=list)


class PartyMember(BaseModel):
    id: str
    name: str
    level: int = Field(ge=1, le=12)
    build_id: str | None = None
    prepared_tags: list[str] = Field(default_factory=list)
    class_name: str | None = None
    status: Literal["active", "camp", "unrecruited", "unavailable", "dead", "departed"] | None = None
    role_override: str | None = None
    is_custom: bool | None = None


class ReadinessRequest(BaseModel):
    checkpoint_id: str
    party: list[PartyMember] = Field(default_factory=list)
    completed_checkpoint_ids: list[str] = Field(default_factory=list)
    checked_preparation: list[str] = Field(default_factory=list)


class ReadinessResponse(BaseModel):
    status: str
    party_level: int
    minimum_level: int
    blockers: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    next_actions: list[str] = Field(default_factory=list)


class ChatContextSnapshot(BaseModel):
    """Player-owned run state for chat; guide prose is deliberately absent."""

    version: int = 1
    scope: Literal["current", "route", "party", "loadout"] = "current"
    guide_version: str = ""
    selected_act: int = Field(default=1, ge=1, le=3)
    map_region: str = "unknown"
    route_phase: str = "unknown"
    detection_timestamp: float | None = None
    detection_confidence: float | None = Field(default=None, ge=0.0, le=1.0)
    recommended_step_id: str | None = None
    focused_step_id: str | None = None
    walkthrough_statuses: dict[str, str] = Field(default_factory=dict)
    walkthrough_outcomes: dict[str, str] = Field(default_factory=dict)
    roster: list[PartyMember] = Field(default_factory=list)
    story_outcomes: list[str] = Field(default_factory=list)
    equipped_by_member: dict[str, list[str]] = Field(default_factory=dict)
    equipment_ownership_known: bool = False
    visual_memory_summary: str | None = None
    visual_memory_timestamp: float | None = None
    visual_memory_completion_step_ids: list[str] = Field(default_factory=list)


class ChatRequest(BaseModel):
    message: str
    checkpoint_id: str
    party: list[PartyMember] = Field(default_factory=list)
    completed_checkpoint_ids: list[str] = Field(default_factory=list)
    walkthrough_step_id: str | None = None
    screenshot_context: str | None = None
    image_base64: str | None = None  # optional BG3 screenshot for the vision model
    screenshot_timestamp: float | None = None
    context: ChatContextSnapshot | None = None


class ChatResponse(BaseModel):
    answer: str
    guide_facts: list[str] = Field(default_factory=list)
    assistant_suggestions: list[str] = Field(default_factory=list)
    unknowns: list[str] = Field(default_factory=list)


class ScreenDetected(BaseModel):
    game: str = "Baldur's Gate 3 or unknown"
    likely_area: str = "unknown"
    screen_kind: str = "unknown"
    visible_enemies: list[str] = Field(default_factory=list)
    visible_party: list[str] = Field(default_factory=list)
    visible_levels: list[int] = Field(default_factory=list)
    dialogue_or_warning: str = "unknown"
    evidence: list[str] = Field(default_factory=list)


class ScreenCandidate(BaseModel):
    checkpoint_id: str
    confidence: float = Field(ge=0.0, le=1.0)
    reason: str


class VisualCompletionCandidate(BaseModel):
    step_id: str
    confidence: float = Field(ge=0.0, le=1.0)
    reason: str


class VisionResult(BaseModel):
    screen_summary: str
    detected: ScreenDetected = Field(default_factory=ScreenDetected)
    candidates: list[ScreenCandidate] = Field(default_factory=list)
    completion_candidates: list[VisualCompletionCandidate] = Field(default_factory=list)
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)


class AnalysisResponse(BaseModel):
    ok: bool
    analysis_id: str
    screen_summary: str = ""
    detected: ScreenDetected = Field(default_factory=ScreenDetected)
    candidates: list[ScreenCandidate] = Field(default_factory=list)
    completion_candidates: list[VisualCompletionCandidate] = Field(default_factory=list)
    confidence: float = 0.0
    latency_ms: int = 0
    error: str | None = None


class HealthResponse(BaseModel):
    ok: bool
    service: str
    pid: int
    parent_pid: int
    packaged: bool
    walkthrough_count: int


class TelemetryEvent(BaseModel):
    sequence: int = Field(ge=1)
    kind: str = Field(min_length=1, max_length=64)
    emitted_at: float | None = None
    actor: str | None = Field(default=None, max_length=256)
    target: str | None = Field(default=None, max_length=256)
    combat_id: str | None = Field(default=None, max_length=256)
    payload: dict[str, str] = Field(default_factory=dict)


class TelemetrySnapshot(BaseModel):
    schema_version: int
    producer_id: str
    producer_version: str
    session_id: str
    written_at: float | None = None
    sequence: int = Field(ge=0)
    events: list[TelemetryEvent] = Field(default_factory=list, max_length=128)


class TelemetryStatus(BaseModel):
    ok: bool = True
    available: bool = False
    active: bool = False
    stale: bool = False
    mode: str = "vanilla"
    message: str = "Vanilla mode • no telemetry mod required"
    producer_version: str | None = None
    session_id: str | None = None
    last_sequence: int = 0
    age_seconds: float | None = None
    events: list[TelemetryEvent] = Field(default_factory=list)


class PlayerPosition(BaseModel):
    lat: float
    lng: float
    source: str = "manual"  # manual | map-align | vision
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)
    zoom: float | None = None
    updated_at: float = 0.0  # unix timestamp


class PositionUpdateRequest(BaseModel):
    lat: float
    lng: float
    source: str = "manual"


class PositionResponse(BaseModel):
    ok: bool
    position: PlayerPosition | None = None


class MapPartyMember(CamelModel):
    id: str
    name: str
    level: int = Field(ge=1, le=12)
    build_id: str | None = None
    prepared_tags: list[str] = Field(default_factory=list)
    class_name: str | None = None
    status: Literal["active", "camp", "unrecruited", "unavailable", "dead", "departed"] = "active"
    role_override: str | None = None
    is_custom: bool = False


class RunState(CamelModel):
    """Shared web-map run progress and party-owned equipment state."""

    equipped_by_member: dict[str, list[str]] = Field(default_factory=dict)
    builds: list[str] = Field(default_factory=list)  # active build ids
    done: list[str] = Field(default_factory=list)  # completed fight marker ids
    walkthrough_statuses: dict[str, str] = Field(default_factory=dict)
    # step id → the decision option that actually happened in this run
    walkthrough_outcomes: dict[str, str] = Field(default_factory=dict)
    focused_walkthrough_step_id: str | None = None
    party: list[MapPartyMember] = Field(default_factory=list)
    roster: list[MapPartyMember] = Field(default_factory=list)
    story_outcomes: list[str] = Field(default_factory=list)
    include_camp_plans: bool = False


class RunStateResponse(RunState):
    ok: bool = True


class Marker(CamelModel):
    """One pin on the companion web map. type is "fight" or "item"; the
    optional groups below belong to one type each and are omitted (None/[])
    on the other."""

    id: str
    name: str
    type: str
    area: str
    region: str
    lat: float
    lng: float
    precision: str  # exact | area | unanchored
    advice: str
    source: str
    importance: str
    build_ids: list[str] = Field(default_factory=list)
    minimum_level: int | None = None
    # fight intel (joined from the reviewed route sheet)
    danger: str | None = None
    route_order: int | None = None
    enemies: str | None = None
    legendary_action: str | None = None
    failure_conditions: list[str] = Field(default_factory=list)
    preparation: list[str] = Field(default_factory=list)
    irreversible_warnings: list[str] = Field(default_factory=list)
    # item fields
    item_key: str | None = None
    icon: str | None = None  # servable URL under /map-assets/
    slot: str | None = None
    priority: str | None = None
    why: str | None = None
    effect: str | None = None  # what the item does (bg3.wiki lead)
    acquire_detail: str | None = None  # wiki "where to find" specifics
    wiki: str | None = None  # canonical bg3.wiki page URL


class TimedEvent(CamelModel):
    id: str
    name: str
    kind: str  # point_of_no_return | long_rest | immediate
    trigger: str
    deadline: str
    consequence: str
    severity: str  # critical | high | moderate | low
    source: str


class DecisionOption(CamelModel):
    label: str
    benefits: list[str] = Field(default_factory=list)
    costs: list[str] = Field(default_factory=list)


class WalkthroughDecision(CamelModel):
    prompt: str
    recommended: DecisionOption
    alternatives: list[DecisionOption] = Field(default_factory=list)
    reversible: bool = False
    authority: str = "guide_fact"


class IncidentProtocol(CamelModel):
    trigger: str
    safe_actions: list[str] = Field(default_factory=list)
    never: str
    escape: str
    honor_delta: str = ""
    post_fight: list[str] = Field(default_factory=list)
    authority: str = "assistant_suggestion"
    source_url: str = ""


class RiskReward(CamelModel):
    reward: str
    risk: str
    skip_cost: str
    return_by: str


class WalkthroughDependency(CamelModel):
    step_id: str
    kind: Literal["completion_required", "resolution_required", "outcome_required", "warning_only"] = "resolution_required"
    reason: str
    required_outcome: str | None = None


class WalkthroughStep(CamelModel):
    id: str
    order: int
    phase: str
    phase_order: int
    title: str
    kind: str  # exploration | dialogue | pickup | mini_fight | major_fight | gate
    importance: str  # required | recommended | optional
    region: str
    area: str
    minimum_level: int = Field(ge=1, le=12)
    summary: str
    avoid: str = ""
    why: str = ""
    rewards: list[str] = Field(default_factory=list)
    completion_checks: list[str] = Field(default_factory=list)
    prerequisites: list[str] = Field(default_factory=list)
    dependencies: list[WalkthroughDependency] = Field(default_factory=list)
    checkpoint_id: str | None = None
    marker_id: str | None = None
    decision: WalkthroughDecision | None = None
    incident: IncidentProtocol | None = None
    risk_reward: RiskReward | None = None
    authority: str = "assistant_suggestion"
    source_label: str
    source_url: str


class MapTilesStart(CamelModel):
    lat: float
    lng: float
    zoom: int


class MapTiles(CamelModel):
    tile_url: str
    min_zoom: int
    max_zoom: int
    start: MapTilesStart
    attribution: str


class ActOneMap(CamelModel):
    act: int
    markers: list[Marker]
    regions: list[str]
    builds: list[BuildSummary]
    timed_events: list[TimedEvent]
    walkthrough: list[WalkthroughStep]
    mapgenie_url: str
    mapgenie: MapTiles
    coordinate_note: str


class MarkerSyncRequest(CamelModel):
    act: int = Field(default=1, ge=1, le=3)
    party_level: int = Field(ge=1, le=12)
    build_ids: list[str] = Field(default_factory=list)
    completed_checkpoint_ids: list[str] = Field(default_factory=list)
    equipped_item_keys: list[str] = Field(default_factory=list)


class MarkerSyncMarker(CamelModel):
    id: str
    label: str
    type: str
    region: str
    area: str
    lat: float
    lng: float
    precision: str
    recommended_level: int
    level_source: str  # guide_fact | assistant_suggestion
    reason: str
    source: str


class MarkerSyncPreview(CamelModel):
    act: int
    party_level: int
    phase: str
    fingerprint: str
    markers: list[MarkerSyncMarker] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    already_synced: bool = False


class MarkerSyncConfirmRequest(CamelModel):
    fingerprint: str


class MarkerSyncConfirmResponse(CamelModel):
    ok: bool = True
    fingerprint: str


class LatLng(BaseModel):
    lat: float
    lng: float


class MapAlignTarget(BaseModel):
    id: str
    label: str
    kind: str = "checkpoint"
    danger: str = "moderate"
    lat: float
    lng: float
    x: float  # screenshot pixel coordinates
    y: float
    on_screen: bool = False


class MapAlignResponse(BaseModel):
    ok: bool
    map_open: bool = False
    inliers: int = 0
    confidence: float = 0.0
    zoom: float | None = None
    center: LatLng | None = None
    position_updated: bool = False
    targets: list[MapAlignTarget] = Field(default_factory=list)
    latency_ms: int = 0
    error: str | None = None
