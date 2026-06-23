<details>
<summary><strong>API: POST /{student_id}/transfer</strong></summary>

# API: POST /{student_id}/transfer

## Operation Type

```text
CRUD Operation: UPDATE

HTTP Method: POST

Purpose:
Transfers an existing student from one
class/section to another.

Optionally accepts a new face image.
If no image is uploaded, the current
enrollment photo is reused.
```

### Authentication

```python
_user = RequireOperator
```

Only Operator users can access this API.

---

### Request Parameters

| Parameter            | Type | Required | Description                              |
| -------------------- | ---- | -------- | ---------------------------------------- |
| student_id           | Path | Yes      | Student identifier                       |
| image                | File | No       | New face image                           |
| to_class_section     | Form | Yes      | Target class-section (e.g. IV-F)         |
| purpose              | Form | No       | Transfer reason                          |
| crop_enrollment_face | Form | No       | Whether uploaded image should be cropped |

---

### Request Example

```text
POST /students/STU001/transfer
```

Form Data:

```text
to_class_section = IV-F
purpose = Promotion
image = student.jpg
crop_enrollment_face = true
```

---

### Step 1: Find Student

```python
student = (
    db.query(Student)
    .filter(Student.student_id == student_id)
    .first()
)
```

Purpose:

```text
Load the student record.
```

Student Found?

#### NO

Return:

```json
{
  "detail": "Student not found"
}
```

HTTP Status:

```text
404 Not Found
```

#### YES

Continue.

---

<details>
<summary><strong>Internal Function: parse_class_section()</strong></summary>

### Step 2: Parse Target Class Section

```python
to_class, to_section =
parse_class_section(to_class_section)
```

Input:

```text
IV-F
```

Output:

```python
("IV", "F")
```

Example:

```text
IV-F
  ↓
Class = IV
Section = F
```

### Validation

```python
if not to_class:
```

Return:

```json
{
  "detail": "to_class_section must contain at least class (e.g. IV-F or IV)"
}
```

HTTP Status:

```text
400 Bad Request
```

</details>

---

### Step 3: Generate Combined Class Section

```python
to_class_section_combined =
f"{to_class}-{to_section}"
```

Example:

```text
IV-F
```

---

### Step 4: Normalize Purpose

```python
purpose = (
    purpose or ""
).strip() or "Transfer"
```

Examples:

```text
""          → Transfer
Promotion   → Promotion
Internal Transfer → Internal Transfer
```

---

### Step 5: Check For Same Class

```python
if (
    student.student_class == to_class
    and
    (student.section or "")
    ==
    (to_section or "")
)
```

Purpose:

```text
Prevent transferring a student
to the same class-section.
```

Example:

```text
Current:
III-F

Target:
III-F
```

Return:

```json
{
  "detail": "Student is already in III-F. Choose a different class/section."
}
```

HTTP Status:

```text
400 Bad Request
```

---

### Step 6: Load Services

```python
face_svc = get_face_service()

storage_svc = get_storage_service()

vector_svc = get_vector_db_service()
```

Purpose:

```text
Face Processing Service
Object Storage Service
Vector Database Service
```

---

### Step 7: Process Image

#### New Image Uploaded

```python
image_bytes = image.file.read()
```

Decode image:

```python
img = face_svc.decode_image(
    image_bytes
)
```

Read crop option:

```python
crop = _parse_crop_face_flag(
    crop_enrollment_face
)
```

Finalize enrollment image:

```python
image_bytes, _ =
face_svc.finalize_enrollment_image(
    img,
    crop,
    image_bytes
)
```

---

#### No Image Uploaded

Use current enrollment photo:

```python
image_bytes =
storage_svc.download_image(
    student.minio_object_key
)
```

Decode image:

```python
img =
face_svc.decode_image(image_bytes)
```

---

<details>
<summary><strong>Internal Function: _load_assignments()</strong></summary>

### Step 8: Load Existing Assignments

```python
existing_assignments =
_load_assignments(
    db,
    student_id
)
```

Purpose:

```text
Retrieve all class assignments
associated with the student.
```

</details>

---

<details>
<summary><strong>Internal Function: _assignment_tags()</strong></summary>

### Step 9: Build Assignment Tags

```python
assignment_tags =
_assignment_tags(
    existing_assignments
)
```

Example:

