local M = {
    _buf = nil,
    _win = nil,
    _token = 0,
}

--- @param value any
--- @return string
local function compact(value)
    if value == nil or value == '' then
        return ''
    end
    return tostring(value)
end

--- @param parts string[]
--- @return string
local function join_nonempty(parts)
    local out = {}
    for _, part in ipairs(parts) do
        if part ~= '' then
            out[#out + 1] = part
        end
    end
    return table.concat(out, ' · ')
end

--- @param payload table
--- @return string[]
local function lines_for(payload)
    local label = compact(payload.label or payload.parent_label or payload.id or payload.parent_id)
    local meta = join_nonempty({
        compact(payload.kind),
        payload.level ~= nil and ('level ' .. tostring(payload.level)) or '',
        compact(payload.source),
    })

    if payload.role == 'tab-close' then
        return {
            label ~= '' and ('Close ' .. label) or 'Close tab',
            'Click to close this local tab.',
        }
    end

    if payload.role == 'level-fold' then
        return {
            payload.level ~= nil and ('Fold level ' .. tostring(payload.level)) or 'Fold level',
            'Click to hide this level until it is expanded again.',
        }
    end

    if payload.role == 'level-create' then
        return {
            label ~= '' and ('New child under ' .. label) or 'New child tab',
            'Click to create a tab at this level.',
        }
    end

    local state = join_nonempty({
        payload.current and 'current' or '',
        payload.selected and 'selected' or '',
        meta,
    })

    return {
        label ~= '' and label or 'Tab',
        state ~= '' and state or 'Click to select this tab.',
    }
end

--- @param lines string[]
--- @return string[]
local function padded_lines(lines)
    local padded = {}
    for _, line in ipairs(lines) do
        padded[#padded + 1] = ' ' .. line .. ' '
    end
    return padded
end

local function close()
    if M._win ~= nil and vim.api.nvim_win_is_valid(M._win) then
        vim.api.nvim_win_close(M._win, true)
    end
    M._win = nil
end

--- @return integer
local function ensure_buf()
    if M._buf ~= nil and vim.api.nvim_buf_is_valid(M._buf) then
        return M._buf
    end

    M._buf = vim.api.nvim_create_buf(false, true)
    vim.bo[M._buf].bufhidden = 'hide'
    vim.bo[M._buf].buftype = 'nofile'
    vim.bo[M._buf].swapfile = false
    return M._buf
end

--- @param lines string[]
--- @return integer
local function max_width(lines)
    local width = 1
    for _, line in ipairs(lines) do
        width = math.max(width, vim.fn.strdisplaywidth(line))
    end
    return width
end

--- @param payload table
--- @param height integer
--- @return integer
local function tooltip_row(payload, height)
    local mouse = payload.mouse or {}
    local screenrow = tonumber(mouse.screenrow or payload.row or 1) or 1
    local max_row = math.max(1, vim.o.lines - height - 1)

    if payload.target == 'tabline' or screenrow == 1 then
        return 1
    end

    return math.min(screenrow + 1, max_row)
end

--- @param payload table
local function show(payload)
    local lines = padded_lines(lines_for(payload))
    local buf = ensure_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    local mouse = payload.mouse or {}
    local col = tonumber(mouse.screencol or payload.col or 1) or 1
    local width = max_width(lines)
    local height = #lines
    local editor_width = vim.o.columns

    local row = tooltip_row(payload, height)
    col = math.min(col, math.max(1, editor_width - width - 2))

    local config = {
        relative = 'editor',
        row = row,
        col = col - 1,
        width = width,
        height = height,
        style = 'minimal',
        border = 'rounded',
        focusable = false,
        zindex = 90,
    }

    if M._win ~= nil and vim.api.nvim_win_is_valid(M._win) then
        vim.api.nvim_win_set_config(M._win, config)
        return
    end

    M._win = vim.api.nvim_open_win(buf, false, config)
    vim.wo[M._win].winhl = 'Normal:NormalFloat,FloatBorder:FloatBorder'
end

--- Handle a Tabulature hover payload.
--- @param payload table
function M.handle(payload)
    payload = payload or {}
    M._token = M._token + 1
    local token = M._token
    local scheduled_payload = vim.deepcopy(payload)

    if payload.phase == 'leave' then
        vim.schedule(function()
            if M._token == token then
                close()
            end
        end)
        return nil
    end

    vim.schedule(function()
        if M._token == token then
            show(scheduled_payload)
        end
    end)
    return payload
end

--- Build a direct callback for a render-spec hover action.
--- @param args table
--- @return fun(payload: table): any
function M.callback(args)
    local captured = vim.deepcopy(args or {})
    return function(payload)
        return M.handle(vim.tbl_extend('force', captured, payload or {}))
    end
end

return M
