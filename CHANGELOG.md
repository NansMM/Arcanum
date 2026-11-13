# Arcanum changelog

## 2.1.0 — 2026-11-13

- Arcane Power active: its icon, ringed in purple, shows above the charges with its time left, next to Presence of Mind and Eureka.
- The demo (`/arc demo`) now plays the proc sounds, so you can hear your choices without waiting for a fight. It also shows Arcane Power.

## 2.0.0 — 2026-11-13

- Arcanum now follows your game client's language. English is built in, French is fully translated, other clients show English. Spell names still come from the game, so procs and reminders work in every language.
- Arcanum's settings also appear in the game's Options > AddOns list. `/arc` still opens its own window, which works everywhere, combat included.
- Commands are English: `/arc lock`, `/arc scale 120`, `/arc spread 150`, `/arc sounds`, `/arc sound barrage 888`, `/arc sound barrage voice`. The French ones (`/arc verrou`, `/arc taille`, `/arc ecart`, `/arc sons`, `/arc son`) still work.
- Lighter engine: the old next-spell advice (rotation, burst, multi-target mode, cooldown and mana tracking) was still computed ten times a second although nothing displayed it any more. It is removed; Arcanum now only tracks what it shows.
- Leftovers of the old circle HUD are removed (two textures, unused colors and settings). Old settings are cleaned from your saved variables; your sound choices, position, size and spread are kept.
- Fixed: proc icons could flash for an instant at the start of a fight after a decoration preview, or after switching the HUD off and on.
- Fixed: a proc already on you was announced a second time after a loading screen or after stopping the demo.
- Fixed: with the HUD switched off in the settings, proc sounds still played.
- Fixed: the demo left the last reminders on screen.
- Fixed: Missile Barrage could be announced again right after Arcane Missiles spent it, on clients where only the button glow shows it.
- Fixed: changing the size moved a HUD that had been dragged away from the center. Your saved position is converted.
- The "Also show out of combat" setting is removed: since 1.0 there was nothing left for it to show.
- Fewer game calls when aura events rain (raids), and fewer display calls per frame.
- The repository, the code comments and the tests are now in English.

## 1.5.1 — 2026-11-13

- The game's charge orbs, added in 1.5.0, are removed: those images are made to be shown very small, and enlarged above the character they were pixelated. Charges go back to crystals, one per charge.

## 1.5.0 — 2026-11-13

- Charges as the game's orbs: Arcane Blast charges are shown with the artwork Blizzard painted for the Arcane mage (a base, four orbs, and a flash, a halo and a circle of runes each time a charge is gained or lost), assembled and animated as in the original interface, only larger.
- If your client does not have these images, Arcanum keeps its crystals, without asking you anything. `/arc diag` says whether they were found. The "Charges as the game's orbs" setting also lets you go back to the crystals.

## 1.4.0 — 2026-11-13

- A single proc decoration: the game's rune arc (the former "Game art"), now shown by default. The four decorations drawn by Arcanum (crescents, diamond, rune ring, spark) are removed, along with their textures.
- The "Proc decoration" setting becomes a simple toggle; `/arc decor` shows or hides it. Turning it on shows it on the HUD right away.

## 1.3.2 — 2026-11-13

- Fixed: in the settings preview, the proc decoration was too bright. The echo used as the light wave stayed lit on top of the decoration after a change of decoration or setting, until the next proc.
- Each preview replays the wave, even if both procs are already shown.

## 1.3.1 — 2026-11-13

- The light wave when a proc arrives matches the theme of the chosen decoration: it is an echo of that decoration, which widens and fades, instead of a ring. With no decoration, the ring remains.
- "Game art" decoration: both procs now have the same rune-engraved arc, purple for Barrage, tinted blue for Clearcasting. The previous blue arc was thinner and paler than the other.

## 1.3.0 — 2026-11-13

- New proc decoration, "Game art" (`/arc decor jeu`): the large arcs Blizzard painted for its own proc alerts, read from the game files. The rune-engraved purple arc of Arcane Missiles for Missile Barrage, an ornate arc tinted blue for Clearcasting. If your client does not have these images, the decoration stays empty: pick another one.
- The "Target charges" setting is removed: all it still did was count empty crystals. There is now one crystal per charge, and they lighten at four charges.

## 1.2.0 — 2026-11-13

- Eureka active: its icon, ringed in gold, is shown above the charges with its remaining time, for as long as the buff lasts. If Presence of Mind is active at the same time, the two icons sit side by side.

## 1.1.0 — 2026-11-13

