local root = debug.getinfo(1, 'S').source:sub(2):match('(.*/)') .. '../'
local handlers, writes, migrations = {}, {}, nil
local playerData = {
    citizenid = 'CID-1',
    job = { name = 'police', grade = { level = 2 }, onduty = false },
}

_G.CreateThread = function(handler) handler() end
_G.AddEventHandler = function(name, handler) handlers[name] = handler end
_G.LoadResourceFile = function(_, file)
    local handle = assert(io.open(root .. file, 'r'))
    local contents = handle:read('*a')
    handle:close()
    return contents
end
_G.GetCurrentResourceName = function() return 'kora_multijob' end
_G.json = {
    encode = function(value)
        local police = value.police
        assert(police.gradeLabel == 'Officer' and police.jobLabel == 'Police' and police.pay == 100,
            'saved records must cache the current job display data')
        return ('police:%s:%s'):format(police.name, police.level)
    end,
    decode = function() return {} end,
}

local exported = {}
local dutyCalls, allowDuty = {}, true
_G.exports = setmetatable({
    kora_core = {
        getPlayerData = function(_, src) return src == 1 and playerData or nil end,
        getPlayers = function() return {} end,
        hasPermission = function() return true end,
        setJobDuty = function(_, src, value)
            dutyCalls[#dutyCalls + 1] = { src = src, value = value }
            return allowDuty
        end,
    },
}, { __call = function(_, name, fn) exported[name] = fn end })

_G.Kora = {
    lang = function(key, ...)
        local text = dofile(root .. 'locales/en.lua')[key] or key
        return select('#', ...) > 0 and text:format(...) or text
    end,
    sql = {
        ready = function() return true end,
        ensureTables = function(specs)
            migrations = specs
            return {}
        end,
        single = function() return nil end,
        upsert = function(_, _, rows)
            writes[#writes + 1] = rows[1]
            return 1
        end,
    },
    shared = {
        get = function(_, name)
            local jobs = {
                police = { label = 'Police', grades = { [2] = { name = 'Officer', payment = 100 } } },
                unemployed = { label = 'Unemployed', grades = { [1] = { name = 'Unemployed', payment = 0 } } },
            }
            return jobs[name]
        end,
    },
    callback = { register = function() end },
    notify = { send = function() end },
    commands = { add = function() end },
}

dofile(root .. 'shared/config.lua')
dofile(root .. 'server/schema.lua')
dofile(root .. 'server/server.lua')

assert(migrations == KoraMultijobSchema and #migrations == 1, 'the kora_multijob schema must be declared through ensureTables')
assert(migrations[1].name == 'kora_multijob_jobs', 'the schema must declare kora_multijob_jobs')
local hasName
for _, column in ipairs(migrations[1].columns) do
    if column.name == 'name' and column.type == 'varchar(128)' then hasName = true end
end
assert(hasName, 'the schema must include roster names')

handlers['QBCore:Server:OnJobUpdate'](1)

assert(#writes == 1, 'a kora_core job update must write the roster immediately')
assert(writes[1].pk == 'CID-1', 'the roster write must use the character citizenid')
assert(writes[1].cols.jobs == 'police:police:2', 'the roster must retain kora_core’s one-based grade')
print('kora_multijob server: job updates persist immediately')

local setDuty = assert(exported.setDuty, 'setDuty must be exported')
local ok, reason = setDuty(1, true)
assert(ok == false and reason == 'duty_change_disabled', 'jobs in Config.disabledDuty must refuse duty changes')
assert(#dutyCalls == 0, 'a locked job must never reach kora_core')

playerData.job = { name = 'mechanic', grade = { level = 1 }, onduty = false }
ok, reason = setDuty(1, true)
assert(ok == true and reason == nil, 'an unlocked job can change duty')
assert(#dutyCalls == 1 and dutyCalls[1].src == 1 and dutyCalls[1].value == true, 'kora_core setJobDuty applies the change')

ok, reason = setDuty(1, 'yes')
assert(ok == false and reason == 'invalid_duty', 'duty must be a boolean')
ok, reason = setDuty(99, true)
assert(ok == false and reason == 'character_not_loaded', 'unknown players are refused')
assert(#dutyCalls == 1, 'refused calls never reach kora_core')

allowDuty = false
ok, reason = setDuty(1, false)
assert(ok == false and reason == 'duty_change_failed', 'a kora_core refusal is reported')
print('kora_multijob server: setDuty export honours disabledDuty')
