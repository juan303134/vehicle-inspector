const http = require("node:http");
const { randomUUID } = require("node:crypto");

let Pool;
try {
  ({ Pool } = require("pg"));
} catch (error) {
  Pool = null;
}

const HOST = process.env.HOST || "0.0.0.0";
const PORT = Number(process.env.PORT || 8787);
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const DATABASE_URL = process.env.DATABASE_URL;
const CLOUDINARY_CLOUD_NAME = process.env.CLOUDINARY_CLOUD_NAME;
const CLOUDINARY_API_KEY = process.env.CLOUDINARY_API_KEY;
const CLOUDINARY_API_SECRET = process.env.CLOUDINARY_API_SECRET;
const DEFAULT_OPENAI_MODELS = [
  "gpt-4.1-mini",
  "gpt-4.1",
  "gpt-5.4-mini",
  "gpt-5.4-mini-2026-03-17",
  "gpt-5-mini",
];
const OPENAI_MODELS = (process.env.OPENAI_MODELS || process.env.OPENAI_MODEL || DEFAULT_OPENAI_MODELS.join(","))
  .split(",")
  .map((model) => model.trim())
  .filter(Boolean);
const VERIFY_ANALYSIS = process.env.VERIFY_ANALYSIS !== "false";
const MIN_CONFIDENCE = Number(process.env.MIN_CONFIDENCE || 0.45);
const modelState = {
  accessibleModels: null,
  workingModel: null,
  unavailableModels: new Set(),
  successfulModels: new Set(),
};

const ALLOWED_ANGLES = ["Front", "Driver side", "Passenger side", "Rear", "Free photo"];
const DAMAGE_TYPES = ["Scratch", "Dent", "Paint chip", "Scuff", "Glass/Light"];
const SEVERITIES = ["Low", "Medium", "High"];
const CLOUDINARY_CONFIGURED = Boolean(CLOUDINARY_CLOUD_NAME && CLOUDINARY_API_KEY && CLOUDINARY_API_SECRET);
const db = createDatabaseClient();
let dbInitPromise = null;

const responseSchema = {
  type: "object",
  additionalProperties: false,
  required: ["findings"],
  properties: {
    findings: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["photoID", "angle", "type", "severity", "location", "confidence", "isNew", "region"],
        properties: {
          photoID: { type: "string" },
          angle: { type: "string", enum: ALLOWED_ANGLES },
          type: { type: "string", enum: DAMAGE_TYPES },
          severity: { type: "string", enum: SEVERITIES },
          location: { type: "string" },
          confidence: { type: "number", minimum: 0, maximum: 1 },
          isNew: { type: "boolean" },
          region: {
            type: "object",
            additionalProperties: false,
            required: ["x", "y", "width", "height"],
            properties: {
              x: { type: "number", minimum: 0, maximum: 1 },
              y: { type: "number", minimum: 0, maximum: 1 },
              width: { type: "number", minimum: 0.01, maximum: 1 },
              height: { type: "number", minimum: 0.01, maximum: 1 },
            },
          },
        },
      },
    },
  },
};

