local default_order = { 'normal', 'visual', 'insert', 'terminal', 'replace', 'command' }

local palette_size = 0

local M = {}

local fallback_fill = { fg = 0xcdd6f4, bg = 0x1e1e2e }

local fallback_modes = {
    normal = {
        active = { fg = 0x11111b, bg = 0x89b4fa, bold = true },
        inactive = { fg = 0xcdd6f4, bg = 0x313244 },
    },
    visual = {
        active = { fg = 0x11111b, bg = 0xcba6f7, bold = true },
        inactive = { fg = 0xcdd6f4, bg = 0x45475a },
    },
    insert = {
        active = { fg = 0x11111b, bg = 0xa6e3a1, bold = true },
        inactive = { fg = 0xcdd6f4, bg = 0x3a4a3a },
    },
    terminal = {
        active = { fg = 0x11111b, bg = 0xf9e2af, bold = true },
        inactive = { fg = 0xcdd6f4, bg = 0x4a432f },
    },
    replace = {
        active = { fg = 0x11111b, bg = 0xf38ba8, bold = true },
        inactive = { fg = 0xcdd6f4, bg = 0x4a3039 },
    },
    command = {
        active = { fg = 0x11111b, bg = 0x94e2d5, bold = true },
        inactive = { fg = 0xcdd6f4, bg = 0x314745 },
    },
}

local function get_hl(name)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
    if not ok or type(hl) ~= 'table' then
        return {}
    end
    return hl
end

local function normalize_hl(source, fallback)
    source = source or {}
    fallback = fallback or fallback_fill

    return {
        fg = source.fg or fallback.fg,
        bg = source.bg or fallback.bg,
        bold = source.bold ~= nil and source.bold or fallback.bold,
        italic = source.italic ~= nil and source.italic or fallback.italic,
        underline = source.underline ~= nil and source.underline or fallback.underline,
    }
end

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

    local llchl = normalize_hl(get_hl('lualine_c_normal'), fallback_fill)

    setup_level(0, llchl, llchl, llchl)

    for i, mode in ipairs(order) do
        local fallback = fallback_modes[mode] or fallback_modes.normal
        local llahl = normalize_hl(get_hl('lualine_a_' .. mode), fallback.active)
        local llbhl = normalize_hl(get_hl('lualine_b_' .. mode), fallback.inactive)

        setup_level(i, llahl, llbhl, llchl)
    end

    palette_size = #order
end

function M.palette_size()
    return palette_size
end

return M
