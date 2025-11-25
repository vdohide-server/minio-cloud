# Cloudflare DNS Setup for MinIO

## 🌐 DNS Configuration

### Option 1: DNS Round-Robin (แนะนำ)

ใช้หลาย A records ชี้ไปทุก node - Cloudflare จะกระจาย traffic อัตโนมัติ

```
Type    Name              Content         Proxy    TTL
─────────────────────────────────────────────────────────
A       minio             1.2.3.4         ON       Auto    (Node 1 Public IP)
A       minio             1.2.3.5         ON       Auto    (Node 2 Public IP)
A       minio             1.2.3.6         ON       Auto    (Node 3 Public IP)
A       minio             1.2.3.7         ON       Auto    (Node 4 Public IP)
```

**ผลลัพธ์:** `minio.yourdomain.com` จะ resolve ไปหลาย IPs

---

### Option 2: Single Entry + Load Balancer

ถ้าคุณมี Load Balancer หน้า MinIO:

```
Type    Name              Content         Proxy    TTL
─────────────────────────────────────────────────────────
A       minio             LB_IP           ON       Auto
```

---

## ⚙️ Cloudflare Settings

### 1. SSL/TLS

```
SSL/TLS → Overview:
  Encryption mode: Full (strict)

SSL/TLS → Edge Certificates:
  Always Use HTTPS: ON
  Minimum TLS Version: TLS 1.2
```

### 2. Caching (สำหรับ HLS Streaming)

```
Caching → Configuration:
  Caching Level: Standard
  Browser Cache TTL: Respect Existing Headers

Caching → Tiered Cache:
  Enable Tiered Cache: ON (ถ้ามี)
```

### 3. Speed

```
Speed → Optimization:
  Auto Minify: OFF (สำหรับ binary content)
  Brotli: ON
  HTTP/2: ON
  HTTP/3 (QUIC): ON
```

### 4. Network

```
Network:
  WebSockets: ON (สำหรับ Console)
  gRPC: OFF
  Onion Routing: OFF
```

---

## 🔒 Security Settings

### Firewall Rules (Optional)

สร้าง rule เพื่อป้องกัน abuse:

```
Rule name: Rate Limit MinIO
When: URI Path contains "/videos/"
Then: Rate Limit (100 requests per 10 seconds)
```

### Bot Fight Mode

```
Security → Bots:
  Bot Fight Mode: ON
  
  (ระวัง: อาจ block legitimate video players)
```

---

## 📊 DNS Records Summary

### Production Setup

```
# MinIO API (S3)
minio.example.com      →  A records to all nodes (Proxied)

# MinIO Console (Web UI)
console.example.com    →  A record to any node (Proxied)

# Direct access (bypass Cloudflare - for internal use)
direct.minio.example.com  →  A records (DNS only, no proxy)
```

### Example with IPs

```
# Assuming:
# Node 1: 203.0.113.1
# Node 2: 203.0.113.2
# Node 3: 203.0.113.3
# Node 4: 203.0.113.4

minio.example.com       A    203.0.113.1    Proxied
minio.example.com       A    203.0.113.2    Proxied
minio.example.com       A    203.0.113.3    Proxied
minio.example.com       A    203.0.113.4    Proxied

console.example.com     A    203.0.113.1    Proxied
```

---

## 🧪 Testing

### Verify DNS

```bash
# Check DNS resolution
dig minio.example.com +short

# Should show multiple IPs if using Round-Robin
# 203.0.113.1
# 203.0.113.2
# 203.0.113.3
# 203.0.113.4
```

### Verify Cloudflare Proxy

```bash
# Check if proxied
curl -I https://minio.example.com/minio/health/live

# Look for headers:
# cf-ray: xxxxx
# server: cloudflare
```

### Test S3 API

```bash
# Configure mc
mc alias set mycluster https://minio.example.com admin YourPassword

# Test
mc admin info mycluster
mc ls mycluster
```

---

## ⚠️ Important Notes

1. **Cloudflare Free Plan Limits:**
   - 100MB max upload size (สำหรับ proxied)
   - ถ้า upload ไฟล์ใหญ่ ต้อง bypass proxy หรือ upgrade plan

2. **Upload Large Files:**
   ```
   # ใช้ direct subdomain (ไม่ผ่าน proxy) สำหรับ upload
   direct.minio.example.com → DNS only (grey cloud)
   ```

3. **WebSocket for Console:**
   - ต้องเปิด WebSocket ใน Cloudflare settings
   - ไม่งั้น Console จะไม่ทำงาน

4. **Cache Bypass:**
   - MinIO API ควร bypass cache (POST, PUT, DELETE)
   - Cloudflare จะ auto-handle method-based caching
