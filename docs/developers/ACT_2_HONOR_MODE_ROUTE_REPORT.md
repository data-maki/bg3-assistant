# Act 2 Honor Mode Route Research

**Status:** Source-reviewed research; not app-ready route data

**Research date:** 2026-07-17

**Intended run:** Good-aligned, completionist Honor Mode
**Preferred entry:** Grymforge elevator after completing both the Underdark and Mountain Pass content

This document is the reviewed research layer for a future Act 2 route. It does not make `data/acts/act2.json` route-enabled and must not be treated as shipped guidance until the records are converted to route JSON, validated, and tested in the overlay.

## Route contract

The proposed records retain the field contract used by `data/act1_route.json`:

| Field | Import rule |
|---|---|
| `id` | Stable kebab-case identifier. |
| `routeOrder` | Integer order for the recommended good-aligned path. |
| `danger` | `low`, `medium`, `high`, or `extreme`. |
| `legendaryAction` | Honor-specific behavior or `null`. |
| `failureConditions` | Concrete run, quest, NPC, or reward failures. |
| `preparation` | Actions to take before triggering the step. |
| `completionChecks` | Player-verifiable proof that the step is resolved. |
| `irreversibleWarnings` | Locks, deaths, hostility, and mutually exclusive outcomes. |
| `prerequisites` | Stable IDs that must be resolved first. |
| `notes` | Tactics, acquisition details, checks, and route rationale. |
| `sourceRow` | Leave `null` until an authoritative import row exists; do not fabricate spreadsheet provenance. |

This research adds `classification` and `sources`. `classification` may contain `required`, `recommended`, `optional`, `conditional`, `irreversible`, or `mutually-exclusive`. `sources` must survive any later conversion so factual corrections remain traceable.

Factual claims below are guide facts backed by the listed sources. Tactical ordering and encounter plans are reviewed suggestions derived from those facts. Wiki content and game behavior can change with patches, so every record needs a final in-game review before it becomes app-visible.

## Run assumptions

- Enter Act 2 around level 7 after resolving the Act 1 readiness gate. Reach level 9 before the Gauntlet's hardest fights and level 10 before the Mind Flayer Colony when feasible.
- Preserve Last Light Inn, Isobel, the tieflings, Dammon, Barcus, Jaheira, and Halsin.
- Use the tadpole status to keep Moonrise friendly. Friendly infiltration is not an evil commitment and exposes quests, traders, prisoners, companion scenes, and intelligence that disappear after the Shadowfell.
- Use ordinary light, a lit torch, or the Blood of Lathander only in the weaker curse. Use a Moonlantern or Pixie Blessing in the deep curse.
- Free Dolly Dolly Dolly from Kar'niss's lantern. Pixie Blessing protects the whole party without consuming a weapon slot; other Moonlanterns do not contain a releasable pixie.
- Spare Dame Aylin and trust Shadowheart to reject Shar. Killing Aylin is an incompatible Dark Justiciar route and can destroy Last Light.
- Lift the Shadow Curse, which requires Halsin, Art Cullagh's lead, Thaniel, Oliver, and Ketheric's death.
- Do not enter the Shadowfell until the pre-Shadowfell audit in this report is complete.
- Treat all one-save tactics as optional optimizations. Honor Mode plans must remain viable after a failed dialogue check, initiative roll, or control spell.

## Recommended route records

### 1. Enter through Grymforge

- `id`: `enter-shadow-cursed-lands-grymforge`
- `routeOrder`: 1
- `classification`: `required`, `irreversible`
- `danger`: `medium`
- `legendaryAction`: `null`
- `failureConditions`: A character leaves the light and takes escalating curse damage; a downed cursed character transforms and attacks the party; unresolved Act 1 state was advanced before the readiness gate was complete.
- `preparation`: Finish the Act 1 crèche and Grymforge gates; equip a torch, Light, or the Blood of Lathander; stabilize Gale with Elminster if that scene has not occurred; prepare radiant damage.
- `completionChecks`: Entered the Ruined Battlefield; every active character has working light protection; the Act 1 completion state was recorded.
- `irreversibleWarnings`: Act 2 entry is not the Shadowfell lock and Act 1 areas remain reachable for now, but the player should already have accepted the Act 1 transition consequences.
- `prerequisites`: `fight-wargaz`, `fight-grym`
- `notes`: The Grymforge route opens near Harper scouts and supports the intended Last Light-first route. The curse deals escalating necrotic damage outside protection and can turn a downed character into a hostile undead.
- `sources`: https://bg3.wiki/wiki/Infiltrate_Moonrise_Towers, https://bg3.wiki/wiki/Seek_Protection_from_the_Shadow_Curse
- `sourceRow`: `null`

### 2. Defend the Harper scouts

- `id`: `defend-harper-scouts`
- `routeOrder`: 2
- `classification`: `required`, `recommended`
- `danger`: `high`
- `legendaryAction`: `null`
- `failureConditions`: The party enters unlit; shadows drain Strength and isolate a low-AC character; surviving Harpers are lost; the party pursues enemies away from its light source.
- `preparation`: Keep the group inside overlapping light; equip radiant damage and Turn Undead; spread enough to avoid one darkness effect disabling all protection.
- `completionChecks`: Yonas and all hostile shadows defeated; Harper Lassandra survived; Last Light Inn marked on the map.
- `irreversibleWarnings`: Yonas's transformation is scripted; focus on preserving the remaining Harpers rather than trying to prevent it.
- `prerequisites`: `enter-shadow-cursed-lands-grymforge`
- `notes`: Follow the Harpers directly to Last Light instead of exploring deep-curse areas with ordinary light.
- `sources`: https://bg3.wiki/wiki/Infiltrate_Moonrise_Towers, https://bg3.wiki/wiki/Seek_Protection_from_the_Shadow_Curse
- `sourceRow`: `null`

### 3. Establish Last Light Inn

- `id`: `establish-last-light-inn`
- `routeOrder`: 3
- `classification`: `required`, `recommended`
- `danger`: `low`
- `legendaryAction`: `null`
- `failureConditions`: Jaheira is made hostile; the player conceals enough information to lose the safe introduction; important residents are skipped before the Isobel event.
- `preparation`: Bring the artefact and use the good-aligned tiefling history to establish trust; smell Jaheira's wine with the DC 10 Medicine check if desired, but answer honestly either way.
- `completionChecks`: Last Light waypoint unlocked; Jaheira trusts the party; all floors, docks, cellar access, and resident groups identified.
- `irreversibleWarnings`: Do not initiate Isobel's balcony conversation until the pre-defence hub audit is complete and the party is combat-ready.
- `prerequisites`: `defend-harper-scouts`
- `notes`: Last Light is the Act 2 hub. Jaheira's truth serum does not force a hostile outcome; the route should prioritize preserving trust rather than optimizing the DC 10 detection check.
- `sources`: https://bg3.wiki/wiki/Infiltrate_Moonrise_Towers, https://bg3.wiki/wiki/Last_Light_Inn
- `sourceRow`: `null`

### 4. Complete the Last Light pre-defence audit

- `id`: `audit-last-light-before-isobel`
- `routeOrder`: 4
- `classification`: `recommended`, `conditional`, `irreversible`
- `danger`: `low`
- `legendaryAction`: `null`
- `failureConditions`: Isobel is triggered before shopping and quest intake; Dammon dies before Karlach's second upgrade; Art Cullagh, Florrick, Barcus, or the tiefling quest givers are missed; a build-critical unique item is left in a trader's stock.
- `preparation`: Bring Karlach to Dammon if advancing her quest; bring sufficient gold and barter stock; review active build priorities.
- `completionChecks`: Spoke to Dammon, Quartermaster Talli, Mattis, Barcus, Art Cullagh, Florrick, Alfira, Rolan, Bex, Cerys, Mol, and Raphael where present; accepted the prisoner, Art, and curse quests; bought or deliberately skipped priority stock; looted the Coruscation Ring from the trapped Heavy Chest in the inn's cellar area.
- `irreversibleWarnings`: Losing Isobel removes Last Light's protection and can kill most residents, including traders and quest NPCs. Killing the Strange Ox for the Hat of Fire Acuity ends its Act 3 path and can endanger nearby allies; sparing it is the default good route.
- `prerequisites`: `establish-last-light-inn`
- `notes`: Priority purchases include Darkfire Shortbow from Dammon and Yuan-Ti Scale Mail plus Cloak of Protection from Talli. Barcus can sell Gloves of the Automaton if his Act 1 chain was preserved. Repair Karlach's engine before exposing Dammon to the Isobel battle.
- `sources`: https://bg3.wiki/wiki/Resolve_the_Abduction, https://bg3.wiki/wiki/The_Hellion%27s_Heart, https://bg3.wiki/wiki/Coruscation_Ring, https://bg3.wiki/wiki/Darkfire_Shortbow, https://bg3.wiki/wiki/Yuan-Ti_Scale_Mail, https://bg3.wiki/wiki/Cloak_of_Protection, https://bg3.wiki/wiki/Gloves_of_the_Automaton
- `sourceRow`: `null`

### 5. Defend Isobel

