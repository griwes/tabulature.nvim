package.path = table.concat({
    './lua/?.lua',
    './lua/?/init.lua',
    '../statuesque.nvim/lua/?.lua',
    '../statuesque.nvim/lua/?/init.lua',
    package.path,
}, ';')

local failures = 0

function _G.describe(name, body)
    io.write(name .. '\n')
    body()
end

function _G.it(name, body)
    local ok, err = pcall(body)
    if ok then
        io.write('  ok - ' .. name .. '\n')
    else
        failures = failures + 1
        io.write('  not ok - ' .. name .. '\n')
        io.write(tostring(err) .. '\n')
    end
end

dofile('tests/tabulature_model_spec.lua')
dofile('tests/manifold_capability_spec.lua')
dofile('tests/prototype_state_spec.lua')
dofile('tests/session_spec.lua')

if failures > 0 then
    error(('%d tabulature test(s) failed'):format(failures))
end

io.write('tabulature tests passed\n')
