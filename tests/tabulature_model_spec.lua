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

        assert_equal(spec[1].role, 'domain')
        assert_equal(spec[1].children[1].text, '* ')
        assert_equal(spec[1].children[2].text, 'Alpha')
        assert_equal(spec[3].role, 'tree-depth')
        assert_equal(spec[4].role, 'tab')

        local text = require('statuesque').render(spec, 'text')
        assert(text:find('Alpha', 1, true), text)
        assert(text:find('Scratch', 1, true), text)
    end)
end)
