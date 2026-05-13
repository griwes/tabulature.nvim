local state = require('tabulature.state')
local persistence = require('tabulature.persistence')

local M = {}

---@class tabulature.SessionSnapshot
---@field version integer
---@field active_path integer[]
---@field children table[]

---@class tabulature.SessionSnapshotRef
---@field version integer
---@field state_ref { kind: string, state_file: string, state_dir: string, snapshot_id: string }

---@return tabulature.SessionSnapshot|tabulature.SessionSnapshotRef
function M.capture()
    local snapshot = state.session_snapshot()

    if require('tabulature.config').config.persist_snapshots == false then
        return snapshot
    end

    return persistence.save_snapshot(snapshot)
end

---@param captured tabulature.SessionSnapshot|tabulature.SessionSnapshotRef
---@return continuity.RestorePlanStep[]
function M.plan_restore(captured)
    local snapshot = persistence.load_snapshot(captured)
    local children = type(snapshot) == 'table' and type(snapshot.children) == 'table' and snapshot.children or {}

    if #children == 0 then
        return {}
    end

    return {
        {
            kind = 'tabulature.restore_tabs',
            title = 'Restore Tabulature hierarchy',
            detail = string.format('Restore %d top-level Tabulature tab(s)', #children),
            payload = captured,
        },
    }
end

---@param step continuity.RestorePlanStep
---@return tabulature.SessionSnapshot
function M.restore(step)
    if step.kind ~= 'tabulature.restore_tabs' then
        error(string.format('Unsupported Tabulature restore step: %s', step.kind))
    end

    local snapshot = persistence.load_snapshot(step.payload)
    return state.restore_session_snapshot(snapshot or {})
end

return M
