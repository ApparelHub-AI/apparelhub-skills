# Example — Front-Print T-Shirt End-to-End

A complete walkthrough for the most common workflow: user says "design me a saguaro cactus tee and sync it to my Shopify store."

This is the canonical reference example. Adapt for other front-print apparel (hoodies, tanks, sweatshirts) by swapping the `product_ref_id` and variant IDs.

---

## Setup

```bash
export APPARELHUB_API_KEY=ah_...   # required
BASE=https://api.apparelhub.ai/agents/v1
```

---

## Phase 1 — Generate the design

```bash
GEN=$(curl -sS -X POST "$BASE/images/generate" \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "vector flat illustration saguaro cactus silhouette desert sunset, warm orange and red palette, on solid bright green background #00FF00",
    "source": "Nano Banana",
    "size": "1024x1024"
  }')

GENERATED_IMAGE_UUID=$(echo "$GEN" | jq -r '.generated_image.uuid')
GENERATED_IMAGE_URL=$(echo "$GEN" | jq -r '.generated_image.url')
echo "Generated: $GENERATED_IMAGE_URL"
```

**Verify visually.** Download and view the image. Check that the cactus illustration looks good AND the background is solid green (not white, not checkerboard, not partially transparent). If the design has any text, vision-check the spelling.

---

## Phase 2 — Local transparency processing

```python
# Save as /tmp/process_design.py and run with `python3 /tmp/process_design.py`
import os
import requests
from io import BytesIO
from PIL import Image

URL = os.environ['GENERATED_IMAGE_URL']
img = Image.open(BytesIO(requests.get(URL).content)).convert('RGBA')

target = (0, 255, 0)
tolerance = 60

def color_match(p, t, tol):
    return all(abs(p[i] - t[i]) < tol for i in range(3))

new_data = []
for r, g, b, a in img.getdata():
    if color_match((r, g, b), target, tolerance):
        new_data.append((255, 255, 255, 0))
    else:
        new_data.append((r, g, b, a))
img.putdata(new_data)
img.save('/tmp/design_transparent.png', 'PNG')
print(f"Processed image saved. Size: {img.size}, transparent pixel count: {sum(1 for p in new_data if p[3] == 0)}")
```

**Upload the processed bytes:**

```bash
TRANSFORM=$(curl -sS -X POST "$BASE/images/generated/$GENERATED_IMAGE_UUID/transform" \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -F "image=@/tmp/design_transparent.png")

TRANSPARENT_IMAGE_UUID=$(echo "$TRANSFORM" | jq -r '.generated_image.uuid')
TRANSPARENT_IMAGE_URL=$(echo "$TRANSFORM" | jq -r '.generated_image.url')
```

**Use `TRANSPARENT_IMAGE_UUID` from here on, NOT the original.**

---

## Phase 3 — Generate the mockup

For Bella+Canvas 3001 (Printful product 71), standard chest-filling front print across Black + Heather Midnight Navy + White.

```bash
# Fetch the print template dimensions to be safe
PROVIDER_UUID=c8dff2fa-1a43-4734-93f0-e2ddd03eae53   # Printful prod
PRODUCT_REF_ID=71

curl -sS "$BASE/merchandise/$PROVIDER_UUID/product/$PRODUCT_REF_ID" \
  -H "x-api-key: $APPARELHUB_API_KEY" | jq '.print_templates'
# Expect: area_width=728, area_height=376 for the front placement
```

**Create the preview** with ALL 15 variant IDs in one call:

```bash
PREVIEW=$(curl -sS -X POST "$BASE/merchandise/product/preview" \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"merchandise_provider_uuid\": \"$PROVIDER_UUID\",
    \"generated_image_uuid\": \"$TRANSPARENT_IMAGE_UUID\",
    \"provider_product_ref_id\": \"71\",
    \"templates\": [
      {
        \"provider_ref_id\": \"front\",
        \"image_url\": \"$TRANSPARENT_IMAGE_URL\",
        \"area_width\": 728,
        \"area_height\": 376,
        \"width\": 600,
        \"height\": 600,
        \"top\": 0,
        \"left\": 64
      }
    ],
    \"variant_ids\": [4016, 4017, 4018, 4019, 4020, 8495, 8496, 8497, 8498, 8499, 4012, 4013, 4014, 4015, 4011]
  }")

JOB_UUID=$(echo "$PREVIEW" | jq -r '.job_uuid')
echo "Preview job: $JOB_UUID"
```

**Poll the job until completed:**

```bash
while true; do
  JOB=$(curl -sS "$BASE/merchandise/product/preview/$PROVIDER_UUID/job/$JOB_UUID" \
    -H "x-api-key: $APPARELHUB_API_KEY")
  STATUS=$(echo "$JOB" | jq -r '.status')
  echo "Status: $STATUS"
  [ "$STATUS" = "completed" ] && break
  [ "$STATUS" = "failed" ] && { echo "FAILED"; exit 1; }
  sleep 5
done
```

---

## Phase 3.5 — Wait for preview_url ingestion + verify

```bash
# Poll until at least one preview has a non-null preview_url
while true; do
  PREVIEWS=$(curl -sS "$BASE/merchandise/product/preview-job/$JOB_UUID/previews" \
    -H "x-api-key: $APPARELHUB_API_KEY")
  READY=$(echo "$PREVIEWS" | jq '[.items[] | select(.preview_url != null)] | length')
  echo "Preview rows with S3 URLs: $READY"
  [ "$READY" -gt 0 ] && break
  sleep 8
done

# Visually verify the first front-view mockup
FRONT_MOCKUP=$(echo "$PREVIEWS" | jq -r '
  [.items[] | select(.provider_preview_ref_url | contains("-front-"))][0] | .preview_url // .provider_preview_ref_url
')
echo "Inspect this mockup: $FRONT_MOCKUP"
# Download and view, or hand to a vision tool
```

---

## Phase 4.0 — Pick display_image + build gallery

```bash
# Pick display: dark front-view, prefer S3-mirrored
DISPLAY=$(echo "$PREVIEWS" | jq -r '
  [.items[]
    | select(.provider_preview_ref_url | contains("-front-"))
    | select(.provider_preview_ref_url | test("(black|navy|midnight|charcoal)"; "i"))
  ]
  | sort_by(.preview_url == null)
  | .[0]
  | (.preview_url // .provider_preview_ref_url)
')

# Build gallery: front of each color (dark first), then backs
GALLERY=$(echo "$PREVIEWS" | jq -c '
  [.items[]
    | select(.provider_preview_ref_url | contains("-front-"))
    | (.preview_url // .provider_preview_ref_url)
  ][:5] + [.items[]
    | select(.provider_preview_ref_url | contains("-back-"))
    | (.preview_url // .provider_preview_ref_url)
  ][:3]
')

echo "Display: $DISPLAY"
echo "Gallery: $GALLERY"
```

---

## Phase 4 — Create the product

```bash
PRODUCT=$(curl -sS -X POST "$BASE/product/create" \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"Saguaro Desert Sunset Tee\",
    \"description\": \"Hand-illustrated saguaro silhouette against a warm desert sunset.\",
    \"generated_image_uuid\": \"$TRANSPARENT_IMAGE_UUID\",
    \"preview_job_uuid\": \"$JOB_UUID\",
    \"provider_uuid\": \"$PROVIDER_UUID\",
    \"product_ref_id\": \"71\",
    \"price\": 27.99,
    \"display_image\": \"$DISPLAY\",
    \"gallery_images\": $GALLERY,
    \"print_data\": [
      {
        \"provider_ref_id\": \"front\",
        \"image_url\": \"$TRANSPARENT_IMAGE_URL\",
        \"area_width\": 728,
        \"area_height\": 376,
        \"width\": 600,
        \"height\": 600,
        \"top\": 0,
        \"left\": 64
      }
    ]
  }")

PRODUCT_UUID=$(echo "$PRODUCT" | jq -r '.product.uuid')
echo "Product: $PRODUCT_UUID"
```