- `id`: `defend-isobel-last-light`
- `routeOrder`: 5
- `classification`: `required`, `recommended`, `irreversible`
- `danger`: `extreme`
- `legendaryAction`: `null`
- `failureConditions`: Isobel is knocked unconscious and abducted; Isobel dies; Marcus and the Winged Horrors focus her before the party can act; Last Light falls and its residents become shadow-cursed.
- `preparation`: Long rest; close nearby doors; place party members on the balcony and at room approaches before dialogue; prepare high initiative, Sanctuary, Warding Bond, Protection from Evil and Good, healing, crowd control, and burst damage.
- `completionChecks`: Marcus and all six Winged Horrors defeated; Isobel remains conscious and sustains the ward; Jaheira and key residents survive; Harpers begin preparing the convoy ambush.
- `irreversibleWarnings`: An abducted or dead Isobel collapses the ward and causes a large hostile battle against former residents. Mol's abduction during the attack is scripted even on a successful defence; her quest continues in Act 3.
- `prerequisites`: `audit-last-light-before-isobel`
- `notes`: Focus Marcus, but intercept horrors that can reach Isobel. Sanctuary is a delay rather than a guarantee because Isobel can break it with an offensive action. Heal her proactively. Dark Urge players who refuse to kill Isobel must later prepare for the companion-restraint camp scene; do not take an unprepared long rest after the butler's deadline.
- `sources`: https://bg3.wiki/wiki/Resolve_the_Abduction, https://bg3.wiki/wiki/The_Urge
- `sourceRow`: `null`

### 6. Ambush Kar'niss and claim the Moonlantern

- `id`: `ambush-karniss-convoy`
- `routeOrder`: 6
- `classification`: `required`, `recommended`
- `danger`: `extreme`
- `legendaryAction`: `Fanatic Retaliation: once per round when a Spindleweb Fanatic is killed, Kar'niss can retaliate against the killer for up to 6d10 psychic damage and Silence.`
- `failureConditions`: Kar'niss escapes with the lantern; the Harpers turn hostile after a failed cover story; Sanctuary wastes the party's attacks; Fanatic Retaliation deletes the character who kills a marked fanatic; the party loses deep-curse protection.
- `preparation`: Meet Branthos after saving Isobel; bring a dialogue specialist with Inspiration; spread the party; prepare area damage for Kar'niss's Sanctuary turns and psychic protection where available.
- `completionChecks`: Convoy defeated or talked into surrendering the lantern; Kar'niss's Moonlantern obtained; surviving Harpers remain friendly.
- `irreversibleWarnings`: Shadowheart and good-cleric declarations that reject Kar'niss's queen can start combat. Sending the convoy into the curse avoids the first fight but creates shadow-cursed versions in Reithwin later.
- `prerequisites`: `defend-isobel-last-light`
- `notes`: The safest dialogue line is to make the party known rather than risk the preliminary Stealth and passive Wisdom sequence. The lantern checks are normally DC 14 followed by DC 14; Bard has a DC 10 first check. In combat, do not spend single-target attacks into Sanctuary; use area effects, control the escorts, and have a durable character absorb the first Fanatic Retaliation trigger.
- `sources`: https://bg3.wiki/wiki/Seek_Protection_from_the_Shadow_Curse, https://bg3.wiki/wiki/Kar%27niss, https://bg3.wiki/wiki/Legendary_actions
- `sourceRow`: `null`

### 7. Free Dolly Dolly Dolly

- `id`: `free-dolly-thrice`
- `routeOrder`: 7
- `classification`: `required`, `recommended`
- `danger`: `low`
- `legendaryAction`: `null`
- `failureConditions`: The pixie remains trapped; the lantern is lost or unequipped in the deep curse; the player mistakes Balthazar's later Moonlantern for one containing a releasable pixie.
- `preparation`: Use Inspect Moonlantern on Kar'niss's lantern immediately after obtaining it.
- `completionChecks`: Dolly Dolly Dolly freed; Filigreed Feywild Bell received; Pixie Blessing visible on the party; free movement through the deep curse confirmed.
- `irreversibleWarnings`: Only Kar'niss's Moonlantern grants this release and blessing route. Keeping Dolly imprisoned trades party-wide convenience for carrying the lantern and is not the recommended good outcome.
- `prerequisites`: `ambush-karniss-convoy`
- `notes`: Pixie Blessing affects the whole party without a weapon slot. Keep the bell as recovery if the blessing needs to be renewed.
- `sources`: https://bg3.wiki/wiki/Seek_Protection_from_the_Shadow_Curse, https://bg3.wiki/wiki/Dolly_Dolly_Dolly, https://bg3.wiki/wiki/Filigreed_Feywild_Bell
- `sourceRow`: `null`

### 8. Rescue Rolan and find Arabella

- `id`: `rescue-rolan-find-arabella`
- `routeOrder`: 8
- `classification`: `recommended`, `conditional`, `irreversible`
- `danger`: `high`
- `legendaryAction`: `null`
- `failureConditions`: Rolan is killed by shadows before the party intervenes; Arabella is left in the curse; Rolan's Act 3 alliance chain is broken.
- `preparation`: Obtain Pixie Blessing; start Rolan's missing-siblings dialogue at Last Light; keep radiant damage and mobility ready.
- `completionChecks`: Rolan rescued near the Ruined Battlefield and returned to Last Light; Arabella found near the graveyard and sent to camp; Withers has begun caring for her.
- `irreversibleWarnings`: Approach Rolan's area promptly once his rescue state is active. His survival, the rescue of both siblings, and the Act 1 decision to make him stay are needed for his strongest good-aligned Act 3 outcome.
- `prerequisites`: `free-dolly-thrice`
- `notes`: Do this before the broad Reithwin sweep so neither vulnerable NPC is left behind while the party takes multiple rests.
- `sources`: https://bg3.wiki/wiki/Find_Rolan_in_the_Shadows, https://bg3.wiki/wiki/Find_Arabella%27s_Parents, https://bg3.wiki/wiki/Find_the_Nightsong
- `sourceRow`: `null`

### 9. Infiltrate friendly Moonrise

- `id`: `infiltrate-friendly-moonrise`
- `routeOrder`: 9
- `classification`: `required`, `recommended`, `irreversible`
- `danger`: `medium`
- `legendaryAction`: `null`
- `failureConditions`: The tower is made globally hostile; Ketheric is attacked while invulnerable; Z'rell rejects the party; Minthara's conditional judgment scene is ignored.
- `preparation`: Keep Pixie Blessing active; enter through the main gate as a True Soul; bring the face character and relevant conditional companions.
- `completionChecks`: Moonrise waypoint unlocked; Ketheric's audience witnessed; goblin outcome chosen deliberately; Z'rell's DC 14 loyalty route passed or otherwise resolved; Balthazar assignment and room key obtained; Minthara's prison quest accepted if she survived Act 1.
- `irreversibleWarnings`: Do not attack Ketheric or start a public fight. Moonrise can be freely infiltrated now but becomes the assault zone after the Shadowfell.
- `prerequisites`: `free-dolly-thrice`
- `notes`: Spare the judged goblins for the good route and Sazza continuity where applicable. Z'rell can usually be distracted with romance thoughts or fake devotion at DC 14. Receiving her assignment establishes the intended cover and grants access to Balthazar's room.
- `sources`: https://bg3.wiki/wiki/Infiltrate_Moonrise_Towers, https://bg3.wiki/wiki/Decide_Minthara%27s_Fate
- `sourceRow`: `null`

### 10. Audit Moonrise traders and exclusive choices

- `id`: `audit-moonrise-traders`
- `routeOrder`: 10
- `classification`: `recommended`, `conditional`, `mutually-exclusive`, `irreversible`
- `danger`: `low`
- `legendaryAction`: `null`
- `failureConditions`: Araj, Lann Tarv, or Roah is missed before hostility; Astarion is coerced without understanding the relationship consequence; build-critical unique stock is skipped.
- `preparation`: Bring gold and barter stock; bring Astarion for Araj's personal scene only after deciding whether roleplay or the permanent Strength reward has priority.
- `completionChecks`: Araj Oblodra, Lann Tarv, and Roah Moonglow audited; Risky Ring, Thunderskin Cloak, Ring of Spiteful Thunder, Sentinel Shield, Halberd of Vigilance, and Drakethroat Glaive bought or deliberately skipped; Astarion's Araj outcome recorded.
- `irreversibleWarnings`: Coercing Astarion to bite Araj grants the Potion of Everlasting Vigour but costs approval and violates his stated refusal, with possible romance consequences. Respecting his refusal permanently gives up the potion. Roah and Moonrise stock become unavailable on the good route after the Shadowfell.
- `prerequisites`: `infiltrate-friendly-moonrise`
- `notes`: The potion permanently adds +2 Strength to its drinker, up to 22 before later modifiers. Risky Ring grants attack advantage but imposes saving-throw disadvantage, a serious Honor Mode cost. Lann Tarv and Roah carry several best-in-slot martial and control items.
- `sources`: https://bg3.wiki/wiki/Araj_Oblodra, https://bg3.wiki/wiki/Potion_of_Everlasting_Vigour, https://bg3.wiki/wiki/Risky_Ring, https://bg3.wiki/wiki/Lann_Tarv, https://bg3.wiki/wiki/Roah_Moonglow
- `sourceRow`: `null`

### 11. Rescue the Moonrise prisoners

