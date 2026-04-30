local M = {}

--- @class tabulature.Config
--- @field style? 'inherit'|'slanted'|'capsule'|string
--- @field hover? boolean

--- @type tabulature.Config
M.config = {
    style = 'inherit',
    hover = true,
}

--- @param opts? tabulature.Config
function M.configure(opts)
    M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

--- @return string
function M.style()
    return M.config.style or 'inherit'
end

--- @return boolean
function M.hover_enabled()
    return M.config.hover ~= false
end

return M
