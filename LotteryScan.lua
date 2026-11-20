-- Lottery Scan: หาว่ามีข้อมูลคำตอบลอตเตอรี่ฝั่ง client หรือไม่
-- สคริปต์นี้แค่อ่านและรายงานผล ไม่กดแทงเลขให้
-- รันก่อนลอตเตอรี่เปิด แล้วเทียบเลขที่พบกับเลขที่ออกจริง

local env = (getgenv and getgenv()) or _G
if env.__LotteryScan_Loaded then
    print("[LotteryScan] ทำงานอยู่แล้ว")
    return
end
env.__LotteryScan_Loaded = true

local HttpService = game:GetService("HttpService")
local KEYWORDS = { "lotter", "lucky", "winning", "winner", "answer", "jackpot", "result", "draw", "bet" }

local function hasKeyword(s)
    s = tostring(s):lower()
    for _, k in ipairs(KEYWORDS) do
        if s:find(k, 1, true) then return true end
    end
    return false
end

-- ---------- รายงานผล ----------
local url = env.AntiAFK_Webhook
local httpRequest = request or http_request or (syn and syn.request) or (http and http.request)
local buffer, seen, total = {}, {}, 0
local MAX_REPORTS = 300

local function report(kind, text)
    local key = kind .. "|" .. text
    if seen[key] or total >= MAX_REPORTS then return end
    seen[key] = true
    total += 1
    local line = string.format("[%s] %s: %s", os.date("%H:%M:%S"), kind, text)
    print("[LotteryScan] " .. line)
    buffer[#buffer + 1] = line
end

task.spawn(function()
    while true do
        task.wait(10)
        if #buffer > 0 and url and httpRequest then
            local text = table.concat(buffer, "\n")
            buffer = {}
            pcall(httpRequest, {
                Url = url,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode({
                    username = "Lottery Scan",
                    embeds = { {
                        title = "🔍 Lottery Scan",
                        description = "```\n" .. text:sub(1, 3800) .. "\n```",
                        color = 0x5865F2,
                    } },
                }),
            })
        else
            buffer = {}
        end
    end
end)

local function ser(v, depth)
    depth = depth or 0
    local t = typeof(v)
    if t == "table" then
        if depth >= 2 then return "{...}" end
        local parts, n = {}, 0
        for k, val in pairs(v) do
            n += 1
            if n > 12 then parts[#parts + 1] = "..." break end
            parts[#parts + 1] = tostring(k) .. "=" .. ser(val, depth + 1)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif t == "Instance" then
        return v:GetFullName()
    elseif t == "string" then
        return string.format("%q", v:sub(1, 80))
    end
    return tostring(v)
end

-- ---------- 1. Value และ Attribute ที่ชื่อเกี่ยวกับลอตเตอรี่ ----------
local function scanInstance(inst)
    if inst:IsA("ValueBase") and (hasKeyword(inst.Name) or hasKeyword(inst.Parent and inst.Parent.Name or "")) then
        report("Value", inst:GetFullName() .. " = " .. ser(inst.Value))
        inst.Changed:Connect(function(v)
            report("Value เปลี่ยน", inst:GetFullName() .. " = " .. ser(v))
        end)
    end
    local ok, attrs = pcall(function() return inst:GetAttributes() end)
    if ok then
        for k, v in pairs(attrs) do
            if hasKeyword(k) or hasKeyword(inst.Name) then
                report("Attribute", inst:GetFullName() .. "." .. k .. " = " .. ser(v))
            end
        end
        inst.AttributeChanged:Connect(function(k)
            if hasKeyword(k) or hasKeyword(inst.Name) then
                report("Attribute เปลี่ยน", inst:GetFullName() .. "." .. k .. " = " .. ser(inst:GetAttribute(k)))
            end
        end)
    end
end

local roots = { game:GetService("ReplicatedStorage"), workspace, game:GetService("Players").LocalPlayer }
for _, root in ipairs(roots) do
    pcall(scanInstance, root)
    for _, d in ipairs(root:GetDescendants()) do
        pcall(scanInstance, d)
    end
    root.DescendantAdded:Connect(function(d) pcall(scanInstance, d) end)
end

-- ---------- 2. ข้อมูลที่ server ส่งมาทาง RemoteEvent ----------
-- รายงานทุก remote ที่ชื่อเกี่ยวกับลอตเตอรี่ และทุก remote ในช่วง 5 นาทีแรกของชั่วโมง
local function watchRemote(r)
    if r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent") then
        r.OnClientEvent:Connect(function(...)
            local args = { ... }
            local text = ser(args)
            local min = os.date("*t").min
            if hasKeyword(r.Name) or hasKeyword(text) or min < 5 then
                report("Remote", r:GetFullName() .. " " .. text)
            end
        end)
    end
end

for _, d in ipairs(game:GetDescendants()) do
    pcall(watchRemote, d)
end
game.DescendantAdded:Connect(function(d) pcall(watchRemote, d) end)

-- ---------- 3. ModuleScript ที่ชื่อเกี่ยวกับลอตเตอรี่ ----------
for _, d in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
    if d:IsA("ModuleScript") and hasKeyword(d.Name) then
        local ok, mod = pcall(require, d)
        report("Module", d:GetFullName() .. " = " .. (ok and ser(mod) or "require ไม่ได้"))
    end
end

-- ---------- 4. ตัวแปรในหน่วยความจำของ script ฝั่ง client (ต้องมี getgc) ----------
local function scanGc()
    if not getgc then
        report("GC", "executor ไม่มี getgc ข้ามขั้นนี้")
        return
    end
    local found = 0
    for _, obj in ipairs(getgc(true)) do
        if type(obj) == "table" then
            local ok = pcall(function()
                for k, v in pairs(obj) do
                    if type(k) == "string" and hasKeyword(k)
                        and (type(v) == "number" or type(v) == "string" or type(v) == "boolean") then
                        report("GC", k .. " = " .. ser(v))
                        found += 1
                    end
                end
            end)
            if found >= 80 then break end
        end
    end
end

-- สแกนตอนเริ่ม และสแกนซ้ำทุกนาทีในช่วง 5 นาทีแรกของชั่วโมง
pcall(scanGc)
task.spawn(function()
    while true do
        task.wait(60)
        if os.date("*t").min < 5 then pcall(scanGc) end
    end
end)

print("[LotteryScan] เริ่มสแกนแล้ว ดูผลใน F9" .. (url and " และ Discord" or ""))
