# Iris Vector Extraction Flow

## 1. Entry Point

### extract_search_vector()
```python
async def extract_search_vector(self, image_bytes: bytes, sub_type: str) -> dict[str, Any]:
    response = await self.extract(image_bytes, sub_type)
```

## 2. Core Extraction Function
**extract()**  
Sends iris image to iris extractor service.

```python
async def extract(self, image_bytes: bytes, sub_type: str) -> Dict[str, Any]:
```

### Step-by-step flow:

**Step 1: Convert image → base64**
```python
image_base64 = base64.b64encode(image_bytes).decode('utf-8')
```

**Step 2: Build payload**
```python
payload = {
    "image_data": image_base64,
    "model_name": self.model_name,
    "sub_type": sub_type,
}
```

**Step 3: Call iris extractor**
```python
async with httpx.AsyncClient(timeout=self.timeout) as client:
    response = await client.post(self.base64_extract_url, json=payload)
```

**Step 4: Return raw response**
```python
response.raise_for_status()
return response.json()
```

## 3. Post-processing (VERY IMPORTANT)

**Step 5: Check success**
```python
if not response.get('success', False):
    return response
```

**Step 6: Extract serialized embeddings**
```python
serialized_complex_response = response.get('embedding')
```

If empty:
```python
return {"success": False, "error": "Empty embedding"}
```

**Step 7: Deserialize embeddings**
```python
complex_response = [
    np.load(io.BytesIO(base64.b64decode(encoded)))
    for encoded in serialized_complex_response
]
```

**Step 8: Convert to vector**
```python
return {
    "success": True,
    "embedding": self.complex_response_to_float_vector(complex_response)
}
```

## 4. Flow Summary

```
extract_search_vector()
        ↓
extract()
        ↓
Base64 encode image
        ↓
Send to iris extractor
        ↓
Get serialized embeddings
        ↓
Base64 decode + np.load
        ↓
Convert to float vector
        ↓
Return final embedding vector
```