```python
[
    "class_section:III-F",
    "subject:Math"
]
```

Create target tag:

```python
target_tag =
f"class_section:{to_class_section_combined}"
```

Example:

```text
class_section:IV-F
```

If missing:

```python
assignment_tags.append(target_tag)
```

</details>

---

### Step 10: Store New Face Embedding

```python
vector_svc.insert_face_images(
    to_class_section_combined,
    student_id,
    [(0, image_bytes)],
    tags=assignment_tags
)
```

Purpose:

```text
Store student face embedding
inside target class collection.
```

Collection Example:

```text
IV-F
```

---

### Step 11: Remove Old Embedding

```python
vector_svc.delete_embedding(
    from_class_section,
    student_id
)
```

Purpose:

```text
Remove student's old vector
embedding from previous class.
```

Example:

```text
III-F
  ↓
Deleted
```

Failure:

```text
Logged only.
Transfer continues.
```

---

### Step 12: Upload New Photo

Generate storage path:

```python
new_object_key =
f"{to_class_section_combined}/{student_id}.jpg"
```

Example:

```text
IV-F/STU001.jpg
```

Upload:

```python
storage_svc.upload_image(
    new_object_key,
    image_bytes,
    content_type="image/jpeg"
)
```

---

### Step 13: Delete Old Photo

```python
storage_svc.delete_image(
    student.minio_object_key
)
```

Purpose:

```text
Remove old image from storage.
```

Failure:

```text
Logged only.
Transfer continues.
```

---

### Step 14: Create Transfer Record

```python
transfer = StudentTransfer(
    ...
)
```

Purpose:

```text
Maintain transfer history.
```

Stored Data:

```text
Student ID
Student Name
From Class
From Section
To Class
To Section
Purpose
```

Save:

```python
db.add(transfer)
```

---

### Step 15: Update Student Assignments

Disable existing primary assignment:

```python
StudentAssignment.is_primary = False
```

Find target assignment.

---

#### Assignment Exists

```python
target_assignment.is_primary = True
```

---

#### Assignment Missing

Create new assignment:

```python
StudentAssignment(
    student_id=student_id,
    student_class=to_class,
    section=to_section,
    is_primary=True
)
```

---

### Step 16: Update Student Record

```python
student.student_class =
to_class

student.section =
to_section

student.minio_object_key =
new_object_key
```

Example:

```text
III-F
  ↓
IV-F
```

---

### Step 17: Commit Changes

```python
db.commit()
```

Persist:

```text
Transfer History
Assignments
Student Record
```

Refresh:

```python
db.refresh(transfer)

db.refresh(student)
```

---

### Step 18: Write Audit Log

```python
logger.info(...)
```

Example:

```text
Transferred STU001
III-F → IV-F
(Promotion)
```

---

### Step 19: Return Response

```python
return TransferResponse(...)
```

Example Response:

```json
{
  "student_id": "STU001",
  "name": "John Doe",
  "from_class_section": "III-F",
  "to_class_section": "IV-F",
  "purpose": "Promotion",
  "transferred_at": "2026-06-21T10:00:00Z"
}
```

---

### Flow

```text
POST /{student_id}/transfer
            │
            ▼
Find Student
            │
            ├── Not Found → 404
            │
            ▼
parse_class_section()
            │
            ▼
Validate Target Class
            │
            ▼
Check Same Class
            │
            ├── Same Class → 400
            │
            ▼
Load Services
            │
            ▼
Process Image
(New or Existing)
            │
            ▼
Load Assignments
            │
            ▼
Generate Tags
            │
            ▼
Insert Face Embedding
            │
            ▼
Delete Old Embedding
            │
            ▼
Upload New Image
            │
            ▼
Delete Old Image
            │
            ▼
Create Transfer Record
            │
            ▼
Update Assignments
            │
            ▼
Update Student
            │
            ▼
db.commit()
            │
            ▼
Return TransferResponse
```

</details>
</details>
<details>
<summary><strong>API: GET /{student_id}/transfers</strong></summary>

# API: GET /{student_id}/transfers

## Operation Type

```text
CRUD Operation: READ

HTTP Method: GET

Purpose:
Returns complete transfer history
for a student.

Used to track promotions,
section changes, and internal
transfers over time.
```

### Authentication

```python
_user = RequireViewer
```

Viewer, Operator, and Admin users can access this API.

