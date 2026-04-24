local M = {}

local function next_id(prefix)
    local manifold = require('tabulature.manifold')
    return manifold._next_id(prefix)
end

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

--- Configure optional Tabulature UI surfaces and integrations.
--- @param opts? { tabline?: boolean|table, manifold?: boolean|table, commands?: boolean }
function M.setup(opts)
    opts = opts or {}
    if opts.tabline then
        local tabline_opts = type(opts.tabline) == 'table' and opts.tabline or {}
        require('tabulature.tabline').setup(tabline_opts)
    end
    if opts.commands ~= false then
        install_commands()
    end
    if opts.manifold ~= false then
        local manifold_opts = type(opts.manifold) == 'table' and opts.manifold or {}
        require('tabulature.manifold').auto_setup(manifold_opts)
    end
end

--- Create a top-level tab in Tabulature's hierarchy.
--- @param opts? string|{ label?: string, id?: any }
--- @return any
function M.create_tab(opts)
    opts = opts or {}
    local id = type(opts) == 'table' and opts.id or nil
    id = id or next_id('tabulature-tab')
    local state = require('tabulature.state')
    state.add_tab(option_label(opts, 'Tab ' .. tostring(id)), id)
    state.set_current_tab(id)
    return id
end

--- Create a subtab below the current Tabulature tab.
--- @param opts? string|{ label?: string, id?: any, parent_id?: any }
--- @return any
function M.create_subtab(opts)
    opts = opts or {}
    local id = type(opts) == 'table' and opts.id or nil
    id = id or next_id('tabulature-subtab')
    local parent_id = type(opts) == 'table' and opts.parent_id or nil
    local state = require('tabulature.state')
    parent_id = parent_id or state.get_current_tab().id
    state.add_tab(option_label(opts, 'Subtab ' .. tostring(id)), id, parent_id)
    state.set_current_tab(id)
    return id
end

--- Create a deeper nested chain below the current Tabulature tab.
--- @param opts? string|{ label?: string, depth?: integer }
--- @return any[]
function M.create_nested(opts)
    opts = opts or {}
    local depth = type(opts) == 'table' and tonumber(opts.depth) or nil
    depth = math.max(depth or 2, 1)
    local label = option_label(opts, 'Nested')
    local state = require('tabulature.state')
    local parent_id = state.get_current_tab().id
    local ids = {}
    for index = 1, depth do
        local id = next_id('tabulature-deep')
        ids[#ids + 1] = id
        state.add_tab(string.format('%s %d', label, index), id, parent_id)
        parent_id = id
    end
    state.set_current_tab(parent_id)
    return ids
end

--- Publish the current hierarchy to any detected external consumers.
--- @param opts? table
--- @return integer
function M.publish(opts)
    return require('tabulature.state').publish_manifold(opts)
end

return M
