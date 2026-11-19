-- Anti AFK for Roblox (executor)
-- ป้องกันการถูกเตะออกจากเกมเมื่อไม่มีการขยับ (Idle 20 นาที)

local env = (getgenv and getgenv()) or _G

local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait()
    LocalPlayer = Players.LocalPlayer
end

local function notify(text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Anti AFK",
            Text = text,
            Duration = 4,
        })
    end)
end

-- กันรันซ้ำ
if env.__AntiAFK_Loaded then
    notify("ทำงานอยู่แล้ว")
    print("[Anti AFK] ทำงานอยู่แล้ว ไม่ต้องรันซ้ำ")
    return
end
env.__AntiAFK_Loaded = true

local startTime = os.clock()
local kickBlocked = 0
local reconnectStatus = "ON"
local eventStatus = "กำลังเริ่ม"

-- ตั้งค่า Event Lottery อัตโนมัติ (ทุกชั่วโมง นาทีที่ 00)
local EVENT_ENABLED = true
local EVENT_NUMBERS = { "1", "4" }  -- เลขที่จะกดตามลำดับ
local EVENT_WINDOW_MIN = 5          -- หา popup ในช่วง 5 นาทีแรกของชั่วโมง

-- ตั้งค่า Auto Reconnect
local SCRIPT_URL = "https://raw.githubusercontent.com/nottoio555/AntiAFK/main/AntiAFK.lua"
local AUTO_RECONNECT = true
local RECONNECT_DELAY = 3   -- วินาทีก่อนเริ่ม rejoin
local MAX_RETRIES = 5       -- จำนวนครั้งสูงสุดที่ลองต่อเนื่อง

-- ตัวช่วยแสดงสถานะบนหน้าจอ
local function getGuiParent()
    if gethui then
        local ok, ui = pcall(gethui)
        if ok and ui then return ui end
    end
    local ok, core = pcall(function() return game:GetService("CoreGui") end)
    if ok and core then return core end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local gui = Instance.new("ScreenGui")
gui.Name = "AntiAFKStatus"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
pcall(function()
    if syn and syn.protect_gui then syn.protect_gui(gui) end
end)
gui.Parent = getGuiParent()

local label = Instance.new("TextLabel")
label.Size = UDim2.fromOffset(250, 80)
label.Position = UDim2.new(0, 10, 0, 10)
label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
label.BackgroundTransparency = 0.25
label.TextColor3 = Color3.fromRGB(80, 255, 120)
label.Font = Enum.Font.GothamBold
label.TextSize = 13
label.TextXAlignment = Enum.TextXAlignment.Left
label.Text = ""
label.Parent = gui

local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 8)
pad.Parent = label
Instance.new("UICorner", label).CornerRadius = UDim.new(0, 6)

local function fmt(sec)
    sec = math.floor(sec)
    return string.format("%02d:%02d:%02d", sec // 3600, (sec % 3600) // 60, sec % 60)
end

local function refresh()
    label.Text = string.format(
        "Anti AFK: ON\nเวลาทำงาน %s | กันแล้ว %d ครั้ง\nAuto Reconnect: %s\nEvent: %s",
        fmt(os.clock() - startTime),
        kickBlocked,
        reconnectStatus,
        eventStatus
    )
end
refresh()

-- อัปเดตทุก 1 วินาที
task.spawn(function()
    while gui.Parent do
        refresh()
        task.wait(1)
    end
end)

-- ตัดการเชื่อมต่อเก่าถ้ามี
if env.__AntiAFK_Conn then
    pcall(function() env.__AntiAFK_Conn:Disconnect() end)
end

env.__AntiAFK_Conn = LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
    kickBlocked += 1
    refresh()
    print(string.format("[Anti AFK] ส่ง input ปลอมครั้งที่ %d", kickBlocked))
end)

