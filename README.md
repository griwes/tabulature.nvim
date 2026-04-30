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
