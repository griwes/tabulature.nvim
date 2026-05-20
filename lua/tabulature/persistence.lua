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

---@param value any
---@return string
local function canonical_value(value)
    local value_type = type(value)

    if value_type == 'nil' then
        return 'nil'
    end
    if value_type == 'boolean' then
        return value and 'boolean:true' or 'boolean:false'
    end
    if value_type == 'number' then
        return string.format('number:%s', tostring(value))
    end
    if value_type == 'string' then
        return string.format('string:%d:%s', #value, value)
    end
    if value_type ~= 'table' then
        error(string.format('cannot persist snapshot value of type %s', value_type))
    end

    local entries = {}
    for key, entry in pairs(value) do
        entries[#entries + 1] = {
            key = canonical_value(key),
            value = canonical_value(entry),
        }
    end
    table.sort(entries, function(left, right)
        return left.key < right.key
    end)

    local parts = { 'table:{' }
    for _, entry in ipairs(entries) do
        parts[#parts + 1] = entry.key
        parts[#parts + 1] = '='
        parts[#parts + 1] = entry.value
        parts[#parts + 1] = ';'
    end
    parts[#parts + 1] = '}'
    return table.concat(parts)
end

---@param snapshot tabulature.SessionSnapshot
---@return string
local function snapshot_digest(snapshot)
    return vim.fn.sha256(canonical_value(snapshot))
end

---@param index table
---@param id string
---@return table?
local function find_snapshot(index, id)
    for _, entry in ipairs(index.snapshots) do
        if entry.id == id then
            return entry
        end
    end
    return nil
end

---@param snapshot tabulature.SessionSnapshot
---@return table
function M.save_snapshot(snapshot)
    local digest = snapshot_digest(snapshot)
    local id = string.format('sha256:%s', digest)
    local now = os.time()
    local filename = snapshot_filename(id)
    local index = read_index()
    local snapshot_path = vim.fs.joinpath(state_dir(), filename)
    local stored = read_json(snapshot_path)
    local index_changed = false

    if stored == nil or snapshot_digest(stored) ~= digest then
        write_json(snapshot_path, snapshot)
    end

    if find_snapshot(index, id) == nil then
        table.insert(index.snapshots, {
            id = id,
            created_at = now,
            top_level_count = type(snapshot.children) == 'table' and #snapshot.children or 0,
            file = filename,
        })
        index_changed = true
    end
    if index.latest_snapshot_id ~= id then
        index.latest_snapshot_id = id
        index_changed = true
    end
    if index_changed then
        write_json(state_file(), index)
    end

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
