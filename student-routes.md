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

<details>
<summary><strong>API: GET /{student_id}</strong></summary>

# API: GET /{student_id}

## Operation Type

```text
CRUD Operation: READ

HTTP Method: GET

Purpose:
Returns basic student information
including enrollment details,
assignments, and currently active
face recognition algorithms.
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
GET /students/STU001
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
Verify student exists and
retrieve student information.
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

### Step 2: Load Face Service

```python
face_svc = get_face_service()
```

Purpose:

```text
Access face recognition
configuration and runtime settings.
```

---

<details>
<summary><strong>Internal Function: get_runtime_algorithms()</strong></summary>

### Step 3: Get Active Runtime Algorithms

```python
runtime_detector_backend,
runtime_recognition_model = (
    face_svc.get_runtime_algorithms()
)
```

Purpose:

```text
Retrieve currently active
face detection and face
recognition models.
```

Example:

```python
runtime_detector_backend =
"retinaface"

runtime_recognition_model =
"ArcFace"
```

Possible Values:

```text
Detection:
RetinaFace
OpenCV
YuNet

Recognition:
ArcFace
Facenet
Buffalo_L
```

</details>

---

<details>
<summary><strong>Internal Function: _load_assignments()</strong></summary>

### Step 4: Load Student Assignments

```python
_load_assignments(
    db,
    student.student_id
)
```

Purpose:

```text
Retrieve all active class,
section, and subject assignments
for the student.
```

Example:

```python
[
    {
        "student_class": "III",
        "section": "F"
    }
]
```

</details>

---

<details>
<summary><strong>Internal Function: _student_response()</strong></summary>

### Step 5: Build Response Object

```python
return _student_response(
    student,
    _load_assignments(
        db,
        student.student_id
    ),
    runtime_detector_backend,
    runtime_recognition_model
)
```

Purpose:

```text
Convert database entities into
StudentResponse format.
```

Included Information:

```text
Student ID
Student Name
Class Section
Assignments
Enrollment Status
Runtime Detector
Runtime Recognition Model
```

</details>

---

### Step 6: Return Response

Example Response:

```json
{
  "student_id": "STU001",
  "name": "John Doe",
  "class_section": "III-F",
  "runtime_detector_backend": "retinaface",
  "runtime_recognition_model": "ArcFace"
}
```

---

### Flow

```text
GET /{student_id}
        │
        ▼
Find Student
        │
        ├── Not Found → 404
        │
        ▼
Load Face Service
        │
        ▼
Get Runtime Algorithms
        │
        ▼
Load Assignments
        │
        ▼
Build StudentResponse
        │
        ▼
Return Response
```

</details>
</details>
<details>
<summary><strong>API: GET /{student_id}/detail</strong></summary>

# API: GET /{student_id}/detail

## Operation Type

```text
CRUD Operation: READ

HTTP Method: GET

Purpose:
Returns complete student information
including enrollment status,
assignments, photos, runtime models,
timestamps, and enrollment metadata.
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
GET /students/STU001/detail
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

### Step 2: Load Face Service

```python
face_svc = get_face_service()
```

Purpose:

```text
Access runtime face recognition
configuration.
```

---

<details>
<summary><strong>Internal Function: get_runtime_algorithms()</strong></summary>

### Step 3: Get Runtime Algorithms

```python
runtime_detector_backend,
runtime_recognition_model = (
    face_svc.get_runtime_algorithms()
)
```

Purpose:

```text
Determine which face detection
and recognition models are
currently active.
```

Example:

```text
Detector:
RetinaFace

Recognition:
ArcFace
```

</details>

---

### Step 4: Load Student Photos

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
Retrieve all enrolled
student photos.
```

Example:

```text
Angle 0
Angle 1
Angle 2
```

---

### Step 5: Build Photo Response

#### Multi-Photo Enrollment

```python
if rows:
```

Convert rows:

```python
StudentPhotoItem(
    angle_index=r.angle_index,
    is_primary=bool(r.is_primary),
    photo_url=f"/api/students/{student_id}/photos/{r.angle_index}"
)
```

Example:

```json
[
  {
    "angle_index": 0,
    "is_primary": true
  },
  {
    "angle_index": 1,
    "is_primary": false
  }
]
```

---

#### Legacy Single Photo

```python
elif student.minio_object_key:
```

Build fallback photo:

```python
StudentPhotoItem(
    angle_index=0,
    is_primary=True,
    photo_url=f"/api/students/{student_id}/photo"
)
```

Purpose:

```text
Support older enrollment records.
```

---

#### No Photos

```python
else:
    photos = []
