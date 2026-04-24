local state = require('tabulature.state')

local M = {}

local function inc_hl_level(level)
    local palette_size = require('tabulature.themes.lualine').palette_size()
    if palette_size <= 0 then
        return level
    end
    return level % palette_size + 1
end

local function xor(a, b)
    return (a or b) and not (a and b)
end

local function tab_click_handle(tab_id)
    return type(tab_id) == 'number' and tab_id or 0
end

local function tab_number(tab_id)
    if type(tab_id) ~= 'number' then
        return 999
    end
    return vim.api.nvim_tabpage_get_number(tab_id)
end

local function render_tab(
    tab_id_to_render,
    processed_level_current_tab_id,
    hl_level,
    first_tab,
    previous_active,
    hide_fold
)
    local ret = ''

    local tab = state.get_tab(tab_id_to_render)
    local is_current_level = hl_level ~= 0
    local is_active = is_current_level and tab_id_to_render == processed_level_current_tab_id

    if not first_tab and previous_active ~= nil then
        local hl_previous_active = previous_active and 'Active' or ''
        local suffix = is_active and '' or ''

        ret = ret .. string.format('%%#Tabulature%sSolid%d#%s', hl_previous_active, hl_level, suffix)
    end

    local hl_active = is_active and 'Active' or ''
    local hl_solid = is_current_level and 'Solid' or 'Prefix'

    local separator = (
        xor(first_tab, not is_current_level)
            and tab.parent ~= state.get_root_id()
            and tab.parent ~= state.get_current_tab().id
            and ''
        or ''
    )
        .. (
            not hide_fold
                and first_tab
                and is_current_level
                and string.format(' %%%d@v:lua.tabulature_fold_level@%%X ', tab.tab_level)
            or ''
        )

    local prefix = is_current_level and (previous_active and '' or ((first_tab or is_active) and '' or ''))
        or ''
    local fold = tab_id_to_render == state.get_current_tab().id and ' '
        or (
            is_current_level and ''
            or (
                previous_active ~= nil and ' '
                or string.format('%%%d@v:lua.tabulature_unfold_level@%%X ', tab.tab_level)
            )
        )
    local symbol = (is_current_level and not is_active) and '󰓪' or '󰓩'

    local switch_direct = (is_current_level and not hide_fold) and '' or '_direct'
    local close_handle = tab_number(tab.id)
    ret = ret .. string.format('%s%%#Tabulature%s%s%d#%s', separator, hl_active, hl_solid, hl_level, prefix)
    ret = ret
        .. string.format(
            '%%#Tabulature%s%d# %s%%%d@v:lua.tabulature_switch_tab%s@%s  %s%%X %%%dX %%X ',
            hl_active,
            hl_level,
            fold,
            tab_click_handle(tab.id),
            switch_direct,
            symbol,
            tab.name,
            close_handle
        )

    return ret
end

local function render_tab_end(hl_level, is_active, tab_id, is_upper_triangle)
    local is_current = tab_id == state.get_current_tab().id
    local triangle = is_upper_triangle and ' ' or ''
    local plus = (is_upper_triangle or is_current) and ''
        or string.format('  %%%d@v:lua.tabulature_create_child@ %%X', tab_click_handle(tab_id))
    assert(hl_level ~= 0, 'render_tab_end should only be used for tabs with highlights')
    local hl_active = is_active and 'Active' or ''
    return string.format('%%#Tabulature%sSolid%d#%s%%#Tabulature0#%s', hl_active, hl_level, triangle, plus)
end

local function process_tab(tab, current_levels, is_current, hl_level)
    local ret = ''
    local parent_child_count = 0

    if tab.parent then
        local parent = state.get_tab(tab.parent)
        if parent.parent then
            local parent_tab, new_hl_level = process_tab(parent, current_levels, false, hl_level)
            ret = ret .. parent_tab
            hl_level = new_hl_level
        end

        if is_current or current_levels[tab.tab_level] ~= nil then
            local first_tab = true
            local previous_active = nil
            for _, tab_id in ipairs(parent.children) do
                ret = ret .. render_tab(tab_id, tab.id, hl_level, first_tab, previous_active)
                first_tab = false
                previous_active = tab_id == tab.id
                parent_child_count = parent_child_count + 1
            end

            ret = ret .. render_tab_end(hl_level, previous_active, parent.id == -1 and 0 or parent.id)

            hl_level = inc_hl_level(hl_level)
        end
    end

    if is_current then
        ret = ret .. ' '
    end

    if next(tab.children) then
        local is_a_current_level = is_current or current_levels[tab.tab_level] ~= nil
        local current_hl_level = is_a_current_level and hl_level or 0

        if is_a_current_level then
            ret = ret .. ' '
        end
        ret = ret
            .. render_tab(
                tab.id,
                is_current and tab.id or nil,
                current_hl_level,
                tab.tab_level == 1 or is_a_current_level,
                (is_a_current_level or is_current) and false or nil,
                true
            )
        if is_a_current_level then
            ret = ret .. render_tab_end(current_hl_level, is_current, tab.id, true)
        end
    end

    if is_current then
        local first_tab = true
        ret = ret .. ''
        for _, tab_id in ipairs(tab.children) do
            ret = ret .. render_tab(tab_id, nil, hl_level, first_tab, false)
            first_tab = false
        end
        if not first_tab then
            ret = ret .. render_tab_end(hl_level, false, tab.id)
        end
        if tab.id == state.get_current_tab().id then
            ret = ret
                .. (first_tab and '' or ' ')
                .. string.format(' %%%d@v:lua.tabulature_create_child@ %%X', tab_click_handle(tab.id))
        end
    end

    return ret, hl_level
end

function _G.tabulature_tabline()
    return M.render()
end

--- Render prototype tab state as a Vim tabline string.
---
--- The prototype state module keeps its exported hierarchy backed by
--- `tabulature.model`; this adapter only translates that state into a legacy
--- Vim tabline string.
--- @return string
function M.render()
    local tl = '%#TabulatureActive1# 𝄞 %#TabulatureActiveSolid1#%#Tabulature0# '

    local tab = state.get_current_tab()
    tl = tl .. process_tab(tab, tab.current_levels, true, 1)

    return tl
end

--- Install the prototype tabline renderer into the current Neovim instance.
function M.setup()
    vim.opt.tabline = '%!v:lua.tabulature_tabline()'
    vim.opt.showtabline = 2
end

return M
