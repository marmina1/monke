# monke — Feature Task List

> Status key:  ✅ Done · 🔶 Partial · ⬜ Planned · ❌ Dropped · ❌ Broken

---

## Core Gameplay

| Feature | Status | Notes |
|---|---|---|
| Basic movement (walk, jump) | ✅ Done | CharacterBody3D, gravity, WASD |
| Mouse-look (head pitch + body yaw) | ✅ Done | Sensitivity from GameSettings |
| Vine swinging (both hands) | ✅ Done | Physics pendulum + Verlet chain |
| Vine grab / release | ✅ Done | RayCast3D + ShapeCast3D; hand position fixed |
| Vine variants (twigs, sliders) | ⬜ Planned | Needed for non-jungle maps |
| Alternating-grab combo system | ✅ Done | Streak counter, emits `combo_changed` |
| Dynamic FOV (speed-based) | ✅ Done | Lerps up at high velocity |
| Speed lines screen effect | ✅ Done | CanvasItem shader on SpeedLines node |
| Poo mechanic — create (double-tap) | ✅ Done | Per-hand double-tap window |
| Poo mechanic — throw | ❌ Broken | Launch logic exists but not working |
| Poo mechanic — hit detection / effects | ❌ Broken | No damage/status on hit |
| Banana collectible (restores hunger) | ✅ Done | Area3D pickup, BananaSpawner |
| Hunger / starvation system | ✅ Done | Drains over time; starvation kills |
| Player death (hunger / fall) | ✅ Done | `die()` → `player_died` signal |
| Respawn / round reset | ✅ Done | Positions re-offset from SpawnPoint |

---

## Enemies & Hazards

| Feature | Status | Notes |
|---|---|---|
| Crocodile enemy (swamp areas) | 🔶 Partial | Basic patrol AI, no attack animation |
| Swamp kill zone | ✅ Done | CollisionArea kills on enter |
| Floor-kill in deathmatch | ❌ Dropped | `is_on_floor()` unreliable on puppets — replaced with lava plane |
| Rising lava plane (sudden death) | ✅ Done | Y-position kill; accelerating rise speed; orange emissive mesh |

---

## Maps

| Feature | Status | Notes |
|---|---|---|
| Swamp Forest | 🔶 Partial | Basic geometry; no detailed 3D art/models |
| Rainforest | 🔶 Partial | Basic geometry; no detailed 3D art/models |
| Red Canyon | 🔶 Partial | Basic geometry; no detailed 3D art/models |
| Moon Forest | 🔶 Partial | Basic geometry; no detailed 3D art/models |
| Map thumbnails (for selection cards) | ⬜ Planned | Image files needed per map |

---

## UI / HUD

| Feature | Status | Notes |
|---|---|---|
| Main menu | ✅ Done | Play, Settings, Quit |
| Settings menu (volume, FOV, sensitivity, display) | ✅ Done | Persisted via GameSettings autoload |
| Playground menu | ✅ Done | Singleplayer test with settings |
| In-game HUD (hunger bar, starvation warning) | ✅ Done | Connected via signals |
| Hide hunger HUD on death | ✅ Done | Cleared when `player_died` fires |
| Round / alive count / timer HUD | ✅ Done | Updated by LPS manager |
| Spectator bar HUD | ✅ Done | Shows currently watched player |
| Death label | ✅ Done | Shown on `player_died` |
| Combo label (×N) | ✅ Done | Animated colour gradient |
| Pause menu | 🔶 Partial | Single-player only; disabled in MP |
| Disconnect message on main menu | ✅ Done | Shown after kick / host-leave |

---

## Multiplayer (Core)

| Feature | Status | Notes |
|---|---|---|
| ENet host/join (IP + port 7777) | ✅ Done | Lobby autoload |
| Player list with names | ✅ Done | `Lobby.players` dictionary |
| Duplicate name disambiguation (1), (2)… | ✅ Done | `Lobby.display_name()` |
| Player name label above character | ✅ Done | Billboard Label3D on puppet |
| Player authority / network sync | ✅ Done | Transform RPC unreliable_ordered |
| Puppet capsule mesh (per-peer colour) | ✅ Done | Deterministic HSV from peer ID |
| Host disconnect → clients return to menu | ✅ Done | `server_closed` signal chain |
| Chat system (T to open, Enter to send) | ✅ Done | CanvasLayer 10, all scenes |
| Chat /kick command (host only) | ✅ Done | Target gets message + removed |
| Chat /ban command (host only) | ✅ Done | Peer ID blacklist, persists session |
| Banned player notified on rejoin | ✅ Done | `_rpc_notify_kicked` RPC |

