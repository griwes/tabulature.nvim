local model = require('tabulature.model')

local M = {}

local root_id = -1

---@return table
local function root_tab()
    return {
        name = '<root>',
        id = root_id,
        parent = nil,
        children = {},
        tab_level = 1,
        current_tab = root_id,
        selected_child = nil,
        current_levels = {},
    }
end

local tabs = {
    [root_id] = root_tab(),
}

function M.get_root_id()
    return root_id
end

local current_tab = root_id
local current_tab_list = {}
local parent_id_to_use = nil
local name_to_use = nil
local manifold_sync = {
    enabled = false,
    opts = {},
}

local function new_tree_root()
    return model.root({
        id = 'tabulature',
        label = 'Tabulature',
        source = 'child',
    })
end

local tree_root = new_tree_root()
local tree_nodes = {
    [root_id] = tree_root,
}

local function notify_session()
    local ok, session_plugin = pcall(require, 'continuity')

    if ok and type(session_plugin) == 'table' and type(session_plugin.api) == 'table' then
        if type(session_plugin.api.notify_contributor_changed) == 'function' then
            pcall(session_plugin.api.notify_contributor_changed, 'tabulature')
        end
    end
end

local function tab_kind(tab)
    return tab.parent == root_id and 'tab' or 'subtab'
end

local function tab_model_node(tab)
    return model.node({
        id = tab.id,
        label = tab.name,
        kind = tab_kind(tab),
        source = 'child',
        tab_handle = type(tab.id) == 'number' and tab.id or nil,
        selected_child = tab.selected_child,
        render_meta = {
            tab_level = tab.tab_level,
        },
    })
end

local function append_tree_node(parent_id, tab_id)
    local parent = tree_nodes[parent_id] or tree_root
    local node = tab_model_node(tabs[tab_id])
    parent.children[#parent.children + 1] = node
    tree_nodes[tab_id] = node
    return node
end

local function remove_tree_child(parent_id, tab_id)
    local parent = tree_nodes[parent_id]
    if parent == nil then
        return nil
    end

    for index, child in ipairs(parent.children or {}) do
        if child.id == tab_id then
            return table.remove(parent.children, index)
        end
    end

    return nil
end

local function set_tree_active(tab_id)
    if tree_nodes[tab_id] ~= nil then
        model.set_active(tree_root, tab_id)
    end
end

local function set_selected_child(tab_id, child_id)
    if tabs[tab_id] == nil then
        return
    end
    tabs[tab_id].selected_child = child_id
    tabs[tab_id].current_tab = child_id or tab_id
    if tree_nodes[tab_id] ~= nil then
        tree_nodes[tab_id].selected_child = child_id
    end
end

local function update_selected_child_chain(tab_id, clear_selected_child)
    local child = tab_id
    local parent = tabs[child] and tabs[child].parent or nil
    while parent ~= nil do
        set_selected_child(parent, child)
        child = parent
        parent = tabs[child] and tabs[child].parent or nil
    end

    if clear_selected_child then
        set_selected_child(tab_id, nil)
    end
end

local function is_descendant_of(tab_id, ancestor_id)
    local parent = tabs[tab_id] and tabs[tab_id].parent or nil
    while parent ~= nil do
        if parent == ancestor_id then
            return true
        end
        parent = tabs[parent] and tabs[parent].parent or nil
    end
    return false
end

local function active_path(root)
    return model.path_ids(model.path_to(root, current_tab))
end

---@param root? table
---@return table[]
function M.active_path(root)
    return active_path(root or M.to_tree(manifold_sync.opts))
end

local function emit_change()
    notify_session()

    if not manifold_sync.enabled then
        return
    end

    vim.schedule(function()
        if not manifold_sync.enabled then
            return
        end
        local tree = M.to_tree(manifold_sync.opts)
        require('tabulature.manifold').publish_tree(tree, {
            active_path = active_path(tree),
        })
    end)
end

function M.add_tab(name, id, parent_id)
    parent_id = parent_id or root_id

    local parent_level = tabs[parent_id].tab_level
    local current_levels = tabs[parent_id].current_levels
    current_levels[parent_level] = true

    tabs[id] = {
        name = name,
        id = id,
        parent = parent_id,
        children = {},
        tab_level = parent_level + 1,
        current_tab = id,
        selected_child = nil,
        current_levels = current_levels,
    }

    table.insert(tabs[parent_id].children, id)
    append_tree_node(parent_id, id)
    emit_change()

    return id
end

function M.get_tab(tab_id)
    tab_id = tab_id or root_id
    return tabs[tab_id]
end

function M.get_current_tab()
    return M.get_tab(current_tab)
end

function M.set_current_tab(tab_id)
    current_tab = tab_id
    update_selected_child_chain(tab_id, false)
    set_tree_active(tab_id)
    emit_change()
end

--- Export the prototype tab graph as a shared Tabulature model tree.
--- @param opts? table
--- @return table
function M.to_tree(opts)
    opts = opts or {}
    local snapshot = model.snapshot(tree_root)
    snapshot.id = opts.id or snapshot.id
    snapshot.label = opts.label or snapshot.label
    snapshot.source = 'child'
    return snapshot
end

--- Enable automatic Manifold tree publication for prototype state changes.
--- @param opts? table
function M.enable_manifold_sync(opts)
    manifold_sync.enabled = true
    manifold_sync.opts = opts or {}
    emit_change()
end

function M.disable_manifold_sync()
    manifold_sync.enabled = false
    manifold_sync.opts = {}
end

---@param opts? table
---@return integer
function M.publish_manifold(opts)
    opts = vim.tbl_extend('force', vim.deepcopy(manifold_sync.opts or {}), opts or {})
    local tree = M.to_tree(opts)
    return require('tabulature.manifold').publish_tree(tree, {
        active_path = active_path(tree),
    })
end

function M.is_within_path(_, _)
    return true
end

local function index_of(table, element)
    for i, v in ipairs(table) do
        if v == element then
            return i
        end
    end

    return -1
end

local function table_remove_element(t, element)
    return table.remove(t, index_of(t, element))
end

for _, v in ipairs(vim.api.nvim_list_tabpages()) do
    M.add_tab(tostring(v), v)
end
current_tab = vim.api.nvim_get_current_tabpage()
set_tree_active(current_tab)
current_tab_list = vim.api.nvim_list_tabpages()

vim.api.nvim_create_augroup('TabulatureEvents', { clear = true })
vim.api.nvim_create_autocmd('TabEnter', {
    group = 'TabulatureEvents',
    callback = function()
        local id = vim.api.nvim_get_current_tabpage()

        if tabs[id] == nil then
            M.add_tab(name_to_use or tostring(id), id, parent_id_to_use or M.get_current_tab().parent)
        end

        current_tab_list = vim.api.nvim_list_tabpages()
        M.update_switch_targets(id)
        M.set_current_tab(id)
        parent_id_to_use = nil
        name_to_use = nil
        vim.cmd([[ redrawtabline ]])
    end,
})
vim.api.nvim_create_autocmd('TabClosed', {
    group = 'TabulatureEvents',
    callback = function()
        -- I hate this, but <afile> gives you the *index* of the closed tab instead of its handle.
        -- Sigh.
        local tab_id = current_tab_list[tonumber(vim.fn.expand('<afile>'))]
        assert(tab_id ~= nil)
        local tab = tabs[tab_id]
        local replacement_selected_child = tab.selected_child

        remove_tree_child(tab.parent, tab_id)
        for _, child_id in ipairs(tab.children) do
            tabs[child_id].parent = tab.parent
            table.insert(tabs[tab.parent].children, child_id)
            local child_node = remove_tree_child(tab_id, child_id) or tree_nodes[child_id]
            if child_node ~= nil then
                child_node.kind = tab_kind(tabs[child_id])
                table.insert(tree_nodes[tab.parent].children, child_node)
            end
        end

        if tabs[tab.parent].selected_child == tab_id then
            set_selected_child(tab.parent, replacement_selected_child)
        end
        tree_nodes[tab_id] = nil
        table_remove_element(tabs[tab.parent].children, tab_id)
        tabs[tab_id] = nil
        emit_change()
        current_tab_list = vim.api.nvim_list_tabpages()
        if tab_id ~= current_tab then
            vim.cmd([[ redrawtabline ]])
        end
    end,
})

function M.create_child(parent_id, name)
    parent_id_to_use = parent_id or current_tab
    name_to_use = name
    vim.cmd([[ tabnew ]])
    return vim.api.nvim_get_current_tabpage()
end

---@param tab_id any
---@return any[]
function M.compute_switch_path(tab_id)
    local path = model.resolve_selected_path_ids(tree_root, tab_id)
    if path[1] == tree_root.id then
        table.remove(path, 1)
    end
    return path
end

---@param tab_id any
---@return any
function M.compute_switch_target(tab_id)
    local path = M.compute_switch_path(tab_id)
    return path[#path] or tab_id
end

function M.update_switch_targets(tab_id)
    local current_levels = tabs[tab_id].current_levels

    local parent = tabs[tab_id].parent
    while parent ~= nil do
        if current_levels[tabs[parent].tab_level] ~= nil then
            set_selected_child(parent, tab_id)
            emit_change()
            break
        end
        parent = tabs[parent].parent
    end
end

---@param set table<any, any>?
---@return table<any, boolean>
local function copy_bool_set(set)
    local copy = {}
    for key, value in pairs(set or {}) do
        if value then
            copy[key] = true
        end
    end
    return copy
end

---@param parent_id any
---@param child_id any?
---@return integer?
local function child_index(parent_id, child_id)
    if child_id == nil or tabs[parent_id] == nil then
        return nil
    end

    for index, id in ipairs(tabs[parent_id].children or {}) do
        if id == child_id then
            return index
        end
    end

    return nil
end

---@param tab_id any
---@return table
local function capture_tab(tab_id)
    local tab = tabs[tab_id]
    local children = {}

    for _, child_id in ipairs(tab.children or {}) do
        children[#children + 1] = capture_tab(child_id)
    end

    return {
        label = tab.name,
        kind = tab_kind(tab),
        selected_child_index = child_index(tab_id, tab.selected_child),
        active = tab_id == current_tab,
        current_levels = copy_bool_set(tab.current_levels),
        children = children,
    }
end

---@return integer[]
local function current_active_path_indexes()
    local path = {}
    local parent_id = root_id

    while tabs[parent_id] ~= nil do
        local matched_index = nil
        local matched_child = nil

        for index, child_id in ipairs(tabs[parent_id].children or {}) do
            if child_id == current_tab or is_descendant_of(current_tab, child_id) then
                matched_index = index
                matched_child = child_id
                break
            end
        end

        if matched_index == nil then
            break
        end

        path[#path + 1] = matched_index
        if matched_child == current_tab then
            break
        end

        parent_id = matched_child
    end

    return path
end

---@param root_children table[]
---@param active_path integer[]
local function mark_active_path(root_children, active_path)
    local nodes = root_children
    for _, index in ipairs(active_path) do
        local node = nodes[index]
        if node == nil then
            return
        end
        node.active = true
        nodes = node.children or {}
    end
end

---@param nodes table[]
---@return boolean
local function has_active_node(nodes)
    for _, node in ipairs(nodes or {}) do
        if node.active == true or has_active_node(node.children) then
            return true
        end
    end

    return false
end

---@return table
function M.session_snapshot()
    local active_path = current_active_path_indexes()
    local children = {}

    for _, child_id in ipairs(tabs[root_id].children or {}) do
        children[#children + 1] = capture_tab(child_id)
    end

    if #active_path == 0 and #children > 0 then
        active_path[1] = 1
        mark_active_path(children, active_path)
    end

    return {
        version = 1,
        active_path = active_path,
        children = children,
    }
end

---@param nodes table[]
---@return integer
local function count_nodes(nodes)
    local count = 0

    for _, node in ipairs(nodes or {}) do
        count = count + 1 + count_nodes(node.children)
    end

    return count
end

---@param needed integer
---@return integer[]
local function ensure_tabpages(needed)
    local tabpages = vim.api.nvim_list_tabpages()

    while #tabpages < needed do
        vim.cmd('tabnew')
        tabpages = vim.api.nvim_list_tabpages()
    end

    return tabpages
end

local function reset_state()
    tabs = {
        [root_id] = root_tab(),
    }
    tree_root = new_tree_root()
    tree_nodes = {
        [root_id] = tree_root,
    }
end

---@param nodes table[]
---@param parent_id any
---@param tabpages integer[]
---@param cursor table
---@return any? active_id
---@return any[] restored_ids
local function restore_nodes(nodes, parent_id, tabpages, cursor)
    local active_id = nil
    local restored_ids = {}

    for _, node in ipairs(nodes or {}) do
        cursor.index = cursor.index + 1
        local tab_id = tabpages[cursor.index]

        if tab_id ~= nil then
            M.add_tab(tostring(node.label or tab_id), tab_id, parent_id)
            tabs[tab_id].current_levels = copy_bool_set(node.current_levels)
            restored_ids[#restored_ids + 1] = tab_id

            local child_active, child_ids = restore_nodes(node.children, tab_id, tabpages, cursor)
            local selected_index = tonumber(node.selected_child_index)
            local selected_child = selected_index ~= nil and child_ids[selected_index] or nil
            tabs[tab_id].selected_child = selected_child
            tabs[tab_id].current_tab = selected_child or tab_id
            if tree_nodes[tab_id] ~= nil then
                tree_nodes[tab_id].selected_child = selected_child
            end

            if node.active == true then
                active_id = tab_id
            end
            active_id = child_active or active_id
        end
    end

    return active_id, restored_ids
end

---@param snapshot table
---@return table
function M.restore_session_snapshot(snapshot)
    assert(type(snapshot) == 'table', 'tabulature session snapshot must be a table')

    local children = type(snapshot.children) == 'table' and snapshot.children or {}
    if #children == 0 then
        return M.session_snapshot()
    end

    if not has_active_node(children) and type(snapshot.active_path) == 'table' then
        mark_active_path(children, snapshot.active_path)
    end

    local tabpages = ensure_tabpages(count_nodes(children))

    reset_state()
    local active_id = restore_nodes(children, root_id, tabpages, { index = 0 })

    current_tab = active_id or tabpages[1] or vim.api.nvim_get_current_tabpage()
    current_tab_list = vim.api.nvim_list_tabpages()
    if vim.api.nvim_tabpage_is_valid(current_tab) then
        vim.api.nvim_set_current_tabpage(current_tab)
    end
    set_tree_active(current_tab)
    emit_change()

    return M.session_snapshot()
end

function _G.tabulature_create_child(parent_id, _, _, _)
    M.create_child(parent_id == 0 and -1 or parent_id)
end

function _G.tabulature_fold_level(level, _, _, _)
    M.get_current_tab().current_levels[level] = nil
    M.update_switch_targets(current_tab)
    emit_change()
    vim.cmd([[ redrawtabline ]])
end

function _G.tabulature_unfold_level(level, _, _, _)
    M.get_current_tab().current_levels[level] = true
    M.update_switch_targets(current_tab)
    emit_change()
    vim.cmd([[ redrawtabline ]])
end

function _G.tabulature_switch_tab(tab_id, _, _, _)
    if tabs[tab_id] == nil then
        return nil
    end

    if tab_id == current_tab or is_descendant_of(current_tab, tab_id) then
        set_selected_child(tab_id, nil)
        vim.api.nvim_set_current_tabpage(tab_id)
        return tab_id
    end

    local target = M.compute_switch_target(tab_id)
    vim.api.nvim_set_current_tabpage(target)
    return target
end

function _G.tabulature_switch_tab_direct(tab_id, _, _, _)
    set_selected_child(tab_id, nil)
    vim.api.nvim_set_current_tabpage(tab_id)
    return tab_id
end

return M
