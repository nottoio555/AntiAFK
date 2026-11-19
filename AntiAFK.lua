-- Anti AFK for Roblox (executor)
-- ป้องกันการถูกเตะออกจากเกมเมื่อไม่มีการขยับ (Idle 20 นาที)

local env = (getgenv and getgenv()) or _G

-- กันรันซ้ำ
if env.__AntiAFK_Loaded then
    return
end
env.__AntiAFK_Loaded = true

local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")
local StarterGui = game:GetService("StarterGui")

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

-- ตัดการเชื่อมต่อเก่าถ้ามี
if env.__AntiAFK_Conn then
    pcall(function() env.__AntiAFK_Conn:Disconnect() end)
end

env.__AntiAFK_Conn = LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
end)

notify("เปิดใช้งานแล้ว")