-- ===== Auto Reconnect =====
if AUTO_RECONNECT then
    local TeleportService = game:GetService("TeleportService")
    local GuiService = game:GetService("GuiService")
    local placeId, jobId = game.PlaceId, game.JobId
    local rejoining = false
    local retries = 0

    -- ให้สคริปต์รันต่ออัตโนมัติหลังเข้าเซิร์ฟเวอร์ใหม่
    local queue = queue_on_teleport
        or (syn and syn.queue_on_teleport)
        or (fluxus and fluxus.queue_on_teleport)
    if queue then
        pcall(queue, string.format("loadstring(game:HttpGet(%q))()", SCRIPT_URL))
    end

    local function setStatus(text)
        reconnectStatus = text
        refresh()
    end

    local function rejoin(reason)
        if rejoining then return end
        rejoining = true
        print("[Anti AFK] หลุดจากเซิร์ฟเวอร์: " .. tostring(reason))

        task.spawn(function()
            while retries < MAX_RETRIES do
                retries += 1
                setStatus(string.format("กำลังเชื่อมต่อใหม่ (%d/%d)", retries, MAX_RETRIES))
                task.wait(RECONNECT_DELAY * retries)

                -- ครั้งแรกพยายามกลับเซิร์ฟเวอร์เดิม ครั้งถัดไปเข้าเซิร์ฟเวอร์ใดก็ได้
                local ok, err = pcall(function()
                    if retries == 1 and jobId ~= "" then
                        TeleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
                    else
                        TeleportService:Teleport(placeId, LocalPlayer)
                    end
                end)
                if not ok then
                    warn("[Anti AFK] Rejoin ล้มเหลว: " .. tostring(err))
                end
                task.wait(10) -- ถ้ายังอยู่ที่นี่ แปลว่า teleport ยังไม่สำเร็จ
            end
            setStatus("ล้มเหลว (ครบจำนวนครั้ง)")
            notify("เชื่อมต่อใหม่ไม่สำเร็จ")
            rejoining = false
        end)
    end

    -- ถ้า teleport ล้มเหลว ให้ลองใหม่
    TeleportService.TeleportInitFailed:Connect(function(_, result, msg)
        warn("[Anti AFK] TeleportInitFailed: " .. tostring(result) .. " " .. tostring(msg))
    end)

    -- ตรวจจับหน้าต่าง error ของ Roblox (เน็ตหลุด, ถูกตัดการเชื่อมต่อ)
    local function watchPrompt()
        local ok, overlay = pcall(function()
            return game:GetService("CoreGui")
                :WaitForChild("RobloxPromptGui", 30)
                :WaitForChild("promptOverlay", 30)
        end)
        if ok and overlay then
            overlay.ChildAdded:Connect(function(child)
                if child.Name == "ErrorPrompt" then
                    rejoin("ErrorPrompt")
                end
            end)
        end
    end
    task.spawn(watchPrompt)

    -- ตัวสำรอง ใช้กรณีเข้าถึง CoreGui ไม่ได้
    pcall(function()
        GuiService.ErrorMessageChanged:Connect(function()
            local msg = GuiService:GetErrorMessage()
            if msg and msg ~= "" then
                rejoin(msg)
            end
        end)
    end)

    notify("Auto Reconnect เปิดอยู่")
