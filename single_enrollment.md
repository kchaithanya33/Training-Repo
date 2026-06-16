# Biometric Insert API

```python
@action(detail=False, methods=["post"])
def insert(self, request):
    logger.info(
        "Insert request received - user_id: %s, bio_type: %s, image_type: %s",
        request.data.get("uId"),
        request.data.get("bioType"),
        request.data.get("imageType")
    )

    # Log audit event for insert request
    log_audit_event(
        event_type=EventType.BIOMETRIC_INSERT,
        severity=EventSeverity.INFO,
        user_id=request.data.get("uId"),
        action="insert_biometric",
        resource="biometric_record",
        request=request,
        details={
            "bio_type": request.data.get("bioType"),
            "image_type": request.data.get("imageType"),
            "bio_sub_type": request.data.get("bioSubType"),
            "capture_mode": request.data.get("captureMode"),
        }
    )

    # Normalize captureMode so CTK/any client sending unknown value gets CONTACT
    insert_data = (
        request.data.copy()
        if hasattr(request.data, "copy")
        else dict(request.data)
    )

    insert_data = apply_tenant_collection_to_data(request, insert_data)

    cm = (insert_data.get("captureMode") or "CONTACT").strip().upper()

    if cm not in ("CONTACT", "CONTACTLESS", "ROLLOVER", "NONE"):
        insert_data["captureMode"] = "CONTACT"

    serializer = MetadataInsertReqSerializer(data=insert_data)

    if serializer.is_valid():
        data = serializer.validated_data
        body, code = process_single_insert(request, data)

        if code == status.HTTP_500_INTERNAL_SERVER_ERROR:
            return Response(
                body.get("errorCode", "Unknown error"),
                status=code
            )

        return Response(body, status=code)

    logger.warning("Validation failed: %s", serializer.errors)

    return Response(
        serializer.errors,
        status=status.HTTP_400_BAD_REQUEST
    )
```

