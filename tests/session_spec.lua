local model = require('tabulature.model')
local session = require('tabulature.session')
local state = require('tabulature.state')

local function assert_equal(actual, expected)
    assert(actual == expected, ('expected %q, got %q'):format(tostring(expected), tostring(actual)))
end

describe('tabulature session contributor', function()
    it('restores captured hierarchy onto live Neovim tabpages', function()
        local restored = session.restore({
            kind = 'tabulature.restore_tabs',
            payload = {
                version = 1,
                active_path = { 1, 1, 1 },
                children = {
                    {
                        label = 'One',
                        selected_child_index = 1,
                        children = {
                            {
                                label = 'Two',
                                selected_child_index = 1,
                                children = {
                                    {
                                        label = 'Three',
                                    },
                                },
                            },
                        },
                    },
                    {
                        label = 'Four',
                    },
                },
            },
        })

        assert_equal(restored.children[1].label, 'One')
        assert_equal(restored.children[1].children[1].label, 'Two')
        assert_equal(restored.children[1].children[1].children[1].label, 'Three')
        assert_equal(restored.children[2].label, 'Four')

        local tree = state.to_tree()
        local one = tree.children[1]
        local two = one.children[1]
        local three = two.children[1]

        assert_equal(model.find(tree, three.id).active, true)
        assert_equal(state.compute_switch_target(one.id), three.id)
        assert_equal(state.get_tab(one.id).selected_child, two.id)
        assert_equal(state.get_tab(two.id).selected_child, three.id)
    end)

    it('plans and captures Continuity restore payloads', function()
        local captured = session.capture()
        local steps = session.plan_restore(captured)

        assert_equal(captured.version, 1)
        assert_equal(type(captured.children), 'table')
        assert_equal(#steps, 1)
        assert_equal(steps[1].kind, 'tabulature.restore_tabs')
        assert_equal(steps[1].payload.version, 1)
    end)
end)