- `id`: `rescue-moonrise-prisoners`
- `routeOrder`: 11
- `classification`: `recommended`, `conditional`, `irreversible`
- `danger`: `high`
- `legendaryAction`: `null`
- `failureConditions`: Cell levers send prisoners through hostile corridors; the boat leaves one group behind; prisoners are killed by guards or at the docks; the party rests or fast-travels after telling Wulbren to begin; the Shadowfell is entered first.
- `preparation`: Speak to the tieflings and Wulbren; use Barcus's name or the DC 10 Persuasion route; quietly kill both Scrying Eyes, the Warden, and prison guards without making the upper tower hostile; reach the ledge behind the cells; free the boat from its brittle chains.
- `completionChecks`: Both rear cell walls opened; all surviving tieflings and Ironhand gnomes boarded the boat; destination set to Last Light; prison combat resolved without upper-tower hostility; Wulbren, Lia, Cal, Lakrissa, and Danis accounted for where their prior state permits.
- `irreversibleWarnings`: Entering and returning from the Shadowfell automatically ends both prisoner quests and leaves the prisoners dead. Do not use the master cell lever unless the entire escape route is already safe.
- `prerequisites`: `infiltrate-friendly-moonrise`
- `notes`: The safest completionist route is to clear the prison, break the back walls with Force damage, and use the boat. A bludgeoning weapon or Wulbren's Hammer can start his plan, but do not leave the area after authorizing the escape. Prisoner conversation checks include DC 14 to satisfy an interfering guard and DC 10 to gain Wulbren's trust when Barcus cannot vouch for the party.
- `sources`: https://bg3.wiki/wiki/Rescue_the_Tieflings, https://bg3.wiki/wiki/Rescue_Wulbren
- `sourceRow`: `null`

### 12. Resolve Moonrise secrets and companion content

- `id`: `resolve-moonrise-secrets`
- `routeOrder`: 12
- `classification`: `recommended`, `optional`, `conditional`, `mutually-exclusive`
- `danger`: `medium`
- `legendaryAction`: `null`
- `failureConditions`: Minthara is left for execution; the Spineshudder Mimic is missed; Ketheric's repentance clue is missed; Gale's ritual-circle choice is made accidentally; the gnolls remain enemy reinforcements.
- `preparation`: Keep the tower friendly; bring Gale to Balthazar's hidden ritual circle; bring a character able to communicate with the kitchen gnolls; bring Minthara safely out of the prison if her conditional route exists.
- `completionChecks`: Minthara rescued and recruited if available; Barnabus and the gnolls freed from control; Ketheric's rooms and letters searched; Spineshudder Amulet looted from the Mimic in Isobel's old Moonrise bedroom; Balthazar's hidden room opened; ritual circle destroyed or Shadow Lantern deliberately created.
- `irreversibleWarnings`: Destroying Balthazar's ritual circle is the good Gale route and gives up the Shadow Lantern. Creating the Shadow Lantern is mutually exclusive and produces a summon item that does not protect against the curse. Minthara must be escorted out without exposing the rescue.
- `prerequisites`: `infiltrate-friendly-moonrise`
- `notes`: Read the Letter to Ketheric in his chambers to unlock the DC 10 rooftop repentance opening. Freed gnolls can support the later assault. Quietly removing isolated cultists is an optional difficulty reduction, not a required completionist action, and must never risk tower-wide hostility before the audit is complete.
- `sources`: https://bg3.wiki/wiki/Balthazar%27s_Experiment, https://bg3.wiki/wiki/Spineshudder_Amulet, https://bg3.wiki/wiki/Infiltrate_Moonrise_Towers, https://bg3.wiki/wiki/Decide_Minthara%27s_Fate
- `sourceRow`: `null`

### 13. Collect prisoner rewards at Last Light

- `id`: `collect-prisoner-rescue-rewards`
- `routeOrder`: 13
- `classification`: `recommended`, `conditional`, `irreversible`
- `danger`: `low`
- `legendaryAction`: `null`
- `failureConditions`: Rewards are not claimed before leaving Act 2; Alfira or Lakrissa is absent because the Act 1 or prison chain failed; Rolan remains missing; Barcus is not told Wulbren survived.
- `preparation`: Return to Last Light immediately after the boat escape.
- `completionChecks`: Potent Robe claimed from Alfira where available; spoke to Rolan with Cal and Lia, Bex with Danis, Barcus, and Wulbren; Brilliant Retort claimed; rescue quests marked complete.
- `irreversibleWarnings`: The rescued tieflings do not provide their Act 2 rewards when encountered in Act 3. Potent Robe requires Alfira and Lakrissa's relevant survival state; Dark Urge runs depend on having preserved Alfira in Act 1.
- `prerequisites`: `rescue-moonrise-prisoners`, `rescue-rolan-find-arabella`
- `notes`: Potent Robe is a defining Charisma-caster item. Confirm the actual item is in inventory rather than treating prisoner survival alone as completion proof.
- `sources`: https://bg3.wiki/wiki/Rescue_the_Tieflings, https://bg3.wiki/wiki/Rescue_Wulbren, https://bg3.wiki/wiki/Potent_Robe
- `sourceRow`: `null`

### 14. Investigate the Mason's Guild and Selunite resistance

- `id`: `investigate-masons-guild`
- `routeOrder`: 14
- `classification`: `recommended`, `optional`
- `danger`: `high`
- `legendaryAction`: `null`
- `failureConditions`: Shadows ambush the party in confined rooms; traps around the Gilded Chest are ignored; the Helmet of Arcane Acuity is missed.
- `preparation`: Bring Pixie Blessing, radiant damage, trap tools, and a high Sleight of Hand character.
- `completionChecks`: Mason's Guild basement explored; Helmet of Arcane Acuity looted from the locked trapped Gilded Chest; Selunite resistance evidence chain advanced; relevant Infernal Iron and lore collected.
- `irreversibleWarnings`: This high-value item is not recoverable after leaving the region.
- `prerequisites`: `free-dolly-thrice`
- `notes`: The Helmet of Arcane Acuity is core for weapon-hit control builds. The Selunite investigation links Last Light's cellar, the abandoned potter's area, and the Mason's Guild; track quest completion rather than only the helmet.
- `sources`: https://bg3.wiki/wiki/Investigate_the_Sel%C3%BBnite_Resistance, https://bg3.wiki/wiki/Helmet_of_Arcane_Acuity, https://bg3.wiki/wiki/Mason%27s_Guild
- `sourceRow`: `null`

### 15. Defeat Gerringothe Thorm

- `id`: `defeat-gerringothe-thorm`
- `routeOrder`: 15
- `classification`: `recommended`, `optional`
- `danger`: `extreme`
- `legendaryAction`: `Sublimation: whenever a piece of her coin armour is destroyed, Gerringothe can try to turn an enemy to gold and incapacitate it for four turns; this can trigger more than once in a round.`
- `failureConditions`: The party carries excessive loose gold into combat; multiple armour pieces are removed in one uncontrolled sequence; a character is transmuted and left exposed; Visages remain active while Gerringothe is focused.
- `preparation`: Send most carried gold to camp; bring a high-Charisma face with Inspiration; spread beyond four metres; prepare control and burst for individual Visages if dialogue fails.
- `completionChecks`: Gerringothe defeated through dialogue or combat; Signed Trade Visa and tollhouse valuables considered; no character remains transmuted.
- `irreversibleWarnings`: Dialogue is the recommended Honor route. If combat begins, each destroyed Visage removes part of her armour and can trigger Sublimation.
- `prerequisites`: `free-dolly-thrice`
- `notes`: The common dialogue route uses a DC 18 check followed by DC 21. In combat, kill Visages one at a time from range, recover between armour breaks, and do not burst all armour pieces while the party is grouped.
- `sources`: https://bg3.wiki/wiki/Gerringothe_Thorm, https://bg3.wiki/wiki/Gerringothe_Thorm/Combat, https://bg3.wiki/wiki/Legendary_actions
- `sourceRow`: `null`

### 16. Defeat Thisobald Thorm

- `id`: `defeat-thisobald-thorm`
- `routeOrder`: 16
- `classification`: `recommended`, `optional`
- `danger`: `extreme`
- `legendaryAction`: `Overflowing Brew: once per round when an attack changes his brew, it overflows for 3d6 damage of the corresponding type.`
- `failureConditions`: The face fails repeated drinking or performance checks without Inspiration; the party repeatedly changes the brew and triggers area damage; Thisobald reaches party members while they are grouped.
- `preparation`: Use the party member with the best Constitution or Sleight of Hand and social skills; stack Guidance, Enhance Ability, resistance bonuses, and Inspiration; keep a combat fallback outside melee range.
- `completionChecks`: Thisobald defeated through dialogue or combat; ledger for Punish the Wicked collected; Waning Moon loot and research room checked.
- `irreversibleWarnings`: The dialogue sequence is safer but contains escalating checks. Do not begin it with an unbuffed face if the run depends on avoiding combat.
- `prerequisites`: `free-dolly-thrice`
- `notes`: Drinking uses Constitution DC 14, 16, and 18; faking drinks with Sleight of Hand uses DC 18, 18, and 21. If combat begins, Force and Psychic damage avoid changing his elemental brew; otherwise change it deliberately and only when the party can absorb Overflowing Brew.
- `sources`: https://bg3.wiki/wiki/Thisobald_Thorm, https://bg3.wiki/wiki/Thisobald_Thorm/Combat, https://bg3.wiki/wiki/Legendary_actions
- `sourceRow`: `null`

### 17. Defeat Malus Thorm and recover Art's lute