**Field-name reminders** (FLIPPED from Phase 3):
- `provider_uuid` (NOT `merchandise_provider_uuid`)
- `product_ref_id` (NOT `provider_product_ref_id`)
- `price` (NOT `retail_price`)

---

## Phase 5 — Add variants

```bash
# Black: 4016 4017 4018 4019 4020 (S M L XL 2XL)
# Heather Midnight Navy: 8495-8499
# Solid White Blend / White: 4012-4015 + 4011

declare -A COLORS=(
  [4016]="Black:S" [4017]="Black:M" [4018]="Black:L" [4019]="Black:XL" [4020]="Black:2XL"
  [8495]="Navy:S"  [8496]="Navy:M"  [8497]="Navy:L"  [8498]="Navy:XL"  [8499]="Navy:2XL"
  [4012]="White:S" [4013]="White:M" [4014]="White:L" [4015]="White:XL" [4011]="White:2XL"
)

for vid in "${!COLORS[@]}"; do
  IFS=':' read -r color size <<< "${COLORS[$vid]}"
  curl -sS -X POST "$BASE/product/$PRODUCT_UUID/variants" \
    -H "x-api-key: $APPARELHUB_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"$color\",
      \"price\": 27.99,
      \"color\": \"$color\",
      \"size\": \"$size\",
      \"provider_variant_id\": $vid
    }" > /dev/null
  echo "Variant created: $color $size (provider $vid)"
done
```

---

## Phase 6 — Add product to the user's store

```bash
# List stores first to get the UUID
STORES=$(curl -sS "$BASE/store" -H "x-api-key: $APPARELHUB_API_KEY")
STORE_UUID=$(echo "$STORES" | jq -r '.items[0].uuid')

curl -sS -X POST "$BASE/store/$STORE_UUID/products" \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"product_uuids\": [\"$PRODUCT_UUID\"]}"
```

---

## Phase 7 — Sync to fulfillment + sales channel

```bash
# Step 1: fulfillment FIRST
curl -sS -X POST "$BASE/store/$STORE_UUID/products/$PRODUCT_UUID/sync?target=merchandise" \
  -H "x-api-key: $APPARELHUB_API_KEY"
# Wait for success before continuing

# Step 2: find the user's Shopify integration
INTEGRATION_UUID=$(curl -sS "$BASE/store/$STORE_UUID" \
  -H "x-api-key: $APPARELHUB_API_KEY" | \
  jq -r '.ecommerce_statuses[] | select(.provider_name == "Shopify") | .integration_uuid')

# Step 3: sync to Shopify as DRAFT (default — don't pass listing_state=active)
curl -sS -X POST "$BASE/store/$STORE_UUID/products/$PRODUCT_UUID/sync?target=ecommerce&integration_uuid=$INTEGRATION_UUID" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

---

## Reporting back to the user

> "Saguaro Desert Sunset Tee is live on Bella+Canvas 3001 in 3 colors (Black, Heather Midnight Navy, White) across S–2XL.
>
> - Mockup preview: `<FRONT_MOCKUP_URL>`
> - Product manager: `https://apparelhub.ai/merchandise/my-products`
> - Synced to your Shopify as a DRAFT — review and publish from your Shopify admin when ready. Or re-run sync with `?listing_state=active` to publish directly."

---

## Adapting for other front-print apparel

- **Hoodies (BC 3719 Pullover)**: change `product_ref_id`, retail price `54.99`, use the hoodie variant IDs from the catalog endpoint
- **Tanks (BC 6004)**: smaller print area, scale `width` and `left` accordingly
- **Comfort Colors tees**: change `product_ref_id`, retail price `34.99`, use Comfort Colors variant IDs
- **Different color mix**: just change the variant ID list in Phase 3 + Phase 5

Everything else in the pipeline is identical.
