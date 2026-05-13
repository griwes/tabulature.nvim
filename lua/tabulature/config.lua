local M = {}

--- @class tabulature.Config
--- @field style? 'inherit'|'slanted'|'capsule'|string
--- @field hover? boolean
--- @field persist_snapshots? boolean
--- @field state_file? string
--- @field state_dir? string

local state_root = vim.fs.joinpath(vim.fn.stdpath('state'), 'tabulature.nvim')

---@type tabulature.Config
local defaults = {
    style = 'inherit',
    hover = true,
    persist_snapshots = true,
    state_file = vim.fs.joinpath(state_root, 'snapshots.json'),
    state_dir = vim.fs.joinpath(state_root, 'snapshots'),
}

--- @type tabulature.Config
M.config = vim.deepcopy(defaults)

--- @param opts? tabulature.Config
function M.configure(opts)
    M.config = vim.tbl_deep_extend('force', M.config, opts or {})

    if opts ~= nil and opts.state_file ~= nil and opts.state_dir == nil then
        M.config.state_dir = string.format('%s.d', M.config.state_file)
    end
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