- `id`: `defeat-malus-thorm`
- `routeOrder`: 17
- `classification`: `required`, `recommended`, `optional`
- `danger`: `extreme`
- `legendaryAction`: `Wail of Loss makes every surviving assistant wail after Malus is attacked; Grasping Appendage can pull a creature toward him once per round.`
- `failureConditions`: Assistants remain active and amplify Wail of Loss; Malus pulls a vulnerable character into the operating group; Art's Battered Lute is not looted; Arabella's parents are not identified.
- `preparation`: Read the relevant surgical text for the assisted dialogue route; buff the face and save Inspiration; if fighting, spread out and prioritize nurses before Malus.
- `completionChecks`: Malus dead through dialogue or combat; Battered Lute obtained; Arabella's parents found and interacted with; House of Healing, morgue, and trader nurse audited as desired.
- `irreversibleWarnings`: The good completionist path still requires returning to Arabella at camp and allowing her quest to progress; finding the bodies alone is not completion.
- `prerequisites`: `rescue-rolan-find-arabella`
- `notes`: Dialogue openings are commonly DC 14 or DC 16, followed by a DC 21 final check; reading the primer can expose a DC 18 assisted route. If combat starts, kill or disable assistants before attacking Malus so Wail of Loss cannot multiply.
- `sources`: https://bg3.wiki/wiki/Malus_Thorm, https://bg3.wiki/wiki/Malus_Thorm/Combat, https://bg3.wiki/wiki/Find_Arabella%27s_Parents, https://bg3.wiki/wiki/Legendary_actions
- `sourceRow`: `null`

### 18. Resolve Punish the Wicked

- `id`: `resolve-punish-the-wicked`
- `routeOrder`: 18
- `classification`: `optional`, `mutually-exclusive`
- `danger`: `medium`
- `legendaryAction`: `null`
- `failureConditions`: The ledger is never delivered; the intended moral or reward branch is selected accidentally; He Who Was becomes hostile while the party is unprepared.
- `preparation`: Collect Madeline's ledger from the Waning Moon; decide whether the good-aligned forgiveness outcome or Raven Gloves reward has priority.
- `completionChecks`: Madeline's judgment chosen deliberately; He Who Was resolved; Raven Gloves acquired only if the selected punishment branch supports them.
- `irreversibleWarnings`: Forgiving Madeline is the compassionate outcome but conflicts with satisfying He Who Was for Raven Gloves. Excessive punishment can also anger him; this is not a single outcome that preserves every reward.
- `prerequisites`: `defeat-thisobald-thorm`
- `notes`: The default good route forgives Madeline and accepts losing the gloves. Record the branch rather than marking only the quest complete.
- `sources`: https://bg3.wiki/wiki/Punish_the_Wicked, https://bg3.wiki/wiki/Raven_Gloves
- `sourceRow`: `null`

### 19. Wake Art and defend Halsin's portal

- `id`: `defend-halsin-portal`
- `routeOrder`: 19
- `classification`: `required`, `recommended`, `irreversible`
- `danger`: `extreme`
- `legendaryAction`: `null`
- `failureConditions`: The portal is destroyed before four turns pass; Halsin is permanently lost in the Shadowfell; ranged enemies are allowed to focus the portal; Art's clue is not delivered.
- `preparation`: Play the Battered Lute for Art; bring Halsin to him; long rest before meeting Halsin at the lakeshore; prepare Spirit Guardians, Wall of Fire, Hunger of Hadar, Darkness, sleet or plant control, radiant area damage, and ranged priority damage.
- `completionChecks`: Art awake; portal survives four turns; Halsin returns with Thaniel; Halsin and Thaniel appear at camp; Halsin becomes available as a full companion after the follow-up.
- `irreversibleWarnings`: Portal destruction permanently loses Halsin and fails lifting the curse. If Art died because Last Light fell, Speak with Dead can recover the lead, but preserving him is the intended route.
- `prerequisites`: `defeat-malus-thorm`, `defend-isobel-last-light`
- `notes`: Hold the stair choke and kill ranged attackers first. Radiant Spirit Guardians clears ravens and weak melee units efficiently. Darkness on or near the portal can deny ranged targeting while the party controls approaches.
- `sources`: https://bg3.wiki/wiki/Lift_the_Shadow_Curse, https://bg3.wiki/wiki/Wake_Art_Cullagh
- `sourceRow`: `null`

### 20. Reunite Oliver and Thaniel

- `id`: `reunite-oliver-thaniel`
- `routeOrder`: 20
- `classification`: `required`, `recommended`
- `danger`: `extreme`
- `legendaryAction`: `Vengeful Playmate: once per round after a summoned shadow dies, Oliver can create The Wasting Quiet in an area.`
- `failureConditions`: The Nightdome is attacked directly and reflects damage; the party stands in The Wasting Quiet; Oliver is treated cruelly and Halsin approval is lost; the camp follow-up is skipped.
- `preparation`: Speak to Halsin and Thaniel at camp; bring Halsin if practical; prepare area damage and mobility; spread before following Oliver's portal.
- `completionChecks`: Oliver's summons defeated; Nightdome removed without direct reflected damage; Oliver convinced kindly to reunite; Thaniel awake at camp; quest state reduced to killing Ketheric.
- `irreversibleWarnings`: The land does not heal merely from reuniting the two halves. Ketheric must die and the party must leave Act 2 after the quest is otherwise complete.
- `prerequisites`: `defend-halsin-portal`
- `notes`: Kill Mummy, Daddy, Shadow Plush, and Shadow Friends. Their deaths damage the Nightdome without reflecting the damage. Move out of Wasting Quiet zones and let Halsin handle the reconciliation or use compassionate dialogue.
- `sources`: https://bg3.wiki/wiki/Lift_the_Shadow_Curse, https://bg3.wiki/wiki/Oliver, https://bg3.wiki/wiki/Legendary_actions
- `sourceRow`: `null`

### 21. Defeat the Shadow-Cursed Shambling Mound

- `id`: `defeat-shadow-cursed-shambling-mound`
- `routeOrder`: 21
- `classification`: `optional`
- `danger`: `extreme`
- `legendaryAction`: `Wretched Growth: a creature ending its turn within 5 m takes 3d10 necrotic damage and can be entangled by shadow-cursed vines.`
- `failureConditions`: The party is surprised; multiple Needle Blights chain death explosions through allies; characters end turns within five metres of the mound; the mound devours or restrains a frontliner.
- `preparation`: Approach in stealth from high ground; spread widely; bring ranged burst, forced movement, difficult terrain, and necrotic resistance; avoid a melee-first plan.
- `completionChecks`: Mound and all blights defeated; battlefield loot collected; no party member remains entangled.
- `irreversibleWarnings`: This is optional and should be deferred rather than attempted under-levelled or without a safe ranged opening.
- `prerequisites`: `free-dolly-thrice`
- `notes`: Trigger blight explosions away from the party and use forced movement to turn their death chain against the mound. End every turn outside the five-metre Wretched Growth radius.
- `sources`: https://bg3.wiki/wiki/Shadow-Cursed_Shambling_Mound, https://bg3.wiki/wiki/Legendary_actions
- `sourceRow`: `null`

### 22. Defeat Ch'r'ai Tska'an's ambush

- `id`: `defeat-tskaan-gith-ambush`
- `routeOrder`: 22
- `classification`: `conditional`, `optional`
- `danger`: `extreme`
- `legendaryAction`: `Soul Sacrifice: once per round when a humanoid dies, Tska'an can sacrifice the soul for power; after three souls she gains Vlaakith's Undying Aspect.`
- `failureConditions`: The party is surprised below the arch; ranged raiders use Trip Attack and Arrows of Many Targets from high ground; humanoid allies or enemies die before Tska'an and empower her; Repelling Blast pushes a character from elevation.
- `preparation`: Carry Voss's Qua'nith Psionic Detector if available; approach the Road to Baldur's Gate waypoint from the northern high route; use stealth and mobility to claim the arch; prepare to burn Legendary Resistance before control.
- `completionChecks`: Tska'an defeated before reaching three sacrifices; all raiders cleared; Hr'a'cknir Bracers and Psionic Ward Armour considered; waypoint secured.
- `irreversibleWarnings`: The encounter appears in Act 2 only if Vlaakith marked the party for death. Otherwise Tska'an moves to an Act 3 encounter and this record should be skipped, not failed.
- `prerequisites`: `free-dolly-thrice`
- `notes`: Focus Tska'an before killing humanoid minions. The ambush is at X -263 Y -37 near the Act 2 exit. Starting on the arch reverses the encounter's normal elevation advantage.
- `sources`: https://bg3.wiki/wiki/Tska%27an, https://bg3.wiki/wiki/Legendary_actions
- `sourceRow`: `null`

### 23. Enter the Gauntlet and kill Balthazar in his outpost

- `id`: `kill-balthazar-gauntlet-outpost`
- `routeOrder`: 23
- `classification`: `required`, `recommended`
- `danger`: `extreme`
- `legendaryAction`: `The Dead Wastes creates a 4d6 necrotic miasma at a creature's death that heals undead and harms living creatures; Spectral Aspect can trigger after Balthazar is struck.`
- `failureConditions`: Deep Umbral Tremors spawn overwhelming Justiciars; Flesh remains available to defend Balthazar; dead allies or summons create healing miasmas under the party; Balthazar reaches the Shadowfell alive.
- `preparation`: Meet Raphael outside the mausoleum with Astarion if following his scar quest; destroy Umbral Tremors before their summons; obtain Flesh's bell with DC 14 Persuasion and spend it in another Gauntlet fight if desired; long rest; prepare Counterspell, Silence, radiant damage, and necrotic resistance.
- `completionChecks`: Balthazar and his undead killed in the outpost; Flesh removed; Circle of Bones and key loot collected; Callous Glow Ring looted from the DC 30/Knock-accessible vault; Gauntlet waypoint active.
- `irreversibleWarnings`: Allowing Balthazar into the Shadowfell produces a much harder fight on small platforms with many summoned undead and shove deaths. Killing him in his room is the default Honor plan.
- `prerequisites`: `resolve-moonrise-secrets`, `reunite-oliver-thaniel`
- `notes`: Keep living characters out of corpse miasmas and prevent Cloudkill or other concentration spells. The vault near his outpost contains the Callous Glow Ring and Infernal Iron. Trial rooms restrict fast travel and resting after their doors are entered, but the wider Gauntlet remains restable before the Shadowfell.
- `sources`: https://bg3.wiki/wiki/Gauntlet_of_Shar, https://bg3.wiki/wiki/Balthazar, https://bg3.wiki/wiki/Callous_Glow_Ring, https://bg3.wiki/wiki/Legendary_actions
- `sourceRow`: `null`

