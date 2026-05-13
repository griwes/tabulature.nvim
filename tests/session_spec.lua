local model = require('tabulature.model')
local session = require('tabulature.session')
local state = require('tabulature.state')

local function assert_equal(actual, expected)
    assert(actual == expected, ('expected %q, got %q'):format(tostring(expected), tostring(actual)))
end

local function read_json(path)
    return vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
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

    it('trims physical tabpages that are not part of the restored hierarchy', function()
        vim.cmd.tabnew()
        vim.cmd.tabnew()

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

    it('adopts existing tabpages when restoring an empty snapshot', function()
        local restored = session.restore({
            kind = 'tabulature.restore_tabs',
            payload = {
                version = 1,
                active_path = {},
                children = {},
            },
        })

        assert_equal(#restored.children, #vim.api.nvim_list_tabpages())
        assert_equal(state.tabpage_for(restored.children[1].id), vim.api.nvim_get_current_tabpage())
    end)
end)