```

Example:

```json
[]
```

---

<details>
<summary><strong>Internal Function: _load_assignments()</strong></summary>

### Step 6: Load Assignments

```python
_load_assignments(
    db,
    student.student_id
)
```

Purpose:

```text
Retrieve all active student
assignments.
```

Example:

```text
Class Assignment
Subject Assignment
Section Assignment
```

</details>

---

<details>
<summary><strong>Internal Function: _assignment_row_to_schema()</strong></summary>

### Step 7: Convert Assignments

```python
[
    _assignment_row_to_schema(a)
    .dict()
    for a in _load_assignments(...)
]
```

Purpose:

```text
Convert database assignment
objects into API schema format.
```

Example:

```json
{
  "student_class": "III",
  "section": "F",
  "is_primary": true
}
```

</details>

---

### Step 8: Build Detail Response

```python
StudentDetailResponse(
    ...
)
```

Included Fields:

```text
Student ID
Name
Class Section
Student Class
Section
Enrollment Status
Enrollment Started Time
Enrollment Stored Time
Enrollment Errors
Runtime Detector
Runtime Recognition Model
Created Time
Updated Time
Assignments
Photos
```

---

### Step 9: Return Response

Example Response:

```json
{
  "student_id": "STU001",
  "name": "John Doe",
  "class_section": "III-F",
  "enrollment_status": "COMPLETED",
  "runtime_detector_backend": "retinaface",
  "runtime_recognition_model": "ArcFace",
  "photos": [
    {
      "angle_index": 0,
      "is_primary": true
    }
  ]
}
```

---

### Flow

```text
GET /{student_id}/detail
            │
            ▼
Find Student
            │
            ├── Not Found → 404
            │
            ▼
Load Face Service
            │
            ▼
Get Runtime Algorithms
            │
            ▼
Load Student Photos
            │
            ▼
Build Photo List
            │
            ▼
Load Assignments
            │
            ▼
Convert Assignments
            │
            ▼
Build StudentDetailResponse
            │
            ▼
Return Response
```

</details>
</details>

<details>
<summary><strong>API: DELETE /{student_id}/photos/{angle_index}</strong></summary>

# API: DELETE /{student_id}/photos/{angle_index}

## Operation Type

```text
CRUD Operation: DELETE

HTTP Method: DELETE

Purpose:
Removes one enrolled face photo
from a student.

At least one face photo must
always remain for the student.

After deletion, all face
embeddings are rebuilt using
the remaining photos.
```

### Authentication

```python
_user = RequireOperator
```

Only Operator users can access this API.

---

### Request Parameters

| Parameter   | Type | Required | Description                |
| ----------- | ---- | -------- | -------------------------- |
| student_id  | Path | Yes      | Student identifier         |
| angle_index | Path | Yes      | Face photo angle to remove |

---

### Request Example

```text
DELETE /students/STU001/photos/2
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
Verify the student exists.
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

### Step 2: Load Student Photos

```python
rows = (
    db.query(StudentFaceImage)
    .filter(StudentFaceImage.student_id == student_id)
    .order_by(StudentFaceImage.angle_index.asc())
    .all()
)
```

Purpose:

```text
Retrieve all enrolled face photos.
```

Example:

```text
Angle 0
Angle 1
Angle 2
```

---

### Step 3: Verify Photo Deletion Is Allowed

#### No Multi-Photo Records Found

```python
if not rows:
```

Check legacy enrollment:

```python
if student.minio_object_key:
```

Return:

```json
{
  "detail": "Cannot delete the only stored photo. Replace it or remove the student."
}
```

HTTP Status:

```text
400 Bad Request
```

---

#### No Photos Exist

```python
raise HTTPException(
    status_code=404,
    detail="Photo not found"
)
```

Return:

```json
{
  "detail": "Photo not found"
}
```

---

#### Only One Photo Exists

```python
if len(rows) <= 1:
```

Purpose:

```text
Prevent deletion of the
last remaining enrollment photo.
```

Return:

