# Fingerprint Vector Extraction Flow

## 1. Entry Point

### extract_search_vector()
```python
async def extract_search_vector(self, image_bytes: bytes, sub_type: str) -> Dict[str, Any]:
    return await self.extract(image_bytes, sub_type)
```

What it does:

*  Directly calls extract()
*  No fallback logic
*  Pure pass-through to extractor service

## 2. Core Extraction Function
extract()
This function sends fingerprint image to remote extractor service.

```python
async def extract(self, image_bytes: bytes, sub_type: str) -> Dict[str, Any]:
```

Step-by-step flow:

**Step 1: Convert image → base64**

```python
image_base64 = base64.b64encode(image_bytes).decode("utf-8")
```

**Step 2: Build payload**

```python
payload = {
    "image_data": image_base64,
    "model_name": self.model_name,
    "parameters": self.extract_params,
    "use_surrogate_embedding": self._fir_surrogate_embedding_enabled(),
}
```

Optional:

```python
embedding_variant = self._resolve_embedding_variant()
if embedding_variant:
    payload["embedding_variant"] = embedding_variant
```

**Step 3: Call extractor service (HTTP request)**

```python
async with httpx.AsyncClient(timeout=float(self.timeout)) as client:
    response = await client.post(self.base64_extract_url, json=payload)
```

**Step 4: Validate response**

```python
response.raise_for_status()
data = response.json()
```

**Step 5: Handle failure response**

```python
if not data.get("success", False):
    return {"success": False, "error": data.get("error")}
```

**Step 6: Return success response**

```python
return data
```

## 3. Error Handling

**Timeout**

```python
except httpx.TimeoutException:
    return {"success": False, "error": "Request timed out"}
```

**HTTP error**

```python
except httpx.HTTPStatusError as e:
    return {"success": False, "error": f"HTTP {code}: {err}"}
```

**Generic error**

```python
except Exception as e:
    return {"success": False, "error": str(e)}
```

## 4. Summary Flow

```
extract_search_vector()
        ↓
extract()
        ↓
Base64 encode image
        ↓
Build payload
        ↓
HTTP call to fingerprint extractor
        ↓
Return embeddings OR error
```
