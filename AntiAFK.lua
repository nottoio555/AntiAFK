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
label.Size = UDim2.fromOffset(230, 62)
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
        "Anti AFK: ON\nเวลาทำงาน %s | กันแล้ว %d ครั้ง\nAuto Reconnect: %s",
        fmt(os.clock() - startTime),
        kickBlocked,
        reconnectStatus
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
notify("เปิดใช้งานแล้ว")
print("[Anti AFK] เปิดใช้งานแล้ว")