---

### Request Parameters

| Parameter  | Type | Required | Description        |
| ---------- | ---- | -------- | ------------------ |
| student_id | Path | Yes      | Student identifier |

---

### Request Example

```text
GET /students/STU001/transfers
```

---

### Step 1: Query Transfer Records

```python
transfers = (
    db.query(StudentTransfer)
    .filter(
        StudentTransfer.student_id
        == student_id
    )
    .order_by(
        StudentTransfer.transferred_at.desc()
    )
    .all()
)
```

Purpose:

```text
Retrieve all transfer history
records for the student.
```

Equivalent SQL:

```sql
SELECT *
FROM student_transfer
WHERE student_id='STU001'
ORDER BY transferred_at DESC;
```

---

### Step 2: Sort Records

```python
.order_by(
    StudentTransfer.transferred_at.desc()
)
```

Purpose:

```text
Show newest transfer first.
```

Example:

```text
2026-06-21
2026-05-01
2025-12-15
```

---

### Step 3: Convert Records To Response

```python
StudentTransferResponse(
    id=t.id,
    student_id=t.student_id,
    student_name=t.student_name,
    from_student_class=t.from_student_class,
    from_section=t.from_section,
    to_student_class=t.to_student_class,
    to_section=t.to_section,
    purpose=t.purpose,
    transferred_at=t.transferred_at,
)
```

Purpose:

```text
Convert database objects into
API response format.
```

Example:

```json
{
  "student_id": "STU001",
  "student_name": "John Doe",
  "from_student_class": "III",
  "from_section": "F",
  "to_student_class": "IV",
  "to_section": "A",
  "purpose": "Promotion"
}
```

---

### Step 4: Calculate Total Transfers

```python
total = len(transfers)
```

Purpose:

```text
Return total number of
transfer records.
```

Example:

```text
3 Transfers
```

---

### Step 5: Return Response

```python
return TransferListResponse(...)
```

Example Response:

```json
{
  "transfers": [
    {
      "student_id": "STU001",
      "student_name": "John Doe",
      "from_student_class": "III",
      "to_student_class": "IV",
      "purpose": "Promotion"
    }
  ],
  "total": 1
}
```

---

### Flow

```text
GET /{student_id}/transfers
            │
            ▼
Query StudentTransfer
            │
            ▼
Filter By Student ID
            │
            ▼
Sort By Transfer Date
            │
            ▼
Build Response Objects
            │
            ▼
Calculate Total
            │
            ▼
Return TransferListResponse
```

</details>
</details>
<details>
<summary><strong>API: GET /{student_id}/photo</strong></summary>

# API: GET /{student_id}/photo

## Operation Type

```text
CRUD Operation: READ

HTTP Method: GET

Purpose:
Returns the student's enrolled
face image from object storage.

Used for UI thumbnails,
student profile pictures,
and attendance dashboards.
```

### Authentication

```python
_user = RequireViewer
```

Viewer, Operator, and Admin users can access this API.

---

### Request Parameters

| Parameter  | Type | Required | Description        |
| ---------- | ---- | -------- | ------------------ |
| student_id | Path | Yes      | Student identifier |

---

### Request Example

```text
GET /students/STU001/photo
```

---

### Step 1: Find Student

```python
student = (
    db.query(Student)
    .filter(
        Student.student_id == student_id
    )
    .first()
)
```

Purpose:

```text
Verify student exists.
```

Student Found?

#### NO

Return:

```json
{
  "detail": "Student not found"
}
```

HTTP Status:

```text
404 Not Found
```

#### YES

Continue.

---

### Step 2: Load Storage Service

```python
storage_svc =
get_storage_service()
```

Purpose:

```text
Access object storage
(MinIO/S3).
```

---

### Step 3: Find Primary Face Image

```python
primary_row = (
    db.query(StudentFaceImage)
    .filter(
        StudentFaceImage.student_id
        == student_id,

        StudentFaceImage.is_primary
        .is_(True)
    )
    .order_by(
        StudentFaceImage.angle_index.asc()
    )
    .first()
)
```

Purpose:

```text
Find the student's
primary enrollment photo.
```

Example:

```text
Front Face
Angle 0
Primary = True
```

---

### Step 4: Determine Object Key

```python
object_key =
(
    primary_row.minio_object_key
    if primary_row
    else student.minio_object_key
)
```