end
-- ===== Event Lottery อัตโนมัติ =====
if EVENT_ENABLED then
    local VIM = game:GetService("VirtualInputManager")
    local GuiService = game:GetService("GuiService")
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
    local doneKey = nil
    local state = { key = nil, digitsDone = false, betTries = 0 }

    local function isShown(inst)
        local cur = inst
        while cur and cur ~= PlayerGui do
            if cur:IsA("GuiObject") and not cur.Visible then return false end
            if cur:IsA("ScreenGui") and not cur.Enabled then return false end
            cur = cur.Parent
        end
        return cur == PlayerGui
    end

    local function textOf(inst)
        if inst:IsA("TextLabel") or inst:IsA("TextButton") then
            return (inst.Text:gsub("<[^>]->", ""):gsub("^%s+", ""):gsub("%s+$", ""))
        end
    end

    local function findText(scope, matcher)
        for _, d in ipairs(scope:GetDescendants()) do
            local txt = textOf(d)
            if txt and matcher(txt:upper()) and isShown(d) then
                return d
            end
        end
    end

    local function findPopup()
        local lbl = findText(PlayerGui, function(s) return s == "LOTTERY" end)
        return lbl and lbl:FindFirstAncestorWhichIsA("ScreenGui")
    end

    local function clickableOf(inst, root)
        local cur = inst
        while cur and cur ~= root do
            if cur:IsA("GuiButton") then return cur end
            cur = cur.Parent
        end
    end

    local function press(target, root)
        -- วิธีที่ 1: ยิง connection ของปุ่มโดยตรง
        local btn = clickableOf(target, root)
        local fired = 0
        if btn and getconnections then
            for _, sig in ipairs({ btn.MouseButton1Click, btn.Activated }) do
                local ok, conns = pcall(getconnections, sig)
                if ok and conns then
                    for _, c in ipairs(conns) do
                        if pcall(function() c:Fire() end) then fired += 1 end
                    end
                end
            end
        end
        if fired > 0 then return true end

        -- วิธีที่ 2: คลิกเมาส์จำลองที่กึ่งกลางปุ่ม
        local obj = btn or target
        local pos, size = obj.AbsolutePosition, obj.AbsoluteSize
        local x, y = pos.X + size.X / 2, pos.Y + size.Y / 2
        local sg = obj:FindFirstAncestorWhichIsA("ScreenGui")
        if sg and not sg.IgnoreGuiInset then
            local inset = GuiService:GetGuiInset()
            x, y = x + inset.X, y + inset.Y
        end
        VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.05)
        VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
        return true
    end

    local function isLocked(root)
        return findText(root, function(s) return s:find("LOCKED", 1, true) ~= nil end) ~= nil
    end

    local function attempt(root, key)
        if isLocked(root) then
            doneKey = key
            return
        end

        if not state.digitsDone then
            for _, digit in ipairs(EVENT_NUMBERS) do
                local d = findText(root, function(s) return s == digit end)
                if not d then
                    eventStatus = "ไม่พบปุ่มเลข " .. digit
                    return
                end
                press(d, root)
                task.wait(0.4)
            end
            state.digitsDone = true
        end

        local bet = findText(root, function(s) return #s <= 8 and s:find("BET", 1, true) ~= nil end)
        if not bet then
            eventStatus = "ไม่พบปุ่ม BET"
            return
        end
        press(bet, root)
        state.betTries += 1
        task.wait(1.5)

        if isLocked(root) then
            doneKey = key
            eventStatus = "ทำ Event สำเร็จ"
            print("[Anti AFK] ทำ Event Lottery สำเร็จ")
            notify("ทำ Event สำเร็จ")
        elseif state.betTries >= 3 then
            doneKey = key
            eventStatus = "กด BET ไม่ติด (ข้ามรอบนี้)"
            warn("[Anti AFK] กด BET ไม่ติดหลังลอง 3 ครั้ง")
        end
    end

    task.spawn(function()
        while gui.Parent do
            local ok, err = pcall(function()
                local t = os.date("*t")
                local key = string.format("%d-%d-%d", t.year, t.yday, t.hour)
                local secs = (59 - t.min) * 60 + (60 - t.sec)

                if state.key ~= key then
                    state = { key = key, digitsDone = false, betTries = 0 }
                end

                if doneKey == key then
                    if eventStatus:find("สำเร็จ") == nil and eventStatus:find("ข้าม") == nil then
                        eventStatus = "เสร็จแล้ว"
                    end
                elseif t.min < EVENT_WINDOW_MIN then
                    local root = findPopup()
                    if root then
                        eventStatus = "กำลังทำ Event..."
                        attempt(root, key)
                    else
                        eventStatus = "รอ popup..."
                    end
                else
                    eventStatus = "รอบหน้าใน " .. fmt(secs)
                end
            end)
            if not ok then
                warn("[Anti AFK] Event error: " .. tostring(err))
            end
            refresh()
            task.wait(1)
        end
    end)
end
notify("เปิดใช้งานแล้ว")
print("[Anti AFK] เปิดใช้งานแล้ว")
