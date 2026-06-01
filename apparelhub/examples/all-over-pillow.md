# Example — All-Over Print Pillow End-to-End

A complete walkthrough for an 18×18 square pillow with an edge-to-edge floral pattern. Same workflow applies to doormats, area rugs, and other all-over-print products — adjust dimensions and orientation per the product.

**Read `references/all-over-print.md` first.** Don't skip it.

---

## Setup

```bash
export APPARELHUB_API_KEY=ah_...
BASE=https://api.apparelhub.ai/agents/v1
PROVIDER_UUID=c8dff2fa-1a43-4734-93f0-e2ddd03eae53   # Printful prod
PRODUCT_REF_ID=214                                    # Pillow
```

---

## Phase 1 — Generate the design (DO NOT mention "pillow" in the prompt)

```bash
# WRONG: "decorative pillow with watercolor flowers"
# RIGHT: "flat watercolor wildflower pattern, edge-to-edge teal background, all-over textile graphic"

GEN=$(curl -sS -X POST "$BASE/images/generate" \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "flat watercolor wildflower pattern, scattered daisies and small pink blooms, edge-to-edge teal #1E7B7B background, all-over textile graphic, repeating motif fills entire canvas including all four corners",
    "source": "Seedream 4.5",
    "size": "1024x1024"
  }')

GENERATED_IMAGE_UUID=$(echo "$GEN" | jq -r '.generated_image.uuid')
GENERATED_IMAGE_URL=$(echo "$GEN" | jq -r '.generated_image.url')
```

**CRITICAL — verify the background reaches all 4 corners:**

```python
import requests
from io import BytesIO
from PIL import Image

URL = os.environ['GENERATED_IMAGE_URL']
img = Image.open(BytesIO(requests.get(URL).content)).convert('RGB')
w, h = img.size
corners = [(0,0), (w-1,0), (0,h-1), (w-1,h-1)]
print("Corner pixels (must all be teal-ish):")
for x, y in corners:
    print(f"  ({x},{y}): {img.getpixel((x, y))}")
```

If any corner is white, off-color, or differs significantly from the dominant background, regenerate with a more emphatic prompt or post-process locally to extend the background. **Do not proceed with an image that has white/incorrect corners** — it will print as a pillow with white borders.

---

## Phase 2 — SKIP

All-over print products use the raw image directly. No transparency processing.

`GENERATED_IMAGE_UUID` and `GENERATED_IMAGE_URL` are what you'll use downstream.

---

## Phase 3 — Generate the mockup at FULL area dimensions

For an 18×18 pillow, area = 2717 × 2717 px. The template's `width` and `height` MUST equal `area_width` and `area_height`. NEVER shrink.

```bash
# Verify the product's print template dimensions
curl -sS "$BASE/merchandise/$PROVIDER_UUID/product/$PRODUCT_REF_ID" \
  -H "x-api-key: $APPARELHUB_API_KEY" | jq '.print_templates'
# Expect: front placement with area_width=2717, area_height=2717 for 18×18

PREVIEW=$(curl -sS -X POST "$BASE/merchandise/product/preview" \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"merchandise_provider_uuid\": \"$PROVIDER_UUID\",
    \"generated_image_uuid\": \"$GENERATED_IMAGE_UUID\",
    \"provider_product_ref_id\": \"214\",
    \"templates\": [
      {
        \"provider_ref_id\": \"front\",
        \"image_url\": \"$GENERATED_IMAGE_URL\",
        \"area_width\": 2717,
        \"area_height\": 2717,
        \"width\": 2717,
        \"height\": 2717,
        \"top\": 0,
        \"left\": 0
      },
      {
        \"provider_ref_id\": \"back\",
        \"image_url\": \"$GENERATED_IMAGE_URL\",
        \"area_width\": 2717,
        \"area_height\": 2717,
        \"width\": 2717,
        \"height\": 2717,
        \"top\": 0,
        \"left\": 0
      }
    ],
    \"variant_ids\": [9515]
  }")

JOB_UUID=$(echo "$PREVIEW" | jq -r '.job_uuid')
```

For lumbar (20×12) or 22×22, swap the variant ID AND the area dimensions to match the catalog response.

---

## Phase 3.5 — Poll + verify

```bash
while true; do
  STATUS=$(curl -sS "$BASE/merchandise/product/preview/$PROVIDER_UUID/job/$JOB_UUID" \
    -H "x-api-key: $APPARELHUB_API_KEY" | jq -r '.status')
  echo "Status: $STATUS"
  [ "$STATUS" = "completed" ] && break
  sleep 5
done

# Poll for S3 ingestion
while true; do
  PREVIEWS=$(curl -sS "$BASE/merchandise/product/preview-job/$JOB_UUID/previews" \
    -H "x-api-key: $APPARELHUB_API_KEY")
  READY=$(echo "$PREVIEWS" | jq '[.items[] | select(.preview_url != null)] | length')
  [ "$READY" -gt 0 ] && break
  sleep 8
done

MOCKUP=$(echo "$PREVIEWS" | jq -r '.items[0].preview_url // .items[0].provider_preview_ref_url')
echo "Inspect: $MOCKUP"
```

