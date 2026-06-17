# API Flow: GET /metadata/records/

## Overview
This document describes the complete flow for the GET `/metadata/records/` endpoint in the ABIS system.

## Request
- **Method**: GET
- **Endpoint**: `/metadata/records/`
- **Header**: `X-ABIS-Api-Key: key123`

## 1. Authentication & Middleware
Authentication happens **before** the `records()` view runs.

- Reads header: `X-ABIS-Api-Key: key123`
- Finds tenant:
  ```python
  Tenant(
      name="ABC Bank",
      vector_collection_name="abc_faces"
  )
  ```
- Attaches to request: `request.integrator_tenant = tenant`

## 2. records() Function
```python
def records(self, request):
```

## 3. Audit Logging
- `log_audit_event(...)`
- Stores:
  - Who accessed the API
  - Page Number
  - Filters used
  - Time
- Purpose: Tracking and auditing.

## 4. Read Query Parameters
Common parameters:
- `page`
- `page_size`
- `search`
- `status`
- `bio_type`
- `tags`
- `vector_collection`
- `sort_by`
- `sort_order`
- `paginate_by`

**Example**:
```
GET /metadata/records/?page=1&status=STORED
```
→ `page = 1`, `status = "STORED"`

## 5. Base Queryset
```python
Metadata.objects.all()
```

**Sample Data**:
| user_id | collection     |
|---------|----------------|
| U001    | abc_faces      |
| U002    | abc_faces      |
| U003    | xyz_faces      |

## 6. Tenant Collection Filtering
```python
queryset = apply_tenant_collection_to_queryset(
    request,
    Metadata.objects.all()
)
```

### 6.1 Get Tenant Collection Name
```python
tenant_vector_collection(request)
```
→ Calls `get_request_tenant(request)` → returns `request.integrator_tenant` → `"abc_faces"`

### 6.2 Apply Filter
```python
filter_metadata_queryset_by_vector_collection(
    queryset,
    "abc_faces"
)
```
→ `queryset.filter(vector_collection_name="abc_faces")`

**After Filter**:
- U001 (abc_faces)
- U002 (abc_faces)
- ~~U003 (xyz_faces)~~ (removed)

## 7. Additional Filters

### Search Filter
`?search=U001`
```python
queryset.filter(user_id__icontains="U001")
```

### Status Filter
`?status=STORED`
```python
queryset.filter(status="STORED")
```

### Bio Type Filter
`?bio_type=FID`
```python
queryset.filter(bio_type="FID")
```

### Tags Filter
`filter_queryset_by_all_tags(...)`

## 8. Sorting
- Example: `?sort_by=user_id` → `queryset.order_by("user_id")`
- Default: `queryset.order_by("-created_at")` (Newest first)

## 9. Count Records
```python
total_count = queryset.count()
```
Example: 100 records found.

## 10. Pagination
- `paginate_by` parameter
- **Default Mode** (`record`): Standard pagination (e.g., 20 records/page)
- **User Mode** (`user`): Groups by `user_id` and paginates users

## 11. Serialization
```python
serializer = MetadataSerializer(...)
```
Converts Django objects to JSON:
```json
{
  "user_id": "U001",
  "status": "STORED"
}
```

## 12. Build Response
```python
response_data = {
    "results": [...],
    "count": 100,
    "page": 1,
    "page_size": 20
}
```

## 13. Next/Previous URLs
Uses `page_obj.has_next()` etc. to generate links like `?page=2`

## 14. Return Response
```python
return Response(response_data, status=200)
```

## Complete Flow Diagram (Text)
```
Request
   │
   ▼
Authentication
   │
   ▼
Find Tenant
   │
   ▼
request.integrator_tenant
   │
   ▼
tenant.vector_collection_name
   │
   ▼
records()
   │
   ▼
log_audit_event()
   │
   ▼
Read Query Params
   │
   ▼
Metadata.objects.all()
   │
   ▼
apply_tenant_collection_to_queryset()
   │
   ▼
queryset.filter(vector_collection_name="abc_faces")
   │
   ▼
Search Filter
   │
   ▼
Status Filter
   │
   ▼
Bio Type Filter
   │
   ▼
Tags Filter
   │
   ▼
Sorting
   │
   ▼
Count
   │
   ▼
Pagination
   │
   ▼
Serializer
   │
   ▼
Build JSON Response
   │
   ▼
Return Response
```
