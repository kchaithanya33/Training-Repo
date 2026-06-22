<details>
<summary><b>API: POST /unknown/resolve </b></summary>
 
```text
Resolve an unknown face by linking it to an existing student.
Marks attendance, enrolls the face into the student's gallery,
updates ABIS, and removes the unknown face from the pending list.
```

### Endpoint

```http
POST /unknown/resolve
```

### Request

```json
{
  "session_id": "session_123",
  "class_section": "10-A",
  "unknown_id": "unknown_face_001",
  "student_id": "ST101",
  "result_id": "result_456"
}
```

### Response

```json
{
  "success": true,
  "student_id": "ST101",
  "student_name": "John Doe",
  "class_section": "10-A",
  "session_id": "session_123",
  "recognized_face_photo_url": "/api/attendance/images/...",
  "frame_photo_url": "/api/attendance/images/...",
  "total_student_photos": 8
}
```

<details>
<summary><b>Internal Function Called</b></summary>

```python
_resolve_unknown_face_impl(...)
```

Responsibilities:

- Validate student
- Verify class-section assignment
- Mark attendance
- Save recognized face image
- Add face to StudentFaceImage
- Insert face into ABIS/Milvus
- Resolve unknown face
- Return response

```

Flow:

```text
Unknown Face
      |
Select Existing Student
      |
POST /unknown/resolve
      |
Validate Session
      |
Validate Student
      |
Mark Attendance
      |
Add Face To Student Gallery
      |
Insert Face Into ABIS
      |
Remove Unknown Face
      |
Return Response
```
</details>
</details>
