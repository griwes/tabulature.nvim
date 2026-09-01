local M = {}

function M.check()
    vim.health.start('tabulature.nvim')

    if vim.fn.has('nvim-0.11') == 1 then
        vim.health.ok('Neovim 0.11 or newer')
    else
        vim.health.error('Neovim 0.11 or newer is required')
    end

    if pcall(require, 'statuesque') then
        vim.health.ok('Statuesque tabline renderer is available')
    else
        vim.health.warn('statuesque.nvim is required to render the Tabulature tabline')
    end

    if pcall(require, 'continuity') then
        vim.health.ok('Continuity snapshot integration is available')
    else
        vim.health.info('Continuity snapshot integration is not installed')
    end

    local config = require('tabulature.config').config
    if config.persist_snapshots then
        vim.health.info('Snapshots will be stored under: ' .. config.state_dir)
    else
        vim.health.ok('Snapshot persistence is disabled')
    end
end

return M
