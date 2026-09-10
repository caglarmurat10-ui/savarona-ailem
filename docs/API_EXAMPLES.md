# API Examples

## Bootstrap owner

```bash
curl -X POST "$API/v1/admin/bootstrap" \
  -H "content-type: application/json" \
  -H "x-bootstrap-secret: $BOOTSTRAP_SECRET" \
  -d '{"family_name":"Çağlar Ailesi","owner_name":"Murat","device_name":"Murat Telefon","platform":"android"}'
```

Yanıttaki `device_token` yalnızca cihaz secure storage'a yazılmalıdır.

## Invite

```bash
curl -X POST "$API/v1/invites" -H "Authorization: Bearer $DEVICE_TOKEN"
```

## Join

```bash
curl -X POST "$API/v1/join" \
  -H "content-type: application/json" \
  -d '{"invite_code":"ABCDEFGH","member_name":"Aile Üyesi","device_name":"iPhone","platform":"ios"}'
```

## Location

```bash
curl -X POST "$API/v1/location" \
  -H "Authorization: Bearer $DEVICE_TOKEN" \
  -H "content-type: application/json" \
  -d '{"captured_at":1789066800000,"lat":36.265,"lng":29.318,"accuracy_m":8.5,"speed_mps":18.2,"heading_deg":220,"battery_pct":74,"activity":"automotive","sequence_no":1}'
```
