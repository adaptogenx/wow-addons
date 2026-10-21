-- Minimal offline WoW environment for loading shared/ui files.
-- Frames are recording fakes: enough surface for PHUI/MetricRow/ScrollBar/
-- GlanceFrame/PositionStrategy, not a client emulator.
local M = {}

local function newFake(kind, parent)
    local f = { __kind = kind, __parent = parent, __scripts = {}, __points = {}, __calls = {} }
    local methods = {}
    function methods.SetSize(self, w, h) self.w, self.h = w, h end
    function methods.GetSize(self) return self.w, self.h end
    function methods.SetWidth(self, w) self.w = w end
    function methods.SetHeight(self, h) self.h = h end
    function methods.GetWidth(self) return self.w end
    function methods.GetHeight(self) return self.h end
    function methods.SetPoint(self, ...) self.__points[#self.__points + 1] = { ... } end
    function methods.ClearAllPoints(self) self.__points = {} end
    function methods.GetPoint(self)
        local p = self.__points[#self.__points]
        if not p then return nil end
        return p[1], p[2], p[3], p[4], p[5]
    end
    function methods.SetScript(self, name, fn) self.__scripts[name] = fn end
    function methods.GetScript(self, name) return self.__scripts[name] end
    function methods.SetText(self, t) self.text = t end
    function methods.GetText(self) return self.text end
    function methods.SetTextColor(self, r, g, b, a) self.textColor = { r, g, b, a } end
    function methods.SetFont(self, p, s, fl) self.font = { p, s, fl } end
    function methods.SetBackdrop(self, b) self.backdrop = b end
    function methods.SetBackdropColor(self, r, g, b, a) self.backdropColor = { r, g, b, a } end
    function methods.SetBackdropBorderColor(self, r, g, b, a) self.borderColor = { r, g, b, a } end
    function methods.SetTexture(self, t) self.texture = t end
    function methods.GetTexture(self) return self.texture end
    function methods.SetTexCoord(self, ...) self.texCoord = { ... } end
    function methods.SetNormalTexture(self, t) self.normalTexture = t end
    function methods.SetPushedTexture(self, t) self.pushedTexture = t end
    function methods.SetColorTexture(self, r, g, b, a) self.colorTexture = { r, g, b, a } end
    function methods.CreateTexture(self) return newFake("Texture", self) end
    function methods.CreateFontString(self, _, _, template)
        local fs = newFake("FontString", self)
        fs.template = template
        return fs
    end
    function methods.CreateFrame(self) return newFake("Frame", self) end
    function methods.Show(self) self.shown = true end
    function methods.Hide(self) self.shown = false end
    function methods.IsShown(self) return self.shown == true end
    function methods.SetMinMaxValues(self, a, b) self.min, self.max = a, b end
    function methods.GetMinMaxValues(self) return self.min or 0, self.max or 0 end
    function methods.SetValue(self, v)
        self.value = v
        if self.__scripts.OnValueChanged then self.__scripts.OnValueChanged(self, v) end
    end
    function methods.SetShown(self, v) self.shown = v and true or false end
    function methods.SetVerticalScroll(self, v) self.vscroll = v end
    function methods.GetVerticalScroll(self) return self.vscroll or 0 end
    function methods.GetParent(self) return self.__parent end
    function methods.GetValue(self) return self.value or 0 end
    function methods.GetEffectiveScale() return 1 end
    function methods.GetLeft(self) return self.left end
    function methods.GetTop(self) return self.top end
    return setmetatable(f, {
        __index = function(_, k)
            if methods[k] then return methods[k] end
            if type(k) == "string" and k:match("^[A-Z]") then
                return function() end -- unknown Set*/Enable*/... calls are no-ops
            end
            return nil
        end,
    })
end

-- opts.interface: toc number returned by GetBuildInfo (default 11504)
-- opts.noPortraitTemplate: CreateFrame errors for PortraitFrameTemplate
function M.newEnv(opts)
    opts = opts or {}
    local env = { writes = {} }
    local globals = {
        math = math, string = string, table = table, select = select, type = type,
        tonumber = tonumber, tostring = tostring, pairs = pairs, ipairs = ipairs,
        pcall = pcall, error = error, setmetatable = setmetatable, unpack = unpack or table.unpack,
        next = next, print = print,
    }
    globals.GetBuildInfo = function() return "1.0", "1", "d", opts.interface or 11504 end
    globals.UIParent = newFake("Frame")
    globals.UIParent.left, globals.UIParent.top, globals.UIParent.w, globals.UIParent.h = 0, 1080, 1920, 1080
    globals.GameTooltip = newFake("Frame")
    globals.GameTooltip.shown = false
    globals.GameTooltip.SetOwner = function(self, owner, anchor) self.owner, self.anchor = owner, anchor end
    globals.GameTooltip.SetText = function(self, t) self.text = t end
    globals.GameTooltip.Show = function(self) self.shown = true end
    globals.GameTooltip.Hide = function(self) self.shown = false end
    globals.CreateFrame = function(kind, name, parent, template)
        if template == "PortraitFrameTemplate" then
            if opts.noPortraitTemplate then error("no such template") end
            local f = newFake(kind, parent)
            f.template = template
            f.PortraitContainer = { portrait = newFake("Texture") }
            f.SetTitle = function(self, t) self.title = t end
            f.CloseButton = newFake("Button")
            return f
        end
        local f = newFake(kind, parent)
        f.template = template
        return f
    end
    -- Globals the stub environment knows; anything else read is nil, any
    -- WRITE is recorded as a leak.
    env.G = setmetatable({}, {
        __index = globals,
        __newindex = function(_, k, v) env.writes[#env.writes + 1] = tostring(k) end,
    })
    rawset(env.G, "_G", env.G)
    return env
end

-- Load a Lua file as an addon chunk: `...` = (addonName, addonTable), global
-- environment = env.G. Works on Lua 5.1 (setfenv) and 5.2+ (load env arg).
function M.loadAddonFile(env, path, addonName, addonTable)
    local fh = assert(io.open(path, "r"), "cannot open " .. path)
    local src = fh:read("*a")
    fh:close()
    local chunk, err
    if setfenv then
        chunk, err = loadstring(src, "@" .. path)
        if chunk then setfenv(chunk, env.G) end
    else
        chunk, err = load(src, "@" .. path, "t", env.G)
    end
    assert(chunk, err)
    return chunk(addonName, addonTable)
end

function M.newFake(kind) return newFake(kind) end

return M
