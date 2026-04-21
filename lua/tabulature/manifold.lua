local model = require('tabulature.model')

local M = {
    _pending_tree_publishes = setmetatable({}, {
        __mode = 'k',
    }),
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

return M
