local model = require('tabulature.model')
local session = require('tabulature.session')
local state = require('tabulature.state')

local function assert_equal(actual, expected)
    assert(actual == expected, ('expected %q, got %q'):format(tostring(expected), tostring(actual)))
end

local function read_json(path)
    return vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
end

local function open_tabpage()
    return vim.api.nvim_open_tabpage(0, true, {})
end

local function count_files(path)
    local count = 0
    for _, entry_type in vim.fs.dir(path) do
        if entry_type == 'file' then
            count = count + 1
        end
    end
    return count
end

local function has_top_level_label(snapshot, label)
    for _, child in ipairs(snapshot.children or {}) do
        if child.label == label then
            return true
        end
    end
    return false
end

local function count_nodes(nodes)
    local count = 0
    for _, node in ipairs(nodes or {}) do
        count = count + 1 + count_nodes(node.children)
    end
    return count
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

    it('trims multi-window tabpages that are not part of the restored hierarchy', function()
        local multi_window_tabpage = open_tabpage()
        vim.cmd.vsplit()
        assert_equal(#vim.api.nvim_tabpage_list_wins(multi_window_tabpage), 2)
        open_tabpage()

        local restored = session.restore({
            kind = 'tabulature.restore_tabs',
            payload = {
                version = 1,
                active_path = { 1 },
                children = {
                    {
                        label = 'Only',
                        active = true,
                    },
                    {
                        label = 'Sibling',
                    },
                },
            },
        })

        assert_equal(#vim.api.nvim_list_tabpages(), 2)
        assert_equal(vim.api.nvim_tabpage_is_valid(multi_window_tabpage), false)
        assert_equal(#restored.children, 2)
        assert_equal(restored.children[1].label, 'Only')
        assert_equal(restored.children[2].label, 'Sibling')
    end)

    it('does not preserve legacy auto-derived file labels as durable tab names', function()
        local path = vim.fs.joinpath(vim.uv.os_tmpdir(), ('tabulature-legacy-label-%s.lua'):format(vim.uv.hrtime()))
        local file = assert(vim.uv.fs_open(path, 'w', 420))
        assert(vim.uv.fs_write(file, 'return true\n'))
        assert(vim.uv.fs_close(file))

        vim.cmd.edit({ args = { path } })

        local restored = session.restore({
            kind = 'tabulature.restore_tabs',
            payload = {
                version = 1,
                active_path = { 1 },
                children = {
                    {
                        id = 'tabulature:7',
                        label = path:match('[^/\\]+$'),
                        active = true,
                    },
                },
            },
        })

        assert_equal(restored.children[1].label, '7')
        assert_equal(state.get_current_tab().name, '7')
    end)

    it('does not rederive transient auto labels from restored tabpage buffers', function()
        local path =
            vim.fs.joinpath(vim.uv.os_tmpdir(), ('tabulature-restored-auto-label-%s.lua'):format(vim.uv.hrtime()))
        local file = assert(vim.uv.fs_open(path, 'w', 420))
        assert(vim.uv.fs_write(file, 'return true\n'))
        assert(vim.uv.fs_close(file))

        vim.cmd.edit({ args = { path } })

        local restored = session.restore({
            kind = 'tabulature.restore_tabs',
            payload = {
                version = 1,
                active_path = { 1 },
                children = {
                    {
                        id = 'tabulature:9',
                        label = path:match('[^/\\]+$'),
                        auto_label = true,
                        active = true,
                    },
                },
            },
        })

        vim.api.nvim_exec_autocmds('BufEnter', {
            modeline = false,
        })

        assert_equal(restored.children[1].label, '9')
        assert_equal(state.get_current_tab().name, '9')
        assert_equal(state.get_current_tab().auto_label, false)
    end)

    it('preserves explicit labels even when they look like file names', function()
        local path = vim.fs.joinpath(vim.uv.os_tmpdir(), ('tabulature-explicit-label-%s.lua'):format(vim.uv.hrtime()))
        local file = assert(vim.uv.fs_open(path, 'w', 420))
        assert(vim.uv.fs_write(file, 'return true\n'))
        assert(vim.uv.fs_close(file))

        vim.cmd.edit({ args = { path } })

        local label = path:match('[^/\\]+$')
        local restored = session.restore({
            kind = 'tabulature.restore_tabs',
            payload = {
                version = 1,
                active_path = { 1 },
                children = {
                    {
                        id = 'tabulature:8',
                        label = label,
                        auto_label = false,
                        active = true,
                    },
                },
            },
        })

        assert_equal(restored.children[1].label, label)
        assert_equal(state.get_current_tab().name, label)
    end)

    it('plans and captures Continuity restore payloads', function()
        local state_file = vim.fn.tempname()
        require('tabulature.config').configure({
            persist_snapshots = true,
            state_file = state_file,
        })

        local captured = session.capture()
        local steps = session.plan_restore(captured)
        local index = read_json(state_file)
        local snapshot = read_json(vim.fs.joinpath(string.format('%s.d', state_file), index.snapshots[1].file))

        assert_equal(captured.version, 1)
        assert_equal(captured.state_ref.kind, 'tabulature.snapshot')
        assert_equal(type(captured.children), 'nil')
        assert_equal(type(snapshot.children), 'table')
        assert_equal(#steps, 1)
        assert_equal(steps[1].kind, 'tabulature.restore_tabs')
        assert_equal(steps[1].payload.version, 1)
    end)

    it('reuses durable storage for repeated unchanged captures', function()
        local state_file = vim.fn.tempname()
        require('tabulature.config').configure({
            persist_snapshots = true,
            state_file = state_file,
        })

        local first = session.capture()
        local first_index = read_json(state_file)
        local first_file_count = count_files(first.state_ref.state_dir)
        local second = session.capture()
        local second_index = read_json(state_file)

        assert_equal(second.state_ref.snapshot_id, first.state_ref.snapshot_id)
        assert_equal(#second_index.snapshots, #first_index.snapshots)
        assert_equal(count_files(second.state_ref.state_dir), first_file_count)
    end)

    it('keeps references to changed snapshots restorable', function()
        local state_file = vim.fn.tempname()
        local label = ('Changed Snapshot %s'):format(vim.uv.hrtime())
        require('tabulature.config').configure({
            persist_snapshots = true,
            state_file = state_file,
        })

        local first = session.capture()
        local first_snapshot = require('tabulature.persistence').load_snapshot(first)
        require('tabulature').create_tab({ label = label })
        local second = session.capture()

        assert(first.state_ref.snapshot_id ~= second.state_ref.snapshot_id, 'changed snapshot reused a stale reference')

        local restored_first = session.restore({
            kind = 'tabulature.restore_tabs',
            payload = first,
        })
        assert_equal(#vim.api.nvim_list_tabpages(), count_nodes(restored_first.children))
        local restored_second = session.restore({
            kind = 'tabulature.restore_tabs',
            payload = second,
        })
        assert_equal(#vim.api.nvim_list_tabpages(), count_nodes(restored_second.children))

        assert_equal(#restored_first.children, #first_snapshot.children)
        assert_equal(has_top_level_label(restored_first, label), false)
        assert_equal(has_top_level_label(restored_second, label), true)
        assert_equal(#read_json(state_file).snapshots, 2)
    end)

    it('adopts existing tabpages when restoring an empty snapshot', function()
        local current_tabpage = vim.api.nvim_get_current_tabpage()
        local restored = session.restore({
            kind = 'tabulature.restore_tabs',
            payload = {
                version = 1,
                active_path = {},
                children = {},
            },
        })

        assert_equal(#restored.children, #vim.api.nvim_list_tabpages())
        assert_equal(state.tabpage_for(state.get_current_tab().id), current_tabpage)
    end)
end)
