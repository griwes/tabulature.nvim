--- @class tabulature.StatuesqueWidgetOptions
--- @field tree_opts? table
--- @field local_actions? boolean Enable direct local Neovim tabpage actions for locally sourced Tabulature state.
--- @field hover? boolean Enable Tabulature hover callbacks for rendered tabline controls.
--- @field [string] any

--- @param opts? tabulature.StatuesqueWidgetOptions
--- @return statuesque.RenderFunction
return function(opts)
    opts = opts or {}
    return function()
        local render_ok, renderer = pcall(require, 'tabulature.render.statuesque')
        if not render_ok or type(renderer.to_spec) ~= 'function' then
            return false
        end

        local root
        local local_actions = opts.local_actions
        local state_ok, state = pcall(require, 'tabulature.state')
        if state_ok and type(state) == 'table' and type(state.to_tree) == 'function' then
            root = state.to_tree(opts.tree_opts or {})
            if local_actions == nil then
                local_actions = true
            end
        else
            local tabulature_ok, tabulature = pcall(require, 'tabulature')
            if tabulature_ok and type(tabulature) == 'table' and type(tabulature.api) == 'table' then
                root = type(tabulature.api.tree) == 'function' and tabulature.api.tree() or nil
            end
        end

        if root == nil then
            return false
        end

        return renderer.to_spec(root, vim.tbl_extend('force', opts, { local_actions = local_actions }))
    end
end