const server = http.createServer(async (req, res) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  setCorsHeaders(res);
  const requestUrl = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  const pathname = requestUrl.pathname;

  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  if (req.method === "GET" && pathname === "/health") {
    sendJson(res, 200, {
      ok: true,
      models: OPENAI_MODELS,
      workingModel: modelState.workingModel,
      hasApiKey: Boolean(OPENAI_API_KEY),
      database: {
        configured: Boolean(DATABASE_URL),
        driverLoaded: Boolean(Pool),
      },
      cloudinary: {
        configured: CLOUDINARY_CONFIGURED,
      },
    });
    return;
  }

  if (req.method === "GET" && pathname === "/models") {
    try {
      if (!OPENAI_API_KEY) {
        sendJson(res, 500, { error: "Missing OPENAI_API_KEY" });
        return;
      }

      const models = await listOpenAIModels();
      modelState.accessibleModels = models;
      sendJson(res, 200, {
        configuredModels: OPENAI_MODELS,
        accessibleModels: models,
      });
    } catch (error) {
      console.error(error);
      sendJson(res, 500, { error: "Could not list models", detail: error.message });
    }
    return;
  }

  if (req.method === "GET" && pathname === "/vehicles") {
    try {
      await ensureDatabase();
      const result = await db.query(
        `SELECT
          v.*,
          COUNT(i.id)::int AS inspection_count,
          MAX(i.created_at) AS last_inspection_at
        FROM vehicles v
        LEFT JOIN inspections i ON i.vehicle_id = v.id
        GROUP BY v.id
        ORDER BY v.updated_at DESC`
      );
      sendJson(res, 200, { vehicles: result.rows });
    } catch (error) {
      handleRouteError(res, error, "Could not load vehicles");
    }
    return;
  }

  if (req.method === "POST" && pathname === "/vehicles") {
    try {
      await ensureDatabase();
      const body = await readJson(req);
      const vehicle = normalizeVehicleInput(body);
      const result = await db.query(
        `INSERT INTO vehicles (id, vin, plate, make, model, year, color, label)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         ON CONFLICT (id) DO UPDATE SET
          vin = EXCLUDED.vin,
          plate = EXCLUDED.plate,
          make = EXCLUDED.make,
          model = EXCLUDED.model,
          year = EXCLUDED.year,
          color = EXCLUDED.color,
          label = EXCLUDED.label,
          updated_at = NOW()
         RETURNING *`,
        [vehicle.id, vehicle.vin, vehicle.plate, vehicle.make, vehicle.model, vehicle.year, vehicle.color, vehicle.label]
      );
      sendJson(res, 201, { vehicle: result.rows[0] });
    } catch (error) {
      handleRouteError(res, error, "Could not create vehicle");
    }
    return;
  }

  const vehicleMatch = pathname.match(/^\/vehicles\/([^/]+)$/);
  if (req.method === "GET" && vehicleMatch) {
    try {
      await ensureDatabase();
      const vehicle = await getVehicle(vehicleMatch[1]);
      if (!vehicle) {
        sendJson(res, 404, { error: "Vehicle not found" });
        return;
      }
      sendJson(res, 200, { vehicle });
    } catch (error) {
      handleRouteError(res, error, "Could not load vehicle");
    }
    return;
  }

  const vehicleInspectionsMatch = pathname.match(/^\/vehicles\/([^/]+)\/inspections$/);
  if (req.method === "GET" && vehicleInspectionsMatch) {
    try {
      await ensureDatabase();
      const vehicleId = vehicleInspectionsMatch[1];
      const vehicle = await getVehicle(vehicleId);
      if (!vehicle) {
        sendJson(res, 404, { error: "Vehicle not found" });
        return;
      }

      const result = await db.query(
        `SELECT
          i.*,
          COUNT(DISTINCT p.id)::int AS photo_count,
          COUNT(DISTINCT f.id)::int AS finding_count
        FROM inspections i
        LEFT JOIN inspection_photos p ON p.inspection_id = i.id
        LEFT JOIN damage_findings f ON f.inspection_id = i.id
        WHERE i.vehicle_id = $1
        GROUP BY i.id
        ORDER BY i.created_at DESC`,
        [vehicleId]
      );
      sendJson(res, 200, { vehicle, inspections: result.rows });
    } catch (error) {
      handleRouteError(res, error, "Could not load inspections");
    }
    return;
  }

  if (req.method === "POST" && vehicleInspectionsMatch) {
    try {
      await ensureDatabase();
      const vehicleId = vehicleInspectionsMatch[1];
      const vehicle = await getVehicle(vehicleId);
      if (!vehicle) {
        sendJson(res, 404, { error: "Vehicle not found" });
        return;
      }

      const body = await readJson(req);
      const inspection = await createInspection(vehicleId, body);
      sendJson(res, 201, { vehicle, inspection });
    } catch (error) {
      handleRouteError(res, error, "Could not create inspection");
    }
    return;
  }

  const inspectionMatch = pathname.match(/^\/inspections\/([^/]+)$/);
  if (req.method === "GET" && inspectionMatch) {
    try {
      await ensureDatabase();
      const inspection = await getInspection(inspectionMatch[1]);
      if (!inspection) {
        sendJson(res, 404, { error: "Inspection not found" });
        return;
      }
      sendJson(res, 200, { inspection });
    } catch (error) {
      handleRouteError(res, error, "Could not load inspection");
    }
    return;
  }

  if (req.method === "POST" && pathname === "/analyze") {
    try {
      if (!OPENAI_API_KEY) {
        sendJson(res, 500, { error: "Missing OPENAI_API_KEY" });
        return;
      }

      const body = await readJson(req);
      const photos = Array.isArray(body.photos) ? body.photos : [];
      const validPhotos = photos.filter((photo) => photo.id && ALLOWED_ANGLES.includes(photo.angle) && photo.imageBase64);
      console.log(`Received ${validPhotos.length} valid photo(s) for analysis`);

      if (validPhotos.length === 0) {
        sendJson(res, 400, { error: "No valid photos received" });
        return;
      }

      const findings = await analyzeVehiclePhotos(validPhotos);
      console.log(`OpenAI returned ${findings.findings?.length || 0} finding(s)`);
      sendJson(res, 200, findings);
    } catch (error) {
      console.error(error);
      sendJson(res, 500, { error: "Analysis failed", detail: error.message });
    }
    return;
  }

  sendJson(res, 404, { error: "Not found" });
});

