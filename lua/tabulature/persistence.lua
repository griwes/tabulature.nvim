local config = require('tabulature.config')

local M = {}

---@return string
local function state_file()
    return config.config.state_file
end

---@return string
local function state_dir()
    return config.config.state_dir or string.format('%s.d', state_file())
end

---@param value string
---@return string
local function encode_path_component(value)
    return value:gsub('[^%w._-]', function(char)
        return string.format('%%%02X', char:byte())
    end)
end

---@param id string
---@return string
local function snapshot_filename(id)
    return string.format('%s.json', encode_path_component(id))
end

---@param path string
---@param payload table
local function write_json(path, payload)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
    vim.fn.writefile({ vim.json.encode(payload) }, path)
end

---@param path string
---@return table?
local function read_json(path)
    if vim.fn.filereadable(path) == 0 then
        return nil
    end

    local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), '\n'))
    if not ok or type(decoded) ~= 'table' then
        return nil
    end

    return decoded
end

---@return table
local function read_index()
    local decoded = read_json(state_file())
    if type(decoded) ~= 'table' or decoded.version ~= 1 then
        return {
            version = 1,
            latest_snapshot_id = nil,
            snapshots = {},
        }
    end

    decoded.snapshots = type(decoded.snapshots) == 'table' and decoded.snapshots or {}
    return decoded
end

---@return string
local function allocate_snapshot_id()
    return string.format('snapshot:%d:%d', os.time(), vim.uv.hrtime())
end

---@param snapshot tabulature.SessionSnapshot
---@return table
function M.save_snapshot(snapshot)
    local id = allocate_snapshot_id()
    local now = os.time()
    local filename = snapshot_filename(id)
    local index = read_index()

    write_json(vim.fs.joinpath(state_dir(), filename), snapshot)

    table.insert(index.snapshots, {
        id = id,
        created_at = now,
        top_level_count = type(snapshot.children) == 'table' and #snapshot.children or 0,
        file = filename,
    })
    index.latest_snapshot_id = id
    write_json(state_file(), index)

    return {
        version = 1,
        state_ref = {
            kind = 'tabulature.snapshot',
            state_file = state_file(),
            state_dir = state_dir(),
            snapshot_id = id,
        },
    }
end

---@param captured table
---@return tabulature.SessionSnapshot?
function M.load_snapshot(captured)
    if type(captured) ~= 'table' then
        return nil
    end

    local ref = type(captured.state_ref) == 'table' and captured.state_ref or {}
    if captured.version ~= 1 or ref.kind ~= 'tabulature.snapshot' then
        return captured
    end

    if type(ref.snapshot_id) ~= 'string' then
        return nil
    end

    local dir = type(ref.state_dir) == 'string' and ref.state_dir or state_dir()
    return read_json(vim.fs.joinpath(dir, snapshot_filename(ref.snapshot_id)))
end

return M
