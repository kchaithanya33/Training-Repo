# Delete By Tags API Flow Documentation

## Overview
This document describes the complete flow of the `delete_by_tags` API endpoint, which handles deletion of biometric metadata records based on tags, ensuring consistency across Milvus (vector DB), storage, and PostgreSQL.

## Step 1: API Request Arrives
The request reaches:
```python
delete_by_tags(self, request)
```

**Example request:**
```json
{
    "tags": ["employee", "india"],
    "bioType": "FID",
    "dryRun": false
}
```

## Step 2: Validate Request
```python
serializer = MetadataDeleteByTagsReqSerializer(data=request.data)

if not serializer.is_valid():
    return Response(...)
```

**What it does:**
- Validates the request body.
- Ensures required fields are present.
- Returns HTTP 400 if validation fails.

## Step 3: Extract Input Values
```python
tags = serializer.validated_data["tags"]

bio_type = (
    serializer.validated_data.get("bioType")
    or "FID"
).strip().upper()

dry_run = bool(
    serializer.validated_data.get("dryRun")
)
```

**Result Example:**
- `tags = ["employee", "india"]`
- `bio_type = "FID"`
- `dry_run = False`

## Step 4: Filter Matching Metadata
```python
queryset = filter_queryset_by_all_tags(
    self.get_queryset().filter(
        bio_type=bio_type
    ),
    tags,
)
```

**Functions Called:**
- `self.get_queryset()`: Returns all metadata records.
- `.filter(bio_type=bio_type)`: Filters by biometric type.
- `filter_queryset_by_all_tags()`: Filters records containing **all** specified tags.

## Step 5: Count Matching Records
```python
matched_count = queryset.count()
```

**Example:** `matched_count = 25`

## Step 6: Dry Run Check
```python
if dry_run:
    return Response(...)
```

**Response (dry run):**
```json
{
    "matched_count": 25,
    "dry_run": true
}
```

## Step 7: Audit Logging
```python
log_audit_event(...)
```

Creates audit logs with:
- User
- Action
- Tags
- Bio type
- Match count

## Step 8: Call Deletion Function
```python
result = delete_metadata_queryset(queryset)
```

### Inside `delete_metadata_queryset()`

#### Step 8.1: Read Metadata Records
```python
rows = list(
    queryset.only(
        "gallery_id",
        "bio_type"
    )[:LIMIT + 1]
)
```

#### Step 8.2: Maximum Deletion Check
```python
if len(rows) > LIMIT:
    raise ValueError(...)
```
Prevents mass deletion.

#### Step 8.3: Group by Bio Type
```python
by_bio = defaultdict(list)

for row in rows:
    by_bio[row.bio_type].append(
        row.gallery_id
    )
```

**Example:**
```json
{
    "FID": ["g1", "g2"],
    "IRIS": ["g3"]
}
```

#### Step 8.4: Get Vector DB Service
```python
vector_db = get_vector_db_service()
```

#### Step 8.5: Delete from Milvus
```python
vector_db.delete_biometric_bulk(
    bio_type,
    gallery_ids
)
```

##### Inside `delete_biometric_bulk()`

**8.5.1:** Metadata Lookup
```python
Metadata.objects.filter(
    gallery_id__in=gallery_ids
)
```

**8.5.2:** Determine Collection
```python
self._get_collection_name()
```
Example: `FID` → `arcface_collection`

**8.5.3:** Check Collection Exists
```python
self._has_collection()
```

**8.5.4:** Delete Vectors
```python
self.client.delete_vectors(
    collection_name,
    expr
)
```
Example expression: `gallery_id in ["g1", "g2"]`

#### Step 8.6: Vector Delete Failed?
If Milvus deletion fails:
- Stop deletion
- Do **NOT** delete storage
- Do **NOT** delete PostgreSQL

#### Step 8.7: Get Storage Service
```python
storage = get_storage_service()
```

#### Step 8.8: Delete Files
```python
storage.delete_file(gid)
```

**Inside `delete_file()`:**
```python
def delete_file(self, file_name):
    file_path = os.path.join(
        self.base_path,
        file_name
    )

    if os.path.exists(file_path):
        os.remove(file_path)
        return True
```

#### Step 8.9: Delete PostgreSQL Metadata
```python
queryset.filter(
    gallery_id__in=gallery_ids
).delete()
```

Equivalent SQL:
```sql
DELETE FROM metadata
WHERE gallery_id IN (...);
```

#### Step 8.10: Return Result
```json
{
    "deleted_count": deleted_count,
    "vector_db_deleted": True,
    "storage_deleted_count": storage_deleted_count,
    "gallery_ids": gallery_ids
}
```

## Step 9: Agent Debug Logging
```python
agent_debug_log(...)
```

## Step 10: Return API Response

**Success:**
```json
{
    "success": true,
    "matched_count": 25,
    "deleted_count": 25
}
```

**Failure:**
```json
{
    "success": false,
    "error": "Vector bulk deletion failed"
}
```

## Complete Flow Diagram
```
POST /delete-by-tags
        ↓
Validate Request
        ↓
Extract tags and bioType
        ↓
Filter Metadata by Tags
        ↓
Count Matching Records
        ↓
Dry Run?
    Yes → Return count
        ↓ No
Create Audit Log
        ↓
delete_metadata_queryset()
        ↓
Group gallery IDs by bio type
        ↓
delete_biometric_bulk()
        ↓
_get_collection_name()
        ↓
_has_collection()
        ↓
delete_vectors()   ← Milvus deletion
        ↓
get_storage_service()
        ↓
delete_file()
        ↓
os.path.join()
        ↓
os.path.exists()
        ↓
os.remove()
        ↓
Delete PostgreSQL rows
        ↓
Return Success Response
```

This API ensures that biometric data is deleted **consistently** across Milvus, Storage, and PostgreSQL.