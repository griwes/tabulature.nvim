local state = require('tabulature.state')
local model = require('tabulature.model')

local function assert_equal(actual, expected)
    assert(actual == expected, ('expected %q, got %q'):format(tostring(expected), tostring(actual)))
end

describe('tabulature prototype state integration', function()
    it('creates real Neovim tabpages through Tabulature commands', function()
        require('tabulature').setup({ commands = true, manifold = false })
        local before = #vim.api.nvim_list_tabpages()

        vim.cmd('TabulatureNewTab CommandTop')
        local top = vim.api.nvim_get_current_tabpage()
        vim.cmd('TabulatureNewSubtab CommandSub')
        local sub = vim.api.nvim_get_current_tabpage()
        vim.cmd('TabulatureNewNested CommandDeep')
        local final_nested = vim.api.nvim_get_current_tabpage()

        assert_equal(#vim.api.nvim_list_tabpages(), before + 4)
        assert_equal(state.get_tab(top).name, 'CommandTop')
        assert_equal(state.get_tab(sub).name, 'CommandSub')
        assert_equal(state.get_tab(sub).parent, top)
        assert_equal(state.get_tab(final_nested).name, 'CommandDeep 2')
    end)

    it('creates real Neovim tabpages through the public API', function()
        local tabulature = require('tabulature')
        local before = #vim.api.nvim_list_tabpages()

        local top = tabulature.create_tab({ label = 'Real Top' })
        local sub = tabulature.create_subtab({ label = 'Real Sub' })
        local nested = tabulature.create_nested({ label = 'Real Deep', depth = 2 })

        assert_equal(type(top), 'number')
        assert_equal(type(sub), 'number')
        assert_equal(type(nested[1]), 'number')
        assert_equal(#vim.api.nvim_list_tabpages(), before + 4)

        local tree = state.to_tree()
        assert_equal(state.get_tab(top).name, 'Real Top')
        assert_equal(state.get_tab(sub).name, 'Real Sub')
        assert_equal(state.get_tab(nested[2]).name, 'Real Deep 2')
        assert_equal(state.get_tab(sub).parent, top)
        assert_equal(state.get_tab(nested[1]).parent, sub)
        assert_equal(model.find(tree, nested[2]).active, true)
    end)

    it('does not redirect physical tabnext or tabprevious through nested switch targets', function()
        local tabulature = require('tabulature')
        local top = tabulature.create_tab({ label = 'Nav Top' })
        local sub = tabulature.create_subtab({ label = 'Nav Sub' })

        vim.api.nvim_set_current_tabpage(sub)
        vim.cmd.tabprevious()
        assert_equal(vim.api.nvim_get_current_tabpage(), top)

        vim.cmd.tabnext()
        assert_equal(vim.api.nvim_get_current_tabpage(), sub)
    end)

    it('switches into a tab subtree by chasing selected children', function()
        local tabulature = require('tabulature')
        local top_one = tabulature.create_tab({ label = 'Remember One' })
        local one_child = tabulature.create_subtab({ label = 'Remember Two' })
        local one_leaf = tabulature.create_subtab({ label = 'Remember Three' })
        local top_four = tabulature.create_tab({ label = 'Remember Four' })
        local four_child = tabulature.create_subtab({ label = 'Remember Five' })
        local four_leaf = tabulature.create_subtab({ label = 'Remember Six' })

        assert_equal(state.get_tab(top_one).selected_child, one_child)
        assert_equal(state.get_tab(one_child).selected_child, one_leaf)
        assert_equal(state.get_tab(top_four).selected_child, four_child)
        assert_equal(state.get_tab(four_child).selected_child, four_leaf)

        _G.tabulature_switch_tab(top_one)
        assert_equal(vim.api.nvim_get_current_tabpage(), one_leaf)

        _G.tabulature_switch_tab(top_four)
        assert_equal(vim.api.nvim_get_current_tabpage(), four_leaf)

        _G.tabulature_switch_tab(top_four)
        assert_equal(vim.api.nvim_get_current_tabpage(), top_four)
        assert_equal(state.get_tab(top_four).selected_child, nil)

        _G.tabulature_switch_tab(top_one)
        assert_equal(vim.api.nvim_get_current_tabpage(), one_leaf)
    end)

    it('dispatches Statuesque-rendered local tab clicks and close buttons', function()
        local tabulature = require('tabulature')
        local clicks = require('statuesque.clicks')
        local target = tabulature.create_tab({ label = 'Clickable Tab' })
        local origin = vim.api.nvim_list_tabpages()[1]
        vim.api.nvim_set_current_tabpage(origin)

        local rendered = require('statuesque').render(require('statuesque.widgets').tabulature()(), 'tabline')
        assert(rendered:find('@v:lua.__statuesque_click@', 1, true), rendered)
        assert(rendered:find('', 1, true), rendered)

        local switch_click
        local close_click
        local close_node
        for id, record in pairs(clicks._handlers) do
            local node = record.context and record.context.node
            if node ~= nil and node.role == 'tab-body' and node.children ~= nil then
                for _, child in ipairs(node.children) do
                    if child.text == 'Clickable Tab' then
                        switch_click = id
                        for _, body_child in ipairs(node.children) do
                            if body_child.role == 'tab-close' then
                                close_node = body_child
                            end
                        end
                    end
                end
            end
        end

        assert(switch_click ~= nil, 'missing switch click handler')
        for id, record in pairs(clicks._handlers) do
            local node = record.context and record.context.node
            if node ~= nil and node == close_node then
                close_click = id
            end
        end

        clicks.dispatch(switch_click)
        assert_equal(vim.api.nvim_get_current_tabpage(), target)

        assert(close_click ~= nil, 'missing close click handler')
        clicks.dispatch(close_click)
        assert_equal(vim.api.nvim_tabpage_is_valid(target), false)
    end)

    it('dispatches Statuesque-rendered level create buttons as real nested tabs', function()
        local tabulature = require('tabulature')
        local clicks = require('statuesque.clicks')
        local parent = tabulature.create_tab({ label = 'Plus Parent' })
        local before = #vim.api.nvim_list_tabpages()

        local rendered = require('statuesque').render(require('statuesque.widgets').tabulature()(), 'tabline')
        assert(rendered:find('󰐕', 1, true), rendered)

        local create_click
        for id, record in pairs(clicks._handlers) do
            local node = record.context and record.context.node
            if node ~= nil and node.role == 'level-create' then
                create_click = create_click == nil and id or math.max(create_click, id)
            end
        end

        assert(create_click ~= nil, 'missing create click handler')
        local created = clicks.dispatch(create_click)

        assert_equal(#vim.api.nvim_list_tabpages(), before + 1)
        assert_equal(type(created), 'number')
        assert_equal(state.get_tab(created).parent, parent)
    end)

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
