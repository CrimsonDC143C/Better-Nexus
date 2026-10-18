-- Explicit UI consent. This module never performs a game/save action.
Nexus = Nexus or {}
local M = { VERSION = 1 }
Nexus.OverwriteWarning = M
local frame, active, onboardingOutcome
local TEXT = "Auto can overwrite your active game Saved Build. It may replace Echoes you value, including Echoes obtained with Orbs. Nexus cannot undo that save or recover spent Orbs.\n\nAfter a finished run at level 80, changing the assignment or saving edits to its assigned Wishlist can cause replacement without a new run.\n\nChoose No to keep Auto OFF. Opening this warning does not enable Auto."

local function CurrentOwner()
    local store = Nexus.Store
    if not store or type(store.CurrentOwnerKey) ~= "function" then return nil end
    local ok, owner = pcall(store.CurrentOwnerKey)
    return ok and owner or nil
end

local function Suppressed(kind)
    local prefs = type(NexusDB) == "table" and rawget(NexusDB, "overwriteWarnings")
    local entry = type(prefs) == "table" and rawget(prefs, kind)
    return type(entry) == "table" and rawget(entry, "version") == M.VERSION
        and rawget(entry, "suppressed") == true
end

local function SaveSuppression(request)
    if type(NexusDB) ~= "table" or NexusDB ~= request.database then return false end
    local store = Nexus.Store
    if type(store) ~= "table" or type(store.StateWriteStatus) ~= "function" then return false end
    local ok, status = pcall(store.StateWriteStatus)
    if not ok or type(status) ~= "table" or status.mode ~= "durable" then return false end
    if type(Nexus.StartupStatus) ~= "function" then return false end
    local ready, startup = pcall(Nexus.StartupStatus)
    if not ready or type(startup) ~= "table" or not startup.coreReady then return false end
    local prefs = rawget(NexusDB, "overwriteWarnings")
    if prefs ~= nil and type(prefs) ~= "table" then return false end
    local entry = prefs and rawget(prefs, request.kind)
    -- Preserve unknown/future saved values rather than repairing them here.
    if entry ~= nil then
        if type(entry) ~= "table" then return false end
        local version, suppressed = rawget(entry,"version"), rawget(entry,"suppressed")
        if type(version) ~= "number" or version ~= version or version < 0
            or version > M.VERSION or version ~= math.floor(version)
            or type(suppressed) ~= "boolean" then return false end
    end
    if not prefs then prefs = {}; NexusDB.overwriteWarnings = prefs end
    entry = entry or {}
    entry.version = M.VERSION; entry.suppressed = true
    prefs[request.kind] = entry
    return true
end

local function ReadingClock()
    if type(GetTime) ~= "function" then return nil end
    local ok, now = pcall(GetTime)
    if not ok or type(now) ~= "number" or now ~= now or now < 0
        or now >= math.huge then return nil end
    return now
end

local function Remaining()
    if not active or active.kind ~= "onboarding" then return 0 end
    local now = ReadingClock()
    if not now then
        active.startedAt, active.lastClock = nil, nil
        return 5
    end
    -- An unavailable or reversed clock proves no reading interval. Recover
    -- from the first valid sample instead of inventing a time-zero deadline.
    if not active.startedAt or (active.lastClock and now < active.lastClock) then
        active.startedAt = now
    end
    active.lastClock = now
    return math.max(0, math.ceil(5 - (now - active.startedAt)))
end

local UpdateCountdown
local function Finish(yes, closing)
    if not active then return false end
    if not closing and Remaining() > 0 then
        UpdateCountdown()
        return false
    end
    local request, value = active, frame.suppress:GetChecked()
    local checked = value == true or value == 1 -- legacy CheckButton return contract
    active = nil -- revoke before Hide/callbacks so reentrancy cannot accept twice
    frame:SetScript("OnUpdate", nil)
    frame:Hide()
    yes = yes == true and request.database == NexusDB and request.ownerKey == CurrentOwner()
    if request.kind == "onboarding" then onboardingOutcome = yes and "accepted" or "declined" end
    if yes then
        if checked then SaveSuppression(request) end
        -- The runtime's original welcome check runs once. Resume that existing
        -- first-time navigation after reading; this grants no Auto permission.
        if request.kind == "onboarding" and Nexus.QuickStart then Nexus.QuickStart.ShowIfFirstTime() end
        if request.accept then return request.accept() end
    end
    return false
end

UpdateCountdown = function()
    local remaining = Remaining()
    if remaining ~= frame.lastCountdown then
        frame.lastCountdown = remaining
        frame.countdown:SetText(remaining > 0 and ("Read the warning: " .. remaining .. " seconds")
            or "Do you understand?")
    end
    if remaining == 0 then
        frame.yes:Enable(); frame.no:Enable(); frame.suppress:Enable()
        frame.suppress:EnableMouse(true)
        frame:SetScript("OnUpdate", nil)
    else
        frame.yes:Disable(); frame.no:Disable(); frame.suppress:Disable()
        frame.suppress:SetChecked(false); frame.suppress:EnableMouse(false)
        frame:SetScript("OnUpdate", UpdateCountdown)
    end