**Visually verify:**
- Background reaches all four edges (no white margins on the mockup)
- Floral motifs aren't cut off at the pillow seams
- Front and back both look intentional

---

## Phase 4 — Create the product

Pricing for all-over pillows: ~$24 cost, recommended retail $44.99 for 18×18.

```bash
PRODUCT=$(curl -sS -X POST "$BASE/product/create" \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"Teal Wildflower Throw Pillow\",
    \"description\": \"Hand-painted-style watercolor wildflower motif on a deep teal field. 18×18 polyester throw pillow with concealed zipper. Edge-to-edge print on both sides.\",
    \"generated_image_uuid\": \"$GENERATED_IMAGE_UUID\",
    \"preview_job_uuid\": \"$JOB_UUID\",
    \"provider_uuid\": \"$PROVIDER_UUID\",
    \"product_ref_id\": \"214\",
    \"price\": 44.99,
    \"display_image\": \"$MOCKUP\",
    \"gallery_images\": [\"$MOCKUP\"],
    \"print_data\": [
      {
        \"provider_ref_id\": \"front\",
        \"image_url\": \"$GENERATED_IMAGE_URL\",
        \"area_width\": 2717,
        \"area_height\": 2717,
        \"width\": 2717,
        \"height\": 2717,
        \"top\": 0,
        \"left\": 0
      },
      {
        \"provider_ref_id\": \"back\",
        \"image_url\": \"$GENERATED_IMAGE_URL\",
        \"area_width\": 2717,
        \"area_height\": 2717,
        \"width\": 2717,
        \"height\": 2717,
        \"top\": 0,
        \"left\": 0
      }
    ]
  }")

PRODUCT_UUID=$(echo "$PRODUCT" | jq -r '.product.uuid')
```

---

## Phase 5 — Add the variant

Single variant for 18×18:

```bash
curl -sS -X POST "$BASE/product/$PRODUCT_UUID/variants" \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "18×18",
    "price": 44.99,
    "size": "18×18",
    "color": "Teal",
    "provider_variant_id": 9515
  }'
```

For all 3 sizes:
```bash
for vid_size in "9515:18×18:44.99" "7907:20×12 Lumbar:42.99" "11077:22×22:54.99"; do
  IFS=':' read -r vid size price <<< "$vid_size"
  curl -sS -X POST "$BASE/product/$PRODUCT_UUID/variants" \
    -H "x-api-key: $APPARELHUB_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"$size\",
      \"price\": $price,
      \"size\": \"$size\",
      \"color\": \"Teal\",
      \"provider_variant_id\": $vid
    }" > /dev/null
done
```

---

## Phase 6 + 7 — Store + sync

Identical to the front-print-tee example. Add to store, sync fulfillment FIRST, then sync to sales channel as DRAFT.

```bash
STORE_UUID=$(curl -sS "$BASE/store" -H "x-api-key: $APPARELHUB_API_KEY" | jq -r '.items[0].uuid')

curl -sS -X POST "$BASE/store/$STORE_UUID/products" \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"product_uuids\": [\"$PRODUCT_UUID\"]}"

curl -sS -X POST "$BASE/store/$STORE_UUID/products/$PRODUCT_UUID/sync?target=merchandise" \
  -H "x-api-key: $APPARELHUB_API_KEY"

INTEGRATION_UUID=$(curl -sS "$BASE/store/$STORE_UUID" \
  -H "x-api-key: $APPARELHUB_API_KEY" | \
  jq -r '.ecommerce_statuses[] | select(.provider_name == "Shopify") | .integration_uuid')

curl -sS -X POST "$BASE/store/$STORE_UUID/products/$PRODUCT_UUID/sync?target=ecommerce&integration_uuid=$INTEGRATION_UUID" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

---

## Adapting for doormats and area rugs

Doormat product 924. Key differences from a pillow:

- **Doormats MUST be landscape** — variant IDs 23705 (36×24), 23706 (60×36), 23707 (72×48)
- Use a DARK background — people step on it. Light backgrounds show dirt.
- Print area is different per size. 36×24 = 1437 × 972 px.
- No back side — single `front` template only.
- Recommended retail: $34.99 (36×24), $49.99 (60×36), $69.99 (72×48)

Adjust the prompt to describe a horizontal layout: "flat landscape graphic, horizontal welcome text reading left-to-right, edge-to-edge dark brown background."

For luggage tags (product 938), see `references/all-over-print.md` section 6 — the rounded corners + real strap hole rules make it the trickiest of the all-over products.

---

## Reporting back to the user

> "Teal Wildflower Pillow is live in 3 sizes (18×18, 20×12 lumbar, 22×22).
>
> - Mockup: `<MOCKUP_URL>`
> - Product manager: `https://apparelhub.ai/merchandise/my-products`
> - Synced to your Shopify as DRAFT — review on your Shopify admin, then publish or re-run sync with `?listing_state=active`."