### 24. Resolve Yurgir and Raphael's contract

- `id`: `resolve-yurgir-contract`
- `routeOrder`: 24
- `classification`: `required`, `recommended`, `mutually-exclusive`, `conditional`
- `danger`: `extreme`
- `legendaryAction`: `Blinding Ambush: once per round Yurgir can deal 5d10 radiant damage and attempt to Blind a Hunted creature within 3 m when it attacks or casts against him.`
- `failureConditions`: The party follows Nessa into a low-ground ambush; Yurgir and seven Merregons retain full action economy; a Hunted character attacks within three metres; bombs detonate around grouped allies; Yurgir's invisibility is not countered.
- `preparation`: Trade with the Hoarding Merregon before hostility; bring Astarion for Raphael's quest; stack social bonuses for the DC 14 passive Investigation and DC 16/21/21 Persuasion chain; for combat, approach from the southern high route and bring See Invisibility or water.
- `completionChecks`: Yurgir killed or contract deliberately broken; fourth Umbral Gem obtained; Hellfire Hand Crossbow looted if Yurgir died; Raphael/Astarion outcome recorded; Hoarding Merregon stock audited first.
- `irreversibleWarnings`: Killing Yurgir satisfies Raphael's deal to interpret Astarion's scars and grants his loot. Killing Lyrthindor to break the contract frees Yurgir, breaks Raphael's promised scar explanation, and changes Yurgir's later disposition. These outcomes cannot be combined.
- `prerequisites`: `kill-balthazar-gauntlet-outpost`
- `notes`: The dialogue kill route can remove Merregons at DC 16, Nessa at DC 21, and Yurgir at DC 21 after the passive insight into his contract. If fighting, keep the Hunted character farther than three metres before acting, deny invisibility with Wet or See Invisibility, and move bombs before their initiative count detonates them.
- `sources`: https://bg3.wiki/wiki/Kill_Raphael%27s_Old_Enemy, https://bg3.wiki/wiki/Break_Yurgir%27s_Contract, https://bg3.wiki/wiki/Yurgir, https://bg3.wiki/wiki/Yurgir/Combat
- `sourceRow`: `null`

### 25. Complete Shar's trials and the Silent Library

- `id`: `complete-shar-trials-library`
- `routeOrder`: 25
- `classification`: `required`, `conditional`
- `danger`: `high`
- `legendaryAction`: `null`
- `failureConditions`: A trial is entered without the right utility; Self-Same participants attack another character's copy while their own lives and gain Cheater's Folly; the Gauntlet lift loses a character; the Spear of Night is omitted with Shadowheart present.
- `preparation`: Let Shadowheart offer blood for approval if following her route; use one capable scout for Soft-Step; prepare each Self-Same participant to defeat its own copy; bring mobility for Faith-Leap; use martial damage and darkness-safe tactics in the silenced library.
- `completionChecks`: Three trial gems collected; Yurgir's fourth gem held; Killer's Sweetheart collected from Self-Same; Silent Library cleared; Riddle of the Night answered with The Nightsinger; Spear of Night obtained; both transport platforms operated safely.
- `irreversibleWarnings`: Shadowheart requires the Spear of Night to proceed with her personal quest. Ungroup and place characters individually on the lift because platform-positioning failures can be fatal.
- `prerequisites`: `resolve-yurgir-contract`
- `notes`: Soft-Step can be prepared before offering blood. In Self-Same, a character can help after its own copy dies; summons can attack any copy without Cheater's Folly. Do not use route-breaking skips that leave trial or quest completion uncertain.
- `sources`: https://bg3.wiki/wiki/Gauntlet_of_Shar, https://bg3.wiki/wiki/Silent_Library, https://bg3.wiki/wiki/Spear_of_Night
- `sourceRow`: `null`

### 26. Pass the pre-Shadowfell audit

- `id`: `audit-before-shadowfell`
- `routeOrder`: 26
- `classification`: `required`, `irreversible`
- `danger`: `low`
- `legendaryAction`: `null`
- `failureConditions`: Any friendly Moonrise, prisoner, Last Light, companion, trader, curse, or Act 1 task remains unresolved; the player accepts the warning without reviewing branch state.
- `preparation`: Use the full audit later in this report; return to every trader; resolve pending camp scenes; long rest and restock; bring Shadowheart and the intended final party.
- `completionChecks`: Prisoners and rewards resolved; all desired trader items acquired; Minthara, Astarion, Gale, Karlach, Wyll, Halsin, Jaheira, Arabella, Rolan, and Dark Urge conditionals reviewed; Thaniel and Oliver reunited; three Thorm encounters and side quests deliberately completed or skipped; Balthazar dead; four gems and Spear of Night held.
- `irreversibleWarnings`: Entering the Shadowfell permanently closes Act 1 travel, auto-resolves major Moonrise content, kills unresolved prisoners, removes friendly Moonrise trading, and advances Act 2 into its assault phase.
- `prerequisites`: `collect-prisoner-rescue-rewards`, `complete-shar-trials-library`, `reunite-oliver-thaniel`
- `notes`: This is a manual acceptance gate like the existing Act transition gate. It must never auto-complete from location detection or inferred quest state.
- `sources`: https://bg3.wiki/wiki/Shadowfell, https://bg3.wiki/wiki/Find_the_Nightsong, https://bg3.wiki/wiki/Rescue_the_Tieflings, https://bg3.wiki/wiki/Rescue_Wulbren
- `sourceRow`: `null`

### 27. Free Dame Aylin and preserve Shadowheart

- `id`: `free-dame-aylin`
- `routeOrder`: 27
- `classification`: `required`, `recommended`, `mutually-exclusive`, `irreversible`
- `danger`: `high`
- `legendaryAction`: `null`
- `failureConditions`: Shadowheart kills Aylin; Shadowheart leaves because her quest is resolved without her; the player forces the decision and triggers a hostile confrontation; Balthazar was left alive and adds a platform fight.
- `preparation`: Bring Shadowheart, the Spear of Night, and high approval; kill Balthazar first; verify the pre-Shadowfell audit; save Inspiration for dialogue rather than traversal.
- `completionChecks`: Shadowheart chooses to spare Aylin; Aylin freed; Moonlight Glaive received; Shadowheart remains in the party and rejects Shar; Ketheric's immortality broken; assault state begins.
- `irreversibleWarnings`: Killing Aylin creates the Dark Justiciar branch, can destroy Last Light, and permanently excludes the good Selunite outcome. Resolving Aylin without Shadowheart can make Shadowheart leave permanently.
- `prerequisites`: `audit-before-shadowfell`
- `notes`: The safest good route is to trust Shadowheart and avoid commanding her to kill Aylin. Approval of roughly 40 or more is safer, but her hidden Nightsong-point history also matters. If intervention is required, context-dependent checks include DC 14 and DC 21 paths; do not present approval alone as a guarantee.
- `sources`: https://bg3.wiki/wiki/Shadowfell, https://bg3.wiki/wiki/Find_the_Nightsong, https://bg3.wiki/wiki/Daughter_of_Darkness
- `sourceRow`: `null`

### 28. Assault Moonrise with Jaheira

- `id`: `assault-moonrise-towers`
- `routeOrder`: 28
- `classification`: `required`, `recommended`, `irreversible`
- `danger`: `extreme`
- `legendaryAction`: `null`
- `failureConditions`: Jaheira dies under AI control; Z'rell and multiple casters retain the central choke; Harpers rush through Hunger of Hadar and other area effects; the party reaches the roof depleted.
- `preparation`: Long rest after the Shadowfell; speak to Jaheira outside; ask her to join as an attached follower so the player can control her; enter from a favorable route; prepare Counterspell, area denial, forced movement, and anti-concentration damage.
- `completionChecks`: Jaheira survives; ground floor and upper route cleared; Harper losses minimized; rooftop access secured; optional prison undead battle deliberately completed or skipped.
- `irreversibleWarnings`: Jaheira's death ends her recruitment and Act 3 quest line. Do not leave her as an uncontrolled front-line AI if preservation is a goal.
- `prerequisites`: `free-dame-aylin`
- `notes`: Control the central doorway instead of charging into enemy area spells. Remove Adepts and Z'rell early, break concentration, and let enemies enter prepared zones. Previously freed gnolls can join the friendly side.
- `sources`: https://bg3.wiki/wiki/Infiltrate_Moonrise_Towers, https://bg3.wiki/wiki/Jaheira
- `sourceRow`: `null`

### 29. Defeat rooftop Ketheric

