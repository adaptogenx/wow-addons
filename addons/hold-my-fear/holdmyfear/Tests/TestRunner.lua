--[[
    TestRunner.lua - In-game test runner (/hmf test run)
]]

local _, HMF = ...

HMF.Tests.cases = HMF.Tests.cases or {}

function HMF.Tests.Add(name, fn)
    HMF.Tests.cases[#HMF.Tests.cases + 1] = { name = name, fn = fn }
end

function HMF.Tests.Run()
    local pass, fail = 0, 0
    for _, case in ipairs(HMF.Tests.cases) do
        local ok, err = pcall(case.fn)
        if ok then
            pass = pass + 1
        else
            fail = fail + 1
            HMF.Debug.Print("FAIL", case.name, err)
        end
    end
    HMF.Debug.Print(("tests: %d passed, %d failed"):format(pass, fail))
end