```json
{
  "detail": "Cannot delete the only stored photo. Replace it or remove the student."
}
```

HTTP Status:

```text
400 Bad Request
```

---

### Step 4: Find Requested Photo

```python
target = next(
    (
        r for r in rows
        if int(r.angle_index)
        == int(angle_index)
    ),
    None
)
```

Purpose:

```text
Locate the photo that
must be deleted.
```

Photo Found?

#### NO

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

#### YES

Continue.

---

### Step 5: Load Services

```python
storage_svc = get_storage_service()

vector_svc = get_vector_db_service()
```

Purpose:

```text
Access storage and
vector database services.
```

---

### Step 6: Check Primary Status

```python
was_primary =
bool(target.is_primary)
```

Purpose:

```text
Determine whether the
deleted image is currently
the primary display photo.
```

Example:

```text
True
```

---

### Step 7: Delete Image From Storage

```python
storage_svc.delete_image(
    target.minio_object_key
)
```

Purpose:

```text
Remove image file from
MinIO/Object Storage.
```

Storage Failure?

#### YES

```python
logger.warning(...)
```

Purpose:

```text
Log warning and continue.

Database cleanup should still occur.
```

---

### Step 8: Delete Database Record

```python
db.delete(target)

db.flush()
```

Purpose:

```text
Remove photo metadata from
student_face_images table.
```

Equivalent SQL:

```sql
DELETE
FROM student_face_images
WHERE student_id='STU001'
AND angle_index=2;
```

---

### Step 9: Reassign Primary Photo

Condition:

```python
if was_primary:
```

Purpose:

```text
If the deleted image was
the primary image,
assign a new primary image.
```

Load Remaining Photos:

```python
remaining = (
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

Reset Primary Flags:

```python
for row in remaining:
    row.is_primary = False
```

Assign New Primary:

```python
remaining[0].is_primary = True
```

Example:

```text
Before:

Angle 0 → False
Angle 1 → True
Angle 2 → False

Delete Angle 1

After:

Angle 0 → True
Angle 2 → False
```

---

### Step 10: Mark Student As Processing

```python
student.enrollment_status =
ENROLLMENT_STATUS_PROCESSING
```

Set Processing Time:

```python
student.enrollment_started_at =
datetime.now(timezone.utc)
```

Clear Previous Error:

```python
student.enrollment_error = None
```

Purpose:

```text
Re-indexing is about to begin.
```

---

### Step 11: Commit Changes

```python
db.commit()
```

Purpose:

```text
Persist photo deletion
before rebuilding embeddings.
```

---

<details>
<summary><strong>Internal Function: _reindex_student_face_embeddings()</strong></summary>

### Step 12: Rebuild Face Embeddings

```python
_reindex_student_face_embeddings(
    db,
    student,
    storage_svc,
    vector_svc
)
```

Purpose:

```text
Delete old embeddings and
generate new embeddings using
remaining face photos.
```

Why?

```text
The removed photo may have
contributed to recognition accuracy.

Embeddings must remain consistent.
```

</details>

---

### Step 13: Mark Enrollment As Stored

```python
student.enrollment_status =
ENROLLMENT_STATUS_STORED
```

Store Completion Time:

```python
student.enrollment_stored_at =
datetime.now(timezone.utc)
```

Clear Errors:

```python
student.enrollment_error = None
```

Save:

```python
db.commit()
```

Purpose:

```text
Indicate successful reindexing.
```

---

### Step 14: Handle Reindex Failures

```python
except Exception as e:
```

Rollback Current Transaction:

```python
db.rollback()
```

Reload Student:

```python
failed = (
    db.query(Student)
    .filter(
        Student.student_id == student_id
    )
    .first()
)
```

Mark Error State:

```python
failed.enrollment_status =
ENROLLMENT_STATUS_ERROR