- `id`: `defeat-rooftop-ketheric`
- `routeOrder`: 29
- `classification`: `required`
- `danger`: `extreme`
- `legendaryAction`: `Hordestrike: once per round Ketheric can strike a target after one of his minions attacks it under Deadly Orders.`
- `failureConditions`: The party is grouped for necrotic area attacks; Necromites and other minions remain uncontrolled; the Deadly Orders target is exposed; Aylin or Jaheira is repeatedly downed; the party follows Ketheric into the Colony without recovering resources.
- `preparation`: Rest and replenish before the roof; read Letter to Ketheric; spread before dialogue; prepare radiant damage, anti-undead control, mobility, and a durable character to manage the first Hordestrike cycle.
- `completionChecks`: Rooftop Ketheric reduced to the scripted retreat; Aylin and Jaheira survive; Hollow Tower route opened; party state and resources reviewed before entering the Colony.
- `irreversibleWarnings`: Ketheric's retreat is scripted and cannot end the quest on the roof. Following him changes area into the Colony, where camp and normal fast travel are unavailable.
- `prerequisites`: `assault-moonrise-towers`
- `notes`: Letter to Ketheric can reduce the opening repentance appeal to DC 10; other rooftop routes can be DC 18 or higher. Even a successful appeal does not skip the rooftop battle. Kill or control minions to reduce Hordestrike triggers and keep its target separated.
- `sources`: https://bg3.wiki/wiki/Infiltrate_Moonrise_Towers, https://bg3.wiki/wiki/Ketheric_Thorm/Combat, https://bg3.wiki/wiki/Legendary_actions
- `sourceRow`: `null`

### 30. Complete the Mind Flayer Colony audit

- `id`: `audit-mind-flayer-colony`
- `routeOrder`: 30
- `classification`: `required`, `recommended`, `conditional`, `irreversible`
- `danger`: `extreme`
- `legendaryAction`: `null`
- `failureConditions`: Mizora is annihilated; Zevlor or other pod prisoners die; Us is left caged; the Waking Mind is missed; the wrong character receives the permanent boon; Gale detonates the orb; the final lift is used before the colony is complete.
- `preparation`: Bring Wyll if seeking his Mizora scene and Infernal Rapier; bring the Dark Urge for Kressa's history if applicable; preserve spell slots until the restoration pod; prepare to fight Mind Flayers immediately after opening Zevlor's pods.
- `completionChecks`: Us freed from Chop or its cage; Mizora safely released and Wyll reward handled; Zevlor and surviving Flaming Fists freed; Kressa and barracks resolved; mind-connection puzzle completed; Waking Mind used for Githzerai Mind Barrier on the intended owner; colony lore and loot collected; restoration pod still available for the final fight.
- `irreversibleWarnings`: The Colony cannot be revisited after the finale. The wrong Mizora control can kill her and permanently remove Wyll under his contract. Gale's orb choice ends the run's story early and is not the good completionist route. Mol is not in these pods; her search continues in Act 3.
- `prerequisites`: `defeat-rooftop-ketheric`
- `notes`: Opening Zevlor's pods also releases hostile Mind Flayers, so pre-position and kill them before they dominate allies. The Waking Mind grants permanent advantage on Intelligence saving throws to the interacting character after agreeing to free it. Wyll must be present for the full Mizora reward path. Use the restoration pod only after all optional fights and immediately before descending.
- `sources`: https://bg3.wiki/wiki/Defeat_Ketheric_Thorm, https://bg3.wiki/wiki/Mind_Flayer_Colony, https://bg3.wiki/wiki/Find_Zevlor, https://bg3.wiki/wiki/Us, https://bg3.wiki/wiki/Waking_Mind, https://bg3.wiki/wiki/The_Blade_of_Frontiers
- `sourceRow`: `null`

### 31. Defeat Ketheric and the Apostle of Myrkul

- `id`: `defeat-apostle-of-myrkul`
- `routeOrder`: 31
- `classification`: `required`, `irreversible`
- `danger`: `extreme`
- `legendaryAction`: `Gaze of the Dead: once per round the Apostle uses a second Gaze against the first creature that attacks it, dealing necrotic damage and attempting to Frighten.`
- `failureConditions`: The Mind Flayer dominates Aylin or a striker; Aylin remains imprisoned; Ketheric is skipped directly into the Apostle while all adds remain active; Bone Chilled prevents healing on the platform; Necromites are consumed for an 8d8 heal and Finger of Death; Gaze disables a key attacker; Call of the Damned pulls the party into the aura.
- `preparation`: Use the restoration pod; summon Scratch or another mobile helper; apply long-duration buffs; pre-position an invisible helper near Aylin and mobile strikers toward the Mind Flayer; spread around the arena; prepare magical bludgeoning, radiant damage, Darkness or accuracy denial, summons, and ranged damage.
- `completionChecks`: Aylin freed; Mind Flayer killed immediately; initial adds controlled; Ketheric defeated; Apostle defeated without consuming Necromites if possible; Ketheric's Netherstone, Ketheric's Shield, and Reaper's Embrace looted; portal used only after loot confirmation.
- `irreversibleWarnings`: The DC 18 repentance check can skip Ketheric's colony phase, but in Honor Mode it also brings the Apostle out while the original adds remain. The tactically safer default is to free Aylin, remove the Mind Flayer and adds, then finish Ketheric. The Apostle is immune to incapacitation and many hard-control conditions.
- `prerequisites`: `audit-mind-flayer-colony`
- `notes`: Let a summon or durable attacker trigger the round's Legendary Gaze before the main damage sequence. Keep heal-dependent characters off the Apostle's platform because Myrkul's Presence applies Bone Chilled. Destroy Necromites and incubating pods before they reach the Apostle. Its Honor stats include 390 HP, AC 20, broad physical, cold, necrotic, and poison defenses, so use inspected vulnerabilities and reliable magical damage rather than one damage type.
- `sources`: https://bg3.wiki/wiki/Defeat_Ketheric_Thorm, https://bg3.wiki/wiki/Apostle_of_Myrkul, https://bg3.wiki/wiki/Legendary_actions
- `sourceRow`: `null`

### 32. Close Act 2 and transition deliberately

- `id`: `close-act-two-transition`
- `routeOrder`: 32
- `classification`: `required`, `irreversible`
- `danger`: `medium`
- `legendaryAction`: `null`
- `failureConditions`: Ketheric's loot is left behind; Jaheira is not recruited; Wulbren, Aylin, Isobel, Halsin, or Thaniel follow-ups are skipped; the curse quest is incomplete when the party leaves; camp and inventory are not prepared for the forced transition sequence.
- `preparation`: Return through the portal; speak to every survivor on Moonrise's ground floor and at camp; recruit Jaheira; verify Halsin and Thaniel state; distribute final Act 2 equipment; long rest and restock before taking the Road to Baldur's Gate.
- `completionChecks`: Jaheira recruited; Aylin and Isobel camp state confirmed; Wulbren and surviving prisoners followed up; Lift the Shadow Curse ready to complete on departure; Ketheric loot assigned; Act 2 completion audit accepted; healing-land departure cutscene seen.
- `irreversibleWarnings`: Leaving for Baldur's Gate closes the Shadow-Cursed Lands. If Thaniel and Oliver were not reunited and Ketheric killed, Halsin remains behind and the curse is not lifted.
- `prerequisites`: `defeat-apostle-of-myrkul`, `reunite-oliver-thaniel`
- `notes`: Expect forced camp and transition content before free Act 3 exploration. Do not treat Ketheric's death alone as proof that companion, curse, and reward follow-ups are complete.
- `sources`: https://bg3.wiki/wiki/Lift_the_Shadow_Curse, https://bg3.wiki/wiki/Defeat_Ketheric_Thorm, https://bg3.wiki/wiki/Wyrm%27s_Lookout, https://bg3.wiki/wiki/Jaheira
- `sourceRow`: `null`

## Pre-Shadowfell acceptance gate

Every applicable row must be `complete`, `deliberately skipped`, or `not applicable` before `audit-before-shadowfell` can be accepted.

| Area | Acceptance proof | Consequence if unresolved |
|---|---|---|
| Act 1 travel | All intended Wilderness, Underdark, Grymforge, Mountain Pass, and crèche tasks closed | Act 1 travel and unfinished quests lock on Shadowfell entry |
| Last Light survival | Isobel, Jaheira, Dammon, Art, and intended tieflings alive | Hub, traders, curse chain, and later allies can be lost |
| Last Light shopping | Dammon, Talli, Mattis, Barcus, and Strange Ox branch audited | Unique stock or Act 3 continuity lost |
| Karlach | Dammon's available engine work and dialogue complete | Companion progression stalls if Dammon is lost |
| Moonrise cover | Ketheric audience and Z'rell assignment complete | Infiltration content skipped |
| Moonrise shopping | Araj, Lann Tarv, and Roah stock audited | Traders become unavailable on the good assault route |
| Astarion and Araj | Refusal respected or potion coercion explicitly recorded | Permanent reward or relationship branch lost |
| Prisoners | Tieflings and gnomes escaped by boat; all rewards collected | Prisoners die and Potent Robe becomes unavailable |
| Minthara | Rescued and escorted out if her Act 1 state permits | Conditional companion is executed or lost |
| Moonrise secrets | Letter to Ketheric, Spineshudder Mimic, gnolls, and Gale circle handled | Gear, reduced check, allies, or companion content lost |
| Rolan | Rolan rescued; Cal and Lia safe | Act 3 Rolan alliance weakened or lost |
| Arabella | Arabella at camp; parents found; follow-up progressed | Permanent spell and Act 3 chain can be lost |
| Curse | Art awake; portal defended; Thaniel and Oliver reunited | Halsin can stay behind and the land remains cursed |
| Reithwin bosses | Gerringothe, Thisobald, and Malus deliberately resolved | XP, loot, dialogue content, and lute lead omitted |
| Side quests | Selunite resistance, Punish the Wicked, Shambling Mound, and gith ambush deliberately resolved or skipped | Completionist content or unique loot omitted |
| Gauntlet | Balthazar dead; Yurgir branch recorded; four gems held; Spear of Night held | Harder Shadowfell fight or blocked companion progression |
| Gear | All items in the acquisition matrix reviewed | Unique Act 2 equipment becomes unavailable |
| Camp | Pending long-rest and companion scenes resolved | Events may be displaced by assault and transition scenes |

