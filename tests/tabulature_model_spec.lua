local model = require('tabulature.model')
local statuesque_render = require('tabulature.render.statuesque')

local function assert_equal(actual, expected)
    assert(actual == expected, ('expected %q, got %q'):format(tostring(expected), tostring(actual)))
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
        })

        local spec = statuesque_render.to_spec(root)

        assert_equal(spec.role, 'tabulature-tabline')
        assert_equal(spec.custom_rendered, true)
        assert_equal(spec.children[1].role, 'tab-leading-padding')
        assert_equal(spec.children[2].role, 'tab-leading-separator')
        assert_equal(spec.children[3].role, 'domain')
        assert_equal(spec.children[3].hl, 'TabulatureActive1')
        assert_equal(spec.children[3].children[1].role, 'tab-body')
        assert_equal(spec.children[3].children[1].children[2].text, '* ')
        assert_equal(spec.children[3].children[1].children[3].text, 'Alpha')
        assert_equal(spec.children[4].role, 'tab-trailing-separator')
        assert_equal(spec.children[5].role, 'tab-gap')
        assert_equal(spec.children[6].role, 'tab-depth')
        assert_equal(spec.children[8].role, 'tab')

        local text = require('statuesque').render(spec, 'text')
        assert(text:find('', 1, true), text)
        assert(text:find('', 1, true), text)
        assert(text:find('󰓩', 1, true), text)
        assert(not text:find('', 1, true), text)
        assert(text:find('Alpha', 1, true), text)
        assert(text:find('Scratch', 1, true), text)
    end)

    it('defines concrete Tabulature colors and backgrounds without lualine installed', function()
        local theme = require('tabulature.themes.lualine')

        theme.setup({ order = { 'normal' } })

        local fill = vim.api.nvim_get_hl(0, { name = 'Tabulature0' })
        local active = vim.api.nvim_get_hl(0, { name = 'TabulatureActive1' })
        local inactive = vim.api.nvim_get_hl(0, { name = 'Tabulature1' })
        local active_edge = vim.api.nvim_get_hl(0, { name = 'TabulatureActiveSolid1' })

        assert_equal(fill.fg, 0xcdd6f4)
        assert_equal(fill.bg, 0x1e1e2e)
        assert_equal(active.fg, 0x11111b)
        assert_equal(active.bg, 0x89b4fa)
        assert_equal(inactive.bg, 0x313244)
        assert_equal(active_edge.fg, active.bg)
        assert_equal(active_edge.bg, fill.bg)
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

        local spec = statuesque_render.to_spec(root, { sigil = false, local_actions = true })

        assert_equal(spec.children[3].role, 'tab')
        assert_equal(type(spec.children[3].children[1].on_click), 'function')
        assert_equal(spec.children[3].children[2].role, 'tab-close')
        assert_equal(type(spec.children[3].children[2].on_click), 'function')

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

        local spec = statuesque_render.to_spec(root, { sigil = false, local_actions = true })

        assert_equal(spec.children[3].role, 'tab')
        assert_equal(spec.children[3].children[1].role, 'tab-body')
        assert_equal(type(spec.children[3].children[1].on_click), 'function')
        assert_equal(spec.children[3].children[2].role, 'tab-close')
        assert_equal(type(spec.children[3].children[2].on_click), 'function')
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

        assert_equal(spec.children[3].role, 'tab')
        assert_equal(spec.children[3].children[1].role, 'tab-body')
        assert_equal(type(spec.children[3].children[1].on_click), 'table')
        assert_equal(spec.children[3].children[2].role, 'tab-padding')
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

        assert_equal(spec.children[8].role, 'child-tab')
        assert_equal(spec.children[8].children[1].role, 'tab-body')
        assert_equal(type(spec.children[8].children[1].on_click), 'table')
        assert_equal(spec.children[8].children[2].role, 'tab-padding')

        local vimline = require('statuesque').render(spec, 'tabline')
        assert(vimline:find('@v:lua.__statuesque_click@', 1, true), vimline)
        assert(not vimline:find('', 1, true), vimline)
    end)
end)
