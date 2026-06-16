# Biometric Search System Documentation

## /metadata/search/ & attendance_recognize

### 1. Overview
This document explains the full backend flow of:

* /metadata/search/
* attendance_recognize

It includes:

* request validation
* tenant enforcement
* feature extraction
* vector search
* metadata filtering
* response building

### 2. API Entry: /metadata/search/
**Step 1: Input Logging**

```python
logger.info(
    "Search request received - bio_type: %s, image_type: %s, threshold: %s, limit: %s",
    request.data.get("bioType"),
    request.data.get("imageType"),
    request.data.get("threshold"),
    request.data.get("limit"),
)
```

**Purpose:**

* Debug request inputs
* Observability in production

**Step 2: Audit Logging**

```python
log_audit_event(
    event_type=EventType.BIOMETRIC_SEARCH,
    severity=EventSeverity.INFO,
    action="search_biometrics",
    resource="biometric_record",
    request=request,
)
```

**Purpose:**

* Security tracking
* User activity history
* Compliance logs

### 3. Tenant Enforcement Layer
**Function:** `apply_tenant_collection_to_data(request, data)`

**Flow:**

1. Get tenant from request
2. If tenant not found → return original data
3. Copy request data safely
4. Read client vectorCollection
5. Read server (tenant) vectorCollection
6. If mismatch → log warning
7. Override with tenant value
8. Read face_embedding_backend
9. If bioType == FID → apply backend
10. Return modified data

**Key Idea:**  
Server configuration always overrides client input.

### 4. Serializer Validation
**MetadataSearchReqSerializer**

**What it does:**

* Validates request fields
* Applies defaults
* Sanitizes input

**Fields:**

* encodedImage → required
* bioType → required
* imageType → default "JPG"
* threshold → default 0.8 (0–1)
* limit → default 10
* includeStatistics → default True
* includeDiagnostics → default False
* filterTags → normalized list
* vectorCollection → validated

**Output:**  
`validated_data`

### 5. Feature Extraction Decision

**Case 1: Vector Input**

```python
imageType = VEC | JSON
```

* Directly call:  
  `parse_vector_data()`
* Skip ML pipeline

**Case 2: Image Input**

**Step 1: Decode Base64**

```python
image_bytes = base64.b64decode(encodedImage)
```

**Step 2: Generate Variants**

```python
_build_search_variants(image_bytes, compat_mode)
```

### 6. _build_search_variants

**Flow:**

1. Start with original image
2. If compat_mode = False → return original
3. Decode image using OpenCV
4. If enabled:
   * Apply histogram equalization
   * Improve contrast
   * Add variant
5. If upscale enabled:
   * Resize image (zoom)
   * Add variant
6. Return limited variants

**Purpose:**  
Improve low-quality face detection accuracy

### 7. Embedding Extraction Pipeline

**Function Chain:**

```
extract_sync()
   ↓
extract_search_vector()
   ↓
_extract_with_deepface_fallback()
   ↓
_post_extract()
```

#### 7.1 extract_sync
* Converts input image → bytes
* Runs async function using asyncio.run

#### 7.2 extract_search_vector
```python
return await _extract_with_deepface_fallback()
```
* Wrapper for async extraction logic

#### 7.3 _extract_with_deepface_fallback
**Flow:**

1. Refresh configuration
2. Try InsightFace (primary)
3. If "no face detected":
   * switch to DeepFace
4. Retry extraction
5. Return embedding result

#### 7.4 _post_extract
**Flow:**

1. Convert image bytes → base64
2. Create payload:

```json
{
  "image_data": "...",
  "model_name": "...",
  "parameters": {}
}
```

3. Send HTTP request to extractor service
4. Handle:
   * timeout
   * GPU errors
   * HTTP errors
   * exceptions

**Output:**

```json
{
  "success": true,
  "embedding": [...]
}
```

### 8. Vector Search
**Flow:**

1. Get embeddings
2. Call vector DB:  
   `search_similar()`
3. Merge duplicate gallery IDs
4. Sort by similarity
5. Apply limit

### 9. Metadata Enrichment
**Steps:**

1. Bulk fetch metadata from DB
2. Filter:
   * missing metadata
   * non-STORED status
   * tag mismatch
3. Build final results

### 10. Audit Final Log
Stores:

* extraction time
* search time
* total time
* result count

### 11. Response Structure

```json
{
  "searchResults": [],
  "totalFound": 0,
  "threshold": 0.8,
  "summaryStatistics": {}
}
```

### 12. Attendance Recognize API
**Purpose:**  
Detect multiple faces and search each one independently.

**Flow:**

1. Validate request
2. Decode image
3. Detect faces:
   * InsightFace OR DeepFace OR fallback
4. For each face:
   * crop image
   * extract embedding
   * search vector DB
5. Fetch metadata
6. Filter results
7. Build face-level matches
8. Return response

### 13. Full System Architecture

```
Request
  ↓
Logging + Audit
  ↓
Tenant Enforcement
  ↓
Validation
  ↓
Base64 Decode
  ↓
Variant Generation
  ↓
Embedding Extraction (InsightFace → DeepFace fallback)
  ↓
Vector DB Search
  ↓
Metadata DB Lookup
  ↓
Filtering
```

---

