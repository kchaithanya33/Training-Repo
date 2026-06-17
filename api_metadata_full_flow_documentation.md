# API Metadata - Full Flow Documentation

## Part 1: GET /metadata/records/ Flow

### Step-by-Step Flow

1. **API Request**  
   `GET /metadata/records/`  
   Header: `X-ABIS-Api-Key: key123`

2. **Authentication**  
   Middleware executes first. Reads `X-ABIS-Api-Key: key123`.  
   Finds tenant:  
   ```python
   Tenant(
       name="ABC Bank",
       vector_collection_name="abc_faces"
   )
   ```  
   Attaches to request: `request.integrator_tenant = tenant`

3. **records() Function Starts**

4. **Audit Logging**  
   `log_audit_event(...)`  
   Stores: Who accessed, Page Number, Filters used, Time.

5. **Read Query Parameters**  
   - `page`  
   - `page_size`  
   - `search`  
   - `status`  
   - `bio_type`  
   - `tags`  
   - `vector_collection`  
   - `sort_by`  
   - `sort_order`  
   - `paginate_by`  

   Example: `GET /metadata/records/?page=1&status=STORED`

6. **Base Queryset**  
   `Metadata.objects.all()`

7. **Tenant Collection Filtering**  
   ```python
   queryset = apply_tenant_collection_to_queryset(request, Metadata.objects.all())
   ```  
   - Gets `tenant.vector_collection_name` → `"abc_faces"`  
   - Filters: `queryset.filter(vector_collection_name="abc_faces")`

8. **Additional Filters**  
   - Search: `queryset.filter(user_id__icontains="U001")`  
   - Status: `queryset.filter(status="STORED")`  
   - Bio Type: `queryset.filter(bio_type="FID")`  
   - Tags: `filter_queryset_by_all_tags(...)`

9. **Sorting**  
   `queryset.order_by("user_id")` or default `queryset.order_by("-created_at")`

10. **Count Records**  
    `total_count = queryset.count()`

11. **Pagination**  
    - Default: `paginate_by="record"` (20 records per page)  
    - User mode: `paginate_by="user"` (groups by `user_id`)

12. **Serialize Data**  
    `MetadataSerializer(...)`

13. **Build Response**  
    ```json
    {
      "results": [...],
      "count": 100,
      "page": 1,
      "page_size": 20
    }
    ```

14. **Next/Previous URLs** + Return Response

---

## Part 2: Batch Gallery Status API Flow

### Step-by-Step Flow

1. **API Request**  
   ```json
   {
     "galleryIds": ["111", "222", "333"]
   }
   ```

2. **Read Input**  
   ```python
   raw = request.data.get("galleryIds") or request.data.get("gallery_ids")
   ```

3. **Validate Input**  
   ```python
   if not isinstance(raw, list) or not raw:
   ```  
   Returns error:  
   ```json
   {"error": "galleryIds must be a non-empty JSON array"}
   ```

4. **Read Maximum Allowed IDs**  
   ```python
   max_ids = int(os.getenv("METADATA_BATCH_GALLERY_IDS_MAX", "5000"))
   ```

5. **Normalize IDs**  
   ```python
   n = _normalize_gallery_id_for_lookup(x)
   ```  
   Example: `ABC-123` → `abc-123`

6. **Remove Duplicates**  
   Uses `seen_ids = set()`

7. **Audit Logging**  
   ```python
   log_audit_event(...)
   ```  
   Logs requested vs queried count.

8. **Query Database**  
   ```python
   Metadata.objects.filter(gallery_id__in=ids).values("gallery_id", "status")
   ```

9. **Build Dictionary**  
   ```python
   found = {
       "111": "STORED",
       "222": "FAILED"
   }
   ```

---