## Dialogue and ability-check audit

DCs can vary with tags, prior discoveries, and dialogue order. Store the context with the number rather than exposing a bare DC in the app.

| Encounter | Context | Checks and safe interpretation |
|---|---|---|
| Jaheira | Detect truth serum | Medicine DC 10 detects Klauthgrass; trust can still be earned without passing it |
| Marcus | Probe his mission | Wisdom DC 6; not required to side with Isobel |
| Kar'niss | Remain hidden | Stealth DC 14; failed stealth can lead to passive Wisdom DC 16; making the party known avoids this preliminary sequence |
| Kar'niss | Take lantern and dismiss convoy | Usually DC 14 then DC 14; Bard first option is DC 10 with advantage |
| Harper aftermath | Explain apparent convoy involvement | Persuasion or Deception DC 16 if that branch occurs |
| Z'rell | Hide true loyalty | Common romance-thought Persuasion or fake-devotion Deception DC 14 |
| Prison guard | Speak to prisoners | Deception or Persuasion DC 14 |
| Wulbren | Gain trust | No check with Barcus's lead; otherwise Persuasion DC 10 or several tagged DC 6 routes |
| Gerringothe | Talk her down | Common sequence DC 18 then DC 21 |
| Thisobald | Drink | Constitution DC 14, 16, then 18 |
| Thisobald | Fake drinking | Sleight of Hand DC 18, 18, then 21 |
| Malus | Turn doctrine against him | Openings commonly DC 14 or 16; final check DC 21; primer-assisted route can be DC 18 |
| Balthazar | Obtain Flesh's bell | Persuasion DC 14 |
| Yurgir | Understand and exploit contract | Passive Investigation DC 14, then Persuasion DC 16, 21, and 21 for followers, Nessa, and Yurgir |
| Shadowheart | Spare Aylin | Trust route is preferred; intervention can expose context-dependent DC 14 or DC 21 options and is also affected by hidden Nightsong points |
| Ketheric rooftop | Invoke Melodia after reading letter | Persuasion DC 10 opening; without the clue, available checks can be DC 18 or higher and do not avoid rooftop combat |
| Ketheric colony | Final repentance | Persuasion DC 18; skips directly to Apostle and is not the default Honor recommendation |
| Us and Chop | Free Us | Sleight of Hand, Illithid Wisdom, or Persuasion DC 14; Intimidation DC 18 |
| Kressa | Avoid immediate combat | Deception DC 21 for non-Dark-Urge context; Dark Urge history route still leads to combat unless disguised |

Sources: https://bg3.wiki/wiki/Seek_Protection_from_the_Shadow_Curse, https://bg3.wiki/wiki/Infiltrate_Moonrise_Towers, https://bg3.wiki/wiki/Rescue_the_Tieflings, https://bg3.wiki/wiki/Defeat_Ketheric_Thorm, https://bg3.wiki/wiki/Yurgir/Combat

## Honor encounter audit

Act 2 has 11 Legendary-action encounters. Balthazar and Malus each expose more than one named Legendary Action, but each is one encounter for coverage counting.

| Route | Encounter | Legendary behavior | Honor-safe counterplan |
|---:|---|---|---|
| 6 | Kar'niss | Fanatic Retaliation after a Spindleweb Fanatic dies can deal 6d10 psychic and Silence the killer | Use a durable killer for the first trigger; spread; use area attacks during Kar'niss's Sanctuary; obtain the lantern through dialogue if risk is unacceptable |
| 15 | Gerringothe Thorm | Sublimation can transmute and incapacitate a target whenever armour is lost, potentially multiple times per round | Prefer dialogue; otherwise kill one Visage at a time from range and stabilize between armour breaks |
| 16 | Thisobald Thorm | Overflowing Brew deals 3d6 of the current brew type when an attack changes it | Prefer dialogue; if fighting, use Force or Psychic damage or change the brew only as part of a controlled resistance plan |
| 17 | Malus Thorm | Wail of Loss orders every assistant to wail after he is attacked; Grasping Appendage pulls targets closer | Prefer dialogue; otherwise kill or disable nurses before touching Malus and keep vulnerable units spread |
| 20 | Oliver | Vengeful Playmate creates The Wasting Quiet after a summon dies; Nightdome reflects direct damage | Kill summons to damage the dome indirectly, then leave the new hazard zones |
| 21 | Shadow-Cursed Shambling Mound | Wretched Growth damages and can entangle any creature ending within 5 m | Stay ranged, spread, control add explosions, and use forced movement |
| 22 | Ch'r'ai Tska'an | Soul Sacrifice empowers her whenever a humanoid dies; three souls grant Undying Aspect | Claim the arch and focus Tska'an before killing any humanoid minion |
| 23 | Balthazar | Dead Wastes creates necrotic corpse miasmas; Spectral Aspect triggers after a hit | Kill him in his outpost, spend Flesh elsewhere, counter his spells, and never stand in death zones |
| 24 | Yurgir | Blinding Ambush interrupts a Hunted attacker within 3 m for 5d10 radiant and possible Blind | Use the dialogue sequence or keep the marked target beyond 3 m, reveal invisibility, and control bombs |
| 29 | Ketheric Thorm | Hordestrike follows a minion's Deadly Orders attack once per round | Spread, remove minions, and isolate or protect the marked target |
| 31 | Apostle of Myrkul | The first attacker each round receives an extra Gaze of the Dead | Trigger with a summon or durable unit, then commit the primary damage sequence |

Canonical list: https://bg3.wiki/wiki/Legendary_actions

## High-value acquisition matrix

The first group mirrors `data/gear/act2.tsv`. The second group captures major route missables that should be considered before an Act 2 route is declared complete.

### Repository-priority equipment

| Item | Acquisition | Timing and lock | Build value |
|---|---|---|---|
| Helmet of Arcane Acuity | Locked trapped Gilded Chest in Mason's Guild secret basement | Before leaving Act 2 | Weapon hits stack spell attack and save DC; core control-martial item |
| Risky Ring | Buy from Araj Oblodra | Before Shadowfell; mutually competes with safer save setups | Advantage on attacks, but disadvantage on all saves is dangerous in Honor Mode |
| Potion of Everlasting Vigour | Have Astarion bite Araj | Before Shadowfell; mutually exclusive with respecting his refusal | Permanent +2 Strength, up to 22 before other bonuses |
| Coruscation Ring | Trapped Heavy Chest in Last Light cellar area | Before Last Light is lost or Act 2 ends | Spell damage against illuminated targets applies Radiating Orb |
| Callous Glow Ring | Opulent Chest in the locked Gauntlet vault near Balthazar | Before leaving Gauntlet; use Knock or DC 30 lock | Adds radiant damage against illuminated targets and activates radiant gear |
| Hellfire Hand Crossbow | Loot Yurgir | Requires Yurgir's death | Scorching Ray supplies multi-hit fire damage and Arcane Acuity setup |
| Hat of Fire Acuity | Loot the Strange Ox | Killing it ends the Act 3 ox path; not default good route | Fire damage rapidly stacks Arcane Acuity |
| Spineshudder Amulet | Kill the Mimic in Isobel's old Moonrise bedroom | Before Shadowfell | Ranged spell attacks apply Reverberation |
| Ring of Mental Inhibition | Locked chest in House in Deep Shadows | Before leaving Act 2 | Failed mental saves apply Mental Fatigue |
| Darkfire Shortbow | Buy from Dammon | Before Last Light loss or departure | Passive fire/cold resistance and Haste from the ranged slot |
| Reaper's Embrace | Loot Ketheric after the Colony finale | Loot before using the exit portal | Heavy armour reduces damage and prevents forced movement when enabled |
| Ketheric's Shield | Loot Ketheric after the Colony finale | Loot before using the exit portal | Spell save DC and spell attacks on a defensive shield |
| Thunderskin Cloak | Buy from Araj Oblodra | Before Shadowfell | Dazes attackers that hit while Reverberating |
| Ring of Spiteful Thunder | Buy from Roah Moonglow | Before Shadowfell | Thunder damage can Daze Reverberating targets |

### Additional completionist missables

