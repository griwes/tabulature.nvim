local default_order = { 'normal', 'visual', 'insert', 'terminal', 'replace', 'command' }

local palette_size = 0

local M = {}

local function style()
    return require('statuesque.style')
end

local function derive_fold(inactive)
    return {
        fg = inactive.fg,
        bg = inactive.bg,
        bold = true,
        italic = inactive.italic,
        underline = inactive.underline,
    }
end

local function derive_level(fill, inactive)
    return {
        fg = fill.fg,
        bg = style().interpolate_color(fill.bg, inactive.bg, 0.45),
        bold = fill.bold,
        italic = fill.italic,
        underline = fill.underline,
    }
end

local function inactive_style(mode)
    local levels = style().highlight_levels(2, 'tabline', {
        mode_style = mode,
    })
    return levels[2] or levels[1] or style().backend_defaults('tabline').inner
end

local function setup_level(level_number, active, inactive, fill, fold, level_style)
    local level = tostring(level_number)
    level_style = level_style or fill
    vim.api.nvim_set_hl(0, 'Tabulature' .. level, inactive)
    vim.api.nvim_set_hl(0, 'TabulatureActive' .. level, active)
    vim.api.nvim_set_hl(0, 'TabulatureLevel' .. level, level_style)

    vim.api.nvim_set_hl(0, 'TabulaturePrefix' .. level, { fg = fill.fg, bg = inactive.bg })
    vim.api.nvim_set_hl(0, 'TabulatureActivePrefix' .. level, { fg = fill.fg, bg = active.bg })

    vim.api.nvim_set_hl(0, 'TabulatureSolid' .. level, { fg = inactive.bg, bg = fill.bg })
    vim.api.nvim_set_hl(0, 'TabulatureActiveSolid' .. level, { fg = active.bg, bg = fill.bg })
    vim.api.nvim_set_hl(0, 'TabulatureLevelSolid' .. level, { fg = inactive.bg, bg = level_style.bg })
    vim.api.nvim_set_hl(0, 'TabulatureActiveLevelSolid' .. level, { fg = active.bg, bg = level_style.bg })
    vim.api.nvim_set_hl(0, 'TabulatureFold' .. level, fold or inactive)
    vim.api.nvim_set_hl(0, 'TabulatureFoldSolid' .. level, { fg = (fold or inactive).bg, bg = fill.bg })
    vim.api.nvim_set_hl(0, 'TabulatureFoldLevelSolid' .. level, { fg = (fold or inactive).bg, bg = level_style.bg })
    vim.api.nvim_set_hl(0, 'TabulatureSeparator' .. level, { fg = active.bg, bg = fill.bg, bold = true })
end

function M.setup(opts)
    opts = opts or {}
    local order = opts.order or default_order
    local defaults = style().backend_defaults('tabline', {
        style = opts.style,
    })
    local fill = defaults.base

    setup_level(0, fill, fill, fill, fill, fill)

    for i, mode in ipairs(order) do
        local active = style().mode_style(mode)
        local inactive = inactive_style(mode)
        local fold = derive_fold(inactive)
        local level_style = derive_level(fill, inactive)

        setup_level(i, active, inactive, fill, fold, level_style)
    end

    palette_size = #order
end

function M.palette_size()
    return palette_size
end

return M
