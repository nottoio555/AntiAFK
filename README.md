# Anti AFK (Roblox)

## วิธีอัปโหลด
1. สร้าง repo สาธารณะบน GitHub (เช่น `AntiAFK`)
2. อัปโหลดไฟล์ `AntiAFK.lua` ไปที่ branch `main`

## วิธีใช้ใน executor
แทน `USERNAME` และ `REPO` ด้วยของคุณ:

```lua
loadstring(game:HttpGet('https://raw.githubusercontent.com/USERNAME/REPO/main/AntiAFK.lua'))()
```

## Discord Webhook (แจ้งเตือนการ์ดที่สุ่มได้)

อย่าใส่ URL webhook ลงใน repo สาธารณะ ให้ตั้งค่าฝั่งผู้ใช้แทน มี 2 วิธี:

1. ตั้งค่าก่อนรัน loadstring
```lua
getgenv().AntiAFK_Webhook = "https://discord.com/api/webhooks/ID/TOKEN"
loadstring(game:HttpGet('https://raw.githubusercontent.com/nottoio555/AntiAFK/main/AntiAFK.lua'))()
```
2. สร้างไฟล์ `AntiAFK_Webhook.txt` ในโฟลเดอร์ workspace ของ executor แล้ววาง URL ไว้ในไฟล์
