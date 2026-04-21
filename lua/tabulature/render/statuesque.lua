local M = {}

local DEFAULTS = {
    active_hl = 'TabulatureActive',
    inactive_hl = 'TabulatureInactive',
    separator_hl = 'TabulatureSeparator',
    dirty_text = '*',
    pinned_text = '!',
    separator_text = ' ',
    depth_text = '  ',
}

local function option(opts, key)
    if opts and opts[key] ~= nil then
        return opts[key]
    end
    return DEFAULTS[key]
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

local function click_action(node, opts)
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

local function node_segment(node, depth, opts)
    local children = {}
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

    return {
        id = tostring(node.id),
        role = node.kind,
        hl = node.active and option(opts, 'active_hl') or option(opts, 'inactive_hl'),
        on_click = click_action(node, opts),
        priority = node.render_meta and node.render_meta.priority,
        style = {
            depth = depth,
            source = node.source,
        },
        children = children,
    }
end

local function append_tree(spec, node, depth, opts, state)
    if node.kind ~= 'workspace' then
        if not state.first then
            spec[#spec + 1] = {
                text = option(opts, 'separator_text'),
                role = 'separator',
                hl = option(opts, 'separator_hl'),
            }
        end

        state.first = false

        if depth > 0 then
            spec[#spec + 1] = {
                text = string.rep(option(opts, 'depth_text'), depth),
                role = 'tree-depth',
                hl = option(opts, 'separator_hl'),
            }
        end

        spec[#spec + 1] = node_segment(node, depth, opts)
    end

    for _, child in ipairs(node.children or {}) do
        append_tree(spec, child, node.kind == 'workspace' and depth or depth + 1, opts, state)
    end
end

--- Convert a Tabulature hierarchy tree into a Statuesque render spec.
--- @param root table
--- @param opts? table
--- @return table[]
function M.to_spec(root, opts)
    local spec = {}
    append_tree(spec, root, 0, opts or {}, {
        first = true,
    })
    return spec
end

return M
