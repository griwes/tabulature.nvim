# tabulature.nvim

Neovim tab manager, supporting tab hierarchies, per-tab sessions at any levels
of the tab hierarchy, with hooks into workspace/project management integrations.

Tabulature does not own the Vim tabline directly. It exposes a Statuesque render
component, and Statuesque owns installation and rendering of the actual tabline
surface.

Tabulature contributes that component as `lua/statuesque/widgets/tabulature.lua`
on runtimepath. Statuesque consumes it through the normal `{ name = 'tabulature' }`
widget reference shape; Tabulature keeps the state lookup, rendering adapter, and
local tab actions in its own repository.

Session captures are backed by Tabulature-owned snapshot files. By default
`state_file` points at `stdpath('state')/tabulature.nvim/snapshots.json`, the
full hierarchy snapshots are written one JSON file each under `state_dir`, and
session-manager integrations receive only a stable `tabulature.snapshot`
reference. This keeps Tabulature usable with session managers other than
Continuity while avoiding duplicated tab-tree payloads in Continuity records.
