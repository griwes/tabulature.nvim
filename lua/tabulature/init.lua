local M = {}
local style_subscription = nil

local function option_label(opts, fallback)
    return require('tabulature.manifold')._option_label(opts, fallback)
end

local function define_command(name, callback, opts)
    pcall(vim.api.nvim_create_user_command, name, callback, opts or {})
end

local function install_commands()
    define_command('TabulatureNewTab', function(command)
        M.create_tab({ label = command.args ~= '' and command.args or nil })
    end, { nargs = '?' })
    define_command('TabulatureNewSubtab', function(command)
        M.create_subtab({ label = command.args ~= '' and command.args or nil })
    end, { nargs = '?' })
    define_command('TabulatureNewNested', function(command)
        M.create_nested({ label = command.args ~= '' and command.args or nil })
    end, { nargs = '?' })
end

local function setup_theme(opts)
    if opts.theme == false then
        return
    end

    local theme_opts = type(opts.theme) == 'table' and opts.theme or {}
    require('tabulature.themes.lualine').setup(theme_opts)
end

local function subscribe_to_statuesque_style()
    if style_subscription ~= nil then
        return
    end

    local ok, statuesque = pcall(require, 'statuesque')
    if not ok or type(statuesque.on_style_change) ~= 'function' then
        return
    end

    style_subscription = statuesque.on_style_change(function()
        pcall(vim.cmd, 'redrawtabline')
        pcall(vim.cmd, 'redrawstatus')
    end)
end

--- Configure optional Tabulature integrations.
--- Tabline rendering is owned by Statuesque; Tabulature only provides the
--- `statuesque.widgets.tabulature()` component consumed by that surface.
--- @param opts? { manifold?: boolean|table, commands?: boolean, theme?: boolean|table, style?: 'inherit'|'slanted'|'capsule'|string }
function M.setup(opts)
    opts = opts or {}
    require('tabulature.config').configure({
        style = opts.style,
    })
    subscribe_to_statuesque_style()
    setup_theme(opts)
    if opts.commands ~= false then
        install_commands()
    end
    if opts.manifold ~= false then
        local manifold_opts = type(opts.manifold) == 'table' and opts.manifold or {}
        require('tabulature.manifold').auto_setup(manifold_opts)
    end
end

--- Create a top-level Neovim tab in Tabulature's hierarchy.
--- @param opts? string|{ label?: string }
--- @return integer tabpage
function M.create_tab(opts)
    opts = opts or {}
    local state = require('tabulature.state')
    return state.create_child(state.get_root_id(), option_label(opts))
end

--- Create a Neovim tab nested below the current Tabulature tab.
--- @param opts? string|{ label?: string, parent_id?: any }
--- @return integer tabpage
function M.create_subtab(opts)
    opts = opts or {}
    local parent_id = type(opts) == 'table' and opts.parent_id or nil
    local state = require('tabulature.state')
    parent_id = parent_id or state.get_current_tab().id
    return state.create_child(parent_id, option_label(opts))
end

--- Create a chain of real Neovim tabs below the current Tabulature tab.
--- @param opts? string|{ label?: string, depth?: integer }
--- @return integer[] tabpages
function M.create_nested(opts)
    opts = opts or {}
    local depth = type(opts) == 'table' and tonumber(opts.depth) or nil
    depth = math.max(depth or 2, 1)
    local label = option_label(opts, 'Nested')
    local state = require('tabulature.state')
    local parent_id = state.get_current_tab().id
    local ids = {}
    for index = 1, depth do
        local id = state.create_child(parent_id, string.format('%s %d', label, index))
        ids[#ids + 1] = id
        parent_id = id
    end
    return ids
end

--- Publish the current hierarchy to any detected external consumers.
--- @param opts? table
--- @return integer
function M.publish(opts)
    return require('tabulature.state').publish_manifold(opts)
end

return M
