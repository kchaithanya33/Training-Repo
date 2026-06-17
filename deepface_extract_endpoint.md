# 📄 4. `deepface_extract_endpoint.md`

# Face Extract Base64 Endpoint Flow

## Endpoint Definition

```python
@app.post("/extract-base64", response_model=ExtractResponse)
async def extract_features_base64(request: ExtractRequest):
```

Defines a POST API that:

* Accepts `ExtractRequest`
* Returns `ExtractResponse`

### 1. Dependency Check

```python
if not DEEPFACE_AVAILABLE:
    raise HTTPException(status_code=503, detail="DeepFace is not available")
```

If DeepFace is not installed or loaded → returns **503 Service Unavailable**.

### 2. Model Validation

```python
if request.model_name not in available_models:
    raise HTTPException(
        status_code=400,
        detail=f"Invalid model name. Available models: {available_models}"
    )
```

Ensures only supported face embedding models are used.

### 3. Parameter Extraction

```python
params = request.parameters or {}
detector_backend = params.get("detector_backend", request.detector_backend)
enforce_detection = params.get("enforce_detection", request.enforce_detection)
```

**Priority:**
1. `request.parameters` (nested)
2. Fallback to top-level request fields

Extracts detector backend and enforce_detection flag.

### 4. Start Audit Logging

```python
log_audit_event(
    event_type=EventType.FEATURE_EXTRACTION_START,
    severity=EventSeverity.INFO,
    action="extract_features_base64",
    resource_type="feature_extraction",
    details={...}
)
```

### 5. Start Timer

```python
start_time = time.time()
```

### 6. Base64 Decoding and Image Fix

```python
image_data = base64.b64decode(request.image_data)
img = correct_image_orientation(image_data)
```

If failure → **400 Bad Request**

### 7. Image Validation

```python
if img is None:
    raise HTTPException(status_code=400, detail="Invalid image format")
```

### 8. Image Normalization

```python
img = ensure_bgr_numpy_3ch(img)
img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
```

### 9. Model Loading

```python
ensure_models_available(
    detector_backend=detector_backend,
    model_name=request.model_name,
)
```

### 10. Debug Logging + Async Execution

```python
embedding = await loop.run_in_executor(
    _extraction_executor,
    _deepface_represent_sync,
    img_rgb,
    request.model_name,
    enforce_detection,
    detector_backend
)
```

### 11. Post-processing

- `face_count, embedding = parse_represent_embedding(embedding)`
- `face_detected = face_count > 0`
- `embedding = normalize_embedding(embedding)`

### 12. Processing Time & Success Audit Log

```python
processing_time = time.time() - start_time

log_audit_event(
    event_type=EventType.FEATURE_EXTRACTION_COMPLETE,
    ...
)
```

### 13. Successful Response

```python
return ExtractResponse(
    success=True,
    embedding=embedding if request.return_embedding else None,
    face_detected=face_detected,
    face_count=face_count,
    model_used=request.model_name,
    processing_time=processing_time
)
```

## Flow Summary

```
POST /extract-base64
        ↓
Validation (DeepFace + Model)
        ↓
Base64 Decode + Orientation Fix
        ↓
Image Normalization (BGR → RGB)
        ↓
Ensure Models Loaded
        ↓
DeepFace Represent (in Thread Pool)
        ↓
Parse + Normalize Embedding
        ↓
Audit Log
        ↓
Return ExtractResponse
```