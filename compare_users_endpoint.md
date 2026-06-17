# `compare_users_endpoint.md`

# Compare Users Endpoint Flow

## Endpoint Definition

```python
@action(detail=False, methods=["post"], url_path="compare-users")
def compare_users(self, request):
```

POST /metadata/compare-users/
Compares biometric records between two users (uIdA and uIdB) for a given bioType.

### 1. Request Validation

```python
serializer = CompareUsersRequestSerializer(data=request.data)

if not serializer.is_valid():
    return Response(serializer.errors, status=400)
```

### 2. Extract Input Parameters

```python
data = serializer.validated_data
u_id_a = data["uIdA"].strip()
u_id_b = data["uIdB"].strip()
bio_type = data["bioType"]
bio_sub_raw = data.get("bioSubType") or ""
bio_sub_norm = normalize_bio_sub_type(bio_sub_raw)

filter_all_subtypes = (bio_sub_norm == "" or bio_sub_norm.upper() == "ALL")
```

### 3. Audit Logging (Start)

```python
log_audit_event(
    event_type=EventType.BIOMETRIC_IDENTIFY,
    user_id=u_id_a,
    action="compare_users",
    details={"uIdB": u_id_b, "bio_type": bio_type}
)
```

### 4. latest_by_subtype() Internal Function

This function is called for both users.

```python
def latest_by_subtype(user_id: str):
    qs = Metadata.objects.filter(
        user_id=user_id,
        status=Metadata.Status.STORED,
        bio_type=bio_type,
    )

    # Vector collection filter (if applicable)
    if vector_collection:
        qs = filter_metadata_queryset_by_vector_collection(qs, vector_collection)

    # Subtype filtering
    if not filter_all_subtypes:
        if bio_sub_norm == "":
            qs = qs.filter(models.Q(bio_sub_type__isnull=True) | models.Q(bio_sub_type=""))
        else:
            qs = qs.filter(bio_sub_type=bio_sub_norm)

    qs = qs.order_by("-created_at")

    # Keep only latest record per subtype
    by_sub = {}
    for r in qs:
        key = normalize_bio_sub_type(r.bio_sub_type)
        if key not in by_sub:
            by_sub[key] = r
    return by_sub
```

### 5. Fetch Latest Records for Both Users

```python
by_a = latest_by_subtype(u_id_a)
by_b = latest_by_subtype(u_id_b)
```

### 6. Find Common Subtypes

```python
if filter_all_subtypes:
    common_keys = sorted(set(by_a.keys()) & set(by_b.keys()))
else:
    key = bio_sub_norm
    common_keys = [key] if (key in by_a and key in by_b) else []
```

### 7. Compare Each Matching Subtype

```python
vector_db = get_vector_db_service()

for key in common_keys:
    rec_a = by_a[key]
    rec_b = by_b[key]
    
    ga = str(rec_a.gallery_id)
    gb = str(rec_b.gallery_id)
    
    out = vector_db.compute_pair_similarity(ga, gb, bio_type)
    
    entry = {
        "bioSubType": key if key else "UNSPECIFIED",
        "galleryIdA": ga,
        "galleryIdB": gb,
        "similarity": out.get("similarity"),
        "error": out.get("error"),
    }
    pairs.append(entry)
```

### 8. Final Response Construction

```python
response_data = {
    "uIdA": u_id_a,
    "uIdB": u_id_b,
    "bioType": bio_type,
    "pairs": pairs,
}

if errors:
    response_data["errors"] = errors
```

### 9. Audit Logging (Completion)

```python
log_audit_event(
    event_type=EventType.BIOMETRIC_IDENTIFY,
    user_id=u_id_a,
    action="compare_users_completed",
    details={"uIdB": u_id_b, "pairs_count": len(pairs)}
)
```

### 10. Return Response

```python
return Response(response_data, status=200)
```

## Example Response

```json
{
  "uIdA": "user_001",
  "uIdB": "user_002",
  "bioType": "FACE",
  "pairs": [
    {
      "bioSubType": "LEFT_EYE",
      "galleryIdA": "g1",
      "galleryIdB": "g9",
      "similarity": 0.91,
      "error": null
    }
  ]
}
```

## Flow Summary

```
POST /compare-users
        ↓
Request Validation
        ↓
Fetch Latest Records (both users)
        ↓
Find Common Subtypes
        ↓
compute_pair_similarity() for each pair
        ↓
Build Response + Audit Log
        ↓
Return Comparison Result
```
