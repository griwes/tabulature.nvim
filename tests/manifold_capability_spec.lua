local manifold = require('tabulature.manifold')
local model = require('tabulature.model')

local function assert_equal(actual, expected)
    assert(actual == expected, ('expected %q, got %q'):format(tostring(expected), tostring(actual)))
end

describe('tabulature manifold capability', function()
    it('exposes a versioned Manifold capability record', function()
        local capabilities = manifold.capabilities()

        assert_equal(capabilities.plugin, 'tabulature')
        assert_equal(capabilities.protocol_version, 1)
        assert_equal(capabilities.snapshot, true)
        assert_equal(capabilities.features[1], 'tree_snapshot')
    end)

    it('exports serializable tree snapshots', function()
        local snapshot = manifold.snapshot(model.root({
            children = {
                {
                    id = 'tab:1',
                    label = 'Scratch',
                    render_meta = {
                        callback = function() end,
                    },
                },
            },
        }))

        assert_equal(snapshot.children[1].label, 'Scratch')
        assert_equal(snapshot.children[1].render_meta.callback, nil)
    end)

    it('publishes tree updates through injected Manifold attachments', function()
        local root = model.root({
            children = {
                {
                    id = 'tab:1',
                    label = 'Scratch',
                },
            },
        })

        local original_sockconnect = vim.fn.sockconnect
        local original_rpcnotify = vim.fn.rpcnotify
        local published = nil

        vim.g.manifold_child_control = {
            attachments = {
                ['manifold:child:1'] = {
                    host_server = '/tmp/manifold.sock',
                },
            },
        }
        vim.fn.sockconnect = function(kind, path, opts)
            assert_equal(kind, 'pipe')
            assert_equal(path, '/tmp/manifold.sock')
            assert_equal(opts.rpc, true)
            return 42
        end
        vim.fn.rpcnotify = function(channel, method, source, args)
            published = {
                channel = channel,
                method = method,
                source = source,
                args = args,
            }
            return true
        end

        local count = manifold.publish_tree(root, {
            active_path = { 'workspace', 'tab:1' },
        })

        assert_equal(count, 1)
        assert_equal(published.channel, 42)
        assert_equal(published.method, 'nvim_exec_lua')
        assert(published.source:find('_handle_child_suite_event', 1, true))
        assert_equal(published.args[1], 'manifold:child:1')
        assert_equal(published.args[2].kind, 'tabulature.tree_update')
        assert_equal(published.args[2].root.children[1].label, 'Scratch')
        assert_equal(published.args[2].active_path[2], 'tab:1')
        assert_equal(vim.g.manifold_child_control.attachments['manifold:child:1'].channel, 42)

        vim.fn.sockconnect = original_sockconnect
        vim.fn.rpcnotify = original_rpcnotify
        vim.g.manifold_child_control = nil
    end)

    it('automatically publishes watched tree changes routed through the model', function()
        local root = model.root()
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

        manifold.watch_tree(root)
        model.add_child(root, {
            id = 'tab:auto',
            label = 'Auto Tab',
        })

        local did_publish = vim.wait(1000, function()
            return #published >= 1
        end, 10)

        manifold.unwatch_tree(root)
        vim.fn.sockconnect = original_sockconnect
        vim.fn.rpcnotify = original_rpcnotify
        vim.g.manifold_child_control = nil

        assert(did_publish)
        assert_equal(published[1].kind, 'tabulature.tree_update')
        assert_equal(published[1].root.children[1].label, 'Auto Tab')
    end)

    it('coalesces rapid watched tree publishes to the final tree', function()
        local root = model.root()
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

        manifold.watch_tree(root)
        model.add_child(root, {
            id = 'tab:first',
            label = 'First Tab',
        })
        model.add_child(root, {
            id = 'tab:second',
            label = 'Second Tab',
        })

        local did_publish = vim.wait(1000, function()
            return #published >= 1
        end, 10)

        manifold.unwatch_tree(root)
        vim.fn.sockconnect = original_sockconnect
        vim.fn.rpcnotify = original_rpcnotify
        vim.g.manifold_child_control = nil

        assert(did_publish)
        assert_equal(#published, 1)
        assert_equal(#published[1].root.children, 2)
        assert_equal(published[1].root.children[2].label, 'Second Tab')
    end)
end)
