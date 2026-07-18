from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator
from pydantic.alias_generators import to_camel


class CamelModel(BaseModel):
    """Base for models serialized to the web map as camelCase.

    Fields keep snake_case names in Python (and on the Mac payload, which is
    dumped with by_alias=False); dumping with by_alias=True yields the
    camelCase contract the web frontend consumes. One model, one vocabulary.
    """

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


class StrictCamelModel(CamelModel):
    """Schema used for structured model output; unknown fields are rejected."""

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True, extra="forbid")


class GuideSource(BaseModel):
    sheet: str
    row: int | None = None
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
    x: int | None = None
    y: int | None = None
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
    ability_score_reset: "AbilityScores | None" = None


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
    game_x: int | None = None
    game_y: int | None = None


class CatalogItem(CamelModel):
    """One row of the items table: item facts only, no per-build opinions."""

    item_key: str
    name: str
    slot: str
    act: int
    region: str = ""
    acquisition: str = ""
    game_x: int | None = None
    game_y: int | None = None
    map_objective: bool = True
    effect: str = ""
    acquire: str = ""
    wiki: str = ""
    icon: str = ""
    source: str = ""


class AbilityScores(StrictCamelModel):
    strength: int = Field(ge=8, le=20)
    dexterity: int = Field(ge=8, le=20)
    constitution: int = Field(ge=8, le=20)
    intelligence: int = Field(ge=8, le=20)
    wisdom: int = Field(ge=8, le=20)
    charisma: int = Field(ge=8, le=20)


class AbilityTargetScores(StrictCamelModel):
    strength: int = Field(ge=1, le=30)
    dexterity: int = Field(ge=1, le=30)
    constitution: int = Field(ge=1, le=30)
    intelligence: int = Field(ge=1, le=30)
    wisdom: int = Field(ge=1, le=30)
    charisma: int = Field(ge=1, le=30)


AbilityName = Literal["strength", "dexterity", "constitution", "intelligence", "wisdom", "charisma"]

ABILITY_NAMES: tuple[AbilityName, ...] = (
    "strength", "dexterity", "constitution", "intelligence", "wisdom", "charisma"
)

# BG3 character creation: point cost of each purchasable score; 27 points total.
POINT_BUY_COSTS = {8: 0, 9: 1, 10: 2, 11: 3, 12: 4, 13: 5, 14: 7, 15: 9}


class PointBuyScores(StrictCamelModel):
    strength: int = Field(ge=8, le=15)
    dexterity: int = Field(ge=8, le=15)
    constitution: int = Field(ge=8, le=15)
    intelligence: int = Field(ge=8, le=15)
    wisdom: int = Field(ge=8, le=15)
    charisma: int = Field(ge=8, le=15)


def check_point_buy(
    point_buy_scores: PointBuyScores,
    bonus_two: AbilityName,
    bonus_one: AbilityName,
    final_scores: AbilityScores,
) -> str | None:
    """Single authority on BG3 creation legality: the reason a plan is illegal, or None."""
    if bonus_two == bonus_one:
        return "BG3 +2 and +1 ability bonuses must use different abilities"
    spent = sum(POINT_BUY_COSTS[getattr(point_buy_scores, ability)] for ability in ABILITY_NAMES)
    if spent != 27:
        return f"BG3 point buy must spend exactly 27 points, got {spent}"
    for ability in ABILITY_NAMES:
        expected = getattr(point_buy_scores, ability)
        if ability == bonus_two:
            expected += 2
        elif ability == bonus_one:
            expected += 1
        if getattr(final_scores, ability) != expected:
            return f"Final {ability} must equal point buy plus its assigned ability bonus"
    return None


class AbilitySetupPlan(StrictCamelModel):
    id: str
    level: int = Field(ge=1, le=12)
    label: str
    reason: str
    point_buy_scores: PointBuyScores
    bonus_two: AbilityName
    bonus_one: AbilityName
    final_scores: AbilityScores
    first_class: str
    class_order: str

    @model_validator(mode="after")
    def validate_bg3_point_buy(self):
        reason = check_point_buy(self.point_buy_scores, self.bonus_two, self.bonus_one, self.final_scores)
        if reason is not None:
            raise ValueError(reason)
        return self


