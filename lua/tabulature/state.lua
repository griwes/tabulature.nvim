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
local tabpage_to_id = {}
local next_tab_id = 1

function M.get_root_id()
    return root_id
end

local current_tab = root_id
local current_tab_list = {}
local parent_id_to_use = nil
local name_to_use = nil
local last_left_bufnr = nil
local reset_state
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

---@param bufnr? integer
---@return integer
local function open_tabpage(bufnr)
    return vim.api.nvim_open_tabpage(bufnr or 0, true, {})
end

---@param tabpage integer
local function close_physical_tabpage(tabpage)
    if not vim.api.nvim_tabpage_is_valid(tabpage) or #vim.api.nvim_list_tabpages() <= 1 then
        return
    end

    pcall(vim.api.nvim_cmd, {
        cmd = 'tabclose',
        args = { tostring(vim.api.nvim_tabpage_get_number(tabpage)) },
        bang = true,
    }, {})
end

local function tab_kind(tab)
    return tab.parent == root_id and 'tab' or 'subtab'
end

---@return string
local function allocate_tab_id()
    local id = string.format('tabulature:%d', next_tab_id)
    next_tab_id = next_tab_id + 1
    return id
end

---@param id any
local function account_for_tab_id(id)
    if type(id) ~= 'string' then
        return
    end

    local index = id:match('^tabulature:(%d+)$')
    if index ~= nil then
        next_tab_id = math.max(next_tab_id, tonumber(index) + 1)
    end
end

---@param id any
---@return string?
local function generated_id_label(id)
    if type(id) ~= 'string' then
        return nil
    end

    return id:match('^tabulature:(%d+)$')
end

---@param id any
---@return string
local function default_tab_label(id)
    return generated_id_label(id) or tostring(id)
end

---@param tab_id any
---@return any
local function resolve_tab_id(tab_id)
    if tabs[tab_id] ~= nil then
        return tab_id
    end

    if type(tab_id) == 'number' then
        return tabpage_to_id[tab_id] or tab_id
    end

    return tab_id
end

