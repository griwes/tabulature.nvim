local state = require('tabulature.state')

local M = {}

---@class tabulature.SessionSnapshot
---@field version integer
---@field active_path integer[]
---@field children table[]

---@return tabulature.SessionSnapshot
function M.capture()
    return state.session_snapshot()
end

---@param captured tabulature.SessionSnapshot
---@return continuity.RestorePlanStep[]
function M.plan_restore(captured)
    local children = type(captured) == 'table' and type(captured.children) == 'table' and captured.children or {}

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

    return state.restore_session_snapshot(step.payload)
end

return M
