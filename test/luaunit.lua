local m = {}

local inspect = require "inspect"

local function split(str)
    local r = {}
    str:gsub('[^\n]+', function (w) r[#r+1] = w end)
    return r
end

local sourcename = debug.getinfo(1, "S").source:match "[/\\]([^/\\]*)%.lua$"
local sourcepatt = '[/\\]'..sourcename..'%.lua:%d+: '
local function pretty_trace(funcName, stackTrace)
    local function isInternalLine( s )
        return s:find(sourcepatt) ~= nil
    end
    local lst = split(stackTrace)
    local n = #lst
    local first, last = n, n
    for i = 2, n do
        if not isInternalLine(lst[i]) then
            first = i
            break
        end
    end
    for i = first + 1, n do
        if isInternalLine(lst[i]) then
            last = i - 1
            break
        end
    end
    lst[first-1] = lst[1]
    local trace = table.concat(lst, '\n', first-1, last)
    trace = trace:gsub("in (%a+) 'methodInstance'", "in %1 '"..funcName.."'")
    return trace
end

local function recursion_get(t, actual)
    local subtable = t[actual]
    if not subtable then
        subtable = {}
        t[actual] = subtable
    end
    return subtable
end

local equals_value

local function equals_table(actual, expected, recursions)
    for k, v in pairs(actual) do
        if not equals_value(v, expected[k], recursions) then
            return false
        end
    end
    for k, v in pairs(expected) do
        if not equals_value(actual[k], v, recursions) then
            return false
        end
    end
    return equals_value(getmetatable(actual), getmetatable(expected), recursions)
end

function equals_value(actual, expected, recursions)
    if type(actual) ~= type(expected) then
        return false
    end
    if type(actual) ~= 'table' then
        return actual == expected
    end
    local subtable = recursion_get(recursions, actual)
    local previous = subtable[expected]
    if previous ~= nil  then
        return previous
    end
    subtable[expected] = true
    local ok = equals_table(actual, expected, recursions)
    subtable[expected] = ok
    return ok
end

local function equals(actual, expected)
    local recursions = {}
    return equals_value(actual, expected, recursions)
end

local function failure(...)
    error(string.format(...), 3)
end

function m.assertEquals(actual, expected)
    if not equals(actual, expected) then
        failure("expected: %s, actual: %s", inspect(expected), inspect(actual))
    end
end

function m.assertNotEquals(actual, expected)
    if equals(actual, expected) then
        failure('Received the not expected value: %s', inspect(actual))
    end
end

function m.assertError(f, ...)
    if pcall(f, ...) then
        failure("Expected an error when calling function but no error generated")
    end
end

function m.assertErrorMsgEquals(expectedMsg, func, ...)
    local success, actualMsg = pcall(func, ...)
    if success then
        failure('No error generated when calling function but expected error: %s', inspect(expectedMsg))
    end
    m.assertEquals(actualMsg, expectedMsg)
end

for _, name in ipairs {'Nil', 'Number', 'String', 'Table', 'Boolean', 'Function', 'Userdata', 'Thread'} do
    local typeExpected = name:lower()
    m["assertIs"..name] = function(value)
        if type(value) ~= typeExpected then
            failure('expected: a %s value, actual: type %s, value %s', typeExpected, type(value), inspect(value))
        end
    end
end

local function parseCmdLine(cmdLine)
    local result = {}
    for _, cmdArg in ipairs(cmdLine) do
        if cmdArg:sub(1,1) == '-' then
            if cmdArg == '--verbose' or cmdArg == '-v' then
                result.verbosity = true
            elseif cmdArg == '--shuffle' or cmdArg == '-s' then
                result.shuffle = true
            else
                error('Unknown option: '..cmdArg)
            end
        else
            result[#result+1] = cmdArg
        end
    end
    return result
end

local function errorHandler(e)
    return { msg = e, trace = string.sub(debug.traceback("", 3), 2) }
end

local function execFunction(options, failures, name, classInstance, methodInstance)
    if options.verbosity then
        io.stdout:write("    ", name, " ... ")
        io.stdout:flush()
    end
    local ok, err = xpcall(function () methodInstance(classInstance) end, errorHandler)
    if ok then
        if options.verbosity then
            io.stdout:write("Ok\n")
        else
            io.stdout:write(".")
        end
    else
        err.name = name
        err.trace = pretty_trace(name, err.trace)
        if type(err.msg) ~= 'string' then
            err.msg = inspect(err.msg)
        end
        failures[#failures+1] = err
        if options.verbosity then
            io.stdout:write("FAIL\n")
            io.stdout:write(err.msg)
            io.stdout:write("\n")
        else
            io.stdout:write("F")
        end
    end
    io.stdout:flush()
end

local function matchPattern(expr, patterns)
    for _, pattern in ipairs(patterns) do
        if expr:find(pattern) then
            return true
        end
    end
end

local function selectList(patterns, lst)
    if #patterns == 0 then
        return lst
    end
    local includedPattern, excludedPattern = {}, {}
    for _, pattern in ipairs(patterns) do
        if pattern:sub(1,1) == '~' then
            excludedPattern[#excludedPattern+1] = pattern:sub(2)
        else
            includedPattern[#includedPattern+1] = pattern
        end
    end
    local res = {}
    if #includedPattern ~= 0 then
        for _, v in ipairs(lst) do
            local expr = v[1]
            if matchPattern(expr, includedPattern) and not matchPattern(expr, excludedPattern) then
                res[#res+1] = v
            end
        end
    else
        for _, v in ipairs(lst) do
            local expr = v[1]
            if not matchPattern(expr, excludedPattern) then
                res[#res+1] = v
            end
        end
    end
    return res
end

local function randomizeTable(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        if i ~= j then
            t[i], t[j] = t[j], t[i]
        end
    end
end

local instanceSet = {}

function m.test(name)
    if instanceSet[name] then
        return instanceSet[name]
    end
    local instance = setmetatable({}, {__newindex=function(self, k, v)
        if type(v) == "function" then
            rawset(self, #self+1, k)
        end
        rawset(self, k, v)
    end})
    instanceSet[name] = instance
    instanceSet[#instanceSet+1] = name
    return instance
end

function m.run()
    local options = parseCmdLine(rawget(_G, "arg") or {})
    local lst = {}
    for _, name in ipairs(instanceSet) do
        local instance = instanceSet[name]
        for _, methodName in ipairs(instance) do
            lst[#lst+1] = { name..'.'..methodName, instance, instance[methodName] }
        end
    end
    if options.shuffle then
        randomizeTable(lst)
    end
    local selected = selectList(options, lst)
    if options.verbosity then
        print('Started on '.. os.date())
    end
    local failures = {}
    collectgarbage "collect"
    local startTime = os.clock()
    for _, v in ipairs(selected) do
        local name, instance, methodInstance = v[1], v[2], v[3]
        execFunction(options, failures, name, instance, methodInstance)
    end
    local duration = os.clock() - startTime
    if options.verbosity then
        print("=========================================================")
    else
        print()
    end
    if #failures ~= 0 then
        print("Failed tests:")
        print("-------------")
        for i, err in ipairs(failures) do
            print(i..") "..err.name)
            print(err.msg)
            print(err.trace)
            print()
        end
    end
    local s = {
        string.format('Ran %d tests in %0.3f seconds, %d successes, %d failures', #selected, duration, #selected - #failures, #failures),
    }
    local nonSelectedCount = #lst - #selected
    if nonSelectedCount > 0 then
        s[#s+1] = string.format("%d non-selected", nonSelectedCount)
    end
    print(table.concat(s, ', '))
    if #failures == 0 then
        print('OK')
    end
    return #failures == 0
end

return m
