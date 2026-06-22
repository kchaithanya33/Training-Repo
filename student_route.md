<details>
<summary><b>POST /enroll - Student Face Enrollment API Summary</b></summary>

## Endpoint

```http
POST /enroll
```

## Purpose

Enroll a new student by uploading face images and student details.

This API:

- Creates student record in database
- Generates/validates student ID
- Uploads face images to storage (MinIO/local)
- Creates StudentFaceImage records
- Creates student assignment
- Sets enrollment status as NEW

Note:
This API does **not** create face embeddings or insert data into Milvus.

The later enrollment process handles:

- Face detection
- Face embedding generation
- Milvus vector insertion
- Enrollment completion update

## Request Type

```text
multipart/form-data
```

## Parameters

### Images

```text
image / images
```

Upload student face images.

Allowed:

```text
1 - 10 images
```

Supports:

```text
image = single file

images = multiple files
```

### Primary Image

```text
primary_index
```

Index of the image to mark as primary.

Default:

```text
0
```

Example:

```text
primary_index=1
```

Second uploaded image becomes primary.

### Student Name

```text
name
```

Required.

Example:

```text
name=Rahul
```

### Class Section

```text
class_section
```

Required.

Example:

```text
III-F
```

Stored as:

```text
student_class = III
section = F
```

### Student ID

```text
student_id
```

Optional.

If provided:

- Must be unique
- Must match allowed format

Example:

```text
S001
```

If not provided:

Server generates:

```text
S0001
S0002
...
```

### Crop Enrollment Face

```text
crop_enrollment_face
```

Controls face cropping.

If enabled:

```text
Original Image
       |
       v
Detect Face
       |
       v
Store Cropped Face
```

## Internal Flow

```text
Client
  |
  v
POST /enroll
  |
  v
Validate Images
  |
  v
Create Student ID
  |
  v
Insert Student Record
  |
  v
Upload Images
  |
  v
Create Face Image Records
  |
  v
Set Status = NEW
  |
  v
Return Response
```

## Database Changes

### Student Table

```json
{
 "student_id": "S0001",
 "name": "Rahul",
 "student_class": "III",
 "section": "F",
 "enrollment_status": "NEW"
}
```

### StudentAssignment Table

```json
{
 "student_id": "S0001",
 "student_class": "III",
 "section": "F",
 "active": true
}
```

### StudentFaceImage Table

```json
{
 "student_id": "S0001",
 "minio_object_key": "staging/S0001/faces/0.jpg",
 "is_primary": true
}
```

## Success Response

```json
{
 "student_id": "S0001",
 "name": "Rahul",
 "enrollment_status": "NEW"
}
```

## Error Cases

No image:

```json
{
 "detail": "At least one image is required"
}
```

More than 10 images:

```json
{
 "detail": "You can upload 1..10 images per student"
}
```

Duplicate student ID:

```json
{
 "detail": "This student ID is already in use"
}
```

## Authentication

Required Role:

```text
Operator
```
</details>
