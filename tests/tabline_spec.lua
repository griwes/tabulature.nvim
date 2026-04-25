describe('tabulature tabline adapter', function()
    it('does not install the tabline on require', function()
        local original_tabline = vim.o.tabline
        local original_showtabline = vim.o.showtabline

        package.loaded['tabulature.tabline'] = nil
        require('tabulature.tabline')

        assert(vim.o.tabline == original_tabline)
        assert(vim.o.showtabline == original_showtabline)
    end)

    it('renders without requiring a lualine palette first', function()
        local text = require('tabulature.tabline').render()

        assert(text:find('TabulatureActive1', 1, true) ~= nil)
    end)

    it('installs the tabline only through setup', function()
        local original_tabline = vim.o.tabline
        local original_showtabline = vim.o.showtabline

        require('tabulature').setup({ tabline = true })

        assert(vim.o.tabline == '%!v:lua.tabulature_tabline()')
        assert(vim.o.showtabline == 2)
        assert(vim.api.nvim_get_hl(0, { name = 'TabulatureActive1' }).bg ~= nil)

        vim.o.tabline = original_tabline
        vim.o.showtabline = original_showtabline
    end)
end)
