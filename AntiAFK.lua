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
label.Size = UDim2.fromOffset(210, 44)
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
        "Anti AFK: ON\nเวลาทำงาน %s | กันแล้ว %d ครั้ง",
        fmt(os.clock() - startTime),
        kickBlocked
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

notify("เปิดใช้งานแล้ว")
print("[Anti AFK] เปิดใช้งานแล้ว")
