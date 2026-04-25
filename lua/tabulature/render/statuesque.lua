local M = {}

local DEFAULTS = {
    active_hl_prefix = 'TabulatureActive',
    inactive_hl_prefix = 'Tabulature',
    active_solid_hl_prefix = 'TabulatureActiveSolid',
    inactive_solid_hl_prefix = 'TabulatureSolid',
    fill_hl = 'Tabulature0',
    dirty_text = '*',
    pinned_text = '!',
    active_symbol = '󰓩',
    inactive_symbol = '󰓪',
    leading_padding = ' ',
    tab_gap_text = ' ',
    nested_separator_text = ' 󰇘 ',
    leading_separator_text = '',
    trailing_separator_text = '',
    close_text = '  ',
}

local function option(opts, key)
    if opts and opts[key] ~= nil then
        return opts[key]
    end
    return DEFAULTS[key]
end

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

local function marker(node, opts)
    local text = ''
    if node.pinned then
        text = text .. option(opts, 'pinned_text')
    end
    if node.dirty then
        text = text .. option(opts, 'dirty_text')
    end
    if text ~= '' then
        return text .. ' '
    end
    return text
end

local function palette_size()
    local ok, theme = pcall(require, 'tabulature.themes.lualine')
    if not ok or type(theme.palette_size) ~= 'function' then
        return 0
    end
    return theme.palette_size()
end

local function level_for(depth)
    local size = palette_size()
    if size <= 0 then
        return depth + 1
    end
    return depth % size + 1
end

local function hl_name(prefix, level)
    return prefix .. tostring(level)
end

local function active_hl(level, opts)
    return hl_name(option(opts, 'active_hl_prefix'), level)
end

local function inactive_hl(level, opts)
    return hl_name(option(opts, 'inactive_hl_prefix'), level)
end

local function solid_hl(active, level, opts)
    local prefix = active and option(opts, 'active_solid_hl_prefix') or option(opts, 'inactive_solid_hl_prefix')
    return hl_name(prefix, level)
end

local function click_action(node, opts)
    local handle = tab_handle(node, opts)
    if handle ~= nil then
        return function()
            if type(_G.tabulature_switch_tab_direct) == 'function' then
                return _G.tabulature_switch_tab_direct(handle)
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

local function text_node(text, hl, role)
    return {
        text = text,
        hl = hl,
        role = role,
    }
end

local function node_body_children(node, opts)
    local children = {
        {
            text = ' ' .. (node.active and option(opts, 'active_symbol') or option(opts, 'inactive_symbol')) .. ' ',
            role = 'tab-symbol',
        },
    }
    local prefix = marker(node, opts)

    if prefix ~= '' then
        children[#children + 1] = {
            text = prefix,
            role = 'tab-marker',
        }
    end

    children[#children + 1] = {
        text = node.label,
        max_width = node.render_meta and node.render_meta.max_width,
        truncate = node.render_meta and node.render_meta.truncate or 'right',
    }

    return children
end

local function node_contents(node, opts)
    local children = {
        {
            role = 'tab-body',
            on_click = click_action(node, opts),
            children = node_body_children(node, opts),
        },
    }

    local close = close_action(node, opts)
    if close ~= nil then
        children[#children + 1] = {
            text = option(opts, 'close_text'),
            role = 'tab-close',
            on_click = close,
        }
    else
        children[#children + 1] = {
            text = ' ',
            role = 'tab-padding',
        }
    end

    return children
end

local function append_tab(spec, node, depth, opts, state)
    local level = level_for(depth)
    local current_hl = node.active and active_hl(level, opts) or inactive_hl(level, opts)

    if not state.first then
        spec[#spec + 1] = text_node(option(opts, 'tab_gap_text'), option(opts, 'fill_hl'), 'tab-gap')
    elseif option(opts, 'leading_padding') ~= false then
        spec[#spec + 1] = text_node(option(opts, 'leading_padding'), option(opts, 'fill_hl'), 'tab-leading-padding')
    end

    if depth > 0 then
        spec[#spec + 1] =
            text_node(string.rep(option(opts, 'nested_separator_text'), depth), option(opts, 'fill_hl'), 'tab-depth')
    end

    spec[#spec + 1] =
        text_node(option(opts, 'leading_separator_text'), solid_hl(node.active, level, opts), 'tab-leading-separator')

    spec[#spec + 1] = {
        id = tostring(node.id),
        role = node.kind,
        hl = current_hl,
        priority = node.render_meta and node.render_meta.priority,
        style = {
            depth = depth,
            source = node.source,
            tabulature = 'tab',
        },
        children = node_contents(node, opts),
    }

    spec[#spec + 1] =
        text_node(option(opts, 'trailing_separator_text'), solid_hl(node.active, level, opts), 'tab-trailing-separator')

    state.first = false
end

local function append_tree(spec, node, depth, opts, state)
    if node.kind ~= 'workspace' then
        append_tab(spec, node, depth, opts, state)
    end

    for _, child in ipairs(node.children or {}) do
        append_tree(spec, child, node.kind == 'workspace' and depth or depth + 1, opts, state)
    end
end

--- Convert a Tabulature hierarchy tree into a Statuesque render spec.
--- @param root table
--- @param opts? table
--- @return table
function M.to_spec(root, opts)
    opts = opts or {}
    local children = {}

    local state = { first = true }
    append_tree(children, root, 0, opts, state)

    return {
        role = 'tabulature-tabline',
        custom_rendered = true,
        children = children,
    }
end

return M
