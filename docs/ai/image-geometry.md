# Local image calibration and transform contract

Reference §9 requires actual capture provenance and consistent image transforms before any projection. A `calibration` string alone cannot establish that. `RoomImageCaptureGeometry` is now a versioned **local-only companion** to `RoomImageManifest`, joined by exact image ID/digest, home ID/revision, capture frame and timestamp. It stores original dimensions, rectified intrinsics, rigid camera pose and optional registered-depth metadata. The cloud continues receiving only the existing bounded manifest and selected submitted bytes. Do not forward this companion, source scan/camera IDs, poses or depth through feature or generic tool contexts.

`RoomImageGeometry.rays` executes the recorded transform inverse and returns original pixel corners plus optical-camera rays with z=1. It creates no world points, graph edges, room associations, confirmed concerns, routes or score credit. A ray is not an object position. `hasRecordedAlignedDepth` means matching metadata exists; it does not prove bytes, registration accuracy, confidence or a valid depth sample. Actual sensor capture, byte digests, ARKit convention conversion, depth registration/sampling, camera-to-home registration and native overlays remain Mac responsibilities. If they cannot be verified, keep the finding on the submitted image. Optional manual/no-depth review remains useful.

## Exact conventions

The companion uses `version: dryrun.image-geometry/1`. `intrinsics` is row-major `[fx,0,cx, 0,fy,cy, 0,0,1]` for the **original rectified image**, in pixels. `cameraToCapture` is a row-major rigid 4×4 homogeneous pose from optical camera axes (right/down/forward, metres) into the identified capture frame. Native must explicitly convert ARKit's camera convention and actual frame registration. Matching an ID is a binding check, not proof of physical alignment; never invent a frame ID or identity pose for a real photo. Missing `home.sourceCaptureFrameID` fails this calibrated path. Distorted/unmodeled cameras remain image-space until supported.

Pixel coordinates denote image edges: `[0,width] × [0,height]`. Transforms run in the recorded order from original rectified pixels to exact submitted pixels:

| Kind | `values` | Validation |
| --- | --- | --- |
| crop | `[x,y,width,height]`, current pixels | Integer edges, positive size, within the current image. Record the crop actually executed, after native rounding. |
| resize | `[width,height]` | Positive integer output dimensions, at most16384 on each axis. Anisotropic scaling is explicitly invertible. |
| rotate | `[quarterTurnsClockwise]` | Integer0–3; odd turns swap dimensions. `[90]` is invalid. |
| redact | `[ymin,xmin,ymax,xmax]` | Normalized positive region in the image **at this step**. Geometry unchanged; intersecting evidence cannot yield rays. |

The final dimensions must exactly equal the manifest's submitted width/height. `orientation` remains capture/submission metadata and adds **no implicit extra rotation**. If native bakes EXIF orientation into pixels, record the actual rotation once. `redactedRegions` refers to the final submitted image; both these regions and intermediate redact steps block overlapping boxes. A partial overlap blocks the whole proposed box. Hidden/redacted content is never negative evidence.

Original images are bounded at16384px per axis; the existing submitted-image4096px bound remains. Pose rotation must be proper/orthonormal, intrinsics finite with positive focal lengths, and final rays finite. Unsupported transforms/calibration fail closed rather than clamping or silently guessing. Optional depth metadata must identify the same camera frame/time, original reference dimensions, actual depth dimensions, SHA-256 digest, sceneDepth/smoothedSceneDepth source and `registeredToOriginalRectifiedImage` alignment. Native still verifies actual bytes and meaningful confidence before sampling; no depth samples are persisted by this type.

## Persistence and deletion

`IntegratedAIState.imageGeometryRecords` is optional; old encrypted state decodes with nil. `recordImageGeometry(_:manifest:home:persist:)` validates bindings and transforms, upserts one selected image and saves before publication. It bounds storage to32 selected frames total. This is a local selection budget, not cloud upload permission or whole-scan storage. The cloud operation budget remains at most4 selected images. Remove unneeded selected companions before recording more; do not silently evict another image's review history.

`removeImageGeometry(imageID:persist:)` atomically removes the companion from the encrypted state. Native **also** deletes selected image/depth bytes, cancels active uploads and clears transient capture buffers. This method alone does not delete pixels or promise secure erasure of old encrypted backups. Retain a concern only as explicitly kept review history, with its original source and image availability clearly stated. Revalidate before every calibrated use; a home/frame/revision change cannot silently rebind an old capture.

Example local call (the values come from actual capture, not model output):

```swift
try state.recordImageGeometry(record, manifest: manifest, home: home, persist: savePrivateState)
let rays = try RoomImageGeometry.rays(for: proposal.box, manifest: manifest, record: record, home: home)
// rays are optical-camera directions only. Native registration/depth remain separate.
try state.removeImageGeometry(imageID: manifest.id, persist: savePrivateState)
```

Handle typed `RoomImageGeometryError` by retaining the reviewable submitted-image finding. Failed persistence publishes neither insert nor deletion. Preserve the optional field in every existing Vault save, alongside other AI state; it is never a cloud context. The strict gateway rejects a companion smuggled into a manifest/context before provider dispatch.

## Executable evidence and Mac checks

`fixtures/ai/image-geometry-v1.json` is an explicitly synthetic analytical fixture. Original800×600 → crop(100,50,400,200) → resize200×100 → rotate clockwise → submitted100×200. Box `[.25,.2,.75,.8]` maps to original corners `(200,210),(200,90),(400,90),(400,210)`. Intrinsics fx=fy400,cx400,cy300 produce the recorded optical rays. The fixture's pose/frame IDs are invented test values, never real scan measurements.

Run `scripts/swift.sh packages/DryRunCore test --filter RoomImageGeometryTests` and `scripts/swift.sh packages/DryRunVault test -j 4 --filter IntegratedAIStateTests`; on Mac use the equivalent native Swift package commands. Full portable verification includes these tests. Core tests also cover all quarter turns, stale image/home/frame/time, improper poses, invalid intrinsics/overflow, unmatched depth metadata, no-calibration fallback, redaction before/after transforms, malformed/out-of-bounds/dimension-inconsistent transforms, Codable migration,32-frame bounds, rollback and deletion. Vault tests encrypt/restore the actual companion, scan for plaintext frame canaries and verify saved deletion. A gateway test accepts the fixture manifest but rejects local matrices/companion fields before any model call.

No real-camera, real-depth or 3D alignment accuracy claim follows from these tests. On the wired phone, verify actual AR frame timestamps/convention/intrinsics, crop/resize/orientation once, portrait/landscape and all rotations, registered and missing depth, frame/home edits, redaction boundaries, digest of submitted bytes, no camera/depth data in HTTP/logs, encrypted relaunch and deletion of **both** bytes and companion. Inspect overlays against visible landmarks; keep uncertain associations in image space. Human review of real photos, privacy comprehension, concern usefulness and safety wording remains pending. No new Gemini call is needed to test this host geometry boundary.
