# Vehicle Inspector Backend

Local backend for analyzing iPhone prototype photos with OpenAI.

## Ejecutar

```bash
export OPENAI_API_KEY="tu_api_key"
cd VehicleInspectorBackend
HOST=0.0.0.0 node server.js
```

The backend tries `gpt-4.1-mini`, `gpt-4.1`, `gpt-5.4-mini`, `gpt-5.4-mini-2026-03-17`, and then `gpt-5-mini` by default. If your project has access to different models, you can change the candidate list like this:

```bash
OPENAI_MODELS="gpt-4.1-mini,gpt-4.1,gpt-5.4-mini,gpt-5.4-mini-2026-03-17,gpt-5-mini" HOST=0.0.0.0 node server.js
```

The backend runs a second verification pass by default to reduce false positives. You can tune it like this:

```bash
MIN_CONFIDENCE=0.55 VERIFY_ANALYSIS=true HOST=0.0.0.0 node server.js
```

To temporarily skip the second pass:

```bash
VERIFY_ANALYSIS=false HOST=0.0.0.0 node server.js
```

La app iOS llama por defecto a:

```text
http://10.0.0.169:8787/analyze
```

Your iPhone and Mac must be on the same WiFi network. If your Mac IP changes, update the endpoint in `VehicleDamageAnalysisService.swift`.

```swift
private let endpoint = URL(string: "http://10.0.0.169:8787/analyze")!
```

## Verificar

```bash
curl http://127.0.0.1:8787/health
```

## Deploy to Render

Render runs this backend as a Node web service. The server binds to `process.env.PORT` and `0.0.0.0`, which Render requires for public web services.

### Option A: Dashboard setup

1. Push this project to GitHub.
2. Go to Render and create a new Web Service.
3. Connect the GitHub repository.
4. Set the root directory to:

```text
VehicleInspectorBackend
```

5. Use these commands:

```text
Build Command: npm install
Start Command: npm start
```

6. Set the health check path:

```text
/health
```

7. Add these environment variables:

```text
OPENAI_API_KEY=your_openai_api_key
DATABASE_URL=your_render_internal_database_url
CLOUDINARY_CLOUD_NAME=your_cloudinary_cloud_name
CLOUDINARY_API_KEY=your_cloudinary_api_key
CLOUDINARY_API_SECRET=your_cloudinary_api_secret
OPENAI_MODELS=gpt-4.1-mini,gpt-4.1,gpt-5.4-mini,gpt-5.4-mini-2026-03-17,gpt-5-mini
VERIFY_ANALYSIS=true
MIN_CONFIDENCE=0.45
```

Do not commit `OPENAI_API_KEY`, `DATABASE_URL`, or Cloudinary secrets into the repo.

### Option B: Blueprint

You can also use `render.yaml` from this folder as a Render Blueprint. Render will still ask you to provide `OPENAI_API_KEY` as a secret value.

### After deployment

Render will give you a URL like:

```text
https://vehicle-inspector-zgsi.onrender.com
```

Test:

```bash
curl https://vehicle-inspector-zgsi.onrender.com/health
```

Then update the iPhone app backend URL in `VehicleDamageAnalysisService.swift`.

## Database API

When `DATABASE_URL` is configured, the backend creates the required tables automatically on first database request.

When Cloudinary is configured, inspection photos are uploaded to Cloudinary and PostgreSQL stores `image_url` plus `cloudinary_public_id`. If Cloudinary is not configured, the prototype falls back to storing `image_base64` in PostgreSQL.

Create a vehicle:

```bash
curl -X POST https://vehicle-inspector-zgsi.onrender.com/vehicles \
  -H "Content-Type: application/json" \
  -d '{"label":"Test vehicle","plate":"ABC123","make":"Toyota","model":"Camry","year":2022,"color":"White"}'
```

List vehicles:

```bash
curl https://vehicle-inspector-zgsi.onrender.com/vehicles
```

Create an inspection for a vehicle:

```bash
curl -X POST https://vehicle-inspector-zgsi.onrender.com/vehicles/VEHICLE_ID/inspections \
  -H "Content-Type: application/json" \
  -d '{"status":"Needs review","aiAnalyzed":true,"photos":[],"findings":[],"checklist":[]}'
```

Load an inspection:

```bash
curl https://vehicle-inspector-zgsi.onrender.com/inspections/INSPECTION_ID
```
