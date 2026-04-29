local M = {}

local DEFAULTS = {
    active_hl_prefix = 'TabulatureActive',
    inactive_hl_prefix = 'Tabulature',
    active_solid_hl_prefix = 'TabulatureActiveSolid',
    inactive_solid_hl_prefix = 'TabulatureSolid',
    active_level_solid_hl_prefix = 'TabulatureActiveLevelSolid',
    fold_hl_prefix = 'TabulatureFold',
    fold_level_solid_hl_prefix = 'TabulatureFoldLevelSolid',
    fold_solid_hl_prefix = 'TabulatureFoldSolid',
    inactive_level_solid_hl_prefix = 'TabulatureLevelSolid',
    level_hl_prefix = 'TabulatureLevel',
    separator_hl_prefix = 'TabulatureSeparator',
    fill_hl = 'Tabulature0',
    active_marker_text = ' ',
    child_separator_text = ' :: ',
    close_text = ' ',
    create_text = '󰐕',
    dirty_text = '*',
    fold_text = '',
    inactive_tab_icon_text = '󰓪',
    leading_padding = ' ',
    level_separator_text = ' :: ',
    pinned_text = '!',
    tab_gap_text = ' ',
    tab_icon_text = '󰓩',
    tab_inner_padding = ' ',
    tab_left_cap_text = '',
    tab_right_cap_text = '',
}

local STYLE_DEFAULTS = {
    capsule = {
        child_separator_text = ' :: ',
        fold_text = '',
        level_separator_text = ' :: ',
        tab_gap_text = ' ',
        tab_left_cap_text = '',
        tab_right_cap_text = '',
    },
    slanted = {
        child_separator_text = '',
        create_text = ' 󰐕 ',
        fold_text = '  ',
        leading_padding = '',
        level_separator_text = '',
        tab_gap_text = '',
        tab_left_cap_text = '',
        tab_right_cap_text = '',
    },
}

local STATUESQUE_STYLE_ALIASES = {
    capsule = 'capsule',
    slanted = 'slanted',
}

--- @return string?
local function statuesque_style()
    local ok, statuesque = pcall(require, 'statuesque')
    if not ok or type(statuesque.style_name) ~= 'function' then
        return nil
    end
    return statuesque.style_name()
end

--- @param opts? table
--- @return string
local function resolved_style_name(opts)
    local configured = opts and opts.style or require('tabulature.config').style()
    if configured == nil or configured == 'inherit' then
        configured = statuesque_style() or 'capsule'
    end
    return STATUESQUE_STYLE_ALIASES[configured] or configured
end

--- @param opts? table
--- @return table
local function resolved_opts(opts)
    opts = opts or {}
    local name = resolved_style_name(opts)
    local style_opts = STYLE_DEFAULTS[name] or STYLE_DEFAULTS.capsule
    return vim.tbl_deep_extend('force', style_opts, opts, {
        style = name,
    })
end

--- @param opts? table
--- @param key string
--- @return any
local function option(opts, key)
    if opts and opts[key] ~= nil then
        return opts[key]
    end
    return DEFAULTS[key]
end

--- @param prefix string
--- @param level integer
--- @return string
local function hl_name(prefix, level)
    return prefix .. tostring(level)
end

--- @return integer
local function palette_size()
    local ok, theme = pcall(require, 'tabulature.themes.lualine')
    if not ok or type(theme.palette_size) ~= 'function' then
        return 0
    end
    return theme.palette_size()
end

--- @param depth integer
--- @return integer
local function level_for(depth)
    local size = palette_size()
    if size <= 0 then
        return depth + 1
    end
    return depth % size + 1
end

--- @param depth integer
--- @return integer
local function predecessor_level_for(depth)
    return level_for(math.max(depth - 1, 0))
end

--- @param node table
--- @param opts? table
--- @return integer?
local function tab_handle(node, opts)
    if not (opts and opts.local_actions) then
        return nil
    end
    local handle = nil
    if type(node.tab_handle) == 'number' then
        handle = node.tab_handle
    elseif type(node.id) == 'number' then
        handle = node.id
    end

    if handle == nil or vim == nil or vim.api == nil or not vim.api.nvim_tabpage_is_valid(handle) then
        return nil
    end

    return handle
end

--- @param node table
--- @param opts? table
--- @return string
local function marker(node, opts)
    local text = ''
    if node.pinned then
        text = text .. option(opts, 'pinned_text')
    end
    if node.dirty then
        text = text .. option(opts, 'dirty_text')
    end
    return text
end

--- @param selected boolean
--- @param opts? table
--- @return string
local function icon_for(selected, opts)
    if selected then
        return option(opts, 'tab_icon_text')
    end
    return option(opts, 'inactive_tab_icon_text')
end

