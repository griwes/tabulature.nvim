local M = {}

local SESSION_PROVIDER = nil
local WATCHERS = setmetatable({}, {
    __mode = 'k',
})

local NODE_FIELDS = {
    'id',
    'label',
    'kind',
    'children',
    'active',
    'selected_child',
    'dirty',
    'pinned',
    'source',
    'manifold_domain_id',
    'child_id',
    'tab_handle',
    'session',
    'session_id',
    'worktree_id',
    'render_meta',
}

local NODE_FIELD_SET = {}
for _, field in ipairs(NODE_FIELDS) do
    NODE_FIELD_SET[field] = true
end

local function copy_plain(value)
    if type(value) ~= 'table' then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        if type(child) ~= 'function' then
            copy[key] = copy_plain(child)
        end
    end
    return copy
end

local function append_child(parent, child)
    parent.children[#parent.children + 1] = child
    return child
end

--- @param parent table
--- @param id any
--- @return table?
local function direct_child_by_id(parent, id)
    for _, child in ipairs(parent.children or {}) do
        if child.id == id then
            return child
        end
    end
    return nil
end

local function emit_change(root)
    local callback = WATCHERS[root]
    if type(callback) == 'function' then
        callback(root)
    end
end

--- @param root table
--- @param id any
--- @return table[]
local function path_to_nodes(root, id)
    local path = {}

    local function visit(node)
        path[#path + 1] = node
        if node.id == id then
            return true
        end

        for _, child in ipairs(node.children or {}) do
            if visit(child) then
                return true
            end
        end

        path[#path] = nil
        return false
    end

    if visit(root) then
        return path
    end

    return {}
end

--- Create a normalized hierarchy node.
--- @param data table
--- @return table
function M.node(data)
    assert(type(data) == 'table', 'node data must be a table')
    assert(data.id ~= nil, 'node id is required')

    local node = {
        id = data.id,
        label = tostring(data.label or data.name or data.id),
        kind = data.kind or 'tab',
        children = {},
        active = data.active == true,
        selected_child = data.selected_child,
        dirty = data.dirty == true,
        pinned = data.pinned == true,
        source = data.source or 'user',
    }

    for key, value in pairs(data) do
        if NODE_FIELD_SET[key] and key ~= 'children' then
            node[key] = copy_plain(value)
        end
    end

    if data.children ~= nil then
        for _, child in ipairs(data.children) do
            append_child(node, M.node(child))
        end
    end

    return node
end

--- Create a workspace root node.
--- @param data? table
--- @return table
function M.root(data)
    data = data or {}
    data.id = data.id or 'workspace'
    data.label = data.label or 'Workspace'
    data.kind = data.kind or 'workspace'
    data.source = data.source or 'host'
    return M.node(data)
end

--- Add a normalized child node to a parent.
--- @param parent table
--- @param child table
--- @return table
function M.add_child(parent, child)
    assert(type(parent) == 'table', 'parent must be a node')
    child = M.node(child)
    append_child(parent, child)
    emit_change(parent)
    return child
end

--- Register an optional session provider adapter.
--- @param provider? table
--- @return table? previous_provider
function M.register_session_provider(provider)
    if provider ~= nil then
        assert(type(provider) == 'table', 'session provider must be a table')
    end
    local previous = SESSION_PROVIDER
    SESSION_PROVIDER = provider
    return previous
end

--- Return a flat preorder list of nodes.
--- @param root table
--- @return table[]
function M.flatten(root)
    local nodes = {}

    local function visit(node)
        nodes[#nodes + 1] = node
        for _, child in ipairs(node.children or {}) do
            visit(child)
        end
    end

    visit(root)
    return nodes
end

--- Find a node by id.
--- @param root table
--- @param id any
--- @return table?
function M.find(root, id)
    for _, node in ipairs(M.flatten(root)) do
        if node.id == id then
            return node
        end
    end

    return nil
end

--- Mark one node active and clear active state elsewhere.
--- @param root table
--- @param id any
--- @return table?
function M.set_active(root, id)
    local selected
    local path = path_to_nodes(root, id)
    local path_by_id = {}
    for index, node in ipairs(path) do
        path_by_id[node.id] = {
            index = index,
            node = node,
        }
    end

    for _, node in ipairs(M.flatten(root)) do
        node.active = node.id == id
        if node.active then
            selected = node
        end
        if path_by_id[node.id] ~= nil then
            local next_node = path[path_by_id[node.id].index + 1]
            node.selected_child = next_node and next_node.id or nil
        end
    end
    emit_change(root)
    return selected
end

--- Register a change callback for a root controlled through this model module.
--- @param root table
--- @param callback? fun(root: table)
function M.watch(root, callback)
    assert(type(root) == 'table', 'root must be a node')
    if callback == nil then
        WATCHERS[root] = nil
        return
    end
    assert(type(callback) == 'function', 'callback must be a function')
    WATCHERS[root] = callback
end

--- Return the path from root to a node id.
--- @param root table
--- @param id any
--- @return table[]
function M.path_to(root, id)
    return path_to_nodes(root, id)
end

--- Return node ids for an already resolved path.
--- @param path table[]
--- @return any[]
function M.path_ids(path)
    local ids = {}
    for _, node in ipairs(path or {}) do
        ids[#ids + 1] = node.id
    end
    return ids
end

--- Resolve the session attachment inherited by a node.
--- @param root table
--- @param id any
--- @return table? session
--- @return table? owner
function M.resolve_session(root, id)
    local session = nil
    local owner = nil

    for _, node in ipairs(path_to_nodes(root, id)) do
        if node.session ~= nil then
            session = copy_plain(node.session)
            owner = node
        elseif node.session_id ~= nil then
            session = { id = node.session_id }
            owner = node
        end
    end

    return session, owner
end

--- @param root table
--- @param id any
--- @param action string
--- @param opts? table
--- @return table
local function session_payload(root, id, action, opts)
    local path = path_to_nodes(root, id)
    local node = path[#path]
    local parent = path[#path - 1]
    local session, owner = M.resolve_session(root, id)
    local path_ids = {}
    for _, path_node in ipairs(path) do
        path_ids[#path_ids + 1] = path_node.id
    end

    return vim.tbl_extend('force', opts or {}, {
        action = action,
        node_id = id,
        node = node and M.node(node) or nil,
        parent_id = parent and parent.id or nil,
        path = path_ids,
        session = session,
        session_owner_id = owner and owner.id or nil,
    })
end

--- Request a session provider action for a tab node.
--- @param root table
--- @param id any
--- @param action string
--- @param opts? table
--- @return any
function M.request_session(root, id, action, opts)
    assert(type(action) == 'string' and action ~= '', 'session action must be a non-empty string')
    local payload = session_payload(root, id, action, opts)
    if SESSION_PROVIDER == nil then
        return payload
    end

    local handler = SESSION_PROVIDER[action] or SESSION_PROVIDER.on_request
    if type(handler) == 'function' then
        return handler(payload)
    end

    return payload
end

--- Attach serializable session metadata to a tab node.
--- @param root table
--- @param id any
--- @param session table|string
--- @param opts? table
--- @return any
function M.attach_session(root, id, session, opts)
    local node = M.find(root, id)
    assert(node ~= nil, 'cannot attach session to missing node')
    node.session = type(session) == 'table' and copy_plain(session) or { id = session }
    node.session_id = node.session.id
    emit_change(root)
    return M.request_session(root, id, 'attach', opts)
end

--- Remove direct session metadata from a tab node.
--- @param root table
--- @param id any
--- @param opts? table
--- @return any
function M.detach_session(root, id, opts)
    local node = M.find(root, id)
    assert(node ~= nil, 'cannot detach session from missing node')
    node.session = nil
    node.session_id = nil
    emit_change(root)
    return M.request_session(root, id, 'detach', opts)
end

--- Request restore for the session resolved at a tab node.
--- @param root table
--- @param id any
--- @param opts? table
--- @return any
function M.restore_session(root, id, opts)
    return M.request_session(root, id, 'restore', opts)
end

--- Resolve the selected-child chain below a node.
--- @param root table
--- @param id any
--- @return table?
function M.resolve_selected_child(root, id)
    local path = M.resolve_selected_path(root, id)
    return path[#path]
end

--- Resolve the id of the deepest selected descendant below a node.
--- @param root table
--- @param id any
--- @return any?
function M.resolve_selected_id(root, id)
    local node = M.resolve_selected_child(root, id)
    return node and node.id or nil
end

--- Return the root-to-leaf path after following selected-child links from `id`.
--- @param root table
--- @param id any
--- @return table[]
function M.resolve_selected_path(root, id)
    local path = path_to_nodes(root, id)
    local node = path[#path]
    local seen = {}
    while node ~= nil and node.selected_child ~= nil and not seen[node.id] do
        seen[node.id] = true
        local child = direct_child_by_id(node, node.selected_child)
        if child == nil then
            break
        end
        path[#path + 1] = child
        node = child
    end

    return path
end

--- Return ids for the selected-child path below a node.
--- @param root table
--- @param id any
--- @return any[]
function M.resolve_selected_path_ids(root, id)
    return M.path_ids(M.resolve_selected_path(root, id))
end

--- Serialize a tree snapshot suitable for transfer to a Manifold host.
--- @param root table
--- @return table
function M.snapshot(root)
    return M.node(copy_plain(root))
end

--- Build a Manifold-domain tree.
--- @param domains table[]
--- @param opts? table
--- @return table
function M.from_manifold_domains(domains, opts)
    opts = opts or {}
    local root = M.root({
        id = opts.id or 'manifold',
        label = opts.label or 'Manifold',
        source = 'host',
    })

    for _, domain in ipairs(domains or {}) do
        append_child(
            root,
            M.node({
                id = domain.id or ('domain:' .. tostring(domain.manifold_domain_id)),
                label = domain.label or domain.name or tostring(domain.id),
                kind = 'domain',
                active = domain.active,
                selected_child = domain.selected_child,
                dirty = domain.dirty,
                pinned = domain.pinned,
                source = 'host',
                manifold_domain_id = domain.manifold_domain_id or domain.id,
                children = domain.children,
                render_meta = domain.render_meta,
            })
        )
    end

    return root
end

--- Build a fallback child subtree from Neovim `ext_tabline` data.
--- @param tabline table
--- @param opts? table
--- @return table
function M.from_ext_tabline(tabline, opts)
    opts = opts or {}
    tabline = tabline or {}

    local current = tabline.current
    local tabs = tabline.tabs or tabline
    local root = M.root({
        id = opts.id or 'child-tabs',
        label = opts.label or 'Child tabs',
        kind = 'domain',
        source = 'fallback-ext-tabline',
        child_id = opts.child_id,
    })

    for _, tab in ipairs(tabs) do
        append_child(
            root,
            M.node({
                id = tab.id or tab.tab or tab.handle,
                label = tab.label or tab.name or tostring(tab.tab or tab.id),
                kind = 'child-tab',
                active = tab.active == true or tab.tab == current or tab.id == current,
                selected_child = tab.selected_child,
                dirty = tab.dirty,
                pinned = tab.pinned,
                source = 'fallback-ext-tabline',
                child_id = opts.child_id,
                tab_handle = tab.tab or tab.handle,
                render_meta = tab.render_meta,
            })
        )
    end

    return root
end

return M
