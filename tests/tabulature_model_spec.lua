local model = require('tabulature.model')
local statuesque_render = require('tabulature.render.statuesque')

local function assert_equal(actual, expected)
    assert(actual == expected, ('expected %q, got %q'):format(tostring(expected), tostring(actual)))
end

local function first_child_with_role(spec, role)
    for _, child in ipairs(spec.children or {}) do
        if child.role == role then
            return child
        end
    end
    error('missing child with role ' .. role)
end

local function first_child_with_id(spec, id)
    for _, child in ipairs(spec.children or {}) do
        if child.id == id then
            return child
        end
    end
    error('missing child with id ' .. id)
end

local function has_child_with_role(spec, role)
    for _, child in ipairs(spec.children or {}) do
        if child.role == role then
            return true
        end
    end
    return false
end

local function children_with_role(spec, role)
    local children = {}
    for _, child in ipairs(spec.children or {}) do
        if child.role == role then
            children[#children + 1] = child
        end
    end
    return children
end

describe('tabulature hierarchy model', function()
    it('builds and queries a hierarchy independent of UI rendering', function()
        local root = model.root()
        model.add_child(root, {
            id = 'domain:alpha',
            label = 'Alpha',
            kind = 'domain',
            children = {
                {
                    id = 'tab:1',
                    label = 'Scratch',
                    kind = 'tab',
                },
            },
        })

        model.set_active(root, 'tab:1')

        assert_equal(model.find(root, 'domain:alpha').label, 'Alpha')
        assert_equal(model.find(root, 'tab:1').active, true)
        assert_equal(#model.path_to(root, 'tab:1'), 3)
        assert_equal(#model.flatten(root), 3)
    end)

    it('remembers selected children and resolves them to the deepest selected tab', function()
        local root = model.root({
            children = {
                {
                    id = 'tab:1',
                    label = '1',
                    selected_child = 'tab:2',
                    children = {
                        {
                            id = 'tab:2',
                            label = '2',
                            selected_child = 'tab:3',
                            children = {
                                {
                                    id = 'tab:3',
                                    label = '3',
                                    active = true,
                                },
                            },
                        },
                    },
                },
                {
                    id = 'tab:4',
                    label = '4',
                    selected_child = 'tab:5',
                    children = {
                        {
                            id = 'tab:5',
                            label = '5',
                            selected_child = 'tab:6',
                            children = {
                                {
                                    id = 'tab:6',
                                    label = '6',
                                },
                            },
                        },
                    },
                },
            },
        })

        assert_equal(model.resolve_selected_child(root, 'tab:1').id, 'tab:3')
        assert_equal(model.resolve_selected_child(root, 'tab:4').id, 'tab:6')

        model.set_active(root, 'tab:6')

        assert_equal(root.selected_child, 'tab:4')
        assert_equal(model.find(root, 'tab:4').selected_child, 'tab:5')
        assert_equal(model.find(root, 'tab:5').selected_child, 'tab:6')
        assert_equal(model.find(root, 'tab:6').active, true)
        assert_equal(model.find(root, 'tab:1').selected_child, 'tab:2')
    end)

    it('serializes snapshots without function values', function()
        local root = model.root({
            children = {
                {
                    id = 'domain:alpha',
                    label = 'Alpha',
                    render_meta = {
                        max_width = 12,
                        callback = function() end,
                    },
                },
            },
        })

        local snapshot = model.snapshot(root)

        assert_equal(snapshot.children[1].render_meta.max_width, 12)
        assert_equal(snapshot.children[1].render_meta.callback, nil)
    end)

    it('builds Manifold domain trees', function()
        local root = model.from_manifold_domains({
            {
                id = 'domain:1',
                label = 'Alpha',
                active = true,
                manifold_domain_id = 1,
            },
            {
                id = 'domain:2',
                label = 'Beta',
            },
        })

        assert_equal(root.kind, 'workspace')
        assert_equal(root.children[1].kind, 'domain')
        assert_equal(root.children[1].manifold_domain_id, 1)
        assert_equal(root.children[1].active, true)
    end)

    it('builds fallback subtrees from ext_tabline data', function()
        local root = model.from_ext_tabline({
            current = 2,
            tabs = {
                { tab = 1, name = 'one' },
                { tab = 2, name = 'two' },
            },
        }, {
            child_id = 'child:alpha',
        })

        assert_equal(root.source, 'fallback-ext-tabline')
        assert_equal(root.children[2].kind, 'child-tab')
        assert_equal(root.children[2].active, true)
        assert_equal(root.children[2].child_id, 'child:alpha')
    end)

    it('produces Statuesque render specs for tabline rendering', function()
        local root = model.from_manifold_domains({
            {
                id = 'domain:1',
                label = 'Alpha',
                active = true,
                dirty = true,
                children = {
                    {
                        id = 'tab:1',
                        label = 'Scratch',
                        kind = 'tab',
                    },
                },
            },
            {
                id = 'domain:2',
                label = 'Beta',
                kind = 'domain',
            },
        })

        local spec = statuesque_render.to_spec(root, { style = 'capsule' })

        assert_equal(spec.role, 'tabulature-tabline')
        assert_equal(spec.custom_rendered, true)
        assert_equal(spec.children[1].role, 'tab-leading-padding')
        assert_equal(spec.children[1].text, ' ')
        assert_equal(spec.children[2].role, 'level-fold-left')
        assert_equal(spec.children[2].text, '')
        assert_equal(spec.children[2].on_click.id, 'tabulature.fold_level')
        assert_equal(spec.children[3].role, 'level-fold')
        assert_equal(spec.children[3].text, '')
        assert_equal(spec.children[3].on_click, spec.children[2].on_click)
        assert_equal(spec.children[4].role, 'level-fold-right')
        assert_equal(spec.children[4].text, '')
        assert_equal(spec.children[4].hl, 'TabulatureFoldLevelSolid1')
        assert_equal(spec.children[4].on_click, spec.children[2].on_click)
        assert_equal(spec.children[5].hl, 'TabulatureLevel1')
        assert_equal(spec.children[6].role, 'tab-leading-separator')
        assert_equal(spec.children[6].text, '')
        assert_equal(spec.children[6].hl, 'TabulatureActiveLevelSolid1')
        assert_equal(spec.children[7].role, 'domain')
        assert_equal(spec.children[7].hl, 'TabulatureActive1')
        assert_equal(spec.children[7].children[1].role, 'tab-body')
        assert_equal(spec.children[7].children[1].children[1].text, ' ')
        assert_equal(spec.children[7].children[1].children[2].text, ' ')
        assert_equal(spec.children[7].children[1].children[3].text, '󰓩 ')
        assert_equal(spec.children[7].children[1].children[4].text, '* ')
        assert_equal(spec.children[7].children[1].children[5].text, 'Alpha')
        assert_equal(spec.children[7].children[1].children[6].text, ' ')
        assert_equal(spec.children[8].role, 'tab-trailing-separator')
        assert_equal(spec.children[8].text, '')
        assert_equal(spec.children[8].hl, 'TabulatureActiveLevelSolid1')
        assert_equal(spec.children[9].role, 'tab-gap')
        assert_equal(spec.children[9].hl, 'TabulatureLevel1')
        assert_equal(spec.children[10].role, 'tab-leading-separator')
        assert_equal(spec.children[10].hl, 'TabulatureLevelSolid1')
        assert_equal(spec.children[11].role, 'domain')
        assert_equal(spec.children[11].hl, 'Tabulature1')
        assert_equal(spec.children[11].children[1].children[2].text, '󰓪 ')
        assert_equal(spec.children[12].role, 'tab-trailing-separator')
        assert_equal(spec.children[12].hl, 'TabulatureSolid1')
        assert_equal(spec.children[13].role, 'level-create-gap')
        assert_equal(spec.children[13].text, ' ')
        assert_equal(spec.children[13].hl, 'TabulatureLevel1')
        assert_equal(spec.children[14].role, 'level-create-left')
        assert_equal(spec.children[14].text, '')
        assert_equal(spec.children[14].hl, 'TabulatureFoldLevelSolid1')
        assert_equal(spec.children[14].on_click.id, 'tabulature.create_child')
        assert_equal(spec.children[15].role, 'level-create')
        assert_equal(spec.children[15].text, '󰐕')
        assert_equal(spec.children[15].hl, 'TabulatureFold1')
        assert_equal(spec.children[15].on_click, spec.children[14].on_click)
        assert_equal(spec.children[16].role, 'level-create-right')
        assert_equal(spec.children[16].text, '')
        assert_equal(spec.children[16].hl, 'TabulatureFoldSolid1')
        assert_equal(spec.children[16].on_click, spec.children[14].on_click)
        assert_equal(spec.children[17].role, 'level-separator')
        assert_equal(spec.children[17].text, ' :: ')
        assert_equal(spec.children[17].hl, 'TabulatureSeparator1')
        assert_equal(spec.children[18].hl, 'TabulatureSolid2')
        assert_equal(spec.children[19].role, 'tab')
        assert_equal(spec.children[20].hl, 'TabulatureSolid2')
        assert_equal(spec.children[21].role, 'level-create-gap')
        assert_equal(spec.children[21].text, ' ')
        assert_equal(spec.children[22].role, 'level-create-left')
        assert_equal(spec.children[23].role, 'level-create')
        assert_equal(spec.children[24].role, 'level-create-right')

        local text = require('statuesque').render(spec, 'text')
        assert(text:find('', 1, true), text)
        assert(text:find('', 1, true), text)
        assert(text:find('󰐕', 1, true), text)
        assert(text:find('󰓩 * Alpha', 1, true), text)
        assert(text:find('󰓪 Scratch', 1, true), text)
        assert(text:find(' :: ', 1, true), text)
        assert(text:find('Alpha', 1, true), text)
        assert(text:find('Beta', 1, true), text)
        assert(text:find('Scratch', 1, true), text)
    end)

    it('distinguishes selected path tabs from the current tab marker', function()
        local root = model.root({
            children = {
                {
                    id = 'domain:alpha',
                    label = 'Alpha',
                    kind = 'domain',
                    children = {
                        {
                            id = 'tab:scratch',
                            label = 'Scratch',
                            kind = 'tab',
                            active = true,
                        },
                    },
                },
                {
                    id = 'domain:beta',
                    label = 'Beta',
                    kind = 'domain',
                },
            },
        })

        local spec = statuesque_render.to_spec(root, { style = 'capsule' })
        local alpha_body = first_child_with_id(spec, 'domain:alpha').children[1]
        local beta_body = first_child_with_id(spec, 'domain:beta').children[1]
        local scratch_body = first_child_with_id(spec, 'tab:scratch').children[1]
        local level_separators = children_with_role(spec, 'level-separator')

        assert(not has_child_with_role(alpha_body, 'tab-current-marker'))
        assert_equal(alpha_body.children[2].text, '󰓩 ')
        assert(not has_child_with_role(beta_body, 'tab-current-marker'))
        assert_equal(beta_body.children[2].text, '󰓪 ')
        assert_equal(scratch_body.children[2].text, ' ')
        assert_equal(scratch_body.children[3].text, '󰓩 ')
        assert_equal(level_separators[1].hl, 'TabulatureSeparator1')
        assert_equal(level_separators[2].hl, 'TabulatureSeparator2')
    end)

    it('renders the slanted tabline style with the 27-derived separator shape', function()
        local root = model.from_manifold_domains({
            {
                id = 'domain:1',
                label = 'Alpha',
                active = true,
                children = {
                    {
                        id = 'tab:1',
                        label = 'Scratch',
                        kind = 'tab',
                    },
                },
            },
        })

        local spec = statuesque_render.to_spec(root, { style = 'slanted' })
        local text = require('statuesque').render(spec, 'text')

        assert_equal(spec.children[1].text, '')
        assert_equal(spec.children[2].text, '  ')
        assert_equal(spec.children[3].text, '')
        assert_equal(spec.children[4].text, '')
        assert_equal(spec.children[5].text, '')
        assert_equal(spec.children[6].children[1].children[1].text, ' ')
        assert_equal(spec.children[6].children[1].children[5].text, ' ')
        assert_equal(spec.children[7].text, '')
        assert_equal(spec.children[8].role, 'level-create-left')
        assert_equal(spec.children[8].text, '')
        assert_equal(spec.children[8].hl, 'TabulatureFoldLevelSolid1')
        assert_equal(spec.children[9].role, 'level-create')
        assert_equal(spec.children[9].text, ' 󰐕 ')
        assert_equal(spec.children[9].hl, 'TabulatureFold1')
        assert_equal(spec.children[10].role, 'level-create-right')
        assert_equal(spec.children[10].text, '')
        assert_equal(spec.children[10].hl, 'TabulatureFoldSolid1')
        assert_equal(spec.children[11].text, '')
        assert(text:find('  ', 1, true), text)
        assert(not text:find('  ', 1, true), text)
        assert(text:find('󰐕', 1, true), text)
        assert(text:find('Alpha', 1, true), text)
        assert(text:find('Scratch', 1, true), text)
    end)

    it('opens lone child-level create chips from the fill background', function()
        local root = model.from_manifold_domains({
            {
                id = 'domain:1',
                label = 'Alpha',
                active = true,
            },
            {
                id = 'domain:2',
                label = 'Beta',
            },
        })

        local capsule = statuesque_render.to_spec(root, { style = 'capsule' }).children
        assert_equal(capsule[#capsule - 3].role, 'level-separator')
        assert_equal(capsule[#capsule - 3].hl, 'TabulatureSeparator1')
        assert_equal(capsule[#capsule - 2].role, 'level-create-left')
        assert_equal(capsule[#capsule - 2].text, '')
        assert_equal(capsule[#capsule - 2].hl, 'TabulatureFoldSolid2')
        assert_equal(capsule[#capsule - 1].role, 'level-create')
        assert_equal(capsule[#capsule].role, 'level-create-right')

        local slanted = statuesque_render.to_spec(root, { style = 'slanted' }).children
        assert_equal(slanted[#slanted - 3].role, 'level-separator')
        assert_equal(slanted[#slanted - 3].hl, 'TabulatureSeparator1')
        assert_equal(slanted[#slanted - 2].role, 'level-create-left')
        assert_equal(slanted[#slanted - 2].text, '')
        assert_equal(slanted[#slanted - 2].hl, 'TabulatureFoldSolid2')
        assert_equal(slanted[#slanted - 1].role, 'level-create')
        assert_equal(slanted[#slanted].role, 'level-create-right')
    end)

    it('defines concrete Tabulature colors and backgrounds without lualine installed', function()
        local theme = require('tabulature.themes.lualine')

        theme.setup({ order = { 'normal' } })

        local fill = vim.api.nvim_get_hl(0, { name = 'Tabulature0' })
        local active = vim.api.nvim_get_hl(0, { name = 'TabulatureActive1' })
        local inactive = vim.api.nvim_get_hl(0, { name = 'Tabulature1' })
        local active_edge = vim.api.nvim_get_hl(0, { name = 'TabulatureActiveSolid1' })
        local active_level_edge = vim.api.nvim_get_hl(0, { name = 'TabulatureActiveLevelSolid1' })
        local fold = vim.api.nvim_get_hl(0, { name = 'TabulatureFold1' })
        local fold_level_edge = vim.api.nvim_get_hl(0, { name = 'TabulatureFoldLevelSolid1' })
        local level = vim.api.nvim_get_hl(0, { name = 'TabulatureLevel1' })
        local separator = vim.api.nvim_get_hl(0, { name = 'TabulatureSeparator1' })

        assert(fill.fg ~= nil)
        assert(fill.bg ~= nil)
        assert(active.fg ~= nil)
        assert(active.bg ~= nil)
        assert(inactive.bg ~= nil)
        assert_equal(active_edge.fg, active.bg)
        assert_equal(active_edge.bg, fill.bg)
        assert_equal(fold.bg, inactive.bg)
        assert(level.bg ~= nil)
        assert(level.bg ~= fill.bg)
        assert(level.bg ~= inactive.bg)
        assert_equal(active_level_edge.fg, active.bg)
        assert_equal(active_level_edge.bg, level.bg)
        assert_equal(fold_level_edge.fg, fold.bg)
        assert_equal(fold_level_edge.bg, level.bg)
        assert_equal(separator.fg, active.bg)
        assert_equal(separator.bg, fill.bg)
    end)

    it('renders actionable tab clicks without fake close buttons for non-tab nodes', function()
        local root = model.root({
            children = {
                {
                    id = 'tab:one',
                    label = 'one',
                    kind = 'tab',
                    active = true,
                    source = 'local',
                    tab_handle = vim.api.nvim_get_current_tabpage(),
                },
            },
        })

        local spec = statuesque_render.to_spec(root, { sigil = false, local_actions = true, style = 'slanted' })
        local tab = first_child_with_role(spec, 'tab')
        local body = tab.children[1]
        local body_children = body.children

        assert_equal(type(body.on_click), 'function')
        assert_equal(body_children[#body_children - 1].role, 'tab-close')
        assert_equal(type(body_children[#body_children - 1].on_click), 'function')
        assert_equal(body_children[#body_children].role, 'tab-padding-right')

        local vimline = require('statuesque').render(spec, 'tabline')
        assert(vimline:find('@v:lua.__statuesque_click@', 1, true), vimline)
        assert(vimline:find('', 1, true), vimline)
    end)

    it('renders local child-sourced tab handles as direct local actions when requested', function()
        local root = model.root({
            children = {
                {
                    id = 'child-tab:one',
                    label = 'child tab',
                    kind = 'tab',
                    active = true,
                    source = 'child',
                    tab_handle = vim.api.nvim_get_current_tabpage(),
                },
            },
        })

        local spec = statuesque_render.to_spec(root, { sigil = false, local_actions = true, style = 'capsule' })
        local tab = first_child_with_role(spec, 'tab')
        local body_children = tab.children[1].children

        assert_equal(tab.children[1].role, 'tab-body')
        assert_equal(type(tab.children[1].on_click), 'function')
        assert_equal(body_children[#body_children - 1].role, 'tab-close')
        assert_equal(type(body_children[#body_children - 1].on_click), 'function')
        assert_equal(body_children[#body_children].role, 'tab-padding-right')
    end)

    it('keeps child-published handles inert without local actions enabled', function()
        local root = model.root({
            children = {
                {
                    id = 'child-tab:one',
                    label = 'child tab',
                    kind = 'tab',
                    active = true,
                    source = 'child',
                    tab_handle = vim.api.nvim_get_current_tabpage(),
                },
            },
        })

        local spec = statuesque_render.to_spec(root, { sigil = false })
        local tab = first_child_with_role(spec, 'tab')

        assert_equal(tab.children[1].role, 'tab-body')
        assert_equal(type(tab.children[1].on_click), 'table')
        assert_equal(tab.children[2], nil)
    end)

    it('does not treat child ext_tabline handles as local tabpage handles', function()
        local root = model.from_ext_tabline({
            current = 999,
            tabs = {
                { tab = 999, name = 'remote' },
            },
        }, {
            child_id = 'child:alpha',
        })

        local spec = statuesque_render.to_spec(root, { sigil = false })
        local tab = first_child_with_role(spec, 'child-tab')

        assert_equal(tab.children[1].role, 'tab-body')
        assert_equal(type(tab.children[1].on_click), 'table')
        assert_equal(tab.children[2], nil)

        local vimline = require('statuesque').render(spec, 'tabline')
        assert(vimline:find('@v:lua.__statuesque_click@', 1, true), vimline)
        assert(not vimline:find('', 1, true), vimline)
    end)
end)
