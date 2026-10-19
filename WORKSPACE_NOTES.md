# Workspace notes (Star Wars: Legion TTS mod)

Personal setup + context snapshot, written 2026-10-19 for picking this work up
on another computer. Not meant for the upstream repo.

## Before leaving the old machine

- **`test-build` is local only** (53 commits on top of `origin/Han-and-Chewie`,
  no remote has it). Push it if you want it elsewhere:
  `git push fork test-build`.
- Uncommitted: `.gitignore` adds `.tts` (the TTS Tools extension's working
  folder). Commit or redo.
- The latest shareable build lives outside git:
  `~/Downloads/SWL Test Build 2026-10-16 LOS16.json`. Copy it if needed (or
  rebuild with `npm run compile` from `test-build`).
- Claude's memory for this project is in
  `~/.claude/projects/-Users-rbowensv-Documents-github-tts/memory/`. The folder
  name comes from the repo path; if the repo lives at the same path on the new
  machine, copying the folder carries it over. Everything important in it is
  summarized below anyway.
- Mission builder plan file: `~/.claude/plans/encapsulated-wandering-kahan.md`
  (finished work; only needed for history).

## Remotes

| Remote     | URL                                    | Role |
|------------|----------------------------------------|------|
| `upstream` | https://github.com/swlegion/tts        | original project |
| `origin`   | https://github.com/halestom15/tts      | the active community fork; integration branch is **`Han-and-Chewie`** |
| `fork`     | git@github.com:rbowensv/tts.git (SSH)  | my fork; push feature branches here |

New feature branches should be based on `origin/Han-and-Chewie`, not `main`.
PRs into Han-and-Chewie get no CI (the workflow only runs on `main`).

## Branches

- `test-build` (local): my integration build = Han-and-Chewie + PRs #29 #31 #32
  #35 + Mac fix + mission builder + all the LOS work. Every change lands on a
  topic branch, then gets merged into here ("Merge X into test build").