server.listen(PORT, HOST, () => {
  console.log(`VehicleInspectorBackend listening on http://${HOST}:${PORT}`);
});

function createDatabaseClient() {
  if (!DATABASE_URL || !Pool) {
    return null;
  }

  return new Pool({
    connectionString: DATABASE_URL,
    ssl: DATABASE_URL.includes("localhost") ? false : { rejectUnauthorized: false },
  });
}

async function ensureDatabase() {
  if (!DATABASE_URL) {
    const error = new Error("Missing DATABASE_URL");
    error.status = 503;
    throw error;
  }

  if (!Pool || !db) {
    const error = new Error("PostgreSQL driver is not installed. Run npm install.");
    error.status = 503;
    throw error;
  }

  if (!dbInitPromise) {
    dbInitPromise = initializeDatabase();
  }

  return dbInitPromise;
}

async function initializeDatabase() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS vehicles (
      id TEXT PRIMARY KEY,
      vin TEXT,
      plate TEXT,
      make TEXT,
      model TEXT,
      year INTEGER,
      color TEXT,
      label TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS inspections (
      id TEXT PRIMARY KEY,
      vehicle_id TEXT NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
      status TEXT NOT NULL DEFAULT 'Needs review',
      odometer_text TEXT,
      inspector_notes TEXT,
      ai_analyzed BOOLEAN NOT NULL DEFAULT FALSE,
      summary JSONB NOT NULL DEFAULT '{}'::jsonb,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS inspection_photos (
      id TEXT PRIMARY KEY,
      inspection_id TEXT NOT NULL REFERENCES inspections(id) ON DELETE CASCADE,
      angle TEXT NOT NULL,
      image_base64 TEXT,
      image_url TEXT,
      cloudinary_public_id TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await db.query("ALTER TABLE inspection_photos ADD COLUMN IF NOT EXISTS image_url TEXT");
  await db.query("ALTER TABLE inspection_photos ADD COLUMN IF NOT EXISTS cloudinary_public_id TEXT");
  await db.query("ALTER TABLE inspection_photos ALTER COLUMN image_base64 DROP NOT NULL");

  await db.query(`
    CREATE TABLE IF NOT EXISTS damage_findings (
      id TEXT PRIMARY KEY,
      inspection_id TEXT NOT NULL REFERENCES inspections(id) ON DELETE CASCADE,
      photo_id TEXT,
      angle TEXT,
      type TEXT NOT NULL,
      severity TEXT NOT NULL,
      location TEXT NOT NULL,
      confidence NUMERIC,
      is_new BOOLEAN NOT NULL DEFAULT FALSE,
      region JSONB NOT NULL DEFAULT '{}'::jsonb,
      note TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS checklist_items (
      id TEXT PRIMARY KEY,
      inspection_id TEXT NOT NULL REFERENCES inspections(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      status TEXT NOT NULL,
      note TEXT,
      position INTEGER NOT NULL DEFAULT 0
    )
  `);
}

function normalizeVehicleInput(body) {
  const id = cleanOptionalString(body.id) || randomUUID();
  const make = cleanOptionalString(body.make);
  const model = cleanOptionalString(body.model);
  const plate = cleanOptionalString(body.plate);
  const vin = cleanOptionalString(body.vin);
  const year = Number.isInteger(Number(body.year)) ? Number(body.year) : null;
  const color = cleanOptionalString(body.color);
  const label = cleanOptionalString(body.label) || [year, make, model, plate].filter(Boolean).join(" ") || "Untitled vehicle";

  return { id, vin, plate, make, model, year, color, label };
}

function cleanOptionalString(value) {
  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

async function getVehicle(vehicleId) {
  const result = await db.query("SELECT * FROM vehicles WHERE id = $1", [vehicleId]);
  return result.rows[0] || null;
}

async function createInspection(vehicleId, body) {
  const client = await db.connect();
  const inspectionId = randomUUID();
  const photos = Array.isArray(body.photos) ? body.photos : [];
  const findings = Array.isArray(body.findings) ? body.findings : [];
  const checklist = Array.isArray(body.checklist) ? body.checklist : [];

  try {
    await client.query("BEGIN");

    const inspectionResult = await client.query(
      `INSERT INTO inspections (id, vehicle_id, status, odometer_text, inspector_notes, ai_analyzed, summary)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING *`,
      [
        inspectionId,
        vehicleId,
        cleanOptionalString(body.status) || "Needs review",
        cleanOptionalString(body.odometerText),
        cleanOptionalString(body.inspectorNotes),
        Boolean(body.aiAnalyzed),
        JSON.stringify(body.summary || {}),
      ]
    );

    for (const photo of photos) {
      if (!photo.id || !photo.imageBase64 || !ALLOWED_ANGLES.includes(photo.angle)) {
        continue;
      }

      const upload = await uploadInspectionPhotoToCloudinary({
        inspectionId,
        photoId: String(photo.id),
        angle: photo.angle,
        imageBase64: String(photo.imageBase64),
      });

      await client.query(
        `INSERT INTO inspection_photos (id, inspection_id, angle, image_base64, image_url, cloudinary_public_id)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [
          String(photo.id),
          inspectionId,
          photo.angle,
          upload.imageUrl ? null : String(photo.imageBase64),
          upload.imageUrl,
          upload.publicId,
        ]
      );
    }

    for (const finding of findings) {
      await client.query(
        `INSERT INTO damage_findings
          (id, inspection_id, photo_id, angle, type, severity, location, confidence, is_new, region, note)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)`,
        [
          randomUUID(),
          inspectionId,
          cleanOptionalString(finding.photoID),
          cleanOptionalString(finding.angle),
          DAMAGE_TYPES.includes(finding.type) ? finding.type : "Scratch",
          SEVERITIES.includes(finding.severity) ? finding.severity : "Low",
          cleanOptionalString(finding.location) || "Vehicle damage",
          clampConfidence(finding.confidence),
          Boolean(finding.isNew),
          JSON.stringify(finding.region || {}),
          cleanOptionalString(finding.note),
        ]
      );
    }

    for (const [index, item] of checklist.entries()) {
      await client.query(
        `INSERT INTO checklist_items (id, inspection_id, title, status, note, position)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [
          randomUUID(),
          inspectionId,
          cleanOptionalString(item.title) || "Checklist item",
          cleanOptionalString(item.status) || "Not checked",
          cleanOptionalString(item.note),
          index,
        ]
      );
    }

    await client.query("UPDATE vehicles SET updated_at = NOW() WHERE id = $1", [vehicleId]);
    await client.query("COMMIT");

    return {
      ...inspectionResult.rows[0],
      photos,
      findings,
      checklist,
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

async function getInspection(inspectionId) {
  const inspectionResult = await db.query("SELECT * FROM inspections WHERE id = $1", [inspectionId]);
  const inspection = inspectionResult.rows[0];
  if (!inspection) {
    return null;
  }

  const [photos, findings, checklist] = await Promise.all([
    db.query("SELECT * FROM inspection_photos WHERE inspection_id = $1 ORDER BY created_at ASC", [inspectionId]),
    db.query("SELECT * FROM damage_findings WHERE inspection_id = $1 ORDER BY created_at ASC", [inspectionId]),
    db.query("SELECT * FROM checklist_items WHERE inspection_id = $1 ORDER BY position ASC", [inspectionId]),
  ]);

  return {
    ...inspection,
    photos: photos.rows,
    findings: findings.rows,
    checklist: checklist.rows,
  };
}

function clampConfidence(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return null;
  }

  return Math.max(0, Math.min(1, number));
}

async function uploadInspectionPhotoToCloudinary({ inspectionId, photoId, angle, imageBase64 }) {
  if (!CLOUDINARY_CONFIGURED) {
    return { imageUrl: null, publicId: null };
  }

  const folder = "vehicle-inspector/inspections";
  const safeAngle = angle.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  const publicId = `${folder}/${inspectionId}/${safeAngle}-${photoId}`;
  const uploadUrl = `https://api.cloudinary.com/v1_1/${encodeURIComponent(CLOUDINARY_CLOUD_NAME)}/image/upload`;
  const form = new FormData();
  form.append("file", `data:image/jpeg;base64,${imageBase64}`);
  form.append("public_id", publicId);
  form.append("overwrite", "true");
  form.append("resource_type", "image");
  form.append("tags", "vehicle-inspector,inspection");

  const credentials = Buffer.from(`${CLOUDINARY_API_KEY}:${CLOUDINARY_API_SECRET}`).toString("base64");
  const response = await fetch(uploadUrl, {
    method: "POST",
    headers: {
      "Authorization": `Basic ${credentials}`,
    },
    body: form,
  });

  const json = await response.json().catch(() => ({}));

  if (!response.ok) {
    console.warn(`Cloudinary upload failed for photo ${photoId}: ${json.error?.message || response.status}`);
    return { imageUrl: null, publicId: null };
  }

  return {
    imageUrl: json.secure_url || json.url || null,
    publicId: json.public_id || publicId,
  };
}

async function analyzeVehiclePhotos(photos) {
  console.log(`Sending ${photos.length} photo(s) to OpenAI model candidates: ${OPENAI_MODELS.join(", ")}`);
  const findings = [];
  const failedPhotos = [];

  for (const photo of photos) {
    try {
      const result = await analyzeSingleVehiclePhoto(photo);
      findings.push(...(result.findings || []));
    } catch (error) {
      failedPhotos.push({ photoID: photo.id, angle: photo.angle, error: error.message });
      console.warn(`Skipping photo ${photo.id} (${photo.angle}) after analysis failures: ${error.message}`);
    }
  }

  if (failedPhotos.length > 0) {
    console.warn(`Analysis completed with ${failedPhotos.length} failed photo(s).`);
  }

  return { findings };
}

async function analyzeSingleVehiclePhoto(photo) {
  console.log(`Analyzing photo ${photo.id} (${photo.angle})`);
  const content = [
    {
      type: "input_text",
      text: [
        "You are a strict vehicle damage inspector.",
        `Analyze this single photo only. Photo id: ${photo.id}. Angle: ${photo.angle}.`,
        "First identify the visible vehicle surfaces and parts, then inspect only those vehicle areas.",
        "Analyze ONLY the visible vehicle, not the background.",
        "Ignore sky, clouds, trees, buildings, road, shadows, glare, reflections, dirt, water spots, camera artifacts, and objects that are not physically on the vehicle.",
        "Do not report damage unless the damaged area is clearly on the vehicle body, bumper, trim, wheel, glass, or light.",
        "Detect visible vehicle damage: scratches, dents, paint chips, cracked glass, broken lights, scuffs, and bumper damage.",
        "For dents and collision damage, look for localized panel deformation, bent metal/plastic, crushed bumper areas, warped straight reflection lines on the vehicle surface, uneven body lines, highlight distortion, concave/convex shape changes, and panel gaps that change around the damaged area.",
        "For scratches and scuffs, look for thin bright or dark lines, paint transfer, abrasion marks, scraped clear coat, or clusters of parallel marks on the vehicle surface.",
        "For paint chips, look for small areas where paint is missing and a different underlayer color is visible.",
        "Do not confuse normal body seams, door gaps, handles, trim, badges, reflections, clouds reflected on paint, or lighting gradients with damage.",
        "Do not be overly conservative: if visible evidence on the vehicle suggests probable physical damage, include it with an appropriate confidence score.",
        "If a mark is probably reflection, dirt, shadow, or background, do not include it.",
        "If the photo shows a vehicle but no clear damage, return an empty findings array.",
        "If there is obvious damage, include it even if it is small.",
        "Keep each location short, specific, and tied to a vehicle part.",
        "Use normalized image coordinates: x, y, width, height between 0 and 1.",
        "The region must tightly enclose the actual vehicle damage, not the entire vehicle or any background object.",
        "Because no previous inspection is provided yet, set isNew=true only if the damage looks recent or isolated; otherwise use false.",
        `The angle property must be exactly "${photo.angle}".`,
        `The photoID property must be exactly "${photo.id}".`,
        "If the angle is Free photo, analyze any visible vehicle area without requiring a specific view.",
      ].join("\n"),
    },
    {
      type: "input_image",
      image_url: `data:image/jpeg;base64,${photo.imageBase64}`,
      detail: "high",
    },
  ];

  let lastError;
  const modelCandidates = await getModelCandidates();

  for (const model of modelCandidates) {
    try {
      const result = await analyzeWithModel(model, content);
      const verifiedResult = await verifyVehiclePhotoFindings(photo, result, model);
      modelState.workingModel = model;
      modelState.successfulModels.add(model);
      console.log(`Model ${model} completed analysis for photo ${photo.id}: ${result.findings?.length || 0} initial, ${verifiedResult.findings?.length || 0} confirmed.`);
      return verifiedResult;
    } catch (error) {
      lastError = error;
      if (!isRecoverableModelError(error)) {
        throw error;
      }
      if (!modelState.successfulModels.has(model)) {
        modelState.unavailableModels.add(model);
      }
      if (modelState.workingModel === model) {
        modelState.workingModel = null;
      }
      console.warn(`Model ${model} failed for this request (${error.status || "no status"} ${error.code || "no code"}). Trying next candidate.`);
    }
  }

  throw lastError || new Error("No OpenAI model candidates configured");
}

async function verifyVehiclePhotoFindings(photo, result, preferredModel) {
  const initialFindings = (result.findings || []).filter((finding) => finding.confidence >= MIN_CONFIDENCE);

  if (!VERIFY_ANALYSIS || initialFindings.length === 0) {
    return { findings: initialFindings };
  }

  console.log(`Verifying ${initialFindings.length} finding(s) for photo ${photo.id}.`);

  const content = [
    {
      type: "input_text",
      text: [
        "You are the final quality-control reviewer for vehicle damage detection.",
        "Review the same vehicle photo and the candidate damage findings below.",
        "Return ONLY findings that are clearly physical vehicle damage.",
        "Discard anything that is likely reflection, shadow, glare, road/background, dirt, water spot, camera artifact, normal panel gap, body seam, handle, badge, trim line, or lighting gradient.",
        "For dents, require visible deformation such as warped body lines, bent panel/bumper shape, or distorted reflections tied to the vehicle surface.",
        "For scratches/scuffs, require visible abrasion, paint transfer, clear coat disruption, or a consistent mark on the vehicle surface.",
        "Keep true obvious damage even if it is small.",
        "You may tighten the region and lower or raise confidence.",
        "Do not invent new findings in this verification pass; only keep or refine candidates from the list.",
        "If none are clearly real damage, return an empty findings array.",
        `Photo id: ${photo.id}`,
        `Angle: ${photo.angle}`,
        `Candidate findings: ${JSON.stringify(initialFindings)}`,
      ].join("\n"),
    },
    {
      type: "input_image",
      image_url: `data:image/jpeg;base64,${photo.imageBase64}`,
      detail: "high",
    },
  ];

  const candidates = await getModelCandidates();
  const modelCandidates = [
    preferredModel,
    ...candidates.filter((model) => model !== preferredModel),
  ].filter(Boolean);

  let lastError;

  for (const model of modelCandidates) {
    try {
      const verified = await analyzeWithModel(model, content);
      return {
        findings: (verified.findings || []).filter((finding) => finding.confidence >= MIN_CONFIDENCE),
      };
    } catch (error) {
      lastError = error;
      if (!isRecoverableModelError(error)) {
        throw error;
      }
      console.warn(`Verification with ${model} failed for photo ${photo.id} (${error.status || "no status"} ${error.code || "no code"}). Trying next candidate.`);
    }
  }

  console.warn(`Verification failed for photo ${photo.id}; using initial filtered findings. Last error: ${lastError?.message || "unknown"}`);
  return { findings: initialFindings };
}

async function getModelCandidates() {
  if (!modelState.accessibleModels) {
    try {
      modelState.accessibleModels = await listOpenAIModels();
    } catch (error) {
      console.warn(`Could not refresh OpenAI model list: ${error.message}`);
    }
  }

  const accessible = new Set(modelState.accessibleModels || []);
  const configured = OPENAI_MODELS.filter((model) => {
    const appearsAccessible = accessible.size === 0 || accessible.has(model);
    const canRetry = modelState.successfulModels.has(model) || !modelState.unavailableModels.has(model);
    return appearsAccessible && canRetry;
  });

  if (modelState.workingModel && configured.includes(modelState.workingModel)) {
    return [
      modelState.workingModel,
      ...configured.filter((model) => model !== modelState.workingModel),
    ];
  }

  return configured;
}

async function listOpenAIModels() {
  const response = await fetch("https://api.openai.com/v1/models", {
    method: "GET",
    headers: {
      "Authorization": `Bearer ${OPENAI_API_KEY}`,
    },
  });

  const json = await response.json();

  if (!response.ok) {
    throw new Error(json.error?.message || `OpenAI models request failed with ${response.status}`);
  }

  return (json.data || [])
    .map((model) => model.id)
    .filter((id) => id.includes("gpt"))
    .sort();
}

async function analyzeWithModel(model, content) {
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      input: [
        {
          role: "user",
          content,
        },
      ],
      text: {
        format: {
          type: "json_schema",
          name: "vehicle_damage_analysis",
          strict: true,
          schema: responseSchema,
        },
      },
      max_output_tokens: 3000,
    }),
  });

  const json = await response.json();

  if (!response.ok) {
    const error = new Error(json.error?.message || `OpenAI request failed with ${response.status}`);
    error.status = response.status;
    error.code = json.error?.code;
    error.type = json.error?.type;
    throw error;
  }

  const outputText = extractOutputText(json);
  if (!outputText) {
    const error = new Error(`OpenAI response from ${model} did not include output text`);
    error.status = response.status;
    error.code = json.status || "missing_output_text";
    error.type = "invalid_model_response";
    throw error;
  }

  try {
    return JSON.parse(outputText);
  } catch (parseError) {
    const error = new Error(`OpenAI response from ${model} was not valid JSON`);
    error.status = response.status;
    error.code = "invalid_json";
    error.type = "invalid_model_response";
    throw error;
  }
}

