local M = {}

--- Configure optional Tabulature UI surfaces.
--- @param opts? { tabline?: boolean|table }
function M.setup(opts)
    opts = opts or {}
    if opts.tabline then
        local tabline_opts = type(opts.tabline) == 'table' and opts.tabline or {}
        require('tabulature.tabline').setup(tabline_opts)
    end
end

return M
