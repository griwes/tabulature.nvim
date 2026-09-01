# tabulature.nvim

Neovim tab manager, supporting tab hierarchies, per-tab sessions at any levels
of the tab hierarchy, with hooks into workspace/project management integrations.

## Status

Early development. Tabulature owns a hierarchy over real Neovim tabpages,
snapshot persistence, optional Continuity contribution, and optional Manifold
host/child synchronization.

## Requirements

- Neovim 0.11 or newer
- `statuesque.nvim` to render and install Tabulature's tabline component
- optional: `continuity.nvim` and `manifold.nvim`

Linux is the primary supported and CI-tested platform. The project currently
publishes from `main` without a stable release tag.

## Installation

With `lazy.nvim`:

```lua
{
    'griwes/tabulature.nvim',
    dependencies = {
        'griwes/statuesque.nvim',
    },
    opts = {
        style = 'inherit',
        manifold = false,
    },
}
```

Configure the Statuesque tabline with `{ name = 'tabulature' }`, or use its
default preset. Run `:checkhealth tabulature` after installation and see
`:help tabulature`.

## Commands

- `:TabulatureNewTab [label]` creates a top-level tab.
- `:TabulatureNewSubtab [label]` creates a child below the current tab.
- `:TabulatureNewNested [label]` creates a nested chain below the current tab.

## Lua API

- `require('tabulature').setup(opts)`
- `create_tab(opts)`, `create_subtab(opts)`, and `create_nested(opts)`
- `current_tab_id()` and `adopt_current_tabpage(opts)`
- `publish(opts)`

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

## Development

Run `scripts/ci/run.sh` for formatting and tests.

## License

Apache-2.0. See [`LICENSE`](LICENSE).