function isModelAccessError(error) {
  const message = String(error?.message || "").toLowerCase();
  return (
    error?.status === 404 ||
    message.includes("does not have access to model") ||
    message.includes("model_not_found")
  );
}

function isRecoverableModelError(error) {
  return (
    isModelAccessError(error) ||
    error?.type === "invalid_model_response" ||
    error?.code === "missing_output_text" ||
    error?.code === "invalid_json" ||
    error?.code === "incomplete"
  );
}

function extractOutputText(response) {
  if (typeof response.output_text === "string") {
    return response.output_text;
  }

  for (const item of response.output || []) {
    for (const content of item.content || []) {
      if (typeof content.text === "string") {
        return content.text;
      }
    }
  }

  return "";
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let data = "";

    req.on("data", (chunk) => {
      data += chunk;
      if (data.length > 80 * 1024 * 1024) {
        reject(new Error("Request body too large"));
        req.destroy();
      }
    });

    req.on("end", () => {
      try {
        resolve(JSON.parse(data || "{}"));
      } catch (error) {
        reject(error);
      }
    });

    req.on("error", reject);
  });
}

function sendJson(res, status, payload) {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(payload));
}

function handleRouteError(res, error, fallbackMessage) {
  console.error(error);
  sendJson(res, error.status || 500, {
    error: fallbackMessage,
    detail: error.message,
  });
}

function setCorsHeaders(res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
}