--- @param node table
--- @param opts? table
--- @return function|table
local function click_action(node, opts)
    local handle = tab_handle(node, opts)
    if handle ~= nil then
        return function()
            if type(_G.tabulature_switch_tab) == 'function' then
                return _G.tabulature_switch_tab(handle)
            end
            if vim and vim.api and vim.api.nvim_tabpage_is_valid(handle) then
                return vim.api.nvim_set_current_tabpage(handle)
            end
            return nil
        end
    end

    local action = opts and opts.click_action or 'tabulature.select'
    return {
        id = action,
        args = {
            id = node.id,
            kind = node.kind,
            source = node.source,
            manifold_domain_id = node.manifold_domain_id,
            child_id = node.child_id,
            tab_handle = node.tab_handle,
        },
    }
end

--- @param node table
--- @param opts? table
--- @return function?
local function close_action(node, opts)
    local handle = tab_handle(node, opts)
    if handle == nil then
        return nil
    end

    return function()
        if not vim.api.nvim_tabpage_is_valid(handle) then
            return nil
        end

        local tabnr = vim.api.nvim_tabpage_get_number(handle)
        return pcall(vim.cmd, tostring(tabnr) .. 'tabclose')
    end
end

--- @param parent table?
--- @param opts? table
--- @return function|table
local function create_child_action(parent, opts)
    if opts and opts.local_actions then
        return function()
            local ok, state = pcall(require, 'tabulature.state')
            if not ok or type(state) ~= 'table' or type(state.create_child) ~= 'function' then
                return nil
            end

            local parent_id
            if parent == nil or parent.kind == 'workspace' then
                parent_id = type(state.get_root_id) == 'function' and state.get_root_id() or nil
            elseif type(parent.tab_handle) == 'number' then
                parent_id = parent.tab_handle
            elseif type(parent.id) == 'number' then
                parent_id = parent.id
            end

            if parent_id == nil then
                return nil
            end

            return state.create_child(parent_id)
        end
    end

    local action = opts and opts.create_action or 'tabulature.create_child'
    return {
        id = action,
        args = {
            parent_id = parent and parent.id or nil,
            parent_kind = parent and parent.kind or nil,
            parent_source = parent and parent.source or nil,
            parent_tab_handle = parent and parent.tab_handle or nil,
        },
    }
end

--- @param level integer
--- @param opts? table
--- @return function|table
local function fold_level_action(level, opts)
    if opts and opts.local_actions then
        return function()
            if type(_G.tabulature_fold_level) == 'function' then
                return _G.tabulature_fold_level(level)
            end
            return nil
        end
    end

    local action = opts and opts.fold_action or 'tabulature.fold_level'
    return {
        id = action,
        args = {
            level = level,
        },
    }
end

--- @param text string
--- @param hl string
--- @param role string
--- @param on_click? function|table
--- @return table
local function text_node(text, hl, role, on_click)
    return {
        text = text,
        hl = hl,
        role = role,
        on_click = on_click,
    }
end

--- @param active boolean
--- @param level integer
--- @param opts? table
--- @return string
local function body_hl(active, level, opts)
    local prefix = active and option(opts, 'active_hl_prefix') or option(opts, 'inactive_hl_prefix')
    return hl_name(prefix, level)
end

--- @param active boolean
--- @param level integer
--- @param opts? table
--- @return string
local function solid_hl(active, level, opts)
    local prefix = active and option(opts, 'active_solid_hl_prefix') or option(opts, 'inactive_solid_hl_prefix')
    return hl_name(prefix, level)
end

--- @param active boolean
--- @param level integer
--- @param opts? table
--- @return string
local function level_solid_hl(active, level, opts)
    local prefix = active and option(opts, 'active_level_solid_hl_prefix')
        or option(opts, 'inactive_level_solid_hl_prefix')
    return hl_name(prefix, level)
end

--- @param level integer
--- @param opts? table
--- @return string
local function fold_hl(level, opts)
    return hl_name(option(opts, 'fold_hl_prefix'), level)
end

--- @param level integer
--- @param opts? table
--- @return string
local function fold_solid_hl(level, opts)
    return hl_name(option(opts, 'fold_solid_hl_prefix'), level)
end

--- @param level integer
--- @param opts? table
--- @return string
local function fold_level_solid_hl(level, opts)
    return hl_name(option(opts, 'fold_level_solid_hl_prefix'), level)
end

--- @param level integer
--- @param opts? table
--- @return string
local function level_hl(level, opts)
    return hl_name(option(opts, 'level_hl_prefix'), level)
end

--- @param level integer
--- @param opts? table
--- @return string
local function separator_hl(level, opts)
    return hl_name(option(opts, 'separator_hl_prefix'), level)
end