- Water and food reminders: only conjured items count (bought water no longer exempts you from conjuring some). The items from every rank of Conjure Water and Conjure Food in Forever are recognized.
- The mana gem reminder is back: it shows when the best gem you know how to conjure is not in your bags.
- Charges are only shown when you have some: with no charge, no more empty crystals.
- Procs show their own icon (Clearcasting, Missile Barrage) instead of that of the spell to cast.
- The burst signal is removed (icon, sound, reminder, settings). In its place, above the charges: the Presence of Mind icon, for as long as it is active.
- Proc decoration: a decoration surrounds each proc icon, in its color, for as long as the proc is up. Four decorations to choose from (crescents, diamond, rune ring, spark) or none, in the settings or with `/arc decor`. New textures are added: quit and restart the game after updating (a `/reload` does not see them).
- Default proc sounds: the Clearcasting spell's sound for Clearcasting, the Arcane Missiles sound for Barrage (in place of the Battle.net notification and the minimap ping, which stay in the list).
- The settings fit in one column again.

## 1.0.0 — 2026-11-13

Arcanum starts over on new foundations: the circle gives way to four zones around the character.

- To the left of the character, Clearcasting; to the right, Missile Barrage: a large icon with the remaining time, only when the proc is active.
- At the top, the Arcane Blast charges: one crystal per target charge, and below them the bar of their 18-second window, with the seconds.
- Above the charges, at the burst moment only: the icon of the spell to cast, in gold (Arcane Power, then the burst macro's Wrath). The sound, the wave and the reminder after 6 seconds are kept.
- At the bottom, out of combat: reminders of what is missing. Arcane Intellect and armor, as before, plus water and food when your bags have run out. The mana gem reminder is removed. While resting in a city, the reminders are not shown.
- New "Spread" setting (`/arc ecart 150`): the distance between the character and the zones. The HUD is re-centered on the screen when you update.
- Removed: the circle, the next-spell advice (and `/arc conseil`, `/arc aoe`), the cooldown gems, the mana bar, and the settings that went with them.

## 0.12.2 — 2026-11-12

- Tracking-only mode: with the burst macro ("Burst as one icon" setting, on by default), the center icon shows Arcane Wrath directly instead of Eureka then Presence of Mind: a single key does it all. Arcane Power, which is not in the macro, keeps its icon.

## 0.12.1 — 2026-11-12

- Tracking-only mode: at the burst moment, the icon of the spell to cast is shown in the center of the circle, ringed in gold. The center used to stay empty. It follows the burst order (Arcane Power, then Eureka, then Presence of Mind, then the Wrath that benefits from them) and disappears if a proc is shown there.

## 0.12.0 — 2026-11-12

- "Almost ready" gem: ten seconds before a cooldown ends, the gem gets its colors back, takes a golden edge and counts down the seconds. "Cooldown almost over" setting (5 to 30 seconds, or "no").
- Burst reminder: if the signal stays lit for 6 seconds without you casting a major cooldown, the golden wave and the sound are given once more. Casting one of them restarts the delay for the next ones. "Burst reminder" setting (2 to 12 seconds, or "no"). In tracking-only mode.
- Sounds are picked by name in the settings: one row per signal (Clearcasting, Barrage, Burst), two arrows to step from one sound to the next while hearing it. About fifteen game sounds, plus the game voice, which says the word ("Burst") if a text-to-speech voice is installed. `/arc son burst voix` does the same thing.
- The settings window moves to two columns: it was getting too tall.

## 0.11.0 — 2026-11-12

- A sound when it is the burst moment (the warrior's Recklessness, by default). It plays once when the moment arrives, in tracking-only mode as in advice mode, and is not replayed if the signal goes off and comes back within 8 seconds.
- Sounds can be chosen: `/arc son 888` plays a game sound, `/arc son burst 888` picks it for the burst moment (`clear` or `barrage` for the procs), `/arc son burst` goes back to the default sound. An ID the game does not play is not kept.
- `/arc sons` plays the three sounds and says which ones are played.

## 0.10.0 — 2026-11-12

- Tracking-only mode: Arcanum signals the burst moment. When the target charges are reached, Wrath is ready and no proc has to be spent first, the gems of the ready cooldowns (Eureka, Presence of Mind…) grow and pulse in gold, the ring turns gold and a golden wave spreads from the circle. The "Signal the burst moment" setting (formerly "Advise major cooldowns") turns it off.
- Target charges reached: the crystals and the arc turn very light purple instead of pink, which was too close to Missile Barrage's. They no longer pulse continuously: pulsing is reserved for what calls for an action (procs, burst).
- The charge window arc reads better: the ring fades into a dark track beneath it as long as there are charges.

## 0.9.2 — 2026-11-12

- The demo (`/arc demo`) now plays in the chosen mode. In tracking-only mode, it shows the charges building up, the procs in the center (one, then two side by side) and the cooldowns, with no advice. Until now it always showed advice mode.

## 0.9.1 — 2026-11-12

- Tracking-only mode: active procs are shown as large icons in the center of the circle, in place of the advice. The icon is that of the spell the proc improves (Missiles for Barrage, Arcane Blast for Clearcasting), ringed in the proc's color, with the remaining time. One proc: one centered icon; two: side by side. The bottom orbs are now only used in advice mode.

## 0.9.0 — 2026-11-12

- "Tracking-only" mode: the "Advised next spell" setting (or `/arc conseil`) hides the center icon. The circle then shows only the charges, their window, the procs and the major cooldowns, without advising anything.

## 0.8.3 — 2026-11-12

- "Anticipate" setting: during a Frostbolt or a Fireball, Arcanum still announced a free Arcane Blast even though the spell being cast was going to spend Clearcasting. The anticipation now takes this into account.

- Diagnostics: the log keeps 120 changes instead of 60, and the volleys of a channeled spell fit on one line ("spell missiles x6") instead of filling it up. It also records the delay between Presence of Mind and the Wrath that follows, to tell whether the burst macro casts them on the same key press.

## 0.8.2 — 2026-11-12

- Burst macro: Wrath did not go off on the same key press as Eureka and Presence of Mind. `/arc macro` now separates the spells with `/stopcasting`, the classic form of this macro. Run `/arc macro` again to update yours. Warning: pressed during a cast, the macro interrupts it.

## 0.8.1 — 2026-11-12

Based on a combat report (`/arc diag`).

- Mana: the game hides it in combat, which made the "gem then Evocation below 15% mana" rule ineffective. Arcanum now estimates it from what the game still tells: if a spell that costs less than 15% of your maximum mana becomes unaffordable, you are below 15%.
- Presence of Mind cast before combat stayed marked "active" for the whole fight, which could cause Wrath to be advised wrongly. The first spell with a cast time ends it.

## 0.8.0 — 2026-11-12

Design review: every element had to justify its place.

- Crystals: only one per target charge (two by default), above the circle and slightly larger. One more crystal appears when the game grants a charge. No more permanently unlit crystals, and the window arc is no longer cluttered by them.
- Procs: colored orbs with no icon, so they are no longer confused with the cooldowns.
- Center icon enlarged (64 instead of 56).
- Smaller waves, and none at all when the target charges are reached (the crystals already bounce).
- Removed: the halo behind the circle, the engraved runes and their setting.

Some textures have changed: quit and restart the game after updating.

## 0.7.2 — 2026-11-12

- Clearcasting during a cast: if the proc arrives during a Frostbolt or a Fireball, that cheap spell is the one that would spend it. Arcanum then advises interrupting: the icon switches to Arcane Blast, in light blue, with a fast-pulsing white edge. Nothing changes for a Missile Barrage (it waits for the end of the cast), nor when less than half a second of cast time remains. Configurable.

## 0.7.1 — 2026-11-12

Performance, cleanup and rotation review pass. Nothing changes on screen.

- Far fewer calls to the game: on the simulated game, 42 per second in combat instead of 530, and 13 instead of 114 when the HUD is hidden. Auras, costs, cooldowns, the target and the current cast are only re-read when the game signals a change; in combat, the auras the game classes as secret are no longer requested at all.
- Display: no more tables created every frame, idle crystals are no longer redrawn, and a hidden HUD does almost nothing.
- Lighter addon: four unused textures removed, three others shrunk (350 KB of textures instead of 600).
- Rotation: when the charge window is almost over (less than 4 seconds), Arcanum no longer advises building one more charge; it has you make use of the charges in place.
- Dead code removed; the test bench now checks the number of calls to the game and the absence of stray global variables.

## 0.7.0 — 2026-11-12

- Multi-target mode: it turns on when you cast an area spell (or with `/arc aoe` before the pull) and advises Flamestrike, Eureka, Presence of Mind, then Arcane Explosion. The circle turns orange.
- Filler rank: Frostbolt is advised at rank 1 by default, with a "1" on the icon; "max" setting for the highest rank.
- Burst as one icon: with the ArcBurst macro, Arcanum shows Wrath directly during Eureka and Presence of Mind (configurable).
- The icon turns red when the target is out of range.
- Pre-combat reminders, below the circle: Arcane Intellect, armor, missing mana gem.
- Diagnostics: new "Checked in game" section (mana readable or not in combat, Presence of Mind kept or not after Missiles, Frostbolt ranks).

## 0.6.2 — 2026-11-12

First version of the repository.

- Runic circle: the next spell in the center, the Arcane Blast charges at the top of the ring, the arc of their 18-second window, the major cooldowns on the sides, one gem per proc at the bottom.
- Next-spell advice: Missiles on a Barrage, a free Arcane Blast on Clearcasting, Wrath as an opener then once the target charges are reached (2 by default) with Eureka and Presence of Mind, Frostbolt as filler, mana gem and Evocation when mana runs short.
- Tracking in combat despite the hidden auras: spells cast, spell cost announced by the game, button glows, Cooldown Manager icons.
- `/arc macro` creates the burst macro with the exact spell names; `/arc diag` produces a report to copy.
