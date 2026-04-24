local default_order = { 'normal', 'visual', 'insert', 'terminal', 'replace', 'command' }

local palette_size = 0

local M = {}

local function setup_level(level_number, active, inactive, fill)
    local level = tostring(level_number)
    vim.api.nvim_set_hl(0, 'Tabulature' .. level, inactive)
    vim.api.nvim_set_hl(0, 'TabulatureActive' .. level, active)

    vim.api.nvim_set_hl(0, 'TabulaturePrefix' .. level, { fg = fill.fg, bg = inactive.bg })
    vim.api.nvim_set_hl(0, 'TabulatureActivePrefix' .. level, { fg = fill.fg, bg = active.bg })

    vim.api.nvim_set_hl(0, 'TabulatureSolid' .. level, { fg = inactive.bg, bg = fill.bg })
    vim.api.nvim_set_hl(0, 'TabulatureActiveSolid' .. level, { fg = active.bg, bg = fill.bg })
end

function M.setup(opts)
    opts = opts or {}
    local order = opts.order or default_order

    local llchl = vim.api.nvim_get_hl(0, { name = 'lualine_c_normal' })

    setup_level(0, llchl, llchl, llchl)

    for i, mode in ipairs(order) do
        local llahl = vim.api.nvim_get_hl(0, { name = 'lualine_a_' .. mode })
        local llbhl = vim.api.nvim_get_hl(0, { name = 'lualine_b_' .. mode })

        setup_level(i, llahl, llbhl, llchl)
    end

    palette_size = #order
end

function M.palette_size()
    return palette_size
end

return M
