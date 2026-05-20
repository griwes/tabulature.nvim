local statuesque_path = vim.env.STATUESQUE_NVIM_PATH
if not statuesque_path or statuesque_path == '' then
    error('STATUESQUE_NVIM_PATH must point to a statuesque.nvim checkout')
end
statuesque_path = vim.fs.normalize(statuesque_path)
if vim.fn.isdirectory(statuesque_path) == 0 then
    error('STATUESQUE_NVIM_PATH is not a plugin checkout: ' .. statuesque_path)
end

package.path = table.concat({
    './lua/?.lua',
    './lua/?/init.lua',
    statuesque_path .. '/lua/?.lua',
    statuesque_path .. '/lua/?/init.lua',
    package.path,
}, ';')

function _G.describe(name, body)
    io.write(name .. '\n')
    body()
end

function _G.it(name, body)
    local ok, err = pcall(body)
    if ok then
        io.write('  ok - ' .. name .. '\n')
    else
        io.write('  not ok - ' .. name .. '\n')
        io.write(tostring(err) .. '\n')
        error(err, 0)
    end
end

dofile('tests/tabulature_model_spec.lua')
dofile('tests/manifold_capability_spec.lua')
dofile('tests/prototype_state_spec.lua')
dofile('tests/session_spec.lua')

io.write('tabulature tests passed\n')
