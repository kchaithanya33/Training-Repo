# `identify_endpoint.md`

# Identify Endpoint Flow

## Endpoint Definition

```python
@action(detail=False, methods=["post"])
def identify(self, request):
```

Accepts a POST request containing:
- `uId` (user ID)
- `bioType` (FIR / FID / IIR / ALL)
- `threshold` (similarity threshold)
- `limit` (max results)
- Optional debug and configuration flags

Returns structured biometric match results.

### 1. Audit Logging (Request Start)

```python
log_audit_event(...)
```

Logs incoming request details (user_id, bio_type, threshold, limit, etc.)

### 2. Request Validation

```python
serializer = IdentifyRequestSerializer(data=request.data)
serializer.is_valid(raise_exception=True)
```

Validates required fields. Returns **400 Bad Request** if invalid.

### 3. Parameter Preparation

- `user_id`, `bio_type`, `threshold` (default 0.7), `limit` (default 10)
- Special handling for FIR effective threshold from system config

### 4. Fetch User Biometric Records

```python
Metadata.objects.filter(user_id=user_id, status="STORED", ...)
```

Fetches all relevant biometric records for the user.

### 5. Parallel Search Execution

```python
with ThreadPoolExecutor() as executor:
    results = list(executor.map(_search_single_record, user_records))
```

### 6. `_search_single_record()` Flow

1. Fetch vector from Vector DB (`vector_db.get_biometric_record()`)
2. Prepare feature vector (single vector or [vector, mask] for IIR)
3. Calculate `milvus_k` (search depth)
4. Perform similarity search:
   ```python
   vector_db.search_similar(bio_type, feature_vector, threshold, milvus_k)
   ```
5. Return search results + timing info

### 7. Result Aggregation

- Merge results from all records
- Remove duplicates
- Batch metadata lookup

### 8. FIR Native Reranking (Optional)

- If enabled: Extract templates → Call native matcher → Rerank using native similarity

### 9. Final Processing

- Sort by similarity (or nativeSimilarity)
- Apply limit
- Compute statistics

### 10. Audit Logging (Completion)

Logs total matches, processing time, etc.

### 11. Response

```python
return Response({
    "user_id": user_id,
    "bio_type": bio_type,
    "searchResults": [...],
    "totalFound": total,
    "threshold": threshold,
    ...
})
```

## Flow Summary

```
POST /identify
        ↓
Audit + Request Validation
        ↓
Fetch User Biometric Records
        ↓
Parallel _search_single_record()
        ↓
Vector DB Similarity Search
        ↓
(Optional) FIR Native Reranking
        ↓
Sort + Limit Results
        ↓
Audit Log + Return Response
```