failed.enrollment_error =
str(e)
```

Save:

```python
db.commit()
```

Return:

```json
{
  "detail": "Face photo delete reindex failed: ..."
}
```

HTTP Status:

```text
500 Internal Server Error
```

---

### Step 15: Count Remaining Photos

```python
remaining_count = (
    db.query(StudentFaceImage)
    .filter(
        StudentFaceImage.student_id
        == student_id
    )
    .count()
)
```

Purpose:

```text
Determine how many photos
remain after deletion.
```

Example:

```text
2
```

---

### Step 16: Log Operation

```python
logger.info(
    "Deleted face sample angle %s for %s (%s)",
    angle_index,
    student_id,
    student.name
)
```

Example Log:

```text
Deleted face sample angle 2
for STU001 (John Doe)
```

---

### Step 17: Return Response

```python
return {
    "detail": "Photo removed",
    "remaining_photos": remaining_count
}
```

Example Response:

```json
{
  "detail": "Photo removed",
  "remaining_photos": 2
}
```

---

### Flow

```text
DELETE /{student_id}/photos/{angle_index}
                    │
                    ▼
Find Student
                    │
                    ├── Not Found → 404
                    │
                    ▼
Load Student Photos
                    │
                    ├── No Photos → 404
                    │
                    ├── Only One Photo → 400
                    │
                    ▼
Find Target Photo
                    │
                    ├── Not Found → 404
                    │
                    ▼
Delete Storage Object
                    │
                    ▼
Delete Database Row
                    │
                    ▼
Was Primary?
                    │
              ┌─────┴─────┐
              │           │
             YES          NO
              │
              ▼
Assign New Primary
              │
              ▼
Mark Processing
              │
              ▼
Commit Changes
              │
              ▼
Rebuild Embeddings
              │
        ┌─────┴─────┐
        │           │
     Success      Failure
        │           │
        ▼           ▼
 Mark Stored    Mark Error
        │           │
        ▼           ▼
     Return      HTTP 500
```

</details>
</details>
<details>
<summary><strong>API: DELETE /{student_id}/photos/{angle_index}</strong></summary>

# API: DELETE /{student_id}/photos/{angle_index}

## Operation Type

```text
CRUD Operation: DELETE

HTTP Method: DELETE

Purpose:
Removes one enrolled face photo
from a student.

At least one face photo must
always remain for the student.

After deletion, all face
embeddings are rebuilt using
the remaining photos.
```

### Authentication

```python
_user = RequireOperator
```

Only Operator users can access this API.

---

### Request Parameters

| Parameter   | Type | Required | Description                |
| ----------- | ---- | -------- | -------------------------- |
| student_id  | Path | Yes      | Student identifier         |
| angle_index | Path | Yes      | Face photo angle to remove |

---

### Request Example

```text
DELETE /students/STU001/photos/2
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
Verify the student exists.
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

### Step 2: Load Student Photos

```python
rows = (
    db.query(StudentFaceImage)
    .filter(StudentFaceImage.student_id == student_id)
    .order_by(StudentFaceImage.angle_index.asc())
    .all()
)
```

Purpose:

```text
Retrieve all enrolled face photos.
```

Example:

```text
Angle 0
Angle 1
Angle 2
```

---

### Step 3: Verify Photo Deletion Is Allowed

#### No Multi-Photo Records Found

```python
if not rows:
```

Check legacy enrollment:

```python
if student.minio_object_key:
```

Return:

```json
{
  "detail": "Cannot delete the only stored photo. Replace it or remove the student."
}
```

HTTP Status:

```text
400 Bad Request
```

---

#### No Photos Exist

```python
raise HTTPException(
    status_code=404,
    detail="Photo not found"
)
```

Return:

```json
{
  "detail": "Photo not found"
}
```

---

#### Only One Photo Exists

```python
if len(rows) <= 1:
```

Purpose:

```text
Prevent deletion of the
last remaining enrollment photo.
```

Return:

```json
{
  "detail": "Cannot delete the only stored photo. Replace it or remove the student."
}
```

HTTP Status:

```text
400 Bad Request
```

---

### Step 4: Find Requested Photo

```python
target = next(
    (
        r for r in rows
        if int(r.angle_index)
        == int(angle_index)
    ),
    None
)
```

Purpose:

```text
Locate the photo that
must be deleted.
```

Photo Found?

#### NO

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

#### YES

Continue.

---

### Step 5: Load Services

```python
storage_svc = get_storage_service()

vector_svc = get_vector_db_service()
```

Purpose:

```text
Access storage and
vector database services.
```

---

### Step 6: Check Primary Status

```python
was_primary =
bool(target.is_primary)
```

Purpose:

```text
Determine whether the
deleted image is currently
the primary display photo.
```

Example:

```text
True
```

---

### Step 7: Delete Image From Storage

```python
storage_svc.delete_image(
    target.minio_object_key
)
```

Purpose:

```text
Remove image file from
MinIO/Object Storage.
```

Storage Failure?

#### YES

```python
logger.warning(...)
```

Purpose:

```text
Log warning and continue.

Database cleanup should still occur.
```

---

### Step 8: Delete Database Record

```python
db.delete(target)

db.flush()
```

Purpose:

```text
Remove photo metadata from
student_face_images table.
```

Equivalent SQL:

```sql
DELETE
FROM student_face_images
WHERE student_id='STU001'
AND angle_index=2;
```

---

### Step 9: Reassign Primary Photo

Condition:

```python
if was_primary:
```

Purpose:

```text
If the deleted image was
the primary image,
assign a new primary image.
```

Load Remaining Photos:

```python
remaining = (
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

Reset Primary Flags:

```python
for row in remaining:
    row.is_primary = False
```

Assign New Primary:

```python
remaining[0].is_primary = True
```

Example:

```text
Before:

Angle 0 → False
Angle 1 → True
Angle 2 → False

Delete Angle 1

After:

Angle 0 → True
Angle 2 → False
```

---

### Step 10: Mark Student As Processing

```python
student.enrollment_status =
ENROLLMENT_STATUS_PROCESSING
```

Set Processing Time:

```python
student.enrollment_started_at =
datetime.now(timezone.utc)
```

Clear Previous Error:

```python
student.enrollment_error = None
```

Purpose:

```text
Re-indexing is about to begin.
```

---

### Step 11: Commit Changes

```python
db.commit()
```

Purpose:

```text
Persist photo deletion
before rebuilding embeddings.
```

---

<details>
<summary><strong>Internal Function: _reindex_student_face_embeddings()</strong></summary>

### Step 12: Rebuild Face Embeddings

```python
_reindex_student_face_embeddings(
    db,
    student,
    storage_svc,
    vector_svc
)
```

Purpose:

```text
Delete old embeddings and
generate new embeddings using
remaining face photos.
```

Why?

```text
The removed photo may have
contributed to recognition accuracy.

Embeddings must remain consistent.
```

</details>

---

### Step 13: Mark Enrollment As Stored

```python
student.enrollment_status =
ENROLLMENT_STATUS_STORED
```

Store Completion Time:

```python
student.enrollment_stored_at =
datetime.now(timezone.utc)
```

Clear Errors:

```python
student.enrollment_error = None
```

Save:

```python
db.commit()
```

Purpose:

```text
Indicate successful reindexing.
```

---

### Step 14: Handle Reindex Failures

```python
except Exception as e:
```

Rollback Current Transaction:

```python
db.rollback()
```

Reload Student:

```python
failed = (
    db.query(Student)
    .filter(
        Student.student_id == student_id
    )
    .first()
)
```

Mark Error State:

```python
failed.enrollment_status =
ENROLLMENT_STATUS_ERROR

failed.enrollment_error =
str(e)
```

Save:

```python
db.commit()
```

Return:

```json
{
  "detail": "Face photo delete reindex failed: ..."
}
```

HTTP Status:

```text
500 Internal Server Error
```

---

### Step 15: Count Remaining Photos

```python
remaining_count = (
    db.query(StudentFaceImage)
    .filter(
        StudentFaceImage.student_id
        == student_id
    )
    .count()
)
```

Purpose:

```text
Determine how many photos
remain after deletion.
```

Example:

```text
2
```

---

### Step 16: Log Operation

```python
logger.info(
    "Deleted face sample angle %s for %s (%s)",
    angle_index,
    student_id,
    student.name
)
```

Example Log:

```text
Deleted face sample angle 2
for STU001 (John Doe)
```

---

### Step 17: Return Response

```python
return {
    "detail": "Photo removed",
    "remaining_photos": remaining_count
}
```

Example Response:

```json
{
  "detail": "Photo removed",
  "remaining_photos": 2
}
```

---

### Flow

```text
DELETE /{student_id}/photos/{angle_index}
                    │
                    ▼
Find Student
                    │
                    ├── Not Found → 404
                    │
                    ▼
Load Student Photos
                    │
                    ├── No Photos → 404
                    │
                    ├── Only One Photo → 400
                    │
                    ▼
Find Target Photo
                    │
                    ├── Not Found → 404
                    │
                    ▼
Delete Storage Object
                    │
                    ▼
Delete Database Row
                    │
                    ▼
Was Primary?
                    │
              ┌─────┴─────┐
              │           │
             YES          NO
              │
              ▼
Assign New Primary
              │
              ▼
Mark Processing
              │
              ▼
Commit Changes
              │
              ▼
Rebuild Embeddings
              │
        ┌─────┴─────┐
        │           │
     Success      Failure
        │           │
        ▼           ▼
 Mark Stored    Mark Error
        │           │
        ▼           ▼
     Return      HTTP 500
```

</details>
</details>

<details>
<summary><strong>API: DELETE /{student_id}</strong></summary>

# API: DELETE /{student_id}

## Operation Type

```text id="v3z6o1"
CRUD Operation: DELETE

HTTP Method: DELETE

Purpose:
Completely removes a student
from the system.

This includes:

• Student record
• Face embeddings
• Face images
• Assignments

Used when a student is
permanently removed from
the attendance system.
```

### Authentication

```python id="m0e3k8"
_user = RequireOperator
```

Only Operator users can access this API.

---

### Request Parameters

| Parameter  | Type | Required | Description        |
| ---------- | ---- | -------- | ------------------ |
| student_id | Path | Yes      | Student identifier |

---

### Request Example

```text id="x7q2lp"
DELETE /students/STU001
```

---

### Step 1: Find Student

```python id="qz7bkp"
student = (
    db.query(Student)
    .filter(
        Student.student_id == student_id
    )
    .first()
)
```

Purpose:

```text id="a5vmzw"
Verify student exists.
```

Student Found?

#### NO

Return:

```json id="whh5j4"
{
  "detail": "Student not found"
}
```

HTTP Status:

```text id="3b6lj0"
404 Not Found
```

#### YES

Continue.

---

### Step 2: Load Vector DB Service

```python id="8m3qxr"
vector_svc =
get_vector_db_service()
```

Purpose:

```text id="c3vd4o"
Access Milvus/Vector DB
for embedding cleanup.
```

---

<details>
<summary><strong>Internal Function: _load_assignments()</strong></summary>

### Step 3: Load Student Assignments

```python id="k3oqt8"
assignments =
_load_assignments(
    db,
    student_id
)
```

Purpose:

```text id="5vuj9h"
Retrieve all class-section
assignments for the student.
```

Example:

```text id="yw8n3m"
III-F
IV-A
Math Subject
Science Subject
```

</details>

---

### Step 4: Determine Vector DB Scopes

```python id="9jz4dw"
scopes = {
    a.class_section
    for a in assignments
    if a.class_section
}
```

Purpose:

```text id="tr5f6m"
Find all Milvus collections
where embeddings may exist.
```

Example:

```python id="8i6hqt"
{
    "III-F",
    "IV-A"
}
```

---

### Step 5: Fallback Scope

```python id="w4suyf"
if not scopes:
```

```python id="jlwm0j"
scopes = {
    student.class_section
}
```

Purpose:

```text id="s58h5o"
Ensure at least one
scope exists for cleanup.
```

Example:

```python id="1t4p3f"
{
    "III-F"
}
```

---

### Step 6: Delete Embeddings

```python id="2g6gti"
for scope in scopes:
```

```python id="u0swyz"
vector_svc.delete_embedding(
    scope,
    student_id
)
```

Purpose:

```text id="x44n5q"
Remove all face embeddings
from the vector database.
```

Example:

```text id="8a4y0k"
Milvus Collection:
III-F

Delete:
STU001
```

---

### Step 7: Handle Vector DB Failures

```python id="1d4h7u"
except Exception as e:
```

Log Error:

```python id="fjm3ko"
logger.warning(...)
```

Example Log:

```text id="eqq7lk"
Failed to delete embedding
from vector DB for STU001
```

Purpose:

```text id="l6gkgh"
Continue student removal
even if vector cleanup fails.

Database consistency is
more important.
```

---

### Step 8: Load Face Images

```python id="w6gz5m"
face_rows = (
    db.query(StudentFaceImage)
    .filter(
        StudentFaceImage.student_id
        == student_id
    )
    .all()
)
```

Purpose:

```text id="x4dk53"
Retrieve all stored
face image records.
```

Example:

```text id="dcmjgm"
Angle 0
Angle 1
Angle 2
```

---

### Step 9: Load Storage Service

```python id="f6w7nr"
storage_svc =
get_storage_service()
```

Purpose:

```text id="yq6r4o"
Access MinIO/Object Storage.
```

---

### Step 10: Delete Face Images

```python id="rjkf2h"
for row in face_rows:
```

Delete Object:

```python id="pk0e4d"
storage_svc.delete_image(
    row.minio_object_key
)
```

Purpose:

```text id="8l8j8x"
Remove all enrolled
face image files.
```

Example:

```text id="8ryv2j"
III-F/STU001_0.jpg
III-F/STU001_1.jpg
III-F/STU001_2.jpg
```

---

### Step 11: Handle Storage Failures

```python id="d4gj8q"
except Exception as e:
```

Log Error:

```python id="u4rk7j"
logger.warning(...)
```

Purpose:

```text id="vk5x4u"
Continue deletion even if
an image cannot be removed.
```

Example:

```text id="wkn41m"
Failed to delete face image
III-F/STU001_1.jpg
```

---

### Step 12: Remove StudentFaceImage Records

```python id="9j3gkp"
db.query(StudentFaceImage)
.filter(
    StudentFaceImage.student_id
    == student_id
)
.delete()
```

Equivalent SQL:

```sql id="e4f2ma"
DELETE
FROM student_face_images
WHERE student_id='STU001';
```

Purpose:

```text id="2rhlw5"
Remove all photo metadata.
```

---

### Step 13: Handle Photo Cleanup Errors

```python id="l7nq9o"
except Exception as e:
```

Log Error:

```python id="8n5qde"
logger.warning(...)
```

Purpose:

```text id="w3g4w6"
Continue deletion process
even if photo cleanup fails.
```

---

### Step 14: Legacy Image Cleanup

```python id="5v4g6y"
get_storage_service()
.delete_image(
    student.minio_object_key
)
```

Purpose:

```text id="4tuwto"
Remove old single-photo
enrollment image.
```

Note:

```text id="63r3wa"
May overlap with a primary
multi-photo image.

This is safe.
```

---

### Step 15: Handle Legacy Cleanup Failure

```python id="8i1ozz"
except Exception as e:
```

Log Error:

```python id="wdr6li"
logger.warning(...)
```

Example:

```text id="jix7b4"
Failed to delete image
from MinIO
```

---

### Step 16: Delete Student Record

```python id="v2k9bw"
db.delete(student)
```

Purpose:

```text id="9kqv2f"
Remove student from
students table.
```

Equivalent SQL:

```sql id="6q4pwu"
DELETE
FROM students
WHERE student_id='STU001';
```

---

### Step 17: Delete Assignments

```python id="e6z4gk"
db.query(StudentAssignment)
.filter(
    StudentAssignment.student_id
    == student_id
)
.delete()
```

Purpose:

```text id="52szcz"
Remove all class, section,
and subject assignments.
```

Equivalent SQL:

```sql id="xv8zsj"
DELETE
FROM student_assignment
WHERE student_id='STU001';
```

---

### Step 18: Commit Changes

```python id="xyv3o2"
db.commit()
```

Purpose:

```text id="ym9z9r"
Persist all deletions.
```

---

### Step 19: Return Response

```python id="2e4gcv"
return {
    "detail":
    f"Student {student_id}
    ({student.name})
    removed"
}
```

Example Response:

```json id="p8p4a0"
{
  "detail": "Student STU001 (John Doe) removed"
}
```

---

### Flow

```text id="4c4f1o"
DELETE /{student_id}
          │
          ▼
Find Student
          │
          ├── Not Found → 404
          │
          ▼
Load Assignments
          │
          ▼
Determine Scopes
          │
          ▼
Delete Vector Embeddings
          │
          ├── Failure → Log Warning
          │
          ▼
Load Face Images
          │
          ▼
Delete Image Files
          │
          ├── Failure → Log Warning
          │
          ▼
Delete StudentFaceImage Rows
          │
          ▼
Delete Legacy Image
          │
          ├── Failure → Log Warning
          │
          ▼
Delete Student Record
          │
          ▼
Delete Assignments
          │
          ▼
Commit Changes
          │
          ▼
Return Success
```

</details>
</details>
