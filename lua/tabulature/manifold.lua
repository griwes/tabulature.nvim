local model = require('tabulature.model')
local state = require('tabulature.state')

local M = {
    _pending_tree_publishes = setmetatable({}, {
        __mode = 'k',
    }),
    _next_generated_id = 1,
    _auto = {
        scheduled = false,
        host_attached = false,
        child_attached = false,
        attempts = 0,
    },
}

--- Return Manifold child capability metadata for Tabulature.
--- @return table
function M.capabilities()
    return {
        plugin = 'tabulature',
        version = '0.1.0',
        protocol_version = 1,
        features = {
            'tree_snapshot',
            'statuesque_tabline_spec',
            'ext_tabline_fallback',
        },
        subscribe = true,
        snapshot = true,
    }
end

--- Normalize a tree for transfer to a Manifold host.
--- @param root table
--- @return table
function M.snapshot(root)
    return model.snapshot(root)
end

--- Build a tree update event for a Manifold host.
--- @param root table
--- @param opts? table
--- @return table
function M.tree_update(root, opts)
    opts = opts or {}
    return {
        kind = 'tabulature.tree_update',
        version = 1,
        root = M.snapshot(root),
        active_path = type(opts.active_path) == 'table' and vim.deepcopy(opts.active_path) or {},
        capabilities = M.capabilities(),
    }
end

local function publish_event(event)
    local state = vim.g.manifold_child_control
    if state == nil or state.attachments == nil then
        return 0
    end

    local published = 0
    for token, attachment in pairs(state.attachments) do
        local channel = attachment.channel
        if type(channel) ~= 'number' or channel <= 0 then
            channel = vim.fn.sockconnect('pipe', attachment.host_server, { rpc = true })
            attachment.channel = channel
            state.attachments[token] = attachment
            vim.g.manifold_child_control = state
        end

        if type(channel) == 'number' and channel > 0 then
            local ok = pcall(
                vim.fn.rpcnotify,
                channel,
                'nvim_exec_lua',
                [=[return require('manifold')._handle_child_suite_event(...) ]=],
                { token, event }
            )
            if ok then
                published = published + 1
            end
        end
    end

    return published
end

--- Publish a tree update to attached Manifold hosts.
--- @param root table
--- @param opts? table
--- @return integer
function M.publish_tree(root, opts)
    return publish_event(M.tree_update(root, opts))
end

--- Publish a tree whenever the watched root changes through tabulature.model.
--- @param root table
--- @param opts? table
function M.watch_tree(root, opts)
    opts = opts or {}
    model.watch(root, function(updated)
        if M._pending_tree_publishes[updated] then
            return
        end
        M._pending_tree_publishes[updated] = true
        vim.schedule(function()
            M._pending_tree_publishes[updated] = nil
            M.publish_tree(updated, opts)
        end)
    end)
end

--- Stop automatic tree publishing for a watched root.
--- @param root table
function M.unwatch_tree(root)
    M._pending_tree_publishes[root] = nil
    model.watch(root, nil)
end

local function manifold_module()
    local ok, manifold = pcall(require, 'manifold')
    if ok and type(manifold) == 'table' then
        return manifold
    end
    return nil
end

local function is_manifold_host(manifold)
    return manifold ~= nil and type(manifold.is_host) == 'function' and manifold.is_host()
end

local function has_child_attachment()
    local control = vim.g.manifold_child_control
    return type(control) == 'table' and type(control.attachments) == 'table' and next(control.attachments) ~= nil
end

--- Enable host-side Tabulature provider behavior inside a Manifold host.
--- @param opts? { surface?: string, install?: boolean }
--- @return boolean
function M.setup_host(opts)
    opts = opts or {}
    local manifold = manifold_module()
    if not is_manifold_host(manifold) or type(manifold.install_tabulature_provider) ~= 'function' then
        return false
    end

    return manifold.install_tabulature_provider({
        surface = opts.surface or 'tabline',
        install = opts.install ~= false,
    })
end

local function next_id(prefix)
    local id = string.format('%s:%d', prefix, M._next_generated_id)
    M._next_generated_id = M._next_generated_id + 1
    return id
end

local function option_label(opts, fallback)
    opts = opts or {}
    if type(opts) == 'string' then
        return opts
    end
    return opts.label or fallback
end

--- Enable child-side Tabulature publication to an attached Manifold host.
--- @param opts? { root_id?: string, root_label?: string }
function M.setup_child(opts)
    opts = opts or {}
    local root_opts = {
        id = opts.root_id or 'tabulature-child-root',
        label = opts.root_label or 'Child tabs',
    }
    state.enable_manifold_sync(root_opts)
    state.publish_manifold(root_opts)
end

--- Detect Manifold host/child context and enable the matching integration.
--- @param opts? { host?: table|false, child?: table|false, max_attempts?: integer }
function M.auto_setup(opts)
    opts = opts or {}
    if opts.host ~= false and not M._auto.host_attached and M.setup_host(opts.host or {}) then
        M._auto.host_attached = true
    end

    if opts.child ~= false and not M._auto.child_attached and has_child_attachment() then
        M.setup_child(opts.child or {
            root_id = 'tabulature-child-root',
            root_label = 'Child tabs',
        })
        M._auto.child_attached = true
    end

    if M._auto.host_attached or M._auto.child_attached then
        return
    end
    local max_attempts = opts.max_attempts or 80
    if M._auto.scheduled or M._auto.attempts >= max_attempts then
        return
    end

    M._auto.scheduled = true
    M._auto.attempts = M._auto.attempts + 1
    vim.defer_fn(function()
        M._auto.scheduled = false
        M.auto_setup(opts)
    end, 50)
end

M._next_id = next_id
M._option_label = option_label

return M