---

## Lobby Room

| Feature | Status | Notes |
|---|---|---|
| 3D lobby with capsule avatars | ✅ Done | Hover to see name |
| Hover name labels | ✅ Done | Label3D hidden until mouse hover |
| Round count selector (host) | ✅ Done | SpinBox → GameSettings |
| IP display for sharing | ✅ Done | Local LAN IP shown on screen |
| Server settings panel | ⬜ Planned | Late-join toggle, room password |
| Late-join on/off (host setting) | ⬜ Planned | Needs server settings panel |
| Room password (host setting) | ⬜ Planned | Needs server settings panel |

---

## Selection Screen

| Feature | Status | Notes |
|---|---|---|
| 3D card stations (gamemode / map / buff) | ✅ Done | 3 stations with 3 cards each |
| SubViewport card rendering | ✅ Done | Sprite3D billboard overlay |
| Card top: image thumbnail area | ✅ Done | Coloured placeholder; real images ⬜ |
| Card bottom: item name | ✅ Done | Centred label in SubViewport |
| Card bottom: voter avatar circles | ✅ Done | Coloured circles with initials |
| Voting mechanic (click card) | ✅ Done | RPC to host, majority wins |
| 10-second voting timer | ✅ Done | Timer label, finalises on expire |
| Tie-break (random) | ✅ Done | Random selection among tied cards |
| Winning card highlight | ✅ Done | Scale-up + others fade |
| Real map/buff/gamemode thumbnail images | ⬜ Planned | PNG assets needed |
| Buff camera pivot animation | ✅ Done | AnimationPlayer in SelectionScreen |

---

## Last Person Standing Gamemode

| Feature | Status | Notes |
|---|---|---|
| Multiple rounds (configurable) | ✅ Done | Loaded from GameSettings |
| Accurate alive-count tracking | ✅ Done | Fixed: `_rpc_die` now emits `player_died` |
| Death order tracking | ✅ Done | `_death_order` array on host |
| Placement scoring (1st=3, 2nd=2, 3rd=1) | ✅ Done | `_award_round_points()` |
| Cumulative score across rounds | ✅ Done | Persisted in GameSettings |
| Sudden death after time limit | ✅ Done | 120s → rising lava plane + fewer bananas |
| Spectator mode (dead players) | ✅ Done | Camera cycle via LMB/RMB |
| Spectator auto-switch on target death | ✅ Done | `_refresh_spectate_targets()` |
| Round podium (scores after each round) | ✅ Done | CanvasLayer 9 overlay |
| Final match podium | ✅ Done | Shows "X WINS THE MATCH!" |
| Winner celebration cinematic | ✅ Done | Spotlight, confetti, camera orbit |
| Return to selection screen between rounds | ✅ Done | Saves state in GameSettings |
| Match end → main menu | ✅ Done | Clears LPS state |
| Player leave mid-round handled | ✅ Done | Treated as death |

---

## Buffs

| Feature | Status | Notes |
|---|---|---|
| Buff selection (voting) | ✅ Done | Card station exists in selection screen |
| Speed buff | ⬜ Planned | Not implemented |
| Jump buff | ⬜ Planned | Not implemented |
| Hunger drain reduction buff | ⬜ Planned | Not implemented |
| Arm reach buff | ⬜ Planned | Not implemented |
| Buff effects applied to player | ⬜ Planned | No buff logic exists yet |

---

## Other Gamemodes

| Feature | Status | Notes |
|---|---|---|
| Tag | ⬜ Planned | One player is "it", tag to pass |
| King of the Hill | ⬜ Planned | Hold a zone for points |
| Race | ⬜ Planned | First to reach goal wins |

---

## Polish / Later

| Feature | Status | Notes |
|---|---|---|
| Player customisation (skins / colours) | ⬜ Planned | Affects capsule + puppet colour |
| Sounds & music | 🔶 Partial | No audio assets yet |
| Crocodile attack animation | ⬜ Planned | |
| Poo hit effects (knockback / debuff) | ⬜ Planned | |
| Real images for selection cards | ⬜ Planned | PNG per map / buff / gamemode |
| Server browser (instead of manual IP) | ⬜ Planned | Would need a relay/master server |
| Relay / STUN (no port-forward needed) | ⬜ Planned | e.g. self-hosted Nakama or VPS relay |
| Steam integration | ❌ Dropped | Requires $100 Steamworks fee + accounts |
| Mobile port | ⬜ Planned | Touch controls needed |