--- @param spec table[]
--- @param level integer
--- @param opts? table
local function append_fold_chip(spec, level, opts)
    local action = fold_level_action(level, opts)
    spec[#spec + 1] =
        text_node(option(opts, 'tab_left_cap_text'), fold_solid_hl(level, opts), 'level-fold-left', action)
    spec[#spec + 1] = text_node(option(opts, 'fold_text'), fold_hl(level, opts), 'level-fold', action)
    spec[#spec + 1] =
        text_node(option(opts, 'tab_right_cap_text'), fold_level_solid_hl(level, opts), 'level-fold-right', action)
    spec[#spec + 1] = text_node(option(opts, 'tab_gap_text'), level_hl(level, opts), 'tab-gap')
end

--- @param spec table[]
--- @param parent table?
--- @param level integer
--- @param has_tabs boolean
--- @param opts? table
local function append_create_chip(spec, parent, level, has_tabs, opts)
    if opts and opts.create_controls == false then
        return
    end

    local gap_text = has_tabs and option(opts, 'tab_gap_text') or ''
    if gap_text ~= '' then
        spec[#spec + 1] = text_node(gap_text, level_hl(level, opts), 'level-create-gap')
    end
    local left_hl = has_tabs and fold_level_solid_hl(level, opts) or fold_solid_hl(level, opts)
    local action = create_child_action(parent, opts)
    spec[#spec + 1] = text_node(option(opts, 'tab_left_cap_text'), left_hl, 'level-create-left', action)
    spec[#spec + 1] = text_node(option(opts, 'create_text'), fold_hl(level, opts), 'level-create', action)
    spec[#spec + 1] =
        text_node(option(opts, 'tab_right_cap_text'), fold_solid_hl(level, opts), 'level-create-right', action)
end

--- @param node table
--- @param depth integer
--- @param selected boolean
--- @param current boolean
--- @param opts? table
--- @param close? function
--- @return table[]
local function tab_body_children(node, depth, selected, current, opts, close)
    local children = {}
    local padding = option(opts, 'tab_inner_padding')
    if padding ~= '' then
        children[#children + 1] = {
            text = padding,
            role = 'tab-padding-left',
        }
    end

    if current then
        children[#children + 1] = {
            text = option(opts, 'active_marker_text'),
            role = 'tab-current-marker',
        }
    end

    children[#children + 1] = {
        text = icon_for(selected, opts) .. ' ',
        role = 'tab-icon',
    }

    local prefix = marker(node, opts)
    if prefix ~= '' then
        children[#children + 1] = {
            text = prefix .. ' ',
            role = 'tab-marker',
        }
    end

    children[#children + 1] = {
        text = node.label,
        max_width = node.render_meta and node.render_meta.max_width,
        truncate = node.render_meta and node.render_meta.truncate or 'right',
    }

    if close ~= nil then
        children[#children + 1] = {
            text = option(opts, 'close_text'),
            role = 'tab-close',
            on_click = close,
        }
    end

    if padding ~= '' then
        children[#children + 1] = {
            text = padding,
            role = 'tab-padding-right',
        }
    end

    return children
end

--- @param node table
--- @param depth integer
--- @param selected boolean
--- @param current boolean
--- @param opts? table
--- @return table[]
local function tab_contents(node, depth, selected, current, opts)
    local close = close_action(node, opts)
    local children = {
        {
            role = 'tab-body',
            on_click = click_action(node, opts),
            children = tab_body_children(node, depth, selected, current, opts, close),
        },
    }

    return children
end

--- @param spec table[]
--- @param node table
--- @param depth integer
--- @param selected boolean
--- @param current boolean
--- @param left_on_fill boolean
--- @param right_on_fill boolean
--- @param opts? table
local function append_tab(spec, node, depth, selected, current, left_on_fill, right_on_fill, opts)
    local level = level_for(depth)
    local current_body_hl = body_hl(selected, level, opts)
    local left_solid_hl = left_on_fill and solid_hl(selected, level, opts) or level_solid_hl(selected, level, opts)
    local right_solid_hl = right_on_fill and solid_hl(selected, level, opts) or level_solid_hl(selected, level, opts)

    spec[#spec + 1] = text_node(option(opts, 'tab_left_cap_text'), left_solid_hl, 'tab-leading-separator')
    spec[#spec + 1] = {
        id = tostring(node.id),
        role = node.kind,
        hl = current_body_hl,
        priority = node.render_meta and node.render_meta.priority,
        style = {
            depth = depth,
            source = node.source,
            tabulature = 'tab',
        },
        children = tab_contents(node, depth, selected, current, opts),
    }
    spec[#spec + 1] = text_node(option(opts, 'tab_right_cap_text'), right_solid_hl, 'tab-trailing-separator')
end

--- @param node table
--- @param active_id any
--- @return boolean
local function node_is_active(node, active_id)
    return active_id ~= nil and node.id == active_id
end

--- @param root table
--- @return table?
local function find_active_node(root)
    if root.active == true then
        return root
    end

    for _, child in ipairs(root.children or {}) do
        local active = find_active_node(child)
        if active ~= nil then
            return active
        end
    end

    return nil
end

--- @param root table
--- @return table?
local function find_selected_node(root)
    local node = root
    local seen = {}
    while node ~= nil and node.selected_child ~= nil and not seen[node.id] do
        seen[node.id] = true
        local selected = nil
        for _, child in ipairs(node.children or {}) do
            if child.id == node.selected_child then
                selected = child
                break
            end
        end
        if selected == nil then
            break
        end
        node = selected
    end
    return node
end

--- @param root table
--- @param target any
--- @return table[]
local function path_to(root, target)
    local path = {}

    local function visit(node)
        path[#path + 1] = node
        if node.id == target then
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

    if target ~= nil and visit(root) then
        return path
    end

    return { root }
end

--- @param path table[]
--- @param depth integer
--- @return table?
local function path_node_at(path, depth)
    return path[depth + 2]
end

--- @param spec table[]
--- @param text string
--- @param level integer
--- @param opts? table
local function append_level_separator(spec, text, level, opts)
    spec[#spec + 1] = text_node(text, separator_hl(level, opts), 'level-separator')
end

--- @param spec table[]
--- @param nodes table[]
--- @param depth integer
--- @param active_id any
--- @param current_id any
--- @param starts_on_level boolean
--- @param opts? table
local function append_tab_run(spec, nodes, depth, active_id, current_id, starts_on_level, opts)
    local level = level_for(depth)
    local count = #(nodes or {})
    for index, node in ipairs(nodes or {}) do
        if index > 1 then
            spec[#spec + 1] = text_node(option(opts, 'tab_gap_text'), level_hl(level, opts), 'tab-gap')
        end
        append_tab(
            spec,
            node,
            depth,
            node_is_active(node, active_id),
            node_is_active(node, current_id),
            index == 1 and not starts_on_level,
            index == count,
            opts
        )
    end
    append_create_chip(spec, opts and opts.create_parent, level, count > 0, opts)
end

--- @param spec table[]
--- @param parent table
--- @param path table[]
--- @param depth integer
--- @param current_id any
--- @param has_previous_level boolean
--- @param opts? table
local function append_path_level(spec, parent, path, depth, current_id, has_previous_level, opts)
    local level = level_for(depth)
    if has_previous_level then
        append_level_separator(spec, option(opts, 'level_separator_text'), predecessor_level_for(depth), opts)
    end
    append_fold_chip(spec, level, opts)
    local active_node = path_node_at(path, depth)
    append_tab_run(
        spec,
        parent.children or {},
        depth,
        active_node and active_node.id or nil,
        current_id,
        true,
        vim.tbl_extend('force', opts or {}, { create_parent = parent })
    )
end

--- @param root table
--- @param opts? table
--- @return table[]
local function build_children(root, opts)
    local active_node = find_active_node(root)
        or find_selected_node(root)
        or (root.children and root.children[1])
        or root
    local current_id = active_node and active_node.id or nil
    local path = path_to(root, active_node and active_node.id or nil)
    local children = {}
    local leading_padding = option(opts, 'leading_padding')
    local has_previous_level = false

    if leading_padding ~= false and leading_padding ~= '' then
        children[#children + 1] = text_node(leading_padding, option(opts, 'fill_hl'), 'tab-leading-padding')
    end

    for depth = 0, math.max(#path - 2, 0) do
        local parent = path[depth + 1]
        if parent ~= nil and #(parent.children or {}) > 0 then
            append_path_level(children, parent, path, depth, current_id, has_previous_level, opts)
            has_previous_level = true
        end
    end

    if active_node ~= nil and (opts.create_controls ~= false or #(active_node.children or {}) > 0) then
        local child_depth = math.max(#path - 1, 0)
        local child_level = level_for(child_depth)
        if has_previous_level then
            append_level_separator(
                children,
                option(opts, 'child_separator_text'),
                predecessor_level_for(child_depth),
                opts
            )
        end
        append_tab_run(
            children,
            active_node.children or {},
            child_depth,
            nil,
            current_id,
            false,
            vim.tbl_extend('force', opts or {}, { create_parent = active_node })
        )
    end

    return children
end

--- Convert a Tabulature hierarchy tree into a Statuesque render spec.
--- @param root table
--- @param opts? table
--- @return table
function M.to_spec(root, opts)
    opts = resolved_opts(opts)

    return {
        role = 'tabulature-tabline',
        custom_rendered = true,
        children = build_children(root, opts),
    }
end

return M