Purpose:

```text
Use modern multi-photo
storage first.

Fallback to legacy
single-photo storage.
```

Priority:

```text
StudentFaceImage
        ↓
students.minio_object_key
```

---

### Step 5: Verify Photo Exists

```python
if not object_key:
```

Return:

```json
{
  "detail": "No photo"
}
```

HTTP Status:

```text
404 Not Found
```

---

### Step 6: Download Image

```python
data =
storage_svc.download_image(
    object_key
)
```

Purpose:

```text
Retrieve image bytes
from object storage.
```

Example:

```text
IV-F/STU001.jpg
```

---

### Step 7: Handle Storage Errors

```python
except Exception as e:
```

Log Error:

```python
logger.warning(...)
```

Return:

```json
{
  "detail": "Photo not available"
}
```

HTTP Status:

```text
404 Not Found
```

Example Causes:

```text
Image deleted
Storage unavailable
Corrupted object key
Missing file
```

---

### Step 8: Return Image

```python
return Response(
    content=data,
    media_type="image/jpeg"
)
```

Purpose:

```text
Return raw image bytes
to the browser/UI.
```

Response Type:

```text
image/jpeg
```

---

### Flow

```text
GET /{student_id}/photo
            │
            ▼
Find Student
            │
            ├── Not Found → 404
            │
            ▼
Load Storage Service
            │
            ▼
Find Primary Photo
            │
            ▼
Determine Object Key
            │
            ├── No Key → 404
            │
            ▼
Download Image
            │
            ├── Storage Error → 404
            │
            ▼
Return JPEG Image
```

</details>
</details>

<details>
<summary><strong>API: GET /{student_id}/photos</strong></summary>

# API: GET /{student_id}/photos

## Operation Type

```text
CRUD Operation: READ

HTTP Method: GET

Purpose:
Returns all enrolled photos for a student.

Supports both:

• Multi-photo enrollment
• Legacy single-photo enrollment

Used by student profile screens
and enrollment management pages.
```

### Authentication

```python
_user = RequireViewer
```

Viewer, Operator, and Admin users can access this API.

---

### Request Parameters

| Parameter  | Type | Required | Description        |
| ---------- | ---- | -------- | ------------------ |
| student_id | Path | Yes      | Student identifier |

---

### Request Example

```text
GET /students/STU001/photos
```

---

### Step 1: Find Student

```python
student = (
    db.query(Student)
    .filter(
        Student.student_id == student_id
    )
    .first()
)
```

Purpose:

```text
Verify student exists.
```

Student Found?

#### NO

Return:

```json
{
  "detail": "Student not found"
}
```

HTTP Status:

```text
404 Not Found
```

#### YES

Continue.

---

### Step 2: Query Student Photos

```python
rows = (
    db.query(StudentFaceImage)
    .filter(
        StudentFaceImage.student_id
        == student_id
    )
    .order_by(
        StudentFaceImage.angle_index.asc()
    )
    .all()
)
```

Purpose:

```text
Load all enrollment photos
associated with the student.
```

Equivalent SQL:

```sql
SELECT *
FROM student_face_images
WHERE student_id='STU001'
ORDER BY angle_index ASC;
```

---

### Step 3: Check Multi-Photo Enrollment

```python
if rows:
```

Purpose:

```text
Determine whether student
has photos stored in the
student_face_images table.
```

Example:

```text
Angle 0
Angle 1
Angle 2
```

---

### Step 4: Build Response Objects

```python
StudentPhotoItem(
    angle_index=r.angle_index,
    is_primary=bool(r.is_primary),
    photo_url=f"/api/students/{student_id}/photos/{r.angle_index}"
)
```

Purpose:

```text
Convert database records
into API response objects.
```

Example Response Item:

```json
{
  "angle_index": 0,
  "is_primary": true,
  "photo_url": "/api/students/STU001/photos/0"
}
```

---

### Step 5: Return Multi-Photo List

Example Response:

```json
[
  {
    "angle_index": 0,
    "is_primary": true,
    "photo_url": "/api/students/STU001/photos/0"
  },
  {
    "angle_index": 1,
    "is_primary": false,
    "photo_url": "/api/students/STU001/photos/1"
  }
]
```

---

### Step 6: Legacy Fallback

```python
if student.minio_object_key:
```

Purpose:

