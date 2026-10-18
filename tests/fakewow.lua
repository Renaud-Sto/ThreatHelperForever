-- Template from the wow-addon-dev skill (adapted from CraftProfit, MIT): a fake WoW
-- environment for smoke tests. W.boot loads the REAL addon files, in TOC order, into one
-- namespace whose globals fall back to plain Lua (_G): a WoW global you did not stub is
-- nil, which exercises the addon's guards. Not a test file (run.lua only runs test_*.lua).
--
-- Know its limits (references/testing-and-probe.md):
-- * It draws nothing: layout, atlases, fonts, strata, taint are checked in game only.
-- * Every unknown frame method or field answers a no-op FUNCTION. `frame.Inset` is then a
--   function, not nil: production code guards template internals with
--   `type(x) == "table"`, and tests read what the code stored with `rawget`.
-- * Frames start SHOWN, as on the real client (CreateFrame returns a shown frame).
-- * Freeze this file once tests depend on it: let one person change it, never a task.
local W = {}

-- A permissive fake frame: known methods record state, every other method is a no-op.
function W.frame(kind, name, parent, template)
    local f = { scripts = {}, events = {}, shown = true, kind = kind, name = name,
        parent = parent or false, template = template or false, points = {} }
    local methods = {
        SetText = function(self, t) self.text = t end,
        GetText = function(self) return self.text end,
        SetScript = function(self, what, fn) self.scripts[what] = fn end,
        GetScript = function(self, what) return self.scripts[what] end,
        -- Runs the previous handler first, then the hook, like the client.
        HookScript = function(self, what, fn)
            local old = self.scripts[what]
            self.scripts[what] = old and function(...) old(...); fn(...) end or fn
        end,
        RegisterEvent = function(self, e) self.events[e] = true end,
        UnregisterEvent = function(self, e) self.events[e] = nil end,
        IsEventRegistered = function(self, e) return self.events[e] == true end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        SetShown = function(self, v) self.shown = v and true or false end,
        IsShown = function(self) return self.shown end,
        SetParent = function(self, p) self.parent = p end,
        GetParent = function(self) return self.parent or nil end,
        SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
        ClearAllPoints = function(self) self.points = {} end,
        SetSize = function(self, w, h) self.width, self.height = w, h end,
        SetWidth = function(self, w) self.width = w end,
        SetHeight = function(self, h) self.height = h end,
        GetWidth = function(self) return self.width or 0 end,
        GetHeight = function(self) return self.height or 0 end,
        SetChecked = function(self, v) self.checked = v and true or false end,
        GetChecked = function(self) return self.checked end,
        IsEnabled = function(self) return self.enabled ~= false end,
        SetEnabled = function(self, v) self.enabled = v and true or false end,
        CreateFontString = function(self) return W.frame("FontString", nil, self) end,
        CreateTexture = function(self) return W.frame("Texture", nil, self) end,
    }
    return setmetatable(f, { __index = function(_, k) return methods[k] or function() end end })
end

-- opts: locale ("enUS"), items = { [itemID] = { name, quality, ilvl, sellPrice, classID, bindType } }
function W.boot(H, opts)
    opts = opts or {}
    local ns = {}
    local env = setmetatable({}, { __index = _G })
    local T = { ns = ns, env = env, chat = {}, timers = {}, tickers = {}, frames = {}, clock = 1000 }

    env.GetTime = function() return T.clock end
    env.time = function() return 1700000000 end
    env.date = os.date
    env.GetLocale = function() return opts.locale or "enUS" end
    env.issecretvalue = function() return false end
    env.hooksecurefunc = function() end
    env.UIParent = W.frame("Frame", "UIParent")
    env.UISpecialFrames = {}
    env.SlashCmdList = {}
    env.Enum = {}
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) T.chat[#T.chat + 1] = m end }
    env.CreateFrame = function(kind, name, parent, template)
        local f = W.frame(kind, name, parent, template)
        T.frames[#T.frames + 1] = f
        if name then env[name] = f end
        return f
    end
    -- Unknown atlases by default, so the addon's fallbacks run; a test can stub sizes.
    env.C_Texture = { GetAtlasInfo = function(atlas) return opts.atlases and opts.atlases[atlas] end }
    env.C_Timer = {
        After = function(_, fn) T.timers[#T.timers + 1] = fn end,
        NewTicker = function(_, fn)
            local ticker = { fn = fn, cancelled = false }
            function ticker.Cancel() ticker.cancelled = true end
            T.tickers[#T.tickers + 1] = ticker
            return ticker
        end,
    }
    env.C_Item = {
        GetItemInfo = function(id)
            local i = opts.items and opts.items[id]
            if not i then return nil end
            return i.name or ("Item" .. id), "link", i.quality, i.ilvl, 1, "type", "sub", 1, "", 0,
                i.sellPrice, i.classID, 0, i.bindType
        end,
        RequestLoadItemDataByID = function() end,
    }

    for _, file in ipairs(H.tocFiles()) do
        H.loadModule((file:gsub("%.lua$", "")), ns, env)
    end

    -- Runs every callback scheduled with C_Timer.After (and the ones they schedule).
    function T.run()
        while #T.timers > 0 do table.remove(T.timers, 1)() end
    end
    -- Advances the clock and runs every live ticker once.
    function T.tick(seconds)
        T.clock = T.clock + (seconds or 0)
        for _, t in ipairs(T.tickers) do if not t.cancelled then t.fn(t) end end
    end
    -- Delivers an event to every frame that registered it, as the client would.
    function T.fire(event, ...)
        for _, f in ipairs(T.frames) do
            local handler = rawget(f, "scripts").OnEvent
            if f.events[event] and handler then handler(f, event, ...) end
        end
    end
    return T
end

return W
