local M = {}

local WATCHERS = setmetatable({}, {
    __mode = 'k',
})

local NODE_FIELDS = {
    'id',
    'label',
    'kind',
    'children',
    'active',
    'dirty',
    'pinned',
    'source',
    'manifold_domain_id',
    'child_id',
    'tab_handle',
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

local function emit_change(root)
    local callback = WATCHERS[root]
    if type(callback) == 'function' then
        callback(root)
    end
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
    for _, node in ipairs(M.flatten(root)) do
        node.active = node.id == id
        if node.active then
            selected = node
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
