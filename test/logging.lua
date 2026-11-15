-- Run from the resource root: lua test/logging.lua
-- Schema setup failure must reach Kora.logging.error (event + error in fields), never print.
local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local calls = {}
local function spy(level)
    return function(event, message, fields)
        calls[#calls + 1] = { level = level, event = event, message = message, fields = fields }
        return true
    end
end
local env = setmetatable({}, { __index = _G })
env._G = env
env.print = function() error('server.lua must log through Kora.logging, not print') end
env.CreateThread = function(handler) handler() end
env.AddEventHandler = function() end
env.RegisterNetEvent = function() end
env.KoraMultijobSchema = {}
env.Kora = {
    logging = { error = spy('error'), warn = spy('warn'), info = spy('info') },
    sql = { ready = function() return true end, ensureTables = function() return nil, 'boom' end },
}
local chunk = assert(loadfile(root .. 'server/server.lua', 't', env))
local ok, err = pcall(chunk)
local call = assert(calls[1], 'a logger call was made (load result: ' .. tostring(err) .. ')')
assert(call.level == 'error' and call.event == 'schema.setup_failed', 'stable error event name')
assert(call.fields.error == 'boom', 'logger fields carry the error')
print('kora_multijob: schema failure is logged through Kora.logging')
