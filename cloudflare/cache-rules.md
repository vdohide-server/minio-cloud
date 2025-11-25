# Cloudflare Cache Rules for HLS Streaming

## 🎬 สำหรับใช้กับ nginx-vod-module + MinIO

เมื่อใช้ nginx-vod-module แปลง MP4 เป็น HLS, ต้อง config Cloudflare ให้ cache segments

---

## 📋 Cache Rules

### Rule 1: Cache HLS Segments (.ts)

```
Rule name: Cache HLS Segments
When: URI Path ends with ".ts"

Then:
  Cache eligibility: Eligible for cache
  Edge TTL: 1 month
  Browser TTL: 1 day
  Cache Key: 
    - Query String: Ignore
```

### Rule 2: Cache HLS Playlists (.m3u8)

```
Rule name: Cache HLS Playlists
When: URI Path ends with ".m3u8"

Then:
  Cache eligibility: Eligible for cache
  Edge TTL: 1 hour
  Browser TTL: 5 minutes
```

### Rule 3: Bypass Cache for API

```
Rule name: Bypass MinIO API
When: 
  URI Path contains "/minio/" 
  OR Request Method is not "GET"

Then:
  Cache eligibility: Bypass cache
```

---

## 🛠️ วิธีสร้าง Cache Rules

### Cloudflare Dashboard

1. ไปที่ Domain → **Caching** → **Cache Rules**
2. Click **Create Rule**
3. ใส่ค่าตาม rules ข้างบน

---

## 📝 Page Rules (Alternative - Legacy)

ถ้าใช้ Page Rules แทน Cache Rules:

```
Page Rule 1:
  URL: *example.com/*.ts
  Settings:
    - Cache Level: Cache Everything
    - Edge Cache TTL: 1 month
    - Browser Cache TTL: 1 day

Page Rule 2:
  URL: *example.com/*.m3u8
  Settings:
    - Cache Level: Cache Everything
    - Edge Cache TTL: 1 hour
    - Browser Cache TTL: 300 (5 min)

Page Rule 3:
  URL: *example.com/minio/*
  Settings:
    - Cache Level: Bypass
```

---

## 📊 Expected Cache Performance

### Cache Hit Rates

| Content Type | Expected Hit Rate | TTL |
|--------------|-------------------|-----|
| .ts segments | 80-95% | 1 month |
| .m3u8 playlists | 70-90% | 1 hour |
| /minio/* | 0% (bypass) | - |

### Bandwidth Savings

```
ถ้ามี 100M segment requests/วัน:
- Cache hit 85%: 85M จาก Cloudflare (ฟรี)
- Cache miss 15%: 15M ไป origin (MinIO)

ลด origin bandwidth: 85%!
```

---

## 🔧 Cache-Control Headers

### nginx-vod-module ควร set headers:

```nginx
# ใน nginx.conf
location ~ ^/hls/ {
    # For segments
    add_header Cache-Control "public, max-age=31536000";
    
    # For playlists  
    # (set ใน location ที่ serve .m3u8)
    add_header Cache-Control "public, max-age=3600";
}
```

### Verify Headers

```bash
curl -I https://vod.example.com/hls/videos/movie.mp4/seg-1.ts

# ควรเห็น:
# cache-control: public, max-age=31536000
# cf-cache-status: HIT (or MISS on first request)
```

---

## 🔍 Debugging Cache

### Check Cache Status

```bash
curl -I https://example.com/hls/video.mp4/seg-1.ts | grep -i cf-cache

# cf-cache-status: HIT     ← Cached at edge
# cf-cache-status: MISS    ← Fetched from origin
# cf-cache-status: EXPIRED ← Cache expired, refetched
# cf-cache-status: BYPASS  ← Not cached
```

### Purge Cache

```bash
# Via Cloudflare Dashboard:
# Caching → Configuration → Purge Cache

# Or API:
curl -X POST "https://api.cloudflare.com/client/v4/zones/ZONE_ID/purge_cache" \
     -H "Authorization: Bearer API_TOKEN" \
     -H "Content-Type: application/json" \
     --data '{"files":["https://example.com/hls/videos/movie.mp4/index.m3u8"]}'
```

---

## ⚠️ Common Issues

### Issue: Segments not caching

```
Cause: Cache-Control header missing or wrong
Fix: Add header in nginx config

# Check:
curl -I URL | grep cache-control
```

### Issue: Stale playlist

```
Cause: .m3u8 cached too long
Fix: Reduce TTL to 1 hour or less
```

### Issue: CORS errors

```
Cause: Cross-origin request blocked
Fix: Add CORS headers in nginx:

add_header Access-Control-Allow-Origin "*";
add_header Access-Control-Allow-Methods "GET, OPTIONS";
```

---

## 📈 Monitoring

### Cloudflare Analytics

```
Analytics → Traffic:
- Check "Cached Requests" vs "Uncached Requests"
- Goal: > 80% cached for HLS content
```

### Cache Analytics (Enterprise)

```
Analytics → Cache:
- Detailed cache hit/miss breakdown
- Cache by content type
```
