# Design Rules

Universal rules that apply to ANY design you generate via ApparelHub. Read this before Phase 1 of any new product.

---

## 1. NEVER generate apparel-as-image

The image IS the design that goes ON the product. The garment is the medium, not the subject.

| ❌ Wrong | ✅ Right |
|---|---|
| "A t-shirt with a saguaro cactus on it" | "A saguaro cactus silhouette illustration" |
| "Mockup of a hoodie with mountains" | "Stylized mountain range illustration" |
| "A coffee mug with a cat design" | "Sleeping cat illustration in vintage line-art" |

If the user prompts you with "make me a t-shirt with X", REPHRASE silently before sending to the image API. Generate the design, then put it on the product in Phase 3.

---

## 2. The "don't name the product in the prompt" trap

AI image generators interpret product names too literally. Saying "luggage tag" in the prompt produces a *picture of a luggage tag* — chamfered corners, faux strap hole, ornamental edges — which then prints on a real luggage tag and produces image-on-top-of-image artifacts.

This generalizes. NEVER include the product's literal name in the prompt:

| Product | ❌ Avoid in prompt | ✅ Use instead |
|---|---|---|
| Luggage tag | "luggage tag design" | "flat luxury monogram emblem on burgundy" |
| Pillow | "pillow design" | "flat all-over pattern, edge-to-edge color" |
| Doormat | "doormat design" | "flat landscape graphic, horizontal text, edge-to-edge" |
| T-shirt | "t-shirt design" | "isolated chest-print graphic" (plus the transparency phrasing below) |
| Phone case | "phone case design" | "flat back-print graphic with [color] fill edge-to-edge" |
| Mug | "mug design" / "coffee cup design" | "wraparound graphic strip" or "centered illustration on solid [color]" |

**Diagnostic shape**: if the AI output looks like a shrunken version of the FINAL PRODUCT (has the product's outline, hardware like straps/holes/buttons, decorative edges that match the product's physical edges), the prompt was too literal. Rewrite to describe what's PRINTED ON the product, not the product itself, and regenerate.

---

## 3. Transparent backgrounds — ALWAYS prompt for solid bright green

AI image models cannot produce true transparency. They either render white pixels or bake a fake checkerboard pattern into the RGB pixels. When you later try to remove the background, the result is messy.

**Always prompt for a solid contrasting background — bright green `#00FF00`** — and strip it locally in Phase 2:

```
...on solid bright green background #00FF00
```

Why green specifically:
- Distinct from any natural design content (almost no apparel design legitimately includes pure `#00FF00`)
- High contrast against anti-aliased design edges
- Flood-fills cleanly with no ambiguity between background and design pixels

The actual keying is done in Phase 2 by the bundled `scripts/make_transparent.py` — see `references/product-creation-pipeline.md`. Note the AI rarely returns *exactly* `#00FF00` (corners often come back muted, e.g. `#52C06E`); the script auto-detects the real corner color, so don't assume pure green.

For all-over-print products (pillows, doormats, AOP tees, luggage tags): SKIP this rule. Those need the design to cover edge-to-edge including the background. See `references/all-over-print.md`.

For embroidery: same rule applies — transparent backgrounds work (the bare garment fabric shows through where the design is transparent). See `references/embroidery.md`.

---

## 4. Verify text in designs with vision tools BEFORE Phase 3

AI image models routinely misspell. If the user asked for "STAY WILD" and the image renders "STAY WLID", that error propagates through the mockup into the product into the customer's hands.

**Always run a vision check** on Phase 1 output if the design contains text. If anything is misspelled, regenerate before generating the mockup.

Provider ranking for text accuracy:
1. **Nano Banana** (best)
2. Seedream 4.0
3. Seedream 4.5
4. Flux 1.1 Pro
5. OpenAI (worst — avoid for text)

If multiple regenerations fail to produce correct text, switch sources before increasing prompt verbosity. Some models just can't do text reliably.

---

## 5. AI source selection — which model for which job

Pass the source as the human-readable NAME string, not a UUID.

| Type of design | Recommended source |
|---|---|
| Photorealistic, exact prompt matching | `Nano Banana` or `Seedream 4.5` |
| Design with text (slogans, brand names, monograms) | `Nano Banana` (best) → `Seedream 4.0` (second) |
| Abstract / geometric / shapes / colors | `OpenAI` |
| Lifestyle / nature / animals | `Nano Banana`, `Seedream 4.5`, `Google Imagen 4` |
| Cinematic / mood-heavy / atmospheric | `Flux 1.1 Pro` |
| Vector flat illustration (silhouettes, line art) | `Nano Banana` or `Seedream 4.5` |

When in doubt, default to `Nano Banana` — it's the most consistent across categories.

---

## 6. Color discipline — max 4 colors per design

More than 4 color variants per design creates SKU sprawl that hurts conversion. Pick the 4 best colors for the design and stop.

For dark designs (heavy black/dark linework): Black + 2 dark colors + White
For light designs (line art on light fields): White + 2 light/neutral colors + Black (for contrast)
For colored designs: pick colors that complement the dominant design color, not compete with it.

---

## 7. Mockup verification gate

After Phase 3 (mockup generation), ALWAYS visually inspect the result before proceeding to Phase 4 (product create).

Check for:
- Design renders correctly (not cut off, not distorted)
- Text legible and spelled correctly
- No white halos around transparent edges
- No checkerboard artifacts where transparency should be
- Color contrast is acceptable on the chosen garment
- Design isn't tiny (chest emblem when you wanted chest-filling) or oversized (overflowing the print area)

If anything looks wrong, FIX the design and re-mockup before continuing. Manufacturing follows the mockup.

---

## 8. Pricing discipline — never price below cost + margin

The merchant loses money on negative-margin products. See `references/garment-catalog.md` for current pricing floors per garment.

Margin math:
```
Profit = (Retail Price + Customer Shipping)
       - Fulfillment Cost (Printful/Printify)
       - Fulfillment Shipping (~$5.90)
       - Sales Channel Fee (~3.9% of total)
       - Creator Commission (if applicable, 40% standard)
```

Standard shipping: $8.00 to customer, free over $70.

---

## 9. Default to DRAFT when syncing to sales channels

For channels that support draft state (Etsy, Shopify), push as draft first. The merchant reviews on the channel's admin before customers see it. Only push as `active` when the user EXPLICITLY says "make it live."

The cost of a too-eager publish (typo'd description in front of real customers) is much higher than one extra step.
