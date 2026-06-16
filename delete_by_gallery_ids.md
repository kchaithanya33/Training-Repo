# Delete by Gallery IDs API Documentation

## Endpoint

```python
@action(detail=False, methods=["post"], url_path="delete-by-gallery-ids")
```

**POST /delete-by-gallery-ids**

Deletes biometric data by galleryIds.

---

## 1. Validation

```python
serializer = MetadataDeleteByGalleryIdsReqSerializer(data=request.data)
```

- Validates request body
- If invalid → 400 Bad Request

---

## 2. Input Extraction

```python
gallery_ids = [...]
bio_type = ...
dry_run = ...
```

- `gallery_ids` → List of IDs to delete
- `bio_type` → Default "FID"
- `dry_run` → If true, only preview (no actual deletion)

---

## 3. Fetch Matching Records

```python
queryset = self.get_queryset().filter(...)
matched_count = queryset.count()
```

- Finds matching records in the database
- Counts affected rows

---

## 4. Dry Run Mode

If `dry_run = True`:

- No deletion performed
- Returns preview response:

```json
{
  "success": true,
  "dry_run": true,
  "matched_count": X
}
```

---

## 5. Audit Logging

```python
log_audit_event(...)
```

- Logs the delete action
- Stores user and metadata information for compliance

---

## 6. Core Function — delete_metadata_queryset

```python
def delete_metadata_queryset(queryset) -> dict:
    from collections import defaultdict
```

### 6.1 Limit Check

```python
rows = list(
    queryset.only("gallery_id", "bio_type")[:DELETE_BY_TAGS_MAX_RECORDS + 1]
)
```

- Limits deletion to prevent large operations (e.g., max ~2000 records)
- If exceeded → Raises `ValueError`

### 6.2 Empty Case

- If no rows found → Returns success with 0 counts

### 6.3 Group by Bio Type

```python
by_bio = {FACE: [...], FINGERPRINT: [...]}
```

- Groups records by biometric type for vector database deletion

### 6.4 Vector DB Deletion (First)

```python
vector_db.delete_biometric_bulk(...)
```

- Deletes embeddings from vector database
- If fails → Operation stops immediately

### 6.5 Storage Deletion

```python
storage.delete_file(gid)
```

- Deletes physical files from storage
- Errors are logged but deletion continues

### 6.6 Database Deletion (Last)

```python
queryset.delete()
```

- Deletes records from PostgreSQL

### 6.7 Return Value

```python
{
  "deleted_count": ...,
  "vector_db_deleted": True,
  "storage_deleted_count": ...
}
```

---

## 7. Error Handling

- `ValueError` → 400 (limit exceeded)
- General `Exception` → 500 Internal Server Error
- Vector DB failure → 409 Conflict

---

## 8. Final API Response (Success)

```json
{
  "success": true,
  "deleted_count": X,
  "matched_count": Y
}
```
