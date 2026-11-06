# Spiritbound

Endless-survival bathhouse game for Roblox. Keep the seal intact for as many nights as you can.

## Layout

| Folder | Syncs to | What goes here |
| --- | --- | --- |
| `src/Shared` | `ReplicatedStorage.Shared` | Modules both server and client use (Config, types, utilities) |
| `src/Server` | `ServerScriptService.Server` | Server-only logic: night loop, economy, seal, deals |
| `src/Client` | `StarterPlayer.StarterPlayerScripts.Client` | HUD, input, local effects |
| (project file) | `ReplicatedStorage.Remotes` | RemoteEvents / RemoteFunctions, created by server code at runtime |
| (project file) | `ServerStorage.Assets` | Prefabs the server clones (guests, props) |

The server decides everything that matters (coins, tokens, seal). Clients only send requests.

## Working with Rojo

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` here to get Rojo.
2. In Studio, install the Rojo plugin: `rojo plugin install`.
3. Start the sync server: `rojo serve`.
4. In Studio, open the Rojo plugin and press **Connect**.

While connected, edit scripts in your editor, not in Studio. Rojo overwrites the Studio copies.

## Git

- `main` is always a working build.
- One branch per feature (`night-loop`, `deal-offer`, ...), merge when it runs without errors.
- Never commit `.rbxl` files. Studio keeps the place; Git keeps the code.
