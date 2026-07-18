# Act 3 Honor Mode route research

**Status:** App-ready, source-reviewed route data

**Research date:** 2026-07-18

**Game basis:** Patch 8 and later hotfixes listed by bg3.wiki through Hotfix 36

**Intended run:** Good-aligned Honor Mode with companion finales and the major rescue outcomes preserved

## Shipped data

- `data/act3_fights.json`: 13 checkpoint summaries.
- `data/act3_route.json`: ordered encounter preparation, failure conditions, completion checks, and Honor mechanics.
- `data/act3_walkthrough.json`: 19 player-facing route steps.
- `data/act3_timed_events.json`: 9 trigger-based deadlines and lockouts.
- `data/acts/act3.json`: route enabled, with an external Baldur's Gate map handoff.

The route API serves these records only for Act 3. Nullable source rows and coordinates are intentional: Act 3 uses direct public sources and area names rather than fabricated spreadsheet rows or MapGenie coordinates.

## Route assumptions

- Loot Prelate Lir'i'c during the one-time Astral Plane transition into Act 3 if the Open Hand Monk plan needs the Boots of Uninhibited Kushigo.
- Attend Gortash's coronation peacefully. This moves Duke Ravengard to the Iron Throne and avoids fighting the audience hall's Steel Watchers.
- Triage the Lower City deadlines as soon as their local trigger fires. Most Act 3 quests are safe to postpone; Florrick, Cora, Devella, Stop the Presses, Volo, and the Iron Throne are not.
- Recruit Minsc and use controlled side quests to reach level 12 before the companion finales and Chosen fights.
- Resolve Orin before breaking Gortash's bargain. This is the reviewed low-risk order, not a claim that the game requires Orin before the Iron Throne.
- Complete the Iron Throne before destroying the Steel Watch Foundry or killing Gortash.
- Treat the House of Hope, Cazador, Viconia, and Ansur as optional. The route asks the player to complete or explicitly skip them before the Morphic Pool audit.
- Carry all three Netherstones. The Act 2 stone from Ketheric remains required alongside Orin's and Gortash's.

## Final lockout

Using the Morphic Pool skiff ends ordinary access to camp, storage, party changes, and Withers. The player must move equipment and consumables before boarding.

The failed domination attempt then forces a rest in the Astral Prism. That rest removes elixirs and other Until Long Rest effects, so the route delays those buffs until afterward. The final encounter has two separate clocks: an outer four-turn counter before Nautiloid bombardment and an inner countdown that ends the run if the Netherbrain survives. The game and wiki expose the inner counter; the five-turn value is retained from current in-game/community corroboration because the wiki does not print its number.

## Honor mechanics reviewed

- Cazador: ritual sources, three-round ritual risk, and Vampiric Swarm push damage.
- Raphael: Soul Pillars determine legendary-action charges; Ascended Raphael changes the action to Soul Ascension.
- Sarevok: Murderous Retort and the risk of empowering him by killing the Echoes first.
- Orin: Sanguine Lash, Bhaal's Edict, Unstoppable, and the separate Dark Urge duel branch.
- Steel Watcher Titan: Honor Bulwark, Hellfire Missiles, and Flashblinder removal.
- Ansur: Draconic Wrath and the Unrelenting Storm final phase.
- Gortash: Tyrant's Curse persists after his death until removed or detonated.
- Netherbrain: Aegis of the Absolute, Retributive Brainquake, Orbs of Negation, and the inner loss timer.

## Primary sources

- [Larian Patch 8 release notes](https://baldursgate3.game/news/the-final-patch-new-subclasses-photo-mode-and-cross-play_138)
- [bg3.wiki patch index](https://bg3.wiki/wiki/Patch_notes)
- [Act Three](https://bg3.wiki/wiki/Act_Three)
- [Time-sensitive activities](https://bg3.wiki/wiki/Time-sensitive_activities)
- [Confront the Elder Brain](https://bg3.wiki/wiki/Confront_the_Elder_Brain)
- [Iron Throne](https://bg3.wiki/wiki/Iron_Throne)
- [Morphic Pool](https://bg3.wiki/wiki/Morphic_Pool)
- [Orin combat](https://bg3.wiki/wiki/Orin/Combat)
- [Raphael combat](https://bg3.wiki/wiki/Raphael/Combat)
- [The Netherbrain combat](https://bg3.wiki/wiki/The_Netherbrain/Combat)

Every encounter and walkthrough record also carries its direct source URL. All cited JSON URLs returned successfully during the 2026-07-18 audit.

## Product boundary

This guide recommends one conservative sequence. It does not infer quest completion, promise dialogue outcomes, or auto-complete a step. The player owns all progress and branch decisions.

Act 2 remains `routeAvailable: false`. Normal app progression cannot enter Act 3 until the Act 2 research is converted and tested; that restriction is deliberate and independent of the Act 3 dataset.
