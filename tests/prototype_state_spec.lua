local state = require('tabulature.state')

local function assert_equal(actual, expected)
    assert(actual == expected, ('expected %q, got %q'):format(tostring(expected), tostring(actual)))
end

describe('tabulature prototype state integration', function()
    it('exports prototype tab state as a shared model tree', function()
        local tab_id = 'suite-tab'
        state.add_tab('Suite Tab', tab_id)
        state.set_current_tab(tab_id)

        local tree = state.to_tree()

        assert_equal(tree.kind, 'workspace')
        assert_equal(tree.source, 'child')
        assert_equal(tree.children[#tree.children].id, tab_id)
        assert_equal(tree.children[#tree.children].label, 'Suite Tab')
        assert_equal(tree.children[#tree.children].active, true)
    end)

    it('keeps nested prototype tabs in the shared model tree', function()
        local parent_id = 'suite-parent-tab'
        local child_id = 'suite-child-tab'
        state.add_tab('Suite Parent', parent_id)
        state.add_tab('Suite Child', child_id, parent_id)
        state.set_current_tab(child_id)

        local tree = state.to_tree({
            id = 'custom-root',
            label = 'Custom Root',
        })
        local parent = tree.children[#tree.children]
        local child = parent.children[1]

        assert_equal(tree.id, 'custom-root')
        assert_equal(tree.label, 'Custom Root')
        assert_equal(parent.id, parent_id)
        assert_equal(parent.kind, 'tab')
        assert_equal(child.id, child_id)
        assert_equal(child.kind, 'subtab')
        assert_equal(child.active, true)
    end)

    it('automatically publishes prototype state changes when Manifold sync is enabled', function()
        local original_sockconnect = vim.fn.sockconnect
        local original_rpcnotify = vim.fn.rpcnotify
        local published = {}

        vim.g.manifold_child_control = {
            attachments = {
                ['manifold:child:1'] = {
                    host_server = '/tmp/manifold.sock',
                },
            },
        }
        vim.fn.sockconnect = function()
            return 42
        end
        vim.fn.rpcnotify = function(_, _, _, args)
            published[#published + 1] = args[2]
            return true
        end

        state.enable_manifold_sync()
        state.add_tab('Auto Prototype Tab', 'auto-prototype-tab')

        local did_publish = vim.wait(1000, function()
            return #published >= 1
        end, 10)

        state.disable_manifold_sync()
        vim.fn.sockconnect = original_sockconnect
        vim.fn.rpcnotify = original_rpcnotify
        vim.g.manifold_child_control = nil

        assert(did_publish)
        assert_equal(published[#published].kind, 'tabulature.tree_update')
        assert_equal(
            published[#published].root.children[#published[#published].root.children].label,
            'Auto Prototype Tab'
        )
    end)
end)