- `mission-builder-2024` → fork, PR #38 (open).
- `los-speedup` → fork (17 commits on #29's head `cf77112`). Not its own PR;
  suggested as a comment on PR #29.
- `mac-dev-setup` → fork, PR #36. `format-official-json` → fork, PR #39.
- `mission-setup-2024`: old, based on main, stale. Ignore.

Open PRs on halestom15/tts as of 2026-10-19: #39, #38, #36 (mine);
#35, #32, #31, #29 (ironsquadronfr-hub, all merged into `test-build`).

## Machine setup (macOS)

- Node (had v26), `npm install`. Lua 5.2+ via `brew install lua` (had 5.5) for
  `npm run test:los` and `npm run test:lua`. `luacheck` was not installed.
- Upstream README says Windows only; PR #36 adds Mac support.
- **TTS folder access gotcha:** macOS blocks TTS from following a symlink into
  `~/Documents`. So reverse the link: the real files live in
  `~/Library/Tabletop Simulator/Saves/TTSDevLink/`, and the repo's `dist` is a
  symlink to that folder:
  `ln -s ~/Library/Tabletop\ Simulator/Saves/TTSDevLink dist`.
  Nothing TTS loads should live under the repo path.
- Build: `npm run compile` (writes `dist/StarWarsLegion.json`).
  `npm run extract` pulls a save back into `mod/src`. After a played table,
  extract **selectively** (only objects you moved/added/removed): a played
  save adds ~400 noisy files. Never extract the empty Setup Crate (`d3f3a0`).
- Shareable builds: export to `~/Downloads/"SWL Test Build <date> <tag>.json"`.

## VS Code + TTS Tools MCP

- Extension: **TTS Tools (Community Fork)**, `eunomiac.tts-tools` (was 3.1.0).
  Its gateway owns TTS's editor ports (39998, control 39997), so a plain
  External Editor API client never gets replies. Use its MCP server:
  `node ~/.vscode/extensions/eunomiac.tts-tools-<ver>/dist/mcp/server.js`
  (stdio). Tools: `tts_execute_lua` (arg is `script`, not `code`),
  `tts_send_custom_message`, `tts_status`. No GUID = runs in Global.
- `tool/los/live.mjs` wraps it (`status`, `read`, `hotload`). It finds the
  extension in `~/.vscode/extensions` automatically.
- It is not registered as an MCP server in Claude Code; Claude drives it
  through `live.mjs` or a small script.

## Working agreements with Claude

- **No auto PRs.** Commit on a branch and push to `fork`, then give me the
  `https://github.com/rbowensv/tts/pull/new/<branch>` link and a draft
  description. Only run `gh pr create` when I ask.
- **Debugging the table:** ask me for a manual save (and a name) while the
  state is on screen, then read the newest file in
  `~/Library/Tabletop Simulator/Saves/`. Don't dig through autosaves.
- **Live game:** read-only queries and memory-only hot-loads are OK when I've
  approved them. Ask before anything that changes the table.
- Posting comments on GitHub needs my OK on the text first.

## Line of sight (current main thread)

Engine: `mod/src/includes/LineOfSight.ttslua` (a Global include). Tools and
docs: `tool/los/README.md`.

Why it moved from #29's token script: each order token ran its own copy, so the
mesh cache was empty on every unit's first attack, and the 16x16 grid tested
thousands of triangles per line. Now there is a shared cache, a BVH per mesh,
resumable parse jobs, background prefetch, and frame budgets. Tokens send a
request and get a `losVerdictDone` callback.

Facts found along the way:
- TTS mirrors OBJ X on import, so `losMeshBuild` negates x.
- Nested coroutines work in TTS. If LOS hangs, check `losMeshAdvance` first.
- Asset-bundle terrain (e.g. Alderaan spires, landspeeders) has no OBJ. It
  blocks by visual box, refined by `Physics.cast` against its collider.

Rules I chose (keep them):
- Obscured = no clear line from the leader, OR a line blocked by terrain
  within range ½ (3") of the defender's base edge and not in base contact
  (0.05") with the leader, measured to the real mesh. Cover if ≥ half the
  minis are obscured.
- Area terrain: a defender touching or inside it is obscured, no LOS needed.
- POIs: heavy-cover area terrain (token-wide cylinder, 3" tall). Cover only,
  never block. They don't count toward "completely blocked".
- Cover type comes from the piece's name/description ("- Heavy Cover",
  "Cover: Light", "[Light Cover]", conditional text). If none is given, the
  panel asks "heavy or light?" and players decide.
- Vehicles: only ground vehicles and Hover: Ground repulsors (Infantry Support
  Platform, Saber-Class Tank, WLO-5 Speeder Tank, AAT Battle Tank, A-A5
  Speeder Truck; card field `"hover": "ground"`) block and give cover. A
  repulsor with an unknown card still blocks. They block at any distance but
  give cover only within ½, and it's always **heavy**. Touching a vehicle does
  NOT give cover (reverted). Shape = stadium prism from the collider footprint,
  from the bottom of the base to the card's `silhouette.height`.
- UI: rings per mini (green / yellow = obscured / red = unseen), summary panel
  `ui/LosSummary.xml`.

Status: waiting on ironsquadronfr-hub's reply to my PR #29 comment before
building more. Planned next: per-piece collider-vs-visual check for asset
bundles, right-click overrides, tag-based ignore for mod aids, explain a
verdict, honor "please ignore" / "Decorative", golden-table regression test.

## Mission builder 2024 (done)

TV game controller runs 2024 setup: 3/3/3 battle decks → reveal → 4
alternating modify turns → blue picks edge → cards to mounts. Playtested and
in PR #38. Confirmed rules: forcing the opponent's Advantage is allowed
(`ALLOW_FORCE_OPPONENT_ADVANTAGE = true`). Advantage mounts are seat-based
(`07a89d` nearer blue, `c6b3a9` nearer red). Zones are always drawn on blue's
side. "Far Edge" calls `flipMap()` first, so terrain must be loaded.

## Other findings

- Bundle materials (Silhouette shader): set props via
  `obj.getMaterialsInChildren()[1]` + `get`/`set` **before** `addAttachment`.
  After attaching, material calls throw a C# error that `pcall` can't catch.
  `Component.set` can't set int props.
- The stock Museum background paints over the vehicle silhouettes. Fixing it
  needs a rebuilt bundle (e.g. ZWrite On); Lua can't fix it.
