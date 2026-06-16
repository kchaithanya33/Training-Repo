# DELETE /metadata/delete/ - Delete Biometric Enrollment

## 1. Client Request

```http
DELETE /metadata/delete/

{
  "galleryId": "12345"
}
```

## 2. API Entry Point

```python
def delete(self, request):
```

### 2.1 Log Request
```python
logger.info("Delete request received - gallery_id: %s", request.data.get("galleryId"))
```

### 2.2 Audit Log (Before Deletion)
```python
log_audit_event(
    event_type=BIOMETRIC_DELETE,
    action="delete_biometric",
    resource_id=galleryId,
    request=request
)
```
**Purpose**: Records that a delete request was initiated.

### 2.3 Input Validation
```python
serializer = MetadataDeleteReqSerializer(data=request.data)
```
- **Invalid input** → Return `400 BAD REQUEST`

---

## 3. Core Deletion Logic

```python
deletion_result = delete_enrollment_by_gallery_id(gallery_id)
```

### Inside `delete_enrollment_by_gallery_id(gallery_id)`

#### 3.1 Check Record Exists
```python
metadata = Metadata.objects.filter(gallery_id=gallery_id).first()
```
- **Not found** → Return `{"found": False}`

#### 3.2 Vector DB Deletion (First)
```python
vector_success = vector_db.delete_biometric(gallery_id, bio_type)
```
**Purpose**: Deletes embedding from the vector database (search system).

- **Failure** → Return `{"error": "Vector deletion failed; metadata retained"}` (stops here)

#### 3.3 Storage Deletion
```python
storage_deleted = storage.delete_file(gallery_id)
```
**Purpose**: Deletes stored biometric files/images.

#### 3.4 Database Deletion
```python
deleted, _ = Metadata.objects.filter(gallery_id=gallery_id).delete()
```
**Purpose**: Deletes record from PostgreSQL.

#### 3.5 Return Result
```python
return {
    "storage_deleted": storage_deleted,
    "db_deleted": deleted > 0,
    "vector_db_deleted": vector_success
}
```

---

## 4. API Layer - Post Deletion

### 4.1 Record Not Found
→ Return `404 NOT FOUND`

### 4.2 Audit Log (Success)
```python
log_audit_event(
    action="delete_completed",
    details=deletion_result
)
```

### 4.3 Success Response (200 OK)

```json
{
  "galleryId": "12345",
  "status": "Deleted",
  "storage_deleted": true,
  "db_deleted": true,
  "vector_db_deleted": true
}
```

### 4.4 Consistency Check
- If DB deletion failed → Return `409 CONFLICT`

---

##Summary

```mermaid
flowchart TD
    A[Client Request] --> B[Validation + Audit Log]
    B --> C[delete_enrollment_by_gallery_id]
    C --> D[Vector DB Delete]
    D --> E[Storage Delete]
    E --> F[Database Delete]
    F --> G[Return Result]
    G --> H[Final Audit Log]
    H --> I[Response 200/404/409]
```