def derive_bg3_point_buy(scores: AbilityScores) -> tuple[PointBuyScores, AbilityName, AbilityName] | None:
    """Return one deterministic legal +2/+1 decomposition for final scores."""
    ordered = sorted(ABILITY_NAMES, key=lambda ability: (-getattr(scores, ability), ABILITY_NAMES.index(ability)))
    for bonus_two in ordered:
        for bonus_one in ordered:
            if bonus_one == bonus_two:
                continue
            values = {
                ability: getattr(scores, ability) - (2 if ability == bonus_two else 1 if ability == bonus_one else 0)
                for ability in ABILITY_NAMES
            }
            if any(value not in POINT_BUY_COSTS for value in values.values()):
                continue
            point_buy = PointBuyScores(**values)
            if check_point_buy(point_buy, bonus_two, bonus_one, scores) is None:
                return point_buy, bonus_two, bonus_one
    return None


class AbilityPlanSource(StrictCamelModel):
    id: str
    ability: AbilityName
    kind: Literal["asi", "feat", "permanent", "equipment", "consumable"]
    mode: Literal["add", "minimum"]
    value: int = Field(ge=1, le=30)
    label: str
    minimum_act: int = Field(default=1, ge=1, le=3)
    minimum_level: int = Field(default=1, ge=1, le=12)
    maximum_level: int | None = Field(default=None, ge=1, le=12)
    item_key: str | None = None
    unique_across_party: bool = False
    note: str = ""


class BuildSummary(CamelModel):
    id: str
    name: str
    honor_status: str
    role: str
    final_split: str
    class_progression: str
    starting_abilities: str
    starting_ability_scores: AbilityScores | None = None
    target_ability_scores: AbilityTargetScores | None = None
    target_ability_note: str = ""
    ability_setups: list[AbilitySetupPlan] = Field(default_factory=list)
    ability_sources: list[AbilityPlanSource] = Field(default_factory=list)
    play_pattern: str
    caveat: str
    source: str
    levels: list[BuildLevel] = Field(default_factory=list)
    gear: list[BuildGear] = Field(default_factory=list)


class ActGuideSummary(CamelModel):
    act: int = Field(ge=1, le=3)
    title: str
    route_available: bool
    local_map_available: bool
    map_name: str
    map_url: str
    equipment_file: str
    coordinate_system: str
    coordinate_note: str
    equipment_count: int = 0


class ImportedBuildLevel(StrictCamelModel):
    level: int = Field(ge=1, le=12)
    take: str
    subclass_choice: str
    choices: str
    tactics: str
    confidence: str
    ability_score_reset: AbilityScores | None = None


class ImportedBuildGear(StrictCamelModel):
    item: str
    slot: str
    priority: str
    act: int = Field(ge=1, le=3)
    region: str
    acquisition: str
    why: str
    minimum_level: int = Field(ge=1, le=12)
    maximum_level: int | None
    requirement: str
    alternative: str


class ImportedBuildDraft(StrictCamelModel):
    name: str
    role: str
    final_split: str
    class_progression: str
    starting_ability_scores: AbilityScores
    play_pattern: str
    caveat: str
    levels: list[ImportedBuildLevel]
    gear: list[ImportedBuildGear]


class ImportedLoadoutCharacter(CamelModel):
    name: str
    class_name: str
    level: int = Field(ge=1, le=12)
    is_custom: bool
    ability_scores: AbilityScores
    build: BuildSummary


class ImportedLoadout(CamelModel):
    id: str
    name: str
    source_url: str
    characters: list[ImportedLoadoutCharacter]


class ImportedBuild(CamelModel):
    id: str
    name: str
    source_url: str
    build: BuildSummary


class LoadoutImportRequest(CamelModel):
    url: str