```text
Support older enrollments
that stored only a single image.
```

Example:

```text
students.minio_object_key
```

Build Response:

```python
StudentPhotoItem(
    angle_index=0,
    is_primary=True,
    photo_url=f"/api/students/{student_id}/photo"
)
```

Example Response:

```json
[
  {
    "angle_index": 0,
    "is_primary": true,
    "photo_url": "/api/students/STU001/photo"
  }
]
```

---

### Step 7: No Photos Available

```python
return []
```

Purpose:

```text
Return empty list when
student has no stored photos.
```

Example Response:

```json
[]
```

---

### Flow

```text
GET /{student_id}/photos
            │
            ▼
Find Student
            │
            ├── Not Found → 404
            │
            ▼
Query StudentFaceImage
            │
            ▼
Photos Found?
            │
     ┌──────┴──────┐
     │             │
    YES            NO
     │             │
     ▼             ▼
Build        Legacy Photo?
Photo List         │
     │        ┌────┴────┐
     │        │         │
     │       YES        NO
     │        │         │
     ▼        ▼         ▼
Return    Return     Return
Photos    Legacy       []
           Photo
```

</details>
</details>

<details>
<summary><strong>API: GET /{student_id}/photos/{angle_index}</strong></summary>

# API: GET /{student_id}/photos/{angle_index}

## Operation Type

```text
CRUD Operation: READ

HTTP Method: GET

Purpose:
Returns a specific enrolled
student photo based on angle.

Used for viewing enrollment
images captured from different
camera positions.
```

### Authentication

```python
_user = RequireViewer
```

Viewer, Operator, and Admin users can access this API.

---

### Request Parameters

| Parameter   | Type | Required | Description        |
| ----------- | ---- | -------- | ------------------ |
| student_id  | Path | Yes      | Student identifier |
| angle_index | Path | Yes      | Photo angle index  |

---

### Request Example

```text
GET /students/STU001/photos/1
```

---

### Step 1: Find Student

```python
student = (
    db.query(Student)
    .filter(
        Student.student_id == student_id
    )
    .first()
)
```

Purpose:

```text
Verify student exists.
```

Student Found?

#### NO

Return:

```json
{
  "detail": "Student not found"
}
```

HTTP Status:

```text
404 Not Found
```

#### YES

Continue.

---

### Step 2: Find Requested Photo

```python
row = (
    db.query(StudentFaceImage)
    .filter(
        StudentFaceImage.student_id
        == student_id,

        StudentFaceImage.angle_index
        == angle_index
    )
    .first()
)
```

Purpose:

```text
Locate the requested
photo angle.
```

Example:

```text
Angle 0 → Front
Angle 1 → Left
Angle 2 → Right
```

---

### Step 3: Verify Photo Exists

```python
if not row:
```

Return:

```json
{
  "detail": "Photo not found"
}
```

HTTP Status:

```text
404 Not Found
```

---

### Step 4: Load Storage Service

```python
storage_svc =
get_storage_service()
```

Purpose:

```text
Access object storage.
```

---

### Step 5: Download Image

```python
data =
storage_svc.download_image(
    row.minio_object_key
)
```

Purpose:

```text
Retrieve image bytes
from object storage.
```

Example:

```text
III-F/STU001_angle1.jpg
```

---

### Step 6: Handle Storage Errors

```python
except Exception as e:
```

Log Error:

```python
logger.warning(...)
```

Example Log:

```text
Failed to load photo angle 1
for STU001
```

Return:

```json
{
  "detail": "Photo not available"
}
```

HTTP Status:

```text
404 Not Found
```

Possible Causes:

```text
Image deleted
Invalid object key
Storage unavailable
Corrupted file
```

---

### Step 7: Return Image

```python
return Response(
    content=data,
    media_type="image/jpeg"
)
```

Purpose:

```text
Return image bytes
to the browser/UI.
```

Response Type:

```text
image/jpeg
```

---

### Flow

```text
GET /{student_id}/photos/{angle_index}
                 │
                 ▼
Find Student
                 │
                 ├── Not Found → 404
                 │
                 ▼
Find Photo Angle
                 │
                 ├── Not Found → 404
                 │
                 ▼
Load Storage Service
                 │
                 ▼
Download Image
                 │
                 ├── Error → 404
                 │
                 ▼
Return JPEG Image
```

</details>
</details>