end

local function EnsureFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "NexusOverwriteWarning", UIParent)
    frame:SetSize(520, 410); frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG"); frame:SetFrameLevel(100)
    frame:SetClampedToScreen(true); frame:EnableMouse(true); frame:EnableKeyboard(true)
    frame:Hide()
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=false,edgeSize=16,insets={left=5,right=5,top=5,bottom=5}})
    frame:SetBackdropColor(.055,.065,.09,1)
    local heading = frame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    heading:SetPoint("TOPLEFT",24,-22); heading:SetWidth(472)
    heading:SetJustifyH("LEFT"); heading:SetText("Saved Build overwrite warning")
    local scroll = CreateFrame("ScrollFrame","NexusOverwriteWarningScroll",frame,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",24,-58); scroll:SetSize(446,230)
    local content = CreateFrame("Frame",nil,scroll); content:SetWidth(446)
    scroll:SetScrollChild(content)
    local body = content:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    body:SetPoint("TOPLEFT"); body:SetWidth(446); body:SetJustifyH("LEFT")
    body:SetText(TEXT); body:SetHeight(math.max(220,body:GetStringHeight()))
    content:SetHeight(body:GetHeight()); frame.body = body; frame.scroll = scroll
    frame.suppress = CreateFrame("CheckButton",nil,frame,"UICheckButtonTemplate")
    frame.suppress:SetSize(24,24); frame.suppress:SetPoint("TOPLEFT",24,-298)
    local label = frame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    label:SetPoint("LEFT",frame.suppress,"RIGHT",4,0); label:SetText("Don't warn again")
    frame.suppress:SetScript("OnClick",function(self)
        if not active then
            self:SetChecked(false)
        elseif Remaining() > 0 then
            self:SetChecked(false)
            UpdateCountdown()
        end
    end)
    frame.countdown = frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    frame.countdown:SetPoint("TOPLEFT",24,-332); frame.countdown:SetWidth(472)
    frame.countdown:SetJustifyH("LEFT")
    frame.yes = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    frame.no = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    frame.yes:SetSize(110,28); frame.no:SetSize(110,28)
    frame.yes:SetPoint("BOTTOMRIGHT",-148,20); frame.no:SetPoint("BOTTOMRIGHT",-24,20)
    frame.yes:SetText("Yes"); frame.no:SetText("No")
    frame.yes:SetScript("OnClick",function() return Finish(true,false) end)
    frame.no:SetScript("OnClick",function() return Finish(false,false) end)
    frame.close = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    frame.close:SetSize(24,24); frame.close:SetPoint("TOPRIGHT",-14,-14); frame.close:SetText("X")
    frame.close:SetScript("OnClick",function() return Finish(false,true) end)
    frame:SetScript("OnHide",function() if active then Finish(false,true) end end)
    frame:SetScript("OnKeyDown",function(_,key) if key == "ESCAPE" then Finish(false,true) end end)
    UISpecialFrames[#UISpecialFrames+1] = "NexusOverwriteWarning"
    if Nexus.Theme and Nexus.Theme.StyleButton then
        Nexus.Theme.StyleButton(frame.yes); Nexus.Theme.StyleButton(frame.no)
        Nexus.Theme.StyleButton(frame.close)
    end
    return frame
end

local function Show(kind, owner, accept)
    if active then return false end
    EnsureFrame()
    active = {kind=kind,owner=owner,accept=accept,database=NexusDB,ownerKey=CurrentOwner()}
    frame.suppress:SetChecked(false); frame.lastCountdown = nil
    frame.yes:Disable(); frame.no:Disable(); frame.suppress:Disable()
    frame.suppress:EnableMouse(false); frame.scroll:SetVerticalScroll(0)
    frame:Show(); UpdateCountdown()
    return false
end

function M.EnsureOnboarding()
    -- Reading the same warning once is session-wide; rebinding saved data
    -- does not undo that reading. Active requests still reject a changed root.
    if Suppressed("onboarding") then onboardingOutcome = "accepted"; return "accepted" end
    if onboardingOutcome then return onboardingOutcome end
    Show("onboarding")
    return "pending"
end

function M.RequestAuto(owner, accept)
    if active then return false end
    -- An Auto control cannot bypass the first-open reading delay.
    if M.EnsureOnboarding() == "pending" then return false end
    if Suppressed("auto") then return accept() end
    return Show("auto",owner,accept)
end

function M.CancelAuto(owner)
    if active and active.kind == "auto" and active.owner == owner then Finish(false,true); return true end
    return false
end

return M