class AbilityModifier(CamelModel):
    id: str
    ability: AbilityName
    kind: Literal["permanent", "temporary", "equipment"]
    mode: Literal["add", "minimum"]
    value: int = Field(ge=1, le=30)
    source: str
    plan_source_id: str | None = None


class PartyMember(CamelModel):
    id: str
    name: str
    level: int = Field(ge=1, le=12)
    build_id: str | None = None
    prepared_tags: list[str] = Field(default_factory=list)
    class_name: str | None = None
    status: Literal["active", "camp", "unrecruited", "unavailable", "dead", "departed"] | None = None
    role_override: str | None = None
    is_custom: bool | None = None
    ability_scores: AbilityScores | None = None
    is_hireling: bool | None = None
    source_loadout_id: str | None = None
    ability_modifiers: list[AbilityModifier] | None = None
    uses_build_ability_scores: bool | None = None
    applied_ability_setup_id: str | None = None


class ReadinessRequest(BaseModel):
    checkpoint_id: str
    party: list[PartyMember] = Field(default_factory=list)
    completed_checkpoint_ids: list[str] = Field(default_factory=list)
    skipped_checkpoint_ids: list[str] = Field(default_factory=list)
    checked_preparation: list[str] = Field(default_factory=list)
    walkthrough_statuses: dict[str, str] = Field(default_factory=dict)
    walkthrough_outcomes: dict[str, str] = Field(default_factory=dict)


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
    scope: Literal["current", "route", "party"] = "current"
    guide_version: str = ""
    selected_act: int = Field(default=1, ge=1, le=3)
    map_region: str = "unknown"
    route_phase: str = "unknown"
    recommended_step_id: str | None = None
    focused_step_id: str | None = None
    walkthrough_statuses: dict[str, str] = Field(default_factory=dict)
    walkthrough_outcomes: dict[str, str] = Field(default_factory=dict)
    roster: list[PartyMember] = Field(default_factory=list)
    story_outcomes: list[str] = Field(default_factory=list)
    equipped_by_member: dict[str, list[str]] = Field(default_factory=dict)
    equipment_ownership_known: bool = False


class ChatTurn(BaseModel):
    role: Literal["user", "assistant"]
    content: str


class ChatSource(BaseModel):
    """A clickable web reference backing part of a chat answer."""

    title: str
    url: str
    snippet: str = ""
    image: str = ""  # representative image URL, when the search result has one


class ChatRequest(BaseModel):
    message: str
    checkpoint_id: str | None = None
    party: list[PartyMember] = Field(default_factory=list)
    completed_checkpoint_ids: list[str] = Field(default_factory=list)
    skipped_checkpoint_ids: list[str] = Field(default_factory=list)
    checked_preparation: list[str] = Field(default_factory=list)
    walkthrough_step_id: str | None = None
    image_base64: str | None = None  # optional BG3 screenshot for the vision model
    context: ChatContextSnapshot | None = None
    history: list[ChatTurn] = Field(default_factory=list)  # prior turns, oldest first


class ChatResponse(BaseModel):
    answer: str
    guide_facts: list[str] = Field(default_factory=list)
    assistant_suggestions: list[str] = Field(default_factory=list)
    unknowns: list[str] = Field(default_factory=list)
    sources: list[ChatSource] = Field(default_factory=list)


class HealthResponse(BaseModel):
    ok: bool
    service: str
    pid: int
    parent_pid: int
    packaged: bool
    walkthrough_count: int
    # Whether server-side AI features (chat, build import) can run. The key
    # lives with the backend; clients gate AI UI on this instead of holding
    # their own credentials.
    ai_available: bool = False


class PlayerPosition(BaseModel):
    lat: float
    lng: float
    source: str = "manual"
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
    ability_scores: AbilityScores | None = None
    is_hireling: bool = False
    source_loadout_id: str | None = None
    ability_modifiers: list[AbilityModifier] | None = None
    uses_build_ability_scores: bool | None = None
    applied_ability_setup_id: str | None = None


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