local function tab_model_node(tab)
    return model.node({
        id = tab.id,
        label = tab.name,
        kind = tab_kind(tab),
        source = 'child',
        tab_handle = tab.tabpage,
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
    parent_id = resolve_tab_id(parent_id)

    if tabs[parent_id] == nil then
        parent_id = root_id
    end

    local tabpage = type(id) == 'number' and id or nil
    local tab_id = tabpage ~= nil and allocate_tab_id() or id or allocate_tab_id()
    account_for_tab_id(tab_id)

    local parent_level = tabs[parent_id].tab_level
    local current_levels = tabs[parent_id].current_levels
    current_levels[parent_level] = true

    tabs[tab_id] = {
        name = name or default_tab_label(tab_id),
        id = tab_id,
        tabpage = tabpage,
        parent = parent_id,
        children = {},
        tab_level = parent_level + 1,
        current_tab = tab_id,
        selected_child = nil,
        current_levels = current_levels,
    }

    if tabpage ~= nil then
        tabpage_to_id[tabpage] = tab_id
    end

    table.insert(tabs[parent_id].children, tab_id)
    append_tree_node(parent_id, tab_id)
    emit_change()

    return tab_id
end

function M.get_tab(tab_id)
    tab_id = tab_id or root_id
    tab_id = resolve_tab_id(tab_id)
    return tabs[tab_id]
end

---@param tab_id any
---@return integer?
function M.tabpage_for(tab_id)
    local tab = M.get_tab(tab_id)
    return tab and tab.tabpage or nil
end

function M.get_current_tab()
    return M.get_tab(current_tab)
end

function M.set_current_tab(tab_id)
    tab_id = resolve_tab_id(tab_id)
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
    local index = index_of(t, element)
    if index < 1 then
        return nil
    end
    return table.remove(t, index)
end

local function refresh_tab_metadata(tab_id)
    local tab = tabs[tab_id]
    if tab == nil or tab.parent == nil or tabs[tab.parent] == nil then
        return
    end

    tab.tab_level = tabs[tab.parent].tab_level + 1
    tab.current_levels = tabs[tab.parent].current_levels

    local node = tree_nodes[tab_id]
    if node ~= nil then
        node.kind = tab_kind(tab)
        node.render_meta = node.render_meta or {}
        node.render_meta.tab_level = tab.tab_level
    end

    for _, child_id in ipairs(tab.children or {}) do
        refresh_tab_metadata(child_id)
    end
end

local function move_tab(tab_id, parent_id)
    tab_id = resolve_tab_id(tab_id)
    parent_id = resolve_tab_id(parent_id)

    local tab = tabs[tab_id]
    if tab == nil or tabs[parent_id] == nil or tab.parent == parent_id then
        return false
    end

    if tab_id == parent_id or is_descendant_of(parent_id, tab_id) then
        return false
    end

    local old_parent = tab.parent
    table_remove_element(tabs[old_parent].children, tab_id)
    table.insert(tabs[parent_id].children, tab_id)
    tab.parent = parent_id

    local node = remove_tree_child(old_parent, tab_id) or tree_nodes[tab_id]
    if node ~= nil then
        table.insert(tree_nodes[parent_id].children, node)
    end

    if tabs[old_parent].selected_child == tab_id then
        set_selected_child(old_parent, nil)
    end

    refresh_tab_metadata(tab_id)
    return true
end

---@param bufnr integer
---@param opts? { ignore_bufnr?: integer }
---@return string?
local function buffer_label(bufnr, opts)
    if opts ~= nil and opts.ignore_bufnr == bufnr then
        return nil
    end

    local name = vim.api.nvim_buf_get_name(bufnr)

    if name ~= '' then
        return name:match('[^/\\]+$') or name
    end

    return nil
end

---@return string?
local function current_buffer_label()
    return buffer_label(vim.api.nvim_get_current_buf())
end

---@param tabpage integer
---@param opts? { ignore_bufnr?: integer }
---@return string?
local function tabpage_buffer_label(tabpage, opts)
    if not vim.api.nvim_tabpage_is_valid(tabpage) then
        return nil
    end

    local ok, window = pcall(vim.api.nvim_tabpage_get_win, tabpage)
    if not ok or not vim.api.nvim_win_is_valid(window) then
        return nil
    end

    return buffer_label(vim.api.nvim_win_get_buf(window), opts)
end

---@param tabpage integer
---@param opts? { ignore_bufnr?: integer }
---@return string
local function label_for_current_tabpage(tabpage, opts)
    local label = tabpage_buffer_label(tabpage, opts)
    if label ~= nil then
        return label
    end

    return tostring(tabpage)
end

---@param tabpage integer
---@param opts? { ignore_bufnr?: integer }
---@return string?
---@return boolean
local function auto_label_for_tabpage(tabpage, opts)
    local label = tabpage_buffer_label(tabpage, opts)

    return label, label ~= nil
end

local function refresh_adopted_current_tab_label()
    local tabpage = vim.api.nvim_get_current_tabpage()
    local tab_id = tabpage_to_id[tabpage]
    local tab = tabs[tab_id]
    if tab == nil or tab.auto_label ~= true then
        return
    end

    local label = current_buffer_label()
    if label == nil or label == tab.name then
        return
    end

    tab.name = label
    if tree_nodes[tab_id] ~= nil then
        tree_nodes[tab_id].label = label
    end
    emit_change()
    vim.cmd([[ redrawtabline ]])
end

local function update_tab_label(tab_id, label)
    if label == nil or tabs[tab_id] == nil or tabs[tab_id].name == label then
        return false
    end

    tabs[tab_id].name = label
    if tree_nodes[tab_id] ~= nil then
        tree_nodes[tab_id].label = label
    end
    return true
end

local function remove_registered_tab(tabpage, tab_id)
    local tab = tabs[tab_id]
    if tab == nil then
        tabpage_to_id[tabpage] = nil
        return false
    end

    local replacement_selected_child = tab.selected_child

    remove_tree_child(tab.parent, tab_id)
    for _, child_id in ipairs(tab.children) do
        tabs[child_id].parent = tab.parent
        table.insert(tabs[tab.parent].children, child_id)
        local child_node = remove_tree_child(tab_id, child_id) or tree_nodes[child_id]
        if child_node ~= nil then
            table.insert(tree_nodes[tab.parent].children, child_node)
        end
        refresh_tab_metadata(child_id)
    end

    if tabs[tab.parent].selected_child == tab_id then
        set_selected_child(tab.parent, replacement_selected_child)
    end

    if current_tab == tab_id then
        current_tab = replacement_selected_child or tab.parent or root_id
    end

    tree_nodes[tab_id] = nil
    tabpage_to_id[tabpage] = nil
    table_remove_element(tabs[tab.parent].children, tab_id)
    tabs[tab_id] = nil

    return true
end

local function prune_closed_tabpages()
    local valid_tabpages = {}
    for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
        valid_tabpages[tabpage] = true
    end

    local removed = false
    local stale = {}
    for tabpage, tab_id in pairs(tabpage_to_id) do
        if valid_tabpages[tabpage] ~= true or not vim.api.nvim_tabpage_is_valid(tabpage) then
            stale[#stale + 1] = { tabpage = tabpage, tab_id = tab_id }
        end
    end

    for _, item in ipairs(stale) do
        removed = remove_registered_tab(item.tabpage, item.tab_id) or removed
    end

    local known_tabpages = {}
    local seen = {}
    for _, tabpage in ipairs(current_tab_list) do
        if valid_tabpages[tabpage] == true and seen[tabpage] ~= true then
            known_tabpages[#known_tabpages + 1] = tabpage
            seen[tabpage] = true
        end
    end
    for tabpage in pairs(tabpage_to_id) do
        if valid_tabpages[tabpage] == true and seen[tabpage] ~= true then
            known_tabpages[#known_tabpages + 1] = tabpage
            seen[tabpage] = true
        end
    end
    current_tab_list = known_tabpages

    local current_tabpage = vim.api.nvim_get_current_tabpage()
    local mapped_current = tabpage_to_id[current_tabpage]
    if mapped_current ~= nil then
        current_tab = mapped_current
        set_tree_active(mapped_current)
    elseif tabs[current_tab] == nil then
        current_tab = root_id
        set_tree_active(root_id)
    end

    if removed then
        emit_change()
        vim.cmd([[ redrawtabline ]])
    end

    return removed
end

current_tab_list = vim.api.nvim_list_tabpages()

vim.api.nvim_create_augroup('TabulatureEvents', { clear = true })
vim.api.nvim_create_autocmd('TabLeave', {
    group = 'TabulatureEvents',
    callback = function()
        last_left_bufnr = vim.api.nvim_get_current_buf()
    end,
})
vim.api.nvim_create_autocmd('TabEnter', {
    group = 'TabulatureEvents',
    callback = function()
        local tabpage = vim.api.nvim_get_current_tabpage()
        local id = tabpage_to_id[tabpage]
        local new_tabpage = index_of(current_tab_list, tabpage) < 1

        if id == nil and (name_to_use ~= nil or parent_id_to_use ~= nil or new_tabpage) then
            local current = tabs[current_tab]
            local parent_id = parent_id_to_use or (current and current.parent) or root_id
            local label_opts = new_tabpage
                    and name_to_use == nil
                    and parent_id_to_use == nil
                    and {
                        ignore_bufnr = last_left_bufnr,
                    }
                or nil
            local label = name_to_use
            local can_auto_label = false
            if label == nil then
                label, can_auto_label = auto_label_for_tabpage(tabpage, label_opts)
            end

            id = M.add_tab(label, tabpage, parent_id)
            if new_tabpage and name_to_use == nil and parent_id_to_use == nil then
                tabs[id].auto_label = can_auto_label
            end
        end

        current_tab_list = vim.api.nvim_list_tabpages()
        if id ~= nil then
            M.update_switch_targets(id)
            M.set_current_tab(id)
        end
        parent_id_to_use = nil
        name_to_use = nil
        vim.cmd([[ redrawtabline ]])
    end,
})
vim.api.nvim_create_autocmd({ 'BufEnter', 'BufFilePost' }, {
    group = 'TabulatureEvents',
    callback = refresh_adopted_current_tab_label,
})
vim.api.nvim_create_autocmd('TabClosed', {
    group = 'TabulatureEvents',
    callback = function()
        prune_closed_tabpages()
    end,
})

function M.create_child(parent_id, name)
    parent_id_to_use = resolve_tab_id(parent_id or current_tab)
    name_to_use = name
    open_tabpage()
    return current_tab
end

--- Adopt the current real Neovim tabpage into Tabulature's hierarchy.
--- Existing adopted tabpages can be moved under an explicit parent; this lets
--- external `tabedit` producers create real tabs first, then restore the
--- intended Tabulature parent after Neovim fires `TabEnter`.
--- @param opts? { parent_id?: any, label?: string, auto_label?: boolean }
--- @return any tab_id
function M.adopt_current_tabpage(opts)
    opts = opts or {}
    local tabpage = vim.api.nvim_get_current_tabpage()
    local tab_id = tabpage_to_id[tabpage]
    local parent_id = opts.parent_id ~= nil and resolve_tab_id(opts.parent_id) or nil

    if parent_id ~= nil and tabs[parent_id] == nil then
        parent_id = nil
    end

    local derived_label, derived_auto_label = auto_label_for_tabpage(tabpage)
    local label = opts.label or derived_label
    local auto_label = opts.auto_label == true
        or (opts.auto_label ~= false and opts.label == nil and derived_auto_label)
    if tab_id == nil then
        tab_id = M.add_tab(label, tabpage, parent_id or root_id)
        tabs[tab_id].auto_label = auto_label
    elseif parent_id ~= nil then
        move_tab(tab_id, parent_id)
    end

    if label ~= nil and (opts.label ~= nil or tabs[tab_id].auto_label == true) then
        update_tab_label(tab_id, label)
    end

    M.update_switch_targets(tab_id)
    M.set_current_tab(tab_id)
    return tab_id
end

---Adopt any already-existing Neovim tabpages into the Tabulature model.
---This covers the initial tabpage, which exists before Tabulature's TabEnter
---autocmds are installed, and session-manager restores that recreate physical
---tabs before plugin contributors run.
---@param opts? { auto_label?: boolean, reset?: boolean }
---@return any[] tab_ids
function M.adopt_existing_tabpages(opts)
    opts = opts or {}
    local adopted = {}

    if opts.reset == true then
        reset_state()
    end

    for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
        local tab_id = tabpage_to_id[tabpage]

        if tab_id == nil then
            local auto_label = opts.auto_label == true
            local label = auto_label and auto_label_for_tabpage(tabpage) or nil
            tab_id = M.add_tab(label, tabpage, root_id)
            tabs[tab_id].auto_label = auto_label
        end

        adopted[#adopted + 1] = tab_id
    end

    current_tab_list = vim.api.nvim_list_tabpages()

    local current = tabpage_to_id[vim.api.nvim_get_current_tabpage()]
    if current ~= nil then
        M.set_current_tab(current)
    elseif #adopted > 0 then
        M.set_current_tab(adopted[1])
    end

    return adopted
end

---@param tab_id any
---@return any[]
function M.compute_switch_path(tab_id)
    tab_id = resolve_tab_id(tab_id)
    local path = model.resolve_selected_path_ids(tree_root, tab_id)
    if path[1] == tree_root.id then
        table.remove(path, 1)
    end
    return path
end

---@param tab_id any
---@return any
function M.compute_switch_target(tab_id)
    tab_id = resolve_tab_id(tab_id)
    local path = M.compute_switch_path(tab_id)
    return path[#path] or tab_id
end

function M.update_switch_targets(tab_id)
    tab_id = resolve_tab_id(tab_id)
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
        id = tab.id,
        label = tab.name,
        kind = tab_kind(tab),
        auto_label = tab.auto_label == true,
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
    prune_closed_tabpages()

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

---@param tabpage integer
local function close_tabpage(tabpage)
    close_physical_tabpage(tabpage)
end

---@param needed integer
---@return integer[]
local function ensure_tabpages(needed)
    local tabpages = vim.api.nvim_list_tabpages()

    while #tabpages < needed do
        open_tabpage()
        tabpages = vim.api.nvim_list_tabpages()
    end

    while #tabpages > needed do
        close_tabpage(tabpages[#tabpages])
        tabpages = vim.api.nvim_list_tabpages()
    end

    return tabpages
end

reset_state = function()
    tabs = {
        [root_id] = root_tab(),
    }
    tabpage_to_id = {}
    tree_root = new_tree_root()
    tree_nodes = {
        [root_id] = tree_root,
    }
end

---@param node table
---@param tabpage integer
---@return string
---@return boolean
local function restore_label(node, tabpage)
    local fallback = generated_id_label(node.id) or tostring(node.id or tabpage)
    local saved_label = tostring(node.label or fallback)
    local actual_label = tabpage_buffer_label(tabpage)

    if node.auto_label == true then
        return fallback, false
    end

    if node.auto_label == nil and actual_label ~= nil and saved_label == actual_label then
        return fallback, false
    end

    return saved_label, false
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
        local tabpage = tabpages[cursor.index]

        if tabpage ~= nil then
            local label, auto_label = restore_label(node, tabpage)
            local tab_id = M.add_tab(label, node.id or tabpage, parent_id)
            tabs[tab_id].tabpage = tabpage
            tabs[tab_id].auto_label = auto_label
            tabpage_to_id[tabpage] = tab_id
            if tree_nodes[tab_id] ~= nil then
                tree_nodes[tab_id].tab_handle = tabpage
            end
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
        M.adopt_existing_tabpages({ reset = true })
        return M.session_snapshot()
    end

    if not has_active_node(children) and type(snapshot.active_path) == 'table' then
        mark_active_path(children, snapshot.active_path)
    end

    local tabpages = ensure_tabpages(count_nodes(children))

    reset_state()
    local active_id, restored_ids = restore_nodes(children, root_id, tabpages, { index = 0 })

    current_tab = active_id or restored_ids[1] or root_id
    current_tab_list = vim.api.nvim_list_tabpages()
    local active_tabpage = tabs[current_tab] and tabs[current_tab].tabpage or nil
    if type(active_tabpage) == 'number' and vim.api.nvim_tabpage_is_valid(active_tabpage) then
        vim.api.nvim_set_current_tabpage(active_tabpage)
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
    tab_id = resolve_tab_id(tab_id)
    if tabs[tab_id] == nil then
        return nil
    end

    if tab_id == current_tab or is_descendant_of(current_tab, tab_id) then
        set_selected_child(tab_id, nil)
        if tabs[tab_id].tabpage ~= nil then
            vim.api.nvim_set_current_tabpage(tabs[tab_id].tabpage)
        end
        return tab_id
    end

    local target = M.compute_switch_target(tab_id)
    if tabs[target] ~= nil and tabs[target].tabpage ~= nil then
        vim.api.nvim_set_current_tabpage(tabs[target].tabpage)
    end
    return target
end

function _G.tabulature_switch_tab_direct(tab_id, _, _, _)
    tab_id = resolve_tab_id(tab_id)
    set_selected_child(tab_id, nil)
    if tabs[tab_id] ~= nil and tabs[tab_id].tabpage ~= nil then
        vim.api.nvim_set_current_tabpage(tabs[tab_id].tabpage)
    end
    return tab_id
end

return M
