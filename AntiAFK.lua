-- Anti AFK for Roblox (executor)
-- ป้องกันการถูกเตะออกจากเกมเมื่อไม่มีการขยับ (Idle 20 นาที)

local env = (getgenv and getgenv()) or _G

local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")

-- รอให้เกมโหลดเสร็จก่อน (สำคัญตอนรันอัตโนมัติหลัง rejoin)
if not game:IsLoaded() then
    game.Loaded:Wait()
end

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

local SCRIPT_VERSION = "v3.8"

-- รันซ้ำในเกม: ปิดเซสชันเก่าก่อน แล้วเริ่มใหม่ (ไม่ต้อง rejoin)
-- ทุกลูปของสคริปต์ทำงานตราบที่กล่องสถานะยังอยู่ ลบกล่องเก่าทิ้ง = ลูปเก่าหยุดเอง
if env.__AntiAFK_Loaded then
    local running = env.__AntiAFK_Version or "v1"
    pcall(function()
        if env.__AntiAFK_Cleanup then env.__AntiAFK_Cleanup() end
    end)
    pcall(function()
        if env.__AntiAFK_Conn then env.__AntiAFK_Conn:Disconnect() end
    end)
    -- เวอร์ชันเก่าที่ยังไม่มี Cleanup: หากล่องสถานะเก่าแล้วลบทิ้ง
    local parents = {}
    pcall(function() if gethui then parents[#parents + 1] = gethui() end end)
    pcall(function() parents[#parents + 1] = game:GetService("CoreGui") end)
    pcall(function() parents[#parents + 1] = LocalPlayer:FindFirstChild("PlayerGui") end)
    for _, parent in ipairs(parents) do
        pcall(function()
            for _, child in ipairs(parent:GetChildren()) do
                if child.Name == "AntiAFKStatus" then child:Destroy() end
            end
        end)
    end
    print(string.format("[Anti AFK] ปิดเซสชันเก่า (%s) แล้ว เริ่ม %s ใหม่", running, SCRIPT_VERSION))
    notify(string.format("ปิดเซสชันเก่า (%s) · เริ่ม %s", running, SCRIPT_VERSION))
    task.wait(1.5) -- ให้ลูปเก่าเห็นว่ากล่องหายแล้วหยุดก่อน
end
env.__AntiAFK_Loaded = true
env.__AntiAFK_Version = SCRIPT_VERSION

-- connection ของเซสชันนี้ จะถูกตัดตอนรันซ้ำ
local sessionConns = {}
local function trackConn(conn)
    sessionConns[#sessionConns + 1] = conn
    return conn
end

-- URL Discord Webhook: จาก getgenv ก่อน ถ้าไม่มีอ่านจากไฟล์
-- เมื่อเจอแล้วบันทึกลงไฟล์ไว้ เพื่อให้ใช้ได้ต่อหลังย้ายเซิร์ฟเวอร์ (getgenv ถูกล้างตอนย้าย)
local WEBHOOK_FILE = "AntiAFK_Webhook.txt"
local function isWebhook(u)
    return type(u) == "string" and (u:match("^https://discord%.com/api/webhooks/")
        or u:match("^https://discordapp%.com/api/webhooks/")) ~= nil
end
local WEBHOOK_URL = env.AntiAFK_Webhook
if type(WEBHOOK_URL) == "string" then WEBHOOK_URL = WEBHOOK_URL:gsub("%s+", "") end
if not isWebhook(WEBHOOK_URL) then
    WEBHOOK_URL = nil
    pcall(function()
        if isfile and readfile and isfile(WEBHOOK_FILE) then
            local saved = readfile(WEBHOOK_FILE):gsub("%s+", "")
            if isWebhook(saved) then WEBHOOK_URL = saved end
        end
    end)
end
if WEBHOOK_URL then
    env.AntiAFK_Webhook = WEBHOOK_URL
    pcall(function()
        if writefile and (not (isfile and readfile and isfile(WEBHOOK_FILE))
            or readfile(WEBHOOK_FILE):gsub("%s+", "") ~= WEBHOOK_URL) then
            writefile(WEBHOOK_FILE, WEBHOOK_URL)
        end
    end)
end

local startTime = os.clock()
local kickBlocked = 0
local reconnectStatus = "เปิดอยู่ · พร้อมเชื่อมต่อใหม่"
local loadingStatus = "กำลังตรวจหน้าโหลด..."
local eventStatus = "กำลังเริ่ม"
local rebirthStatus = "กำลังอ่านค่า..."
local webhookStatus = "กำลังเริ่ม"
local lockStatus = "ปิดอยู่"
local fuseStatus = "ปิดอยู่"
local afkBuyStatus = "กำลังเริ่ม"
local hopStatus = "กำลังเริ่ม"

-- ค่าเปิด/ปิดของปุ่ม Toggle (จำไว้ในไฟล์ จะได้ใช้ค่าเดิมหลัง rejoin)
local SETTINGS_FILE = "AntiAFK_Settings.json"
local settings = { autoLock = false, autoFuse = false, afkBuy = true, serverHop = true }
do
    local Http = game:GetService("HttpService")
    pcall(function()
        if isfile and readfile and isfile(SETTINGS_FILE) then
            local saved = Http:JSONDecode(readfile(SETTINGS_FILE))
            for k, v in pairs(saved) do
                if settings[k] ~= nil and type(v) == type(settings[k]) then settings[k] = v end
            end
        end
    end)
end
local function saveSettings()
    pcall(function()
        if writefile then
            writefile(SETTINGS_FILE, game:GetService("HttpService"):JSONEncode(settings))
        end
    end)
end

-- ตั้งค่า Auto Lock: ล็อกการ์ดที่ชื่อหรือป้ายมีคำเหล่านี้
local LOCK_TAGS = { "PRISM", "HOLO" }

-- ตั้งค่า Auto Fuse: ใช้การ์ด 6 ใบที่ชื่อไม่ซ้ำกัน จากรายชื่อนี้
local FUSE_MEMBERS = { "RUKA", "PHARITA", "ASA", "AHYEON", "RAMI", "RORA", "CHIQUITA" }
local FUSE_SLOTS = 6
local FUSE_KEEP_ONE = false         -- true = ใช้เฉพาะการ์ดที่มี x2 ขึ้นไป (เก็บไว้อย่างน้อย 1 ใบ)
local FUSE_DELAY = 4                -- วินาทีที่รอก่อนลองใหม่ เมื่อ Fuse ไม่สำเร็จ
local FUSE_ALLOW_SPECIAL = true     -- true = ใช้การ์ด SHINY / PRISM / HOLO ใน Fuse ได้ (ใช้ใบธรรมดาก่อนถ้าจำนวนเท่ากัน)

-- ตั้งค่า AFK Buy: ถ้าไม่ได้ขยับนานเกินเวลานี้ จะเปิด AFK MODE ให้ และตั้งให้ซื้อแพ็คท้ายๆ
local AFK_BUY_IDLE = 300            -- วินาที (5 นาที)
local AFK_BUY_LAST = 4              -- จำนวนแพ็คท้ายรายการที่ต้องเป็น BUYING เสมอ

-- ตั้งค่า Server Hop ก่อน Lottery: Lottery เริ่มเมื่อมีผู้เล่นอย่างน้อย 4 คน
local HOP_MIN_PLAYERS = 4           -- จำนวนผู้เล่นขั้นต่ำ (นับตัวเองด้วย)
local HOP_CHECK_MINUTE = 58         -- เช็กตอนนาทีนี้ (2 นาทีก่อน Lottery ที่นาที 00)
local HOP_MAX_PER_HOUR = 3          -- ย้ายเซิร์ฟเวอร์ได้สูงสุดกี่ครั้งต่อรอบ กันย้ายวนไม่จบ

-- จดเวลาที่สคริปต์คลิกเอง เพื่อไม่ให้นับเป็นการขยับของผู้ใช้
local lastSyntheticInput = 0
local function markSynthetic()
    lastSyntheticInput = os.clock()
end

-- ตั้งค่า Discord Webhook แจ้งเตือนการ์ด
-- ตั้ง URL ก่อนรัน loadstring ด้วย getgenv().AntiAFK_Webhook = "https://discord.com/api/webhooks/..."
-- หรือเก็บไว้ในไฟล์ AntiAFK_Webhook.txt ในโฟลเดอร์ workspace ของ executor
local WEBHOOK_ENABLED = true

-- ตั้งค่าตัวคำนวณเวลา Rebirth
local REBIRTH_ENABLED = true
local REBIRTH_COST_OVERRIDE = nil   -- ใส่ตัวเลขเองได้ เช่น 160324880000 (ถ้า nil จะอ่านจากหน้า Rebirth)

-- ตั้งค่า Event Lottery อัตโนมัติ (ทุกชั่วโมง นาทีที่ 00)
local EVENT_ENABLED = true
local EVENT_FIXED_NUMBER = nil      -- nil = สุ่มเลข 00-99 ใหม่ทุกชั่วโมง, หรือใส่เลขเอง เช่น 14
local EVENT_WINDOW_MIN = 5          -- หา popup ในช่วง 5 นาทีแรกของชั่วโมง

-- ตั้งค่าข้ามหน้าโหลด (หน้าที่ต้องคลิก 1 ครั้งเพื่อเข้าเกม)
local AUTO_SKIP_LOADING = true
local LOADING_WATCH_SEC = 120       -- เฝ้าหน้าโหลดกี่วินาทีหลังเข้าเซิร์ฟเวอร์

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

local UserInputService = game:GetService("UserInputService")

local gui = Instance.new("ScreenGui")
gui.Name = "AntiAFKStatus"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function()
    if syn and syn.protect_gui then syn.protect_gui(gui) end
end)
gui.Parent = getGuiParent()

-- ให้การรันครั้งถัดไปปิดเซสชันนี้ได้
env.__AntiAFK_Cleanup = function()
    for _, c in ipairs(sessionConns) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(sessionConns)
    pcall(function() gui:Destroy() end)
end

local THEME = {
    bg = Color3.fromRGB(16, 16, 24),
    card = Color3.fromRGB(28, 28, 40),
    accent = Color3.fromRGB(150, 100, 255),
    accent2 = Color3.fromRGB(255, 90, 170),
    text = Color3.fromRGB(240, 240, 250),
    sub = Color3.fromRGB(160, 160, 185),
    ok = Color3.fromRGB(70, 225, 125),
    warn = Color3.fromRGB(255, 195, 70),
    bad = Color3.fromRGB(255, 85, 95),
}

local function make(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local function corner(o, r)
    make("UICorner", { CornerRadius = UDim.new(0, r) }, o)
end

-- กล่องหลัก
local main = make("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(300, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    Position = UDim2.fromOffset(12, 12),
    BackgroundColor3 = THEME.bg,
    BackgroundTransparency = 0.05,
    BorderSizePixel = 0,
}, gui)
corner(main, 12)
local stroke = make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1.5, Transparency = 0.2 }, main)
make("UIGradient", {
    Color = ColorSequence.new(THEME.accent, THEME.accent2),
    Rotation = 45,
}, stroke)
make("UIPadding", {
    PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
    PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
}, main)
make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, main)

-- ส่วนหัว (ลากย้ายได้)
local header = make("Frame", {
    Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = 0, Active = true,
}, main)
local dot = make("Frame", {
    Size = UDim2.fromOffset(10, 10), Position = UDim2.new(0, 2, 0, 4),
    BackgroundColor3 = THEME.ok, BorderSizePixel = 0,
}, header)
corner(dot, 5)
make("TextLabel", {
    Text = "ANTI AFK  " .. SCRIPT_VERSION, Font = Enum.Font.GothamBlack, TextSize = 16, TextColor3 = THEME.text,
    BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -60, 0, 18),
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)
local uptimeLabel = make("TextLabel", {
    Text = "", Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = THEME.sub,
    BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 18), Size = UDim2.new(1, -60, 0, 14),
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)
local minBtn = make("TextButton", {
    Text = "–", Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = THEME.text,
    Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -28, 0, 2),
    BackgroundColor3 = THEME.card, BorderSizePixel = 0, AutoButtonColor = true,
}, header)
corner(minBtn, 8)

-- รายการสถานะ
local body = make("Frame", {
    Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1, LayoutOrder = 1,
}, main)
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, body)

local rows = {}
local toggleRenders = {}
local TweenService = game:GetService("TweenService")

-- ปิด Toggle จากโค้ด (ใช้ตอนระบบหยุดตัวเองเพราะเจอปัญหา)
local function forceOff(settingKey)
    settings[settingKey] = false
    saveSettings()
    if toggleRenders[settingKey] then toggleRenders[settingKey](true) end
end

-- ปุ่ม Toggle แบบสวิตช์ เปลี่ยนค่า settings[settingKey] และบันทึกลงไฟล์
local function addToggle(card, settingKey, onChange)
    local track = make("TextButton", {
        Text = "", AutoButtonColor = false, BorderSizePixel = 0,
        Size = UDim2.fromOffset(38, 20), Position = UDim2.new(1, -46, 0.5, -10),
    }, card)
    corner(track, 10)
    local knob = make("Frame", {
        Size = UDim2.fromOffset(16, 16), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    }, track)
    corner(knob, 8)

    local function render(animate)
        local on = settings[settingKey]
        local goalPos = on and UDim2.fromOffset(20, 2) or UDim2.fromOffset(2, 2)
        local goalColor = on and THEME.ok or Color3.fromRGB(70, 70, 90)
        if animate then
            TweenService:Create(knob, TweenInfo.new(0.15), { Position = goalPos }):Play()
            TweenService:Create(track, TweenInfo.new(0.15), { BackgroundColor3 = goalColor }):Play()
        else
            knob.Position, track.BackgroundColor3 = goalPos, goalColor
        end
    end
    render(false)

    toggleRenders[settingKey] = render
    track.MouseButton1Click:Connect(function()
        settings[settingKey] = not settings[settingKey]
        saveSettings()
        render(true)
        if onChange then onChange(settings[settingKey]) end
    end)
end

local function addRow(key, icon, title, order, toggleKey, onToggle)
    local card = make("Frame", {
        Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = THEME.card,
        BorderSizePixel = 0, LayoutOrder = order,
    }, body)
    corner(card, 8)
    local textWidth = toggleKey and -100 or -52
    if toggleKey then addToggle(card, toggleKey, onToggle) end
    local bar = make("Frame", {
        Size = UDim2.new(0, 3, 1, -16), Position = UDim2.new(0, 6, 0, 8),
        BackgroundColor3 = THEME.ok, BorderSizePixel = 0,
    }, card)
    corner(bar, 2)
    make("TextLabel", {
        Text = icon, Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = THEME.text,
        BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0, 26, 1, 0),
    }, card)
    make("TextLabel", {
        Text = title, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = THEME.text,
        BackgroundTransparency = 1, Position = UDim2.fromOffset(46, 6), Size = UDim2.new(1, textWidth, 0, 14),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, card)
    local value = make("TextLabel", {
        Text = "-", Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = THEME.sub,
        BackgroundTransparency = 1, Position = UDim2.fromOffset(46, 22), Size = UDim2.new(1, textWidth, 0, 14),
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
    }, card)
    rows[key] = { bar = bar, value = value }
end

addRow("afk", "🛡️", "Anti AFK", 1)
addRow("loading", "🚪", "ข้ามหน้าโหลด", 2)
addRow("reconnect", "🔄", "Auto Reconnect", 3)
addRow("event", "🎰", "Lottery " .. SCRIPT_VERSION
    .. (EVENT_FIXED_NUMBER and " · เลขคงที่" or " · สุ่มเลข 00-99"), 4)
addRow("rebirth", "⭐", "Rebirth", 5)
addRow("webhook", "📨", "Discord Webhook", 6)
addRow("lock", "🔒", "Auto Lock PRISM / HOLO", 7, "autoLock", function(on)
    lockStatus = on and "เปิดอยู่ · เปิดหน้า Inventory ค้างไว้" or "ปิดอยู่"
end)
addRow("fuse", "🧬", "Auto Fuse", 8, "autoFuse", function(on)
    fuseStatus = on and "เปิดอยู่ · เปิดหน้า Fusion ค้างไว้" or "ปิดอยู่"
end)
addRow("afkbuy", "💤", "AFK Buy · ซื้อ " .. AFK_BUY_LAST .. " แพ็คท้าย", 9, "afkBuy", function(on)
    afkBuyStatus = on and "เปิดอยู่" or "ปิดอยู่"
end)
addRow("hop", "🌐", "Server Hop ก่อน Lottery", 10, "serverHop", function(on)
    hopStatus = on and "เปิดอยู่" or "ปิดอยู่"
end)

-- ย่อ/ขยาย
local collapsed = false
minBtn.MouseButton1Click:Connect(function()
    collapsed = not collapsed
    body.Visible = not collapsed
    minBtn.Text = collapsed and "+" or "–"
end)

-- ลากย้ายตำแหน่ง
do
    local dragging, dragStart, startPos
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, input.Position, main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    trackConn(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
end

local function fmt(sec)
    sec = math.floor(sec)
    return string.format("%02d:%02d:%02d", sec // 3600, (sec % 3600) // 60, sec % 60)
end

-- สีตามสถานะ: แดง = มีปัญหา, เหลือง = กำลังรอ/ทำงาน, เขียว = ปกติ
local function toneOf(s)
    if s == "ปิดอยู่" or s == "ไม่พบหน้าโหลด" then return THEME.sub end
    if s:find("ไม่") or s:find("ล้มเหลว") or s:find("error") then return THEME.bad end
    if s:find("รอบหน้า") or s:find("รอ AFK") then return THEME.ok end
    if s:find("รอ") or s:find("กำลัง") or s:find("เปิดหน้า") then return THEME.warn end
    return THEME.ok
end

local function setRow(key, text)
    local r = rows[key]
    if not r then return end
    r.value.Text = text
    r.bar.BackgroundColor3 = toneOf(text)
end

local function refresh()
    uptimeLabel.Text = "ทำงานมาแล้ว " .. fmt(os.clock() - startTime)
    setRow("afk", string.format("เปิดอยู่ · กันแล้ว %d ครั้ง", kickBlocked))
    setRow("loading", loadingStatus)
    setRow("reconnect", reconnectStatus)
    setRow("event", eventStatus)
    setRow("rebirth", rebirthStatus)
    setRow("webhook", webhookStatus)
    setRow("lock", lockStatus)
    setRow("fuse", fuseStatus)
    setRow("afkbuy", afkBuyStatus)
    setRow("hop", hopStatus)
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
        markSynthetic()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
    kickBlocked += 1
    refresh()
    print(string.format("[Anti AFK] ส่ง input ปลอมครั้งที่ %d", kickBlocked))
end)

-- ===== ข้ามหน้าโหลด =====
-- บางเกมมีหน้าโหลดเต็มจอที่ต้องคลิก 1 ครั้งก่อนเข้าเกม ส่วนนี้จะคลิกให้อัตโนมัติ
if AUTO_SKIP_LOADING then
    task.spawn(function()
        local VIM = game:GetService("VirtualInputManager")
        local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
        local Camera = workspace.CurrentCamera
        local CUES = { "CLICK", "TAP", "PRESS", "ENTER", "START", "CONTINUE", "PLAY", "คลิก", "แตะ", "เริ่ม", "เข้าเกม" }

        local function shown(inst)
            local cur = inst
            while cur and cur ~= PlayerGui do
                if cur:IsA("GuiObject") and not cur.Visible then return false end
                if cur:IsA("ScreenGui") and not cur.Enabled then return false end
                cur = cur.Parent
            end
            return cur == PlayerGui
        end

        -- หาสิ่งที่บังเต็มจอ และปุ่ม/ข้อความที่บอกให้คลิก ภายในหน้านั้น
        local function findLoading()
            local vp = Camera.ViewportSize
            for _, sg in ipairs(PlayerGui:GetChildren()) do
                if sg:IsA("ScreenGui") and sg.Enabled then
                    local cover
                    for _, d in ipairs(sg:GetDescendants()) do
                        if d:IsA("GuiObject") and d.AbsoluteSize.X >= vp.X * 0.9
                            and d.AbsoluteSize.Y >= vp.Y * 0.9 and shown(d) then
                            local opaque = d.BackgroundTransparency < 0.3
                                or ((d:IsA("ImageLabel") or d:IsA("ImageButton"))
                                    and d.Image ~= "" and d.ImageTransparency < 0.3)
                            if opaque then cover = d break end
                        end
                    end
                    if cover then
                        local cue
                        for _, d in ipairs(sg:GetDescendants()) do
                            if (d:IsA("TextLabel") or d:IsA("TextButton")) and shown(d) and #d.Text <= 40 then
                                local up = d.Text:upper()
                                for _, c in ipairs(CUES) do
                                    if up:find(c, 1, true) then cue = d break end
                                end
                                if cue then break end
                            end
                        end
                        return cover, cue
                    end
                end
            end
        end

        local function fireButton(inst)
            local btn = inst
            while btn and not btn:IsA("GuiButton") do
                btn = btn.Parent
                if btn == PlayerGui then return false end
            end
            if not (btn and getconnections) then return false end
            local fired = false
            for _, sig in ipairs({ btn.MouseButton1Click, btn.Activated, btn.MouseButton1Down }) do
                local ok, conns = pcall(getconnections, sig)
                if ok and conns then
                    for _, c in ipairs(conns) do
                        if pcall(function() c:Fire() end) then fired = true end
                    end
                end
            end
            return fired
        end

        local function clickAt(obj)
            local p, s = obj.AbsolutePosition, obj.AbsoluteSize
            local x, y = p.X + s.X / 2, p.Y + s.Y / 2
            pcall(function()
                markSynthetic(); VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
                task.wait(0.05)
                markSynthetic(); VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
            end)
        end

        local deadline = os.clock() + LOADING_WATCH_SEC
        local clicks = 0
        while os.clock() < deadline and gui.Parent do
            local ok, cover, cue = pcall(findLoading)
            if ok and cover then
                local target = cue or cover
                if not fireButton(target) then
                    clickAt(target)
                end
                clicks += 1
                loadingStatus = string.format("กำลังกดเข้าเกม (%d)", clicks)
                refresh()
                task.wait(2)
            else
                if clicks > 0 then
                    loadingStatus = "กดเข้าเกมแล้ว"
                    print("[Anti AFK] ข้ามหน้าโหลดแล้ว")
                    break
                end
                task.wait(1)
            end
        end
        if clicks == 0 then
            loadingStatus = "ไม่พบหน้าโหลด"
        elseif loadingStatus ~= "กดเข้าเกมแล้ว" then
            loadingStatus = "หน้าโหลดยังไม่หาย"
            warn("[Anti AFK] คลิกหน้าโหลดแล้วแต่ยังไม่หาย")
        end
        refresh()
    end)
else
    loadingStatus = "ปิดอยู่"
end

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
        -- ส่ง URL webhook ไปด้วย เพราะ getgenv ถูกล้างตอนย้ายเซิร์ฟเวอร์
        local code = ""
        if WEBHOOK_URL then
            code = string.format("getgenv().AntiAFK_Webhook = %q\n", WEBHOOK_URL)
        end
        code = code .. string.format("loadstring(game:HttpGet(%q))()", SCRIPT_URL)
        pcall(queue, code)
    end

    local function setStatus(text)
        reconnectStatus = text
        refresh()
    end

    local function rejoin(reason)
        if rejoining or not gui.Parent then return end -- เซสชันนี้ถูกปิดไปแล้ว
        rejoining = true
        print("[Anti AFK] หลุดจากเซิร์ฟเวอร์: " .. tostring(reason))

        task.spawn(function()
            while retries < MAX_RETRIES and gui.Parent do
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
    trackConn(TeleportService.TeleportInitFailed:Connect(function(_, result, msg)
        warn("[Anti AFK] TeleportInitFailed: " .. tostring(result) .. " " .. tostring(msg))
    end))

    -- ตรวจจับหน้าต่าง error ของ Roblox (เน็ตหลุด, ถูกตัดการเชื่อมต่อ)
    local function watchPrompt()
        local ok, overlay = pcall(function()
            return game:GetService("CoreGui")
                :WaitForChild("RobloxPromptGui", 30)
                :WaitForChild("promptOverlay", 30)
        end)
        if ok and overlay then
            trackConn(overlay.ChildAdded:Connect(function(child)
                if child.Name == "ErrorPrompt" then
                    rejoin("ErrorPrompt")
                end
            end))
        end
    end
    task.spawn(watchPrompt)

    -- ตัวสำรอง ใช้กรณีเข้าถึง CoreGui ไม่ได้
    pcall(function()
        trackConn(GuiService.ErrorMessageChanged:Connect(function()
            local msg = GuiService:GetErrorMessage()
            if msg and msg ~= "" then
                rejoin(msg)
            end
        end))
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
    local rng = Random.new()
    local lastNumber = nil

    -- เลขของชั่วโมงนี้: สุ่ม 00-99 ใหม่ทุกชั่วโมง (ไม่ซ้ำกับรอบก่อน)
    local function pickNumber()
        if EVENT_FIXED_NUMBER then
            return math.clamp(math.floor(EVENT_FIXED_NUMBER), 0, 99)
        end
        local n
        repeat
            n = rng:NextInteger(0, 99)
        until n ~= lastNumber
        return n
    end

    local function digitsOf(n)
        local s = string.format("%02d", n)
        return { s:sub(1, 1), s:sub(2, 2) }
    end

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
        markSynthetic(); VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.05)
        markSynthetic(); VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
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
            for _, digit in ipairs(digitsOf(state.number)) do
                -- เลือกเฉพาะเลขที่อยู่บนปุ่ม เพื่อไม่ให้ไปโดนตัวเลขอื่นในหน้าจอ
                local d
                for _, o in ipairs(root:GetDescendants()) do
                    local txt = textOf(o)
                    if txt == digit and isShown(o) and clickableOf(o, root) then
                        d = o
                        break
                    end
                end
                d = d or findText(root, function(s) return s == digit end)
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
            lastNumber = state.number
            eventStatus = string.format("แทงเลข %02d สำเร็จ", state.number)
            print(string.format("[Anti AFK] ทำ Event Lottery สำเร็จ เลข %02d", state.number))
            notify(string.format("แทงเลข %02d สำเร็จ", state.number))
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
                    state = { key = key, digitsDone = false, betTries = 0, number = pickNumber() }
                end
                local num = string.format("%02d", state.number)

                if doneKey == key then
                    if eventStatus:find("สำเร็จ") == nil and eventStatus:find("ข้าม") == nil then
                        eventStatus = "เสร็จแล้ว"
                    end
                    if t.min >= EVENT_WINDOW_MIN then
                        local last = lastNumber and string.format(" · ล่าสุด %02d", lastNumber) or ""
                        eventStatus = "รอบหน้าใน " .. fmt(secs) .. last
                    end
                elseif t.min < EVENT_WINDOW_MIN then
                    local root = findPopup()
                    if root then
                        eventStatus = "กำลังแทงเลข " .. num .. "..."
                        attempt(root, key)
                    else
                        eventStatus = "เลข " .. num .. " · รอ popup..."
                    end
                else
                    local last = lastNumber and string.format(" · ล่าสุด %02d", lastNumber) or ""
                    eventStatus = "รอบหน้าใน " .. fmt(secs) .. last
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
-- ===== ตัวคำนวณเวลา Rebirth =====
if REBIRTH_ENABLED then
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
    local Camera = workspace.CurrentCamera
    local SUFFIX = {
        K = 1e3, M = 1e6, B = 1e9, T = 1e12, QA = 1e15, QI = 1e18,
        SX = 1e21, SP = 1e24, OC = 1e27, NO = 1e30, DC = 1e33,
    }
    local cachedCost = REBIRTH_COST_OVERRIDE

    local function parseNumber(s)
        s = s:gsub("<[^>]->", ""):gsub("[%$%+,%s]", ""):gsub("/[sS]$", "")
        local num, suf = s:match("^(%d+%.?%d*)(%a*)$")
        if not num then return nil end
        local mult = (suf == "") and 1 or SUFFIX[suf:upper()]
        if not mult then return nil end
        return tonumber(num) * mult
    end

    local function shown(inst)
        local cur = inst
        while cur and cur ~= PlayerGui do
            if cur:IsA("GuiObject") and not cur.Visible then return false end
            if cur:IsA("ScreenGui") and not cur.Enabled then return false end
            cur = cur.Parent
        end
        return cur == PlayerGui
    end

    local function labels(scope)
        local list = {}
        for _, d in ipairs(scope:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and shown(d) then
                list[#list + 1] = d
            end
        end
        return list
    end

    local function clean(txt)
        return (txt:gsub("<[^>]->", ""):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    -- อ่านเงินและรายได้/วินาทีจาก HUD มุมซ้ายล่าง
    local function readHud()
        local vp = Camera.ViewportSize
        local money, moneyY, income, incomeY = nil, -1, nil, -1
        for _, l in ipairs(labels(PlayerGui)) do
            local pos = l.AbsolutePosition
            if pos.X < vp.X * 0.4 and pos.Y > vp.Y * 0.5 then
                local txt = clean(l.Text)
                if txt:match("^%+?%$?[%d%.,]+%a*/[sS]$") then
                    if pos.Y > incomeY then income, incomeY = parseNumber(txt), pos.Y end
                elseif txt:match("^[%d,]+$") and #txt >= 4 then
                    if pos.Y > moneyY then money, moneyY = parseNumber(txt), pos.Y end
                end
            end
        end
        return money, income
    end

    -- อ่านราคา Rebirth จากหน้าต่าง Rebirth (เห็นเฉพาะตอนเปิดหน้านั้น)
    local function readCost()
        for _, l in ipairs(labels(PlayerGui)) do
            if clean(l.Text):upper() == "REBIRTH NOW" then
                local root = l:FindFirstAncestorWhichIsA("ScreenGui")
                local best
                for _, c in ipairs(labels(root)) do
                    local txt = clean(c.Text)
                    if txt:match("^%$[%d,%.]+%a*$") then
                        local v = parseNumber(txt)
                        if v and (not best or v > best) then best = v end
                    end
                end
                return best
            end
        end
    end

    local function fmtDur(sec)
        sec = math.floor(sec)
        if sec < 60 then return string.format("%d วินาที", sec) end
        local h, m = sec // 3600, (sec % 3600) // 60
        if h >= 24 then
            return string.format("%d วัน %d ชม. %d นาที", h // 24, h % 24, m)
        end
        return string.format("%d ชม. %d นาที", h, m)
    end

    task.spawn(function()
        while gui.Parent do
            local ok, err = pcall(function()
                local money, income = readHud()
                if not REBIRTH_COST_OVERRIDE then
                    cachedCost = readCost() or cachedCost
                end

                if not cachedCost then
                    rebirthStatus = "เปิดหน้า Rebirth 1 ครั้งเพื่ออ่านราคา"
                elseif not money or not income then
                    rebirthStatus = "อ่านเงิน/รายได้ไม่ได้"
                elseif money >= cachedCost then
                    rebirthStatus = "เงินพอ Rebirth แล้ว"
                elseif income <= 0 then
                    rebirthStatus = "รายได้เป็น 0"
                else
                    rebirthStatus = "อีก " .. fmtDur((cachedCost - money) / income)
                end
            end)
            if not ok then
                warn("[Anti AFK] Rebirth error: " .. tostring(err))
            end
            refresh()
            task.wait(2)
        end
    end)
end

-- ===== Discord Webhook แจ้งเตือนการ์ดที่สุ่มได้ =====
if WEBHOOK_ENABLED then
    local HttpService = game:GetService("HttpService")
    local MarketplaceService = game:GetService("MarketplaceService")
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    local url = WEBHOOK_URL

    local httpRequest = request or http_request
        or (syn and syn.request) or (http and http.request) or (fluxus and fluxus.request)

    local valid = url and (url:match("^https://discord%.com/api/webhooks/")
        or url:match("^https://discordapp%.com/api/webhooks/"))

    if not valid then
        webhookStatus = "ยังไม่ได้ตั้ง URL"
    elseif not httpRequest then
        webhookStatus = "executor ไม่รองรับ request"
    else
        webhookStatus = "พร้อม"

        -- ---------- ส่งข้อความ (มีตัวจำกัดความถี่) ----------
        local lastSend = 0
        local function send(payload)
            local wait = 1.2 - (os.clock() - lastSend)
            if wait > 0 then task.wait(wait) end
            lastSend = os.clock()
            payload.username = payload.username or "Anti AFK"
            local ok, res = pcall(httpRequest, {
                Url = url,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode(payload),
            })
            local code = ok and res and res.StatusCode
            if code == 429 then
                task.wait(5)
                return false
            end
            if not (code and code >= 200 and code < 300) then
                warn("[Anti AFK] ส่ง Webhook ไม่สำเร็จ: " .. tostring(ok and code or res))
                return false
            end
            return true
        end

        local function getJson(u)
            local ok, res = pcall(httpRequest, { Url = u, Method = "GET" })
            if ok and res and res.StatusCode == 200 then
                local ok2, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if ok2 then return data end
            end
        end

        -- รูปโปรไฟล์ผู้เล่น
        local avatarUrl
        task.spawn(function()
            local data = getJson(string.format(
                "https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=%d&size=150x150&format=Png",
                LocalPlayer.UserId))
            avatarUrl = data and data.data and data.data[1] and data.data[1].imageUrl
        end)

        -- รูปการ์ด (แปลง rbxassetid เป็นลิงก์รูปที่ Discord แสดงได้)
        local imageCache = {}
        local function cardImageUrl(image)
            local id = image and tostring(image):match("(%d+)")
            if not id then return nil end
            if imageCache[id] ~= nil then return imageCache[id] or nil end
            local data = getJson(
                "https://thumbnails.roblox.com/v1/assets?assetIds=" .. id
                .. "&returnPolicy=PlaceHolder&size=420x420&format=Png")
            local u = data and data.data and data.data[1] and data.data[1].imageUrl
            imageCache[id] = u or false
            return u
        end

        local gameName = "Roblox"
        pcall(function()
            gameName = MarketplaceService:GetProductInfo(game.PlaceId).Name
        end)

        -- ---------- อ่าน UI ----------
        local function shown(inst)
            local cur = inst
            while cur and cur ~= PlayerGui do
                if cur:IsA("GuiObject") and not cur.Visible then return false end
                if cur:IsA("ScreenGui") and not cur.Enabled then return false end
                cur = cur.Parent
            end
            return cur == PlayerGui
        end

        local function clean(txt)
            return (txt:gsub("<[^>]->", ""):gsub("^%s+", ""):gsub("%s+$", ""))
        end

        -- ตัดสัญลักษณ์ตกแต่ง (✨ • ● - ฯลฯ) ออก เหลือแต่ข้อความ
        local SYMBOLS = { "✨", "•", "●", "◆", "◇", "★", "☆", "⭐", "✦", "❖", "–", "—" }
        local function core(txt)
            for _, s in ipairs(SYMBOLS) do
                txt = txt:gsub(s, "")
            end
            return (txt:gsub("^[%p%s]+", ""):gsub("[%p%s]+$", ""))
        end

        local function alnum(b)
            return b and ((b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122))
        end

        local function isDecorated(txt)
            local c = core(txt)
            if c == "" or c == txt then return false end
            return not alnum(txt:byte(1)) and not alnum(txt:byte(-1))
        end

        local function biggestImage(node)
            local best, area = nil, 0
            for _, d in ipairs(node:GetDescendants()) do
                if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and d.Image ~= "" then
                    local a = d.AbsoluteSize.X * d.AbsoluteSize.Y
                    if a > area then best, area = d, a end
                end
            end
            return best and best.Image
        end

        -- วิธีหลัก: อ่านจาก PlayerGui.CardDisplayGui.CardTemplate ที่ขึ้นตอนสุ่มการ์ด
        local function scanCardDisplay()
            local display = PlayerGui:FindFirstChild("CardDisplayGui")
            if not display then return nil end
            for _, tpl in ipairs(display:GetDescendants()) do
                if tpl.Name == "CardTemplate" and shown(tpl) then
                    local n = tpl:FindFirstChild("NameLabel", true)
                    local r = tpl:FindFirstChild("RarityLabel", true)
                    local t = tpl:FindFirstChild("ThemeLabel", true)
                    if n and r and t and n:IsA("TextLabel") and shown(n) then
                        local name = core(clean(n.Text))
                        if name ~= "" then
                            return {
                                name = name,
                                rarity = core(clean(r.Text)),
                                theme = core(clean(t.Text)),
                                image = biggestImage(tpl),
                            }
                        end
                    end
                end
            end
        end

        -- วิธีสำรอง: 3 บรรทัดที่มีสัญลักษณ์ตกแต่ง เรียงบนลงล่าง = ชื่อ, Rarity, Theme
        local function scanCard()
            local direct = scanCardDisplay()
            if direct then return direct end
            local deco = {}
            for _, l in ipairs(PlayerGui:GetDescendants()) do
                if l:IsA("TextLabel") and shown(l) then
                    local tx = clean(l.Text)
                    if tx ~= "" and isDecorated(tx) then
                        deco[#deco + 1] = { label = l, text = tx, y = l.AbsolutePosition.Y }
                    end
                end
            end
            for _, item in ipairs(deco) do
                local node = item.label.Parent
                for _ = 1, 5 do
                    if not node or node == PlayerGui then break end
                    local group = {}
                    for _, o in ipairs(deco) do
                        if o.label:IsDescendantOf(node) then group[#group + 1] = o end
                    end
                    if #group == 3 then
                        table.sort(group, function(x, y) return x.y < y.y end)
                        return {
                            name = core(group[1].text),
                            rarity = core(group[2].text),
                            theme = core(group[3].text),
                            image = biggestImage(node),
                        }
                    elseif #group > 3 then
                        break
                    end
                    node = node.Parent
                end
            end
        end

        local function readMoney()
            local hud = PlayerGui:FindFirstChild("HUD_MoneyBar")
            local amount = hud and hud:FindFirstChild("Amount", true)
            if amount and amount:IsA("TextLabel") then
                return clean(amount.Text)
            end
        end

        local function readIncome()
            for _, l in ipairs(PlayerGui:GetDescendants()) do
                if l:IsA("TextLabel") and shown(l) then
                    local tx = clean(l.Text)
                    if tx:match("^%+%$[%d%.,]+%a*/[sS]$") then return tx end
                end
            end
        end

        -- ---------- สร้างข้อความแบบ embed ----------
        local RARITY_COLORS = {
            COMMON = 0x9AA0A6, RARE = 0x3498DB, EPIC = 0x9B59B6, LEGENDARY = 0xF1C40F,
            MYTHIC = 0xE74C3C, SECRET = 0x2C2F33, SUPA = 0xEB459E, CELESTIAL = 0x1ABC9C,
        }

        local function cardEmbed(card)
            local lines = {
                string.format("**%s** · %s", card.name, card.rarity),
                "💎 **Rarity:** " .. card.rarity,
                "🎨 **Theme:** " .. card.theme,
            }
            local money, income = readMoney(), readIncome()
            if money then lines[#lines + 1] = "💰 **Money:** " .. money end
            if income then lines[#lines + 1] = "⚡ **Income:** " .. income end

            local embed = {
                author = { name = LocalPlayer.Name, icon_url = avatarUrl },
                title = "🎴 Card Pulled!",
                description = table.concat(lines, "\n"),
                color = RARITY_COLORS[card.rarity:upper()] or 0x5865F2,
                footer = { text = "Anti AFK • " .. gameName },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            }
            local img = cardImageUrl(card.image)
            if img then embed.thumbnail = { url = img } end
            return embed
        end

        -- ---------- ลูปหลัก ----------
        local lastKey, missing = nil, 0

        task.spawn(function()
            webhookStatus = "พร้อม (รอสุ่มการ์ด)"
            while gui.Parent do
                local ok, card = pcall(scanCard)
                if ok and card then
                    missing = 0
                    local key = card.name .. "|" .. card.rarity .. "|" .. card.theme
                    if key ~= lastKey then
                        lastKey = key
                        local sent = send({ embeds = { cardEmbed(card) } })
                        webhookStatus = sent and ("ส่งแล้ว: " .. card.name) or "ส่งไม่สำเร็จ"
                        print("[Anti AFK] การ์ด: " .. key)
                    end
                elseif not ok then
                    warn("[Anti AFK] scanCard error: " .. tostring(card))
                else
                    missing += 1
                    if missing >= 4 then lastKey = nil end -- popup หายไปแล้ว รอการ์ดใบถัดไป
                end
                task.wait(0.5)
            end
        end)
    end
end

-- ===== Auto Lock PRISM/HOLO และ Auto Fuse (กดปุ่มใน UI ของเกม) =====
do
    local VIM = game:GetService("VirtualInputManager")
    local GuiService = game:GetService("GuiService")
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    local function shown(inst)
        local cur = inst
        while cur and cur ~= PlayerGui do
            if cur:IsA("GuiObject") and not cur.Visible then return false end
            if cur:IsA("ScreenGui") and not cur.Enabled then return false end
            cur = cur.Parent
        end
        return cur == PlayerGui
    end

    local function clean(txt)
        return (txt:gsub("<[^>]->", ""):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local function textsOf(scope)
        local list = {}
        for _, d in ipairs(scope:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Visible then
                local tx = clean(d.Text)
                if tx ~= "" then list[#list + 1] = { inst = d, text = tx, up = tx:upper() } end
            end
        end
        return list
    end

    local function scrollIntoView(obj)
        local sf = obj:FindFirstAncestorWhichIsA("ScrollingFrame")
        if not sf then return end
        local sp, ss = sf.AbsolutePosition, sf.AbsoluteSize
        local op, os_ = obj.AbsolutePosition, obj.AbsoluteSize
        local cx, cy = sf.CanvasPosition.X, sf.CanvasPosition.Y
        if op.Y < sp.Y or op.Y + os_.Y > sp.Y + ss.Y then
            cy = math.max(0, cy + (op.Y - sp.Y) - 8)
        end
        if op.X < sp.X or op.X + os_.X > sp.X + ss.X then
            cx = math.max(0, cx + (op.X - sp.X) - 8)
        end
        if cx ~= sf.CanvasPosition.X or cy ~= sf.CanvasPosition.Y then
            sf.CanvasPosition = Vector2.new(cx, cy)
            task.wait(0.15)
        end
    end

    -- กดปุ่ม: ยิง connection ของปุ่มก่อน (ยิงสัญญาณเดียว กันกดซ้ำ 2 ครั้ง) ถ้าไม่ได้ค่อยคลิกเมาส์จำลอง
    local function press(obj)
        local btn = obj
        if not btn:IsA("GuiButton") then
            btn = nil
            for _, d in ipairs(obj:GetDescendants()) do
                if d:IsA("GuiButton") then btn = d break end
            end
        end
        if btn and getconnections then
            for _, sig in ipairs({ btn.MouseButton1Click, btn.Activated }) do
                local ok, conns = pcall(getconnections, sig)
                if ok and conns and #conns > 0 then
                    local fired = false
                    for _, c in ipairs(conns) do
                        if pcall(function() c:Fire() end) then fired = true end
                    end
                    if fired then return end
                end
            end
        end
        local target = btn or obj
        scrollIntoView(target)
        local p, s = target.AbsolutePosition, target.AbsoluteSize
        local x, y = p.X + s.X / 2, p.Y + s.Y / 2
        local sg = target:FindFirstAncestorWhichIsA("ScreenGui")
        if sg and not sg.IgnoreGuiInset then
            local inset = GuiService:GetGuiInset()
            x, y = x + inset.X, y + inset.Y
        end
        pcall(function()
            markSynthetic(); VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.wait(0.05)
            markSynthetic(); VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
    end

    -- ---------- Auto Lock ----------
    local lockBroken = false
    local lockDone = 0

    local function isOrange(c)
        return c.R > 0.75 and c.G > 0.3 and c.G < 0.8 and c.B < 0.35
    end

    -- ไอคอนล็อกของการ์ดที่ล็อกแล้วเป็นสีส้ม (ดูจากรูป Inventory)
    local function lockLooksOn(btn)
        local function check(o)
            if o:IsA("GuiObject") and not o.Visible then return false end
            if (o:IsA("ImageLabel") or o:IsA("ImageButton")) and o.Image ~= ""
                and o.ImageTransparency < 0.5 and isOrange(o.ImageColor3) then return true end
            if o:IsA("GuiObject") and o.BackgroundTransparency < 0.6 and isOrange(o.BackgroundColor3) then return true end
            if o:IsA("UIStroke") and o.Enabled and o.Transparency < 0.6 and isOrange(o.Color) then return true end
            if (o:IsA("TextLabel") or o:IsA("TextButton")) and o.Text ~= ""
                and o.TextTransparency < 0.5 and isOrange(o.TextColor3) then return true end
            return false
        end
        if check(btn) then return true end
        for _, d in ipairs(btn:GetDescendants()) do
            if check(d) then return true end
        end
        return false
    end

    local function isLockedTile(tile, btn)
        for _, name in ipairs({ "Locked", "IsLocked", "locked" }) do
            local v = tile:GetAttribute(name)
            if v == nil then v = btn:GetAttribute(name) end
            if type(v) == "boolean" then return v end
        end
        return lockLooksOn(btn)
    end

    local function isTargetTile(tile)
        for _, t in ipairs(textsOf(tile)) do
            for _, tag in ipairs(LOCK_TAGS) do
                if t.up:find(tag, 1, true) then return true end
            end
        end
        return false
    end

    -- ปุ่มล็อกอยู่มุมซ้ายบน (มุมขวาบนคือปุ่มขาย ห้ามกด)
    local function findLockButton(tile)
        for _, d in ipairs(tile:GetDescendants()) do
            if d:IsA("GuiButton") and d.Name:lower():find("lock") then return d end
        end
        local tp, ts = tile.AbsolutePosition, tile.AbsoluteSize
        for _, d in ipairs(tile:GetDescendants()) do
            if d:IsA("GuiButton") then
                local n = d.Name:lower()
                if not (n:find("sell") or n:find("money") or n:find("coin") or n:find("equip")) then
                    local cx = d.AbsolutePosition.X + d.AbsoluteSize.X / 2
                    local cy = d.AbsolutePosition.Y + d.AbsoluteSize.Y / 2
                    if cx < tp.X + ts.X * 0.35 and cy < tp.Y + ts.Y * 0.3 then return d end
                end
            end
        end
    end

    local function inventoryList()
        local inv = PlayerGui:FindFirstChild("InventoryGui")
        if not inv then return nil end
        for _, d in ipairs(inv:GetDescendants()) do
            if d:IsA("ScrollingFrame") and shown(d) then return d end
        end
    end

    -- นับการ์ด PRISM/HOLO ทั้งหมดในรายการ แยกเป็นล็อกแล้ว / ยังไม่ล็อก
    -- ใช้จำนวนรวมตรวจผล เพราะเกมสร้างรายการการ์ดใหม่ทุกครั้งที่กดล็อก (ปุ่มเดิมหายไป)
    local function scanTargets(list)
        local unlocked, lockedN = {}, 0
        for _, tile in ipairs(list:GetChildren()) do
            if tile:IsA("GuiObject") and tile.Visible and isTargetTile(tile) then
                local btn = findLockButton(tile)
                if btn then
                    if isLockedTile(tile, btn) then
                        lockedN += 1
                    else
                        unlocked[#unlocked + 1] = { tile = tile, btn = btn }
                    end
                end
            end
        end
        return unlocked, lockedN
    end

    local function tileName(tile)
        local t = textsOf(tile)
        for _, x in ipairs(t) do
            if x.up:find("%(") then return x.text end
        end
        return t[1] and t[1].text or tile.Name
    end

    -- กดล็อก 1 ใบ แล้วรอดูผลสูงสุด 4 วินาที (server อาจตอบช้า)
    local function lockOne(list, target, lockedBefore, unlockedBefore)
        local name = tileName(target.tile)
        press(target.btn)
        for _ = 1, 8 do
            task.wait(0.5)
            local current = inventoryList() or list
            local unlocked, lockedN = scanTargets(current)
            if lockedN > lockedBefore and #unlocked < unlockedBefore then
                return "locked", name
            end
        end
        -- จำนวนไม่เปลี่ยน: ถ้าปุ่มเดิมยังอยู่ ให้กดกลับเพื่อคืนสถานะเดิม
        if target.btn:IsDescendantOf(PlayerGui) then
            press(target.btn)
            task.wait(0.8)
            return "failed", name
        end
        return "unknown", name
    end

    task.spawn(function()
        while gui.Parent do
            local waitTime = 2
            if settings.autoLock then
                lockBroken = false -- ผู้ใช้เปิดใหม่เอง ให้ลองอีกครั้ง
                local ok, err = pcall(function()
                    local list = inventoryList()
                    if not list then
                        lockStatus = string.format("รอเปิดหน้า Inventory · ล็อกแล้ว %d ใบ", lockDone)
                        return
                    end
                    local unlocked, lockedN = scanTargets(list)
                    if #unlocked == 0 then
                        lockStatus = string.format("ครบแล้ว · ล็อกอยู่ %d ใบ (รอบนี้ล็อก %d ใบ)", lockedN, lockDone)
                        return
                    end

                    lockStatus = string.format("กำลังล็อก · เหลือ %d ใบ", #unlocked)
                    refresh()
                    local result, name = lockOne(list, unlocked[1], lockedN, #unlocked)
                    if result == "locked" then
                        lockDone += 1
                        print("[Anti AFK] ล็อกการ์ดแล้ว: " .. name)
                        waitTime = 0.3 -- ทำใบถัดไปต่อเลย
                    else
                        lockBroken = true
                        forceOff("autoLock")
                        lockStatus = "ตรวจสถานะล็อกไม่ได้ · ปิด Auto Lock แล้ว"
                        warn(string.format("[Anti AFK] Auto Lock: กดล็อก %s แล้วจำนวนที่ล็อกไม่เพิ่ม (%s) หยุดระบบเพื่อความปลอดภัย", name, result))
                        notify("Auto Lock หยุดทำงาน กรุณาเช็กการ์ด " .. name)
                    end
                end)
                if not ok then
                    lockStatus = "error: " .. tostring(err):sub(1, 60)
                end
            elseif not lockBroken then
                lockStatus = "ปิดอยู่"
            end
            refresh()
            task.wait(waitTime)
        end
    end)

    -- ---------- Auto Fuse ----------
    local SUFFIX = { K = 1e3, M = 1e6, B = 1e9, T = 1e12, QA = 1e15, QI = 1e18 }
    local function parseNumber(s)
        s = s:gsub("[%$%+,%s]", "")
        local num, suf = s:match("^(%d+%.?%d*)(%a*)$")
        if not num then return nil end
        local mult = (suf == "") and 1 or SUFFIX[suf:upper()]
        return mult and tonumber(num) * mult
    end

    local memberSet = {}
    for _, m in ipairs(FUSE_MEMBERS) do memberSet[m] = true end

    local function findFusion()
        for _, sg in ipairs(PlayerGui:GetChildren()) do
            if sg:IsA("ScreenGui") and sg.Enabled then
                for _, t in ipairs(textsOf(sg)) do
                    if t.up == "FUSION REACTOR" and shown(t.inst) then
                        return sg, t.inst
                    end
                end
            end
        end
    end

    -- ปุ่ม Fuse ตรงกลาง: ข้อความขึ้นต้นด้วย FUSION และอยู่ต่ำกว่าหัวข้อ (แท็บ FUSION อยู่ด้านบน)
    local function findFuseButton(root, titleLabel)
        local titleY = titleLabel.AbsolutePosition.Y
        for _, t in ipairs(textsOf(root)) do
            if t.up:match("^FUSION") and t.up ~= "FUSION REACTOR" and shown(t.inst)
                and t.inst.AbsolutePosition.Y > titleY + 20 then
                local cost = t.text:match("([%d%.]+%s*%a*)%s*$")
                if not cost or not parseNumber(cost) then
                    -- ราคาอาจอยู่ใน label แยก ใต้คำว่า FUSION
                    local parent = t.inst.Parent
                    for _, s in ipairs(textsOf(parent)) do
                        if s.inst ~= t.inst and parseNumber(s.text) then cost = s.text break end
                    end
                end
                return t.inst, cost and parseNumber(cost)
            end
        end
    end

    -- อ่านการ์ดในรายการด้านล่างของหน้า Fusion
    -- 1 ช่องในรายการ = การ์ด 1 แบบ (คนเดียวกันต่างธีมนับเป็นคนละแบบ ผสมรวมกันได้)
    local function readCards(root, fuseBtn)
        local list
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("ScrollingFrame") and shown(d) and d.AbsolutePosition.Y > fuseBtn.AbsolutePosition.Y then
                list = d
                break
            end
        end
        if not list then return nil end
        local cards, unknown = {}, {}
        for _, tile in ipairs(list:GetChildren()) do
            if tile:IsA("GuiObject") and tile.Visible then
                local name, count, special = nil, 1, false
                local texts = textsOf(tile)
                for _, t in ipairs(texts) do
                    -- ตัดวงเล็บและสัญลักษณ์ออก เช่น "Pharita (Shiny)" -> PHARITA
                    local letters = t.up:gsub("%b()", ""):gsub("[^A-Z]", "")
                    if memberSet[letters] then name = letters end
                    local c = t.up:match("^X%s*(%d+)$")
                    if c then count = tonumber(c) end
                    -- การ์ดพิเศษ (PRISM, HOLO, SHINY)
                    if t.up:find("PRISM") or t.up:find("HOLO") or t.up:find("SHINY") then special = true end
                end
                if name and (FUSE_ALLOW_SPECIAL or not special) then
                    if not FUSE_KEEP_ONE or count >= 2 then
                        cards[#cards + 1] = { tile = tile, name = name, count = count, special = special }
                    end
                elseif not name and #texts > 0 then
                    unknown[#unknown + 1] = texts[1].text
                end
            end
        end
        return cards, unknown, list
    end

    -- อ่านชื่อการ์ดที่อยู่ในช่อง Fuse แล้ว (แถวช่องด้านบน ระหว่างหัวข้อกับรายการการ์ด)
    local function readSlots(root, fuseBtn, list)
        local top = fuseBtn.AbsolutePosition.Y - 120
        local bottom = list.AbsolutePosition.Y - 5
        local names = {}
        for _, t in ipairs(textsOf(root)) do
            if not t.inst:IsDescendantOf(list) and shown(t.inst) then
                local y = t.inst.AbsolutePosition.Y
                local letters = t.up:gsub("%b()", ""):gsub("[^A-Z]", "")
                if y > top and y < bottom and memberSet[letters] then
                    names[#names + 1] = letters
                end
            end
        end
        return names
    end

    -- การ์ดที่กดแล้วไม่เข้าช่อง (เช่น ถูกล็อกหรือใช้อยู่) จะข้ามไปจนกว่าจะ Fuse สำเร็จ
    local failedTiles = setmetatable({}, { __mode = "k" })

    -- ใส่การ์ดลงช่องจนครบ: กดทีละใบ แล้วเช็กว่าจำนวนการ์ดในช่องเพิ่มขึ้นจริง
    local function fillSlots(root, fuseBtn, cards, list)
        local inSlots = readSlots(root, fuseBtn, list)
        if #inSlots >= FUSE_SLOTS then return true, inSlots, {} end

        local have = {}
        for _, n in ipairs(inSlots) do have[n] = true end
        table.sort(cards, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return (not a.special) and b.special
        end)
        -- คนที่ยังไม่มีในช่องมาก่อน แล้วค่อยเป็นธีมอื่นของคนที่มีแล้ว
        local order = {}
        for _, c in ipairs(cards) do if not have[c.name] then order[#order + 1] = c end end
        for _, c in ipairs(cards) do if have[c.name] then order[#order + 1] = c end end

        local failedNames = {}
        for _, c in ipairs(order) do
            if #inSlots >= FUSE_SLOTS then break end
            if not failedTiles[c.tile] and c.tile:IsDescendantOf(PlayerGui) then
                local before = #inSlots
                press(c.tile)
                local after = before
                for _ = 1, 15 do
                    task.wait(0.1)
                    after = #readSlots(root, fuseBtn, list)
                    if after ~= before then break end
                end
                if after > before then
                    inSlots = readSlots(root, fuseBtn, list)
                else
                    if after < before then press(c.tile) task.wait(0.3) end -- กดแล้วการ์ดออกจากช่อง ให้ใส่กลับ
                    failedTiles[c.tile] = true
                    failedNames[#failedNames + 1] = c.name .. " x" .. c.count
                    warn("[Anti AFK] Fuse: กดการ์ด " .. c.name .. " x" .. c.count .. " แล้วไม่เข้าช่อง")
                end
            end
        end
        return #inSlots >= FUSE_SLOTS, inSlots, failedNames
    end

    local function readMoney()
        local hud = PlayerGui:FindFirstChild("HUD_MoneyBar")
        local amount = hud and hud:FindFirstChild("Amount", true)
        return amount and amount:IsA("TextLabel") and parseNumber(clean(amount.Text))
    end

    local function totalCount(cards)
        local n = 0
        for _, v in ipairs(cards) do n += v.count end
        return n
    end

    -- หน้ารับรางวัลหลัง Fuse: หาปุ่มที่มีคำว่า CLAIM / COLLECT / OK ฯลฯ
    -- ถ้าไม่มีปุ่ม แต่มีการ์ดโชว์อยู่ (CardDisplayGui) ให้คลิกที่การ์ดเพื่อรับ
    local CLAIM_WORDS = { "CLAIM", "COLLECT", "RECEIVE", "OK", "CONTINUE", "TAP", "CLICK", "AWESOME", "NICE" }
    local CLAIM_THAI = { "รับ", "ตกลง", "แตะ", "คลิก" }
    -- ไม่สนข้อความที่อยู่บนจอตั้งแต่ก่อนกด FUSION (ไม่ใช่หน้ารับรางวัล)
    local function findClaim(fuseBtn, ignore)
        for _, d in ipairs(PlayerGui:GetDescendants()) do
            if (d:IsA("TextButton") or d:IsA("TextLabel")) and d ~= fuseBtn
                and not (ignore and ignore[d]) and shown(d) then
                local up = clean(d.Text):upper()
                if up ~= "" and #up <= 30 and not up:find("^FUSION") then
                    for _, w in ipairs(CLAIM_WORDS) do
                        if up:find("%f[%a]" .. w .. "%f[%A]") then return d end
                    end
                    for _, w in ipairs(CLAIM_THAI) do
                        if up:find(w, 1, true) then return d end
                    end
                end
            end
        end
        local display = PlayerGui:FindFirstChild("CardDisplayGui")
        if display and display:IsA("ScreenGui") and display.Enabled then
            for _, d in ipairs(display:GetDescendants()) do
                if d:IsA("GuiObject") and d.Name == "CardTemplate" and shown(d)
                    and not (ignore and ignore[d]) then return d end
            end
        end
    end

    -- จดสิ่งที่ตรงคำค้นและอยู่บนจออยู่แล้ว ก่อนกด FUSION
    local function snapshotClaims(fuseBtn)
        local ignore = {}
        for _ = 1, 10 do
            local d = findClaim(fuseBtn, ignore)
            if not d then break end
            ignore[d] = true
        end
        return ignore
    end

    local function isGone(target)
        return not target:IsDescendantOf(PlayerGui) or not shown(target)
    end

    -- รอหน้ารับรางวัล กดรับ แล้วจบทันทีที่หน้านั้นหายไป
    local function claimReward(fuseBtn, ignore)
        local claimed = 0
        local deadline = os.clock() + 6
        while os.clock() < deadline do
            local target = findClaim(fuseBtn, ignore)
            if target then
                press(target)
                claimed += 1
                -- รอให้หน้ารับรางวัลหาย (สูงสุด 1.5 วินาที)
                local t0 = os.clock()
                while os.clock() - t0 < 1.5 and not isGone(target) do
                    task.wait(0.05)
                end
                if not isGone(target) then
                    ignore[target] = true -- กดแล้วไม่หาย ไม่ใช่ปุ่มรับ ข้ามไป
                end
                -- มีหน้ารับซ้อนอีกไหม ดูแป๊บเดียวแล้วจบ
                task.wait(0.15)
                if not findClaim(fuseBtn, ignore) then break end
                deadline = os.clock() + 2
            elseif claimed > 0 then
                break
            else
                task.wait(0.1)
            end
        end
        return claimed
    end

    local fuseDone, fuseFails = 0, 0
    local lastUnknownLog = ""
    task.spawn(function()
        while gui.Parent do
            local waitTime = 1
            if settings.autoFuse then
                if fuseFails >= 3 then fuseFails = 0 end -- ผู้ใช้เปิดใหม่เอง
                local ok, err = pcall(function()
                    local root, title = findFusion()
                    if not root then
                        fuseStatus = string.format("รอเปิดหน้า Fusion · Fuse แล้ว %d ครั้ง", fuseDone)
                        return
                    end
                    local fuseBtn, cost = findFuseButton(root, title)
                    if not fuseBtn then
                        fuseStatus = "ไม่พบปุ่ม FUSION"
                        return
                    end
                    local cards, unknown, list = readCards(root, fuseBtn)
                    if not cards then
                        fuseStatus = "ไม่พบรายการการ์ด"
                        return
                    end

                    -- การ์ดที่อยู่ในช่องแล้วอาจหายจากรายการ จึงนับรวมกัน
                    local slotCount = #readSlots(root, fuseBtn, list)
                    if #cards + slotCount < FUSE_SLOTS then
                        local names = {}
                        for _, c in ipairs(cards) do names[#names + 1] = c.name .. " x" .. c.count end
                        fuseStatus = string.format("การ์ดไม่พอ (มี %d/%d แบบ) · Fuse แล้ว %d ครั้ง", #cards + slotCount, FUSE_SLOTS, fuseDone)
                        local log = table.concat(names, ", ") .. " | อ่านชื่อไม่ได้: " .. table.concat(unknown, ", ")
                        if log ~= lastUnknownLog then
                            lastUnknownLog = log
                            print("[Anti AFK] Fuse: การ์ดที่ใช้ได้ = " .. log)
                        end
                        return
                    end
                    local money = readMoney()
                    if cost and money and money < cost then
                        fuseStatus = "เงินไม่พอ Fuse · Fuse แล้ว " .. fuseDone .. " ครั้ง"
                        return
                    end

                    fuseStatus = "กำลังใส่การ์ด..."
                    refresh()
                    local full, names, failedNames = fillSlots(root, fuseBtn, cards, list)
                    if not full then
                        fuseStatus = string.format("ใส่การ์ดได้ %d/%d · กดไม่ติด: %s",
                            #names, FUSE_SLOTS, #failedNames > 0 and table.concat(failedNames, ", ") or "-")
                        waitTime = FUSE_DELAY
                        return
                    end
                    local before = totalCount(cards)
                    local ignore = snapshotClaims(fuseBtn)
                    press(fuseBtn)
                    fuseStatus = "กำลัง Fuse..."
                    refresh()

                    -- กดรับรางวัลหลัง Fuse
                    local claimed = claimReward(fuseBtn, ignore)
                    task.wait(0.1)

                    local root2, title2 = findFusion()
                    local btn2 = root2 and findFuseButton(root2, title2)
                    local after = btn2 and readCards(root2, btn2)
                    if after and totalCount(after) < before then
                        fuseDone += 1
                        fuseFails = 0
                        failedTiles = setmetatable({}, { __mode = "k" })
                        fuseStatus = string.format("Fuse สำเร็จ %d ครั้ง · ทำต่อ...", fuseDone)
                        print(string.format("[Anti AFK] Fuse สำเร็จ: %s (กดรับ %d ครั้ง)", table.concat(names, " + "), claimed))
                        waitTime = 0.1 -- ผสมต่อทันที
                    else
                        fuseFails += 1
                        fuseStatus = string.format("Fuse ไม่สำเร็จ (%d/3)", fuseFails)
                        warn("[Anti AFK] Fuse: จำนวนการ์ดไม่ลดลงหลังกด FUSION")
                        if fuseFails >= 3 then
                            forceOff("autoFuse")
                            fuseStatus = "Fuse ไม่สำเร็จ 3 ครั้ง · ปิด Auto Fuse แล้ว"
                            notify("Auto Fuse หยุดทำงาน")
                        end
                        waitTime = FUSE_DELAY
                    end
                end)
                if not ok then
                    fuseStatus = "error: " .. tostring(err):sub(1, 60)
                end
            else
                if fuseStatus:find("3 ครั้ง") == nil then fuseStatus = "ปิดอยู่" end
            end
            refresh()
            task.wait(waitTime)
        end
    end)

    -- ---------- AFK Buy ----------
    -- จับเวลาที่ผู้ใช้ไม่ได้ขยับ (ไม่นับคลิกที่สคริปต์ทำเอง)
    local lastInput = os.clock()
    local USER_INPUTS = {
        [Enum.UserInputType.Keyboard] = true, [Enum.UserInputType.MouseButton1] = true,
        [Enum.UserInputType.MouseButton2] = true, [Enum.UserInputType.MouseButton3] = true,
        [Enum.UserInputType.MouseMovement] = true, [Enum.UserInputType.MouseWheel] = true,
        [Enum.UserInputType.Touch] = true, [Enum.UserInputType.Gamepad1] = true,
    }
    local function onInput(input)
        if os.clock() - lastSyntheticInput < 1 then return end
        if USER_INPUTS[input.UserInputType] then lastInput = os.clock() end
    end
    trackConn(UserInputService.InputBegan:Connect(onInput))
    trackConn(UserInputService.InputChanged:Connect(onInput))

    local Camera = workspace.CurrentCamera

    local function findAfkWindow()
        for _, sg in ipairs(PlayerGui:GetChildren()) do
            if sg:IsA("ScreenGui") and sg.Enabled then
                for _, t in ipairs(textsOf(sg)) do
                    if t.up:find("AFK MODE ACTIVE", 1, true) and shown(t.inst) then
                        return sg
                    end
                end
            end
        end
    end

    -- ปุ่ม AFK MODE (นาฬิกาสีแดง): หาจากชื่อก่อน ถ้าไม่เจอใช้ไอคอนขวาสุดของแถบไอคอนกลางจอด้านบน
    local function findAfkButton()
        for _, d in ipairs(PlayerGui:GetDescendants()) do
            if d:IsA("GuiButton") and d.Name:lower():find("afk") and shown(d) then return d end
        end
        local vp = Camera.ViewportSize
        local best
        for _, d in ipairs(PlayerGui:GetDescendants()) do
            if d:IsA("GuiButton") and shown(d) then
                local s = d.AbsoluteSize
                local cx = d.AbsolutePosition.X + s.X / 2
                local cy = d.AbsolutePosition.Y + s.Y / 2
                if s.X >= 25 and s.X <= 120 and s.Y >= 25 and s.Y <= 120
                    and cy < vp.Y * 0.2 and cx > vp.X * 0.3 and cx < vp.X * 0.7 then
                    if not best or cx > best.AbsolutePosition.X + best.AbsoluteSize.X / 2 then best = d end
                end
            end
        end
        return best
    end

    -- ตั้งให้แพ็คท้ายรายการ AFK_BUY_LAST อันเป็น BUYING (กดทีละอัน แล้วสแกนใหม่)
    local function configurePacks(root)
        local packRows = {}
        for _, t in ipairs(textsOf(root)) do
            if (t.up == "BUYING" or t.up == "IGNORE") and shown(t.inst) then
                packRows[#packRows + 1] = { btn = t.inst, state = t.up, y = t.inst.AbsolutePosition.Y }
            end
        end
        if #packRows == 0 then return "norows", 0 end
        table.sort(packRows, function(a, b) return a.y < b.y end)
        for i = math.max(1, #packRows - AFK_BUY_LAST + 1), #packRows do
            if packRows[i].state == "IGNORE" then
                press(packRows[i].btn)
                return "changed", #packRows
            end
        end
        return "ok", #packRows
    end

    local nextOpenTry = 0
    local configTries = 0
    task.spawn(function()
        while gui.Parent do
            if settings.afkBuy then
                local ok, err = pcall(function()
                    local root = findAfkWindow()
                    if root then
                        if configTries >= 12 then
                            afkBuyStatus = "ตั้งค่าแพ็คไม่ติด · เช็กหน้า AFK เอง"
                            return
                        end
                        local result, total = configurePacks(root)
                        if result == "ok" then
                            configTries = 0
                            afkBuyStatus = string.format("AFK MODE ทำงาน · ซื้อ %d แพ็คท้าย (จาก %d)",
                                math.min(AFK_BUY_LAST, total), total)
                        elseif result == "changed" then
                            configTries += 1
                            afkBuyStatus = "กำลังตั้งค่าแพ็คเป็น BUYING..."
                        else
                            afkBuyStatus = "ไม่พบรายการแพ็คในหน้า AFK"
                        end
                        return
                    end

                    configTries = 0
                    local idle = os.clock() - lastInput
                    if idle < AFK_BUY_IDLE then
                        afkBuyStatus = "รอ AFK อีก " .. fmt(AFK_BUY_IDLE - idle)
                        return
                    end
                    if os.clock() < nextOpenTry then
                        afkBuyStatus = "เปิด AFK MODE ไม่ได้ · ลองใหม่ใน " .. fmt(nextOpenTry - os.clock())
                        return
                    end

                    local btn = findAfkButton()
                    if not btn then
                        afkBuyStatus = "ไม่พบปุ่ม AFK MODE"
                        nextOpenTry = os.clock() + 60
                        return
                    end
                    afkBuyStatus = "กำลังเปิด AFK MODE..."
                    refresh()
                    press(btn)
                    for _ = 1, 8 do
                        task.wait(0.5)
                        if findAfkWindow() then break end
                        -- บางเกมต้องกดเริ่มอีกครั้ง
                        for _, t in ipairs(textsOf(PlayerGui)) do
                            if t.up == "START AFK" and shown(t.inst) then
                                press(t.inst)
                                break
                            end
                        end
                    end
                    if findAfkWindow() then
                        print("[Anti AFK] เปิด AFK MODE แล้ว")
                    else
                        afkBuyStatus = "เปิด AFK MODE ไม่ได้"
                        warn("[Anti AFK] AFK Buy: กดปุ่ม " .. btn:GetFullName() .. " แล้วไม่เห็นหน้า AFK MODE")
                        nextOpenTry = os.clock() + AFK_BUY_IDLE
                    end
                end)
                if not ok then
                    afkBuyStatus = "error: " .. tostring(err):sub(1, 60)
                end
            else
                afkBuyStatus = "ปิดอยู่"
            end
            refresh()
            task.wait(2)
        end
    end)
end

-- ===== Server Hop ก่อน Lottery =====
-- 2 นาทีก่อน Lottery ถ้าผู้เล่นในเซิร์ฟเวอร์น้อยกว่า HOP_MIN_PLAYERS จะย้ายไปเซิร์ฟเวอร์ที่คนเยอะที่สุดที่ยังไม่เต็ม
do
    local TeleportService = game:GetService("TeleportService")
    local HttpService = game:GetService("HttpService")
    local HOP_FILE = "AntiAFK_Hop.json"
    local httpReq = request or http_request
        or (syn and syn.request) or (http and http.request) or (fluxus and fluxus.request)

    local function getJson(url)
        local body
        if httpReq then
            local ok, res = pcall(httpReq, { Url = url, Method = "GET" })
            if ok and res and res.StatusCode == 200 then body = res.Body end
        end
        if not body then
            local ok, res = pcall(function() return game:HttpGet(url) end)
            if ok then body = res end
        end
        if body then
            local ok, data = pcall(HttpService.JSONDecode, HttpService, body)
            if ok then return data end
        end
    end

    -- จำนวนครั้งที่ย้ายในรอบนี้ เก็บในไฟล์ เพราะสคริปต์เริ่มใหม่ทุกครั้งที่ย้ายเซิร์ฟเวอร์
    local function loadHop()
        local ok, data = pcall(function()
            if isfile and readfile and isfile(HOP_FILE) then
                return HttpService:JSONDecode(readfile(HOP_FILE))
            end
        end)
        return (ok and type(data) == "table") and data or {}
    end

    local function saveHop(data)
        pcall(function()
            if writefile then writefile(HOP_FILE, HttpService:JSONEncode(data)) end
        end)
    end

    -- เซิร์ฟเวอร์สาธารณะที่ยังไม่เต็ม เรียงจากคนมากไปน้อย
    local function findServers()
        local data = getJson(string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100&excludeFullGames=true",
            game.PlaceId))
        if not data or type(data.data) ~= "table" then return nil end
        local list = {}
        for _, s in ipairs(data.data) do
            if s.id ~= game.JobId and type(s.playing) == "number" and type(s.maxPlayers) == "number"
                and s.playing < s.maxPlayers then
                list[#list + 1] = s
            end
        end
        table.sort(list, function(a, b) return a.playing > b.playing end)
        return list
    end

    local hopping, hopStartedAt = false, 0
    local triedIds = {}
    trackConn(TeleportService.TeleportInitFailed:Connect(function(player, result, msg)
        if player == LocalPlayer and hopping then
            hopping = false
            hopStatus = "ย้ายเซิร์ฟไม่สำเร็จ · ลองเซิร์ฟถัดไป"
            warn("[Anti AFK] Server Hop ล้มเหลว: " .. tostring(result) .. " " .. tostring(msg))
        end
    end))

    task.spawn(function()
        while gui.Parent do
            if settings.serverHop then
                if hopping and os.clock() - hopStartedAt > 25 then
                    hopping = false -- teleport ค้าง ลองเซิร์ฟถัดไป
                end
                local ok, err = pcall(function()
                    if hopping then return end
                    local count = #Players:GetPlayers()
                    local t = os.date("*t")
                    if t.min ~= HOP_CHECK_MINUTE then
                        hopStatus = string.format("ผู้เล่น %d คน · เช็กตอนนาที %02d", count, HOP_CHECK_MINUTE)
                        return
                    end
                    if count >= HOP_MIN_PLAYERS then
                        hopStatus = string.format("ผู้เล่น %d คน · พอสำหรับ Lottery", count)
                        return
                    end

                    local key = string.format("%d-%d-%d", t.year, t.yday, t.hour)
                    local hop = loadHop()
                    if hop.key ~= key then hop = { key = key, count = 0 } end
                    if hop.count >= HOP_MAX_PER_HOUR then
                        hopStatus = string.format("ผู้เล่น %d คน · ย้ายครบ %d ครั้งแล้วรอบนี้", count, HOP_MAX_PER_HOUR)
                        return
                    end

                    hopStatus = string.format("ผู้เล่น %d คน · กำลังหาเซิร์ฟ...", count)
                    refresh()
                    local servers = findServers()
                    if not servers then
                        hopStatus = "ดึงรายชื่อเซิร์ฟเวอร์ไม่ได้"
                        return
                    end
                    local target
                    for _, s in ipairs(servers) do
                        if not triedIds[s.id] then target = s break end
                    end
                    -- ต้องมีคนมากกว่าเซิร์ฟนี้ และพอสำหรับ Lottery หลังเราเข้าไป
                    if not target or target.playing + 1 < HOP_MIN_PLAYERS or target.playing < count then
                        hopStatus = string.format("ผู้เล่น %d คน · ไม่มีเซิร์ฟที่คนพอ", count)
                        return
                    end

                    hop.count += 1
                    saveHop(hop)
                    triedIds[target.id] = true
                    hopping, hopStartedAt = true, os.clock()
                    hopStatus = string.format("กำลังย้ายไปเซิร์ฟ %d/%d คน...", target.playing, target.maxPlayers)
                    refresh()
                    notify(string.format("ผู้เล่นไม่ถึง %d คน ย้ายไปเซิร์ฟ %d คน", HOP_MIN_PLAYERS, target.playing))
                    print(string.format("[Anti AFK] Server Hop: %d คน -> %s (%d/%d)",
                        count, target.id, target.playing, target.maxPlayers))
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, target.id, LocalPlayer)
                end)
                if not ok then
                    hopping = false
                    hopStatus = "error: " .. tostring(err):sub(1, 60)
                end
            else
                hopStatus = "ปิดอยู่"
            end
            refresh()
            task.wait(3)
        end
    end)
end

notify("เปิดใช้งานแล้ว")
print("[Anti AFK] เปิดใช้งานแล้ว")