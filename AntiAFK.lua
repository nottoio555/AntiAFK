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

local SCRIPT_VERSION = "v2"

-- กันรันซ้ำ: บอกเวอร์ชันที่รันอยู่ และเตือนถ้าโค้ดบน GitHub ใหม่กว่า
if env.__AntiAFK_Loaded then
    local running = env.__AntiAFK_Version or "v1"
    if running ~= SCRIPT_VERSION then
        notify(string.format("กำลังรัน %s อยู่ มี %s แล้ว กรุณา rejoin", running, SCRIPT_VERSION))
        print(string.format("[Anti AFK] กำลังรัน %s อยู่ มีเวอร์ชันใหม่ %s ให้ rejoin แล้วรันใหม่", running, SCRIPT_VERSION))
    else
        notify("ทำงานอยู่แล้ว (" .. running .. ")")
        print("[Anti AFK] ทำงานอยู่แล้ว (" .. running .. ") ไม่ต้องรันซ้ำ")
    end
    return
end
env.__AntiAFK_Loaded = true
env.__AntiAFK_Version = SCRIPT_VERSION

local startTime = os.clock()
local kickBlocked = 0
local reconnectStatus = "เปิดอยู่ · พร้อมเชื่อมต่อใหม่"
local loadingStatus = "กำลังตรวจหน้าโหลด..."
local eventStatus = "กำลังเริ่ม"
local rebirthStatus = "กำลังอ่านค่า..."
local webhookStatus = "กำลังเริ่ม"

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
local function addRow(key, icon, title, order)
    local card = make("Frame", {
        Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = THEME.card,
        BorderSizePixel = 0, LayoutOrder = order,
    }, body)
    corner(card, 8)
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
        BackgroundTransparency = 1, Position = UDim2.fromOffset(46, 6), Size = UDim2.new(1, -52, 0, 14),
        TextXAlignment = Enum.TextXAlignment.Left,
    }, card)
    local value = make("TextLabel", {
        Text = "-", Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = THEME.sub,
        BackgroundTransparency = 1, Position = UDim2.fromOffset(46, 22), Size = UDim2.new(1, -52, 0, 14),
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
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

local function fmt(sec)
    sec = math.floor(sec)
    return string.format("%02d:%02d:%02d", sec // 3600, (sec % 3600) // 60, sec % 60)
end

-- สีตามสถานะ: แดง = มีปัญหา, เหลือง = กำลังรอ/ทำงาน, เขียว = ปกติ
local function toneOf(s)
    if s == "ปิดอยู่" or s == "ไม่พบหน้าโหลด" then return THEME.sub end
    if s:find("ไม่") or s:find("ล้มเหลว") or s:find("error") then return THEME.bad end
    if s:find("รอบหน้า") then return THEME.ok end
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
                VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
                task.wait(0.05)
                VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
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

    local url = env.AntiAFK_Webhook
    if not url and readfile and isfile then
        pcall(function()
            if isfile("AntiAFK_Webhook.txt") then
                url = readfile("AntiAFK_Webhook.txt")
            end
        end)
    end
    if url then url = url:gsub("%s+", "") end

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

notify("เปิดใช้งานแล้ว")
print("[Anti AFK] เปิดใช้งานแล้ว")
