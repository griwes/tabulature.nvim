local model = require('tabulature.model')

local M = {}

local root_id = -1
local tabs = {}
tabs[root_id] = {
    name = '<root>',
    id = root_id,
    parent = nil,
    children = {},
    tab_level = 1,
    current_tab = root_id,
    current_levels = {},
}

function M.get_root_id()
    return root_id
end

local current_tab = root_id
local parent_id_to_use = nil
local manifold_sync = {
    enabled = false,
    opts = {},
}
local tree_root = model.root({
    id = 'tabulature',
    label = 'Tabulature',
    source = 'child',
})
local tree_nodes = {
    [root_id] = tree_root,
}

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

local function active_path(root)
    local path = model.path_to(root, current_tab)
    local ids = {}
    for _, node in ipairs(path) do
        ids[#ids + 1] = node.id
    end
    return ids
end

local function emit_change()
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
local current_tab_list = vim.api.nvim_list_tabpages()

vim.api.nvim_create_augroup('TabulatureEvents', { clear = true })
vim.api.nvim_create_autocmd('TabEnter', {
    group = 'TabulatureEvents',
    callback = function()
        local id = vim.api.nvim_get_current_tabpage()

        if tabs[id] == nil then
            M.add_tab(tostring(id), id, parent_id_to_use or M.get_current_tab().parent)
        end

        M.update_switch_targets(id)
        id = M.compute_switch_target(id)

        current_tab_list = vim.api.nvim_list_tabpages()
        if id == vim.api.nvim_get_current_tabpage() then
            M.set_current_tab(id)
            parent_id_to_use = nil
            vim.cmd([[ redrawtabline ]])
        else
            vim.schedule(function()
                vim.notify('set tabpage')
                vim.api.nvim_set_current_tabpage(id)
            end)
        end
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

function M.create_child(parent_id)
    parent_id_to_use = parent_id or current_tab
    vim.cmd([[ tabnew ]])
end

function M.compute_switch_target(tab_id)
    while tabs[tab_id].current_tab ~= tab_id do
        tab_id = tabs[tab_id].current_tab
    end
    return tab_id
end

function M.update_switch_targets(tab_id)
    local current_levels = tabs[tab_id].current_levels

    local parent = tabs[tab_id].parent
    while parent ~= nil do
        if current_levels[tabs[parent].tab_level] ~= nil then
            tabs[parent].current_tab = tab_id
            emit_change()
            break
        end
        parent = tabs[parent].parent
    end
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
    tab_id = M.compute_switch_target(tab_id)
    vim.api.nvim_set_current_tabpage(tab_id)
end

function _G.tabulature_switch_tab_direct(tab_id, _, _, _)
    tabs[tab_id].current_tab = tab_id
    vim.api.nvim_set_current_tabpage(tab_id)
end

return M
