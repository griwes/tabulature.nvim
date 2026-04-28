# tabulature.nvim

Neovim tab manager, supporting tab hierarchies, per-tab sessions at any levels
of the tab hierarchy, with hooks into workspace/project management integrations.

Tabulature does not own the Vim tabline directly. It exposes a Statuesque render
component, and Statuesque owns installation and rendering of the actual tabline
surface.
