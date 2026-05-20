local state = require('tabulature.state')
local model = require('tabulature.model')

local function assert_equal(actual, expected)
    assert(actual == expected, ('expected %q, got %q'):format(tostring(expected), tostring(actual)))
end

local function close_other_tabpages()
    local current = vim.api.nvim_get_current_tabpage()

    for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
        if tabpage ~= current and vim.api.nvim_tabpage_is_valid(tabpage) then
            pcall(vim.api.nvim_win_close, vim.api.nvim_tabpage_get_win(tabpage), true)
        end
    end

    if vim.api.nvim_tabpage_is_valid(current) then
        vim.api.nvim_set_current_tabpage(current)
    end
end

local function open_tabpage()
    return vim.api.nvim_open_tabpage(0, true, {})
end

local function open_file_tabpage(path)
    return vim.api.nvim_open_tabpage(vim.fn.bufadd(path), true, {})
end

local function close_current_tabpage()
    local tabpage = vim.api.nvim_get_current_tabpage()
    if #vim.api.nvim_list_tabpages() > 1 and vim.api.nvim_tabpage_is_valid(tabpage) then
        pcall(vim.api.nvim_win_close, vim.api.nvim_tabpage_get_win(tabpage), true)
    end
end

local function tabpage_offset(offset)
    local tabpages = vim.api.nvim_list_tabpages()
    local current = vim.api.nvim_get_current_tabpage()

    for index, tabpage in ipairs(tabpages) do
        if tabpage == current then
            local target = tabpages[((index - 1 + offset) % #tabpages) + 1]
            vim.api.nvim_set_current_tabpage(target)
            return target
        end
    end
end

describe('tabulature prototype state integration', function()
    it('does not derive filename labels when adopting existing tabpages by default', function()
        close_other_tabpages()
        local path = vim.fs.joinpath(vim.uv.os_tmpdir(), ('tabulature-existing-%s.lua'):format(vim.uv.hrtime()))
        local file = assert(vim.uv.fs_open(path, 'w', 420))
        assert(vim.uv.fs_write(file, 'return true\n'))
        assert(vim.uv.fs_close(file))

        vim.cmd.edit({ args = { path } })
        local filename = path:match('[^/\\]+$')
        local adopted = state.adopt_existing_tabpages({ reset = true })
        local tab = state.get_tab(adopted[1])

        assert_equal(tab.auto_label, false)
        assert(tab.name ~= filename, 'existing tabpage adopted a transient filename label')
    end)

    it('adopts an existing physical tabpage when no snapshot tabs exist', function()
        require('tabulature.session').restore({
            kind = 'tabulature.restore_tabs',
            payload = {
                version = 1,
                active_path = {},
                children = {},
            },
        })

        local tab = state.get_current_tab()

        assert_equal(type(tab.id), 'string')
        assert_equal(tab.parent, state.get_root_id())
        assert_equal(state.tabpage_for(tab.id), vim.api.nvim_get_current_tabpage())
    end)

    it('creates real Neovim tabpages through Tabulature commands', function()
        require('tabulature').setup({ commands = true, manifold = false })
        local before = #vim.api.nvim_list_tabpages()

        vim.cmd('TabulatureNewTab CommandTop')
        local top = state.get_current_tab().id
        vim.cmd('TabulatureNewSubtab CommandSub')
        local sub = state.get_current_tab().id
        vim.cmd('TabulatureNewNested CommandDeep')
        local final_nested = state.get_current_tab().id

        assert_equal(#vim.api.nvim_list_tabpages(), before + 4)
        assert_equal(state.get_tab(top).name, 'CommandTop')
        assert_equal(state.get_tab(sub).name, 'CommandSub')
        assert_equal(state.get_tab(sub).parent, top)
        assert_equal(state.get_tab(final_nested).name, 'CommandDeep 2')

        local captured = require('tabulature.session').capture()
        captured = require('tabulature.persistence').load_snapshot(captured) or captured
        local command_top = nil
        for _, child in ipairs(captured.children) do
            if child.label == 'CommandTop' then
                command_top = child
            end
        end
        assert(command_top ~= nil, 'created top-level tab was not captured')
        assert_equal(type(command_top.id), 'string')
    end)

    it('creates real Neovim tabpages through the public API', function()
        local tabulature = require('tabulature')
        local before = #vim.api.nvim_list_tabpages()

        local top = tabulature.create_tab({ label = 'Real Top' })
        local sub = tabulature.create_subtab({ label = 'Real Sub' })
        local nested = tabulature.create_nested({ label = 'Real Deep', depth = 2 })

        assert_equal(type(top), 'string')
        assert_equal(type(sub), 'string')
        assert_equal(type(nested[1]), 'string')
        assert_equal(#vim.api.nvim_list_tabpages(), before + 4)

        local tree = state.to_tree()
        assert_equal(state.get_tab(top).name, 'Real Top')
        assert_equal(state.get_tab(sub).name, 'Real Sub')
        assert_equal(state.get_tab(nested[2]).name, 'Real Deep 2')
        assert_equal(state.get_tab(sub).parent, top)
        assert_equal(state.get_tab(nested[1]).parent, sub)
        assert_equal(model.find(tree, nested[2]).active, true)
    end)

    it('does not redirect physical tabpage navigation through nested switch targets', function()
        local tabulature = require('tabulature')
        local top = tabulature.create_tab({ label = 'Nav Top' })
        local sub = tabulature.create_subtab({ label = 'Nav Sub' })

        vim.api.nvim_set_current_tabpage(state.tabpage_for(sub))
        tabpage_offset(-1)
        assert_equal(vim.api.nvim_get_current_tabpage(), state.tabpage_for(top))

        tabpage_offset(1)
        assert_equal(vim.api.nvim_get_current_tabpage(), state.tabpage_for(sub))
    end)

    it('adopts API-opened file tabpages without deriving filename labels', function()
        local parent = require('tabulature').create_tab({ label = 'Adopt Parent' })
        local sibling = require('tabulature').create_subtab({ label = 'Adopt Sibling' })
        local path = vim.fs.joinpath(vim.uv.os_tmpdir(), ('tabulature-adopt-%s.lua'):format(vim.uv.hrtime()))
        local file = assert(vim.uv.fs_open(path, 'w', 420))
        assert(vim.uv.fs_write(file, 'return true\n'))
        assert(vim.uv.fs_close(file))

        assert_equal(state.get_current_tab().id, sibling)
        open_file_tabpage(path)
        local adopted = state.get_current_tab().id

        assert_equal(type(adopted), 'string')
        assert_equal(state.get_tab(adopted).parent, parent)
        assert(state.get_tab(adopted).name ~= path:match('[^/\\]+$'), 'API-opened tabpage derived a filename label')
        assert_equal(state.tabpage_for(adopted), vim.api.nvim_get_current_tabpage())

        require('tabulature').adopt_current_tabpage({ parent_id = sibling })
        assert_equal(state.get_tab(adopted).parent, sibling)
    end)

    it('does not label plain API-opened tabpages from the source buffer filename', function()
        local parent = require('tabulature').create_tab({ label = 'Source Parent' })
        require('tabulature').create_subtab({ label = 'Source Sibling' })
        local path = vim.fs.joinpath(vim.uv.os_tmpdir(), ('tabulature-source-%s.lua'):format(vim.uv.hrtime()))
        local file = assert(vim.uv.fs_open(path, 'w', 420))
        assert(vim.uv.fs_write(file, 'return true\n'))
        assert(vim.uv.fs_close(file))

        vim.cmd('edit ' .. vim.fn.fnameescape(path))
        local source_label = path:match('[^/\\]+$')

        open_tabpage()
        local adopted = state.get_current_tab().id

        assert_equal(type(adopted), 'string')
        assert_equal(state.get_tab(adopted).parent, parent)
        assert(state.get_tab(adopted).name ~= source_label, 'plain API-opened tabpage inherited source buffer label')
    end)

    it('does not auto-label API-opened tabpages after Continuity-style buffer rebinding', function()
        local parent = require('tabulature').create_tab({ label = 'Rebind Parent' })
        require('tabulature').create_subtab({ label = 'Rebind Sibling' })
        local path = vim.fs.joinpath(vim.uv.os_tmpdir(), ('tabulature-rebind-%s.lua'):format(vim.uv.hrtime()))
        local file = assert(vim.uv.fs_open(path, 'w', 420))
        assert(vim.uv.fs_write(file, 'return true\n'))
        assert(vim.uv.fs_close(file))

        open_tabpage()
        local adopted = state.get_current_tab().id
        local original_label = state.get_tab(adopted).name

        vim.cmd.edit({ args = { path } })

        assert_equal(type(adopted), 'string')
        assert_equal(state.get_tab(adopted).parent, parent)
        assert_equal(state.get_tab(adopted).auto_label, false)
        assert_equal(state.get_tab(adopted).name, original_label)
    end)

    it('adopts API-opened tabpages even when session capture runs before TabEnter', function()
        local parent = require('tabulature').create_tab({ label = 'Race Parent' })
        local sibling = require('tabulature').create_subtab({ label = 'Race Sibling' })
        local eventignore = vim.o.eventignore

        vim.o.eventignore = 'TabEnter'
        open_tabpage()
        local native_tabpage = vim.api.nvim_get_current_tabpage()
        vim.o.eventignore = eventignore

        require('tabulature.session').capture()
        vim.api.nvim_exec_autocmds('TabEnter', {
            modeline = false,
        })

        local adopted = state.get_current_tab().id

        assert_equal(type(adopted), 'string')
        assert_equal(state.tabpage_for(adopted), native_tabpage)
        assert_equal(state.get_tab(adopted).parent, parent)
        assert_equal(state.get_tab(sibling).parent, parent)
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
        assert_equal(
            table.concat(state.compute_switch_path(top_one), ','),
            table.concat({ top_one, one_child, one_leaf }, ',')
        )
        assert_equal(state.compute_switch_target(top_four), four_leaf)

        _G.tabulature_switch_tab(top_one)
        assert_equal(vim.api.nvim_get_current_tabpage(), state.tabpage_for(one_leaf))

        _G.tabulature_switch_tab(top_four)
        assert_equal(vim.api.nvim_get_current_tabpage(), state.tabpage_for(four_leaf))

        _G.tabulature_switch_tab(top_four)
        assert_equal(vim.api.nvim_get_current_tabpage(), state.tabpage_for(top_four))
        assert_equal(state.get_tab(top_four).selected_child, nil)

        _G.tabulature_switch_tab(top_one)
        assert_equal(vim.api.nvim_get_current_tabpage(), state.tabpage_for(one_leaf))
    end)

    it('closes multi-window tabs through Statuesque-rendered close buttons', function()
        local tabulature = require('tabulature')
        local clicks = require('statuesque.clicks')
        local target = tabulature.create_tab({ label = 'Clickable Tab' })
        local target_tabpage = state.tabpage_for(target)
        vim.cmd.vsplit()
        assert_equal(#vim.api.nvim_tabpage_list_wins(target_tabpage), 2)
        local origin = vim.api.nvim_list_tabpages()[1]
        vim.api.nvim_set_current_tabpage(origin)

        local rendered = require('statuesque').render({ name = 'tabulature' }, 'tabline')
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
        assert_equal(vim.api.nvim_get_current_tabpage(), state.tabpage_for(target))

        assert(close_click ~= nil, 'missing close click handler')
        clicks.dispatch(close_click)
        assert_equal(vim.api.nvim_tabpage_is_valid(target_tabpage), false)
        assert(
            vim.wait(100, function()
                return model.find(state.to_tree(), target) == nil
            end),
            'closed tab label remained in Tabulature tree'
        )
    end)

    it('prunes stale closed-tab labels before session capture', function()
        local tabulature = require('tabulature')
        local stale = tabulature.create_tab({ label = 'Stale Capture Label' })
        local stale_tabpage = state.tabpage_for(stale)
        local eventignore = vim.o.eventignore

        vim.o.eventignore = 'TabClosed'
        vim.api.nvim_set_current_tabpage(stale_tabpage)
        close_current_tabpage()
        vim.o.eventignore = eventignore

        local captured = require('tabulature.session').capture()

        local function contains_label(nodes, label)
            for _, node in ipairs(nodes or {}) do
                if node.label == label or contains_label(node.children, label) then
                    return true
                end
            end
            return false
        end

        assert_equal(vim.api.nvim_tabpage_is_valid(stale_tabpage), false)
        assert_equal(contains_label(captured.children, 'Stale Capture Label'), false)
    end)

    it('dispatches Statuesque-rendered level create buttons as real nested tabs', function()
        local tabulature = require('tabulature')
        local clicks = require('statuesque.clicks')
        local parent = tabulature.create_tab({ label = 'Plus Parent' })
        local before = #vim.api.nvim_list_tabpages()

        local rendered = require('statuesque').render({ name = 'tabulature' }, 'tabline')
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
        assert_equal(type(created), 'string')
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