| Item or reward | Acquisition | Miss condition | Route treatment |
|---|---|---|---|
| Potent Robe | Rescue Lakrissa and speak to Alfira at Last Light | Alfira/Lakrissa dead, prisoners unresolved, or reward not claimed before Act 3 | Recommended for Charisma casters |
| Yuan-Ti Scale Mail | Buy from Quartermaster Talli | Last Light lost or Act 2 left | Recommended medium armour |
| Cloak of Protection | Buy from Quartermaster Talli | Last Light lost or Act 2 left | Broad AC and saving-throw defence |
| Sentinel Shield | Buy from Lann Tarv | Moonrise hostile after Shadowfell | High initiative and Perception support |
| Halberd of Vigilance | Buy from Lann Tarv | Moonrise hostile after Shadowfell | Strong reach weapon and initiative support |
| Drakethroat Glaive | Buy from Roah Moonglow | Moonrise hostile after Shadowfell | Draconic Elemental Weapon can buff another weapon until long rest |
| Gloves of the Automaton | Buy from Barcus at Last Light if his chain is intact | Barcus not preserved or Last Light lost | Once-per-short-rest attack advantage and construct state |
| Killer's Sweetheart | Ground where the player character's Self-Same copy dies | Trial skipped or unusual kill method prevents drop | Once-per-long-rest forced critical after a kill |
| Raven Gloves | Satisfy He Who Was's accepted punishment branch | Forgive Madeline or anger He Who Was | Mutually exclusive with compassionate default |
| Infernal Rapier | Bring Wyll through Mizora's Colony rescue and secure reward | Wyll absent or reward dialogue missed | Spellcasting-ability weapon with cambion summon |
| Moonlight Glaive | Free Aylin | Aylin killed or handed to Balthazar | Good-route immediate reward |
| Selune's Spear of Night | Spare Aylin and complete camp follow-up | Dark Justiciar route chosen | Good Shadowheart-route reward |
| Shar's Spear of Evening | Have Shadowheart kill Aylin | Good route chosen | Explicitly incompatible evil-route reward |
| Hr'a'cknir Bracers | Loot Tska'an | Conditional ambush skipped or loot missed | Telekinesis and Strength-save support |

Item sources: https://bg3.wiki/wiki/Helmet_of_Arcane_Acuity, https://bg3.wiki/wiki/Risky_Ring, https://bg3.wiki/wiki/Potion_of_Everlasting_Vigour, https://bg3.wiki/wiki/Coruscation_Ring, https://bg3.wiki/wiki/Callous_Glow_Ring, https://bg3.wiki/wiki/Hellfire_Hand_Crossbow, https://bg3.wiki/wiki/Hat_of_Fire_Acuity, https://bg3.wiki/wiki/Spineshudder_Amulet, https://bg3.wiki/wiki/Ring_of_Mental_Inhibition, https://bg3.wiki/wiki/Darkfire_Shortbow, https://bg3.wiki/wiki/Reaper%27s_Embrace, https://bg3.wiki/wiki/Ketheric%27s_Shield, https://bg3.wiki/wiki/Thunderskin_Cloak, https://bg3.wiki/wiki/Ring_of_Spiteful_Thunder

## Permanent power and companion ledger

These outcomes must be recorded separately from ordinary loot and route completion.

| Outcome | Owner or state | Completion proof | Exclusivity or failure |
|---|---|---|---|
| Potion of Everlasting Vigour | Chosen Strength user | Permanent +2 Strength visible and owner recorded | Requires coercing Astarion to bite Araj |
| Githzerai Mind Barrier | Chosen long-term character | Advantage on Intelligence saves visible | Only the interacting character receives it; Colony is one-visit content |
| Arabella's shadow magic | Arabella quest state | Arabella follow-up and granted ability recorded | Requires finding Arabella, her parents, and completing camp progression |
| Pixie Blessing | Party route state | Blessing active and bell retained | Requires freeing Dolly from Kar'niss's lantern |
| Halsin | Recruited companion | Portal defended, Oliver reunited, Halsin selectable | Fails if Halsin or portal is lost; he leaves if curse remains unresolved |
| Jaheira | Recruited companion | Selectable after Ketheric and Moonrise follow-up | Fails if she dies during Last Light or assault |
| Minthara | Conditional recruited companion | Escorted from Moonrise and selectable | Requires an Act 1 survival state and prison rescue |
| Us | Permanent summon | Summon Us item available | Requires Nautiloid survival and Colony rescue |
| Astarion scar knowledge | Companion quest state | Raphael's explanation scene completed | Requires completing Raphael's Yurgir deal rather than freeing Yurgir |
| Karlach engine progression | Companion quest state | Dammon's Act 2 work and dialogue complete | Dammon must survive and be visited before leaving |
| Wyll and Mizora | Companion quest state | Mizora freed, Wyll retained, rapier outcome recorded | Wrong Colony control can permanently lose both reward and companion |
| Shadowheart Selunite path | Companion quest state | Aylin spared, Shadowheart remains, camp reward collected | Mutually exclusive with Dark Justiciar path |
| Dame Aylin and Isobel | Camp and ally state | Both survive and join the good-route camp outcome | Lost if Isobel or Aylin dies |
| Lifted Shadow Curse | World and Halsin state | Thaniel and Oliver reunited, Ketheric dead, healing departure cutscene seen | Leaving without full chain fails the restoration |

## Mutually exclusive decision ledger

| Decision | Recommended good route | Alternative and cost |
|---|---|---|
| Strange Ox | Spare it for Act 3 continuity | Kill for Hat of Fire Acuity and end its later quest |
| Astarion and Araj | Respect Astarion's refusal | Coerce bite for Potion of Everlasting Vigour, losing approval and agency-respecting outcome |
| Gale and ritual circle | Destroy the circle | Create Shadow Lantern and give up the good Mystra-aligned choice |
| He Who Was and Madeline | Forgive Madeline | Apply He Who Was's accepted punishment for Raven Gloves |
| Yurgir | Kill him under Raphael's deal | Free him by killing Lyrthindor, breaking Raphael's scar bargain and altering later disposition |
| Dame Aylin | Spare and free her | Kill her for Dark Justiciar Shadowheart and Shar's Spear of Evening, with severe good-route losses |
| Shadowheart | Trust her to spare Aylin | Command or fight her, risking permanent departure or death |
| Ketheric colony dialogue | Fight the manageable first phase after clearing adds | Pass DC 18 to skip directly to Apostle while adds remain |

## Coverage index

### Main and hub quests

- Seek Protection from the Shadow Curse: route 1-7.
- Infiltrate Moonrise Towers: route 3-12 and 28-29.
- Resolve the Abduction: route 4-5.
- Rescue the Tieflings: route 4, 8, 11, and 13.
- Rescue Wulbren: route 4, 11, 13, and 32.
- Decide Minthara's Fate: route 9 and 12 when applicable.
- Lift the Shadow Curse and Wake Art Cullagh: route 4, 17, 19-20, 31-32.
- Find Ketheric Thorm's Relic and Find the Nightsong: route 23-27.
- Defeat Ketheric Thorm: route 28-32.

### Side and companion quests

- Find Rolan in the Shadows: route 8 and 13.
- Find Arabella's Parents: route 8 and 17.
- Investigate the Selunite Resistance: route 14.
- Punish the Wicked: route 16 and 18.
- Kill Raphael's Old Enemy and Break Yurgir's Contract: route 24.
- Daughter of Darkness: route 25-27.
- The Pale Elf and Raphael's scar bargain: route 24.
- The Hellion's Heart: route 4.
- The Wizard of Waterdeep and Balthazar's Experiment: route 12.
- The Blade of Frontiers, Mizora, and the Infernal Rapier: route 30.
- Find Zevlor: route 30.
- Find Mol: intake at Last Light, scripted abduction at route 5, then continue in Act 3; she is not a Colony prisoner.
- The Urge: Isobel refusal at route 5 and Kressa history at route 30.

## Import blockers

- Perform an in-game review on the current supported patch, especially Shadowheart's Nightsong decision logic, Dark Urge restraint checks, trader stock gates, and the Infernal Rapier reward dialogue.
- Decide whether non-combat audits remain route records or become decision/checklist records in a normalized Act 2 schema.
- Assign real `sourceRow` values only if the project spreadsheet gains authoritative Act 2 rows.
- Add exact map pins only after each coordinate passes the workbook's `Exact reviewed pin` standard. Existing `data/gear/act2.tsv` coordinates are item anchors, not proof that every route milestone has a reviewed marker.
- Convert the accepted records to a separate Act 2 route data file, add schema validation and order/dependency tests, then deliberately set `routeAvailable` only after native UI verification.
- Keep all app-visible claims labelled as guide fact, reviewed suggestion, or unknown, as required by the workbook contract.

## Primary source set

- Shadow-Cursed Lands: https://bg3.wiki/wiki/Shadow-Cursed_Lands
- Curse protection: https://bg3.wiki/wiki/Seek_Protection_from_the_Shadow_Curse
- Main infiltration: https://bg3.wiki/wiki/Infiltrate_Moonrise_Towers
- Isobel defence: https://bg3.wiki/wiki/Resolve_the_Abduction
- Tiefling rescue: https://bg3.wiki/wiki/Rescue_the_Tieflings
- Wulbren rescue: https://bg3.wiki/wiki/Rescue_Wulbren
- Curse lifting: https://bg3.wiki/wiki/Lift_the_Shadow_Curse
- Gauntlet: https://bg3.wiki/wiki/Gauntlet_of_Shar
- Shadowfell event horizon: https://bg3.wiki/wiki/Shadowfell
- Nightsong chain: https://bg3.wiki/wiki/Find_the_Nightsong
- Ketheric and Colony: https://bg3.wiki/wiki/Defeat_Ketheric_Thorm
- Honor catalog: https://bg3.wiki/wiki/Legendary_actions
- Apostle of Myrkul: https://bg3.wiki/wiki/Apostle_of_Myrkul
