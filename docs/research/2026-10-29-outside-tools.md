# Outside tools for product stills and films, and the way back into Blender

Date: 2026-10-29. Role: researcher. Scope: one question, six parts (see headings).

Conventions. Retrieved = 2026-10-29 for every URL below unless stated. Levels follow
`docs/library/procedures/evidence-levels.md`: E2 vendor page (a claim of the vendor), E6
independent review or community test, E8 unverified. Every version, licence, price or capability
line is marked VERIFY 2026-10-29. "Unverified" = not found on the vendor's own page in this session,
reason given. Several fetches went through a summarising tool, so tables read from a page are
paraphrases; the garbled ones are flagged.

Access problems this session: autodesk.com, unrealengine.com and some maxon.net pages returned
HTTP 403 or no prices. Anything about those vendors therefore rests on secondary sources and is E8
or E6 at best, and is labelled so.

## 1. Houdini (SideFX)

### 1.1 Tiers, price, usage

| Tier | Usage | Price (USD) | Source | Level |
|---|---|---|---|---|
| Apprentice | Non-commercial only | Free (licence acquired on install) | https://www.sidefx.com/buy/ , https://www.sidefx.com/products/houdini-apprentice/ | E2 claim, VERIFY 2026-10-29 |
| Indie | Limited commercial | $299 for 1 year or $449 for 2 years (workstation) | https://www.sidefx.com/products/houdini-indie/ | E2 claim, VERIFY 2026-10-29 |
| Core | Commercial | $1995 perpetual node-locked (compare page, table text garbled) | https://www.sidefx.com/products/compare/ | E2 claim, VERIFY 2026-10-29 |
| FX | Commercial | $4495 perpetual node-locked (compare page, table text garbled) | https://www.sidefx.com/products/compare/ | E2 claim, VERIFY 2026-10-29 |
| Education (students) | Non-commercial | Annual Global Access $95 per compare page; the buy page lists no price | https://www.sidefx.com/products/compare/ , https://www.sidefx.com/buy/ | E2 claim, VERIFY 2026-10-29 |
| Education (schools) | Non-commercial | Free for instructors and secondary schools; contact SideFX | https://www.sidefx.com/buy/ | E2 claim, VERIFY 2026-10-29 |

- Billing for Core and FX: the compare page shows perpetual node-locked prices and the buy page
  mentions an Annual Upgrade Plan (AUP) that keeps bundled Karma tokens available. AUP price:
  unverified (not shown on fetched pages). Source: https://www.sidefx.com/buy/ . E2, VERIFY 2026-10-29.
- Karma renderer is bundled with Core, FX, Indie, Education and Apprentice per the buy page. E2,
  VERIFY 2026-10-29.
- Current docs are for Houdini 22.0 and list bundled libraries OpenVDB 13.0.0, USD 26.05, Alembic
  1.8.3. Source: https://www.sidefx.com/docs/houdini/licenses/index.html . E2, VERIFY 2026-10-29.

### 1.2 Commercial-use terms and restrictions

| Item | Apprentice | Indie | Core / FX |
|---|---|---|---|
| Commercial use | No: "must be used on Non-commercial projects" | Yes, if gross revenue of the entity and contracting entities does not exceed $100K USD per year and funding in the last 24 months is under $1,000,000 USD | Yes, no cap found |
| Seat limits | No floating licences | Up to 3 Indie and 3 Engine Indie per entity; second-computer licence for one artist | 5 workstation licences per studio on the buy page |
| Render resolution | 1920x1080 | Compare page says unlimited (table garbled; the Indie product page is silent) | Unlimited |
| Watermark | Rendering to formats other than .picnc is wordmarked | None stated | None stated |
| Scene format | .hipnc (also opens in Education) | Own limited-commercial format; compare page garbled on the exact extension, a community post says .hiplc | .hip |
| Third-party renderers | Not supported | Supported: RenderMan, Arnold, Redshift, V-Ray, 3Delight, Octane, plus Karma | Supported |
| Same pipeline as commercial Houdini | Not allowed | Not allowed | n/a |
| Houdini Engine assets | Assets cannot be used with Engine or Engine Indie | Engine Indie exists | Engine exists |

Sources: https://www.sidefx.com/faq/question/apprentice-restrictions/ (E2),
https://www.sidefx.com/products/houdini-apprentice/ (E2),
https://www.sidefx.com/products/houdini-indie/ (E2),
https://sidefx.com/faq/question/indie-restrictions (E2),
https://www.sidefx.com/products/compare/ (E2, garbled),
https://www.sidefx.com/forum/topic/104016/ (E8: a community member, not staff, names the
.hiplc limited-commercial format and says the finished film may be freely distributed).
All VERIFY 2026-10-29.

### 1.3 Can caches (Alembic, VDB, USD) from each tier be used in a commercial film rendered elsewhere?

What the vendor pages say: nothing explicit about caches. Neither the Apprentice, Indie, FAQ nor
buy pages mention Alembic, VDB or USD export rules. The licence agreement fetched
(https://www.sidefx.com/legal/license-agreement/ , dated 2021-10-13, text truncated) contains no
Apprentice or Indie terms. Status: unverified for all tiers (reason: vendor pages silent, EULA
text incomplete in the fetch). E2, VERIFY 2026-10-29.

What secondary sources say:

| Claim | Source | Level |
|---|---|---|
| Apprentice cannot write Alembic; a scene begun in Apprentice still cannot after opening in Indie; Alembic out only for scenes built wholly on a non-Apprentice licence | Staff replies 2017-2019 as summarised by a search tool; thread https://www.sidefx.com/forum/post/155104/ shows only the 2014 post below | E8, old, VERIFY 2026-10-29 |
| A SideFX staff post of 2014-08-07 lists "FBX and Alembic out" among the additions of Indie over Apprentice HD | https://www.sidefx.com/forum/post/155151/ and https://www.sidefx.com/forum/post/155104/ | E8 (2014, product has changed) |
| A community member says in 2023 that Apprentice cannot export Alembic while Education can, from the same .hipnc files | https://www.sidefx.com/forum/post/387781/ | E8 |
| OBJ export from Apprentice reported possible (2018) | search summary of a SideFX forum reply | E8 |
| VDB and USD export by tier | no source found | unverified |

## 2. KeyShot

### 2.1 Licence options and prices (USD, no code shown on page)

| Option | Price | Billing | Source / level |
|---|---|---|---|
| Studio Professional | $1,299.00 per year ($108.25 per user per month) | Annual; 3-year $3,897.00 | https://www.keyshot.com/pricing/ , E2 claim |
| Studio Business | $1,599.00 per year ($133.25 per user per month) | Annual; 3-year $4,797.00 | same |
| Studio Enterprise | Custom | Flexible; contact sales | same |
| Studio VR add-on | $1,188 per year | Annual | same |
| NX plugin add-on | $348 per year | Annual | same |
| Network Rendering add-on (32-core tier shown) | $749.00 per year | Annual | same |
| Cloud rendering credits | 100 credits $25.00; 500 $119.00; 1,000 $225.00 (larger packs listed) | One-time prepaid, excludes tax | same |
| Education | $95.00 per year | Annual, full-time students and faculty | same |

All VERIFY 2026-10-29. The page lists subscriptions and credits only; perpetual licences are not mentioned.

### 2.2 Strengths (vendor claims) and limits

Source: https://www.keyshot.com/features/ (E2 claims, VERIFY 2026-10-29), and
https://manual.keyshot.com/keyshot-manual/animation/ (E2).

- CAD: "34 3D file formats natively", LiveLinking with 14 CAD plugins; the page's format list is an
  image, so formats are not named in text. The same page states 36 formats in one place and 34 in
  another.
- Materials: drag-and-drop library; partner libraries named include Pantone, RAL, Mold-Tech,
  Sorensen, Coloro, INTERPON, Axalta; Professional tier adds Material Graph.
- Animation: turntables, exploded views, colourway transitions; manual lists part, camera,
  environment, material and "deformation animations" (animated geometry imported from CAD), on a
  timeline. The manual page calls animation a "Pro" feature (older tier naming possible).
- Rendering: CPU, GPU or both; AI denoise (vendor speed claims, E8).
- Liquids: not mentioned on the features page; the animation manual page lists no physics or
  simulation animation. So no native liquid simulation is documented (absence of a statement, not
  proof of absence). Pre-baked liquid geometry is rendered via Alembic, per a community forum
  post (https://community.keyshot.com/forum/t/liquid-with-bubbles-experiment/10256 , login
  redirect blocked the fetch, content known only from a search summary). E8.
- Volumes: a community user states KeyShot cannot import VDB as a per-frame sequence and does not
  support multiple channels in one VDB (search summary, source thread not identified). E8,
  unverified.

## 3. Maya with Arnold (Autodesk)

Autodesk pages returned HTTP 403 in this session. All items below rest on secondary sources or
search-tool summaries of Autodesk pages, and none is verified on the vendor page.

| Item | Statement | Source | Level |
|---|---|---|---|
| Price | $2,010 per year; $255 per month; Flex $99 minimum for 33 tokens, 6 tokens per day opened. US list, read from Autodesk buy page on 2026-09-03 by the author of the source | https://superrendersfarm.com/article/how-much-does-maya-cost | E6 (third-party, a render farm), VERIFY 2026-10-29 |
| Indie price | Not published; appears only in checkout | same | E6, VERIFY 2026-10-29 |
| Indie eligibility | Under $100,000 USD gross creative revenue in the last 12 months; original creative work only; fewer than 5 employees; not a subsidiary; annual term only, no prorated refund | https://superrendersfarm.com/article/autodesk-indie-license-guide-2026 (published 2026-03-18, updated 2026-10-26) | E6, VERIFY 2026-10-29 |
| Indie thresholds differ by country (CAD 100,000; GBP 80,000; USD 50,000 for Egypt) and a project value cap of $100,000 is mentioned | Autodesk campaign pages https://www.autodesk.com/campaigns/me-indie/maya-indie , seen only as search-tool summary (fetch 403) | E8, unverified |
| Arnold in Maya | An Autodesk help page says Arnold for Maya (mtoa.mll) ships with a default Maya install, but the local version works interactively only: batch rendering is not available and images carry a watermark unless an Arnold licence is present | https://help.autodesk.com/cloudhelp/ENU/MayaCRE-Rendering/files/GUID-AD1E74F3-471A-4B5D-8FB0-9E4EC6EC5252.htm (seen as search summary; page date unknown, may be old) | E8, unverified for 2026 |
| Arnold in Indie | "all Arnold render engine updates" are part of Indie per a third-party guide | indie guide URL above | E6 |
| Bifrost plug-ins | Maya 2026 plug-in list includes Bifrost graph, Bifrost fluid simulation framework, Bifrost Ocean, bifmeshio (per-frame .bif mesh cache), AbcExport and the Maya USD plug-in; Arnold (mtoa) is not in that list | https://help.autodesk.com/cloudhelp/2026/ENU/Maya-Customizing/files/GUID-DF9366D9-E24B-4A08-88F1-8EE1B78A52F9.htm | E2, VERIFY 2026-10-29 |
| Bifrost to Alembic | A Bifrost mesh exports via the Alembic window; "Write Color Sets" carries channels such as velocity; liquid channels include vorticity, curvature, churn; velocity is in units per second | https://help.autodesk.com/cloudhelp/2017/ENU/Maya/files/GUID-05E68AC2-9189-4381-8A42-1C4A364B95D6.htm | E2, 2017 page, VERIFY 2026-10-29 |
| Media and Entertainment Collection | Bundles Maya with Arnold and Bifrost licences (5 Arnold, Bifrost on 15 machines); price not retrieved | https://www.autodesk.com/collections/media-entertainment/included-software (search summary; fetch 403) | E8 |

Bifrost VDB and USD cache export: unverified (no Autodesk page found).

## 4. Other tools commonly used for product films

| Tool | Licence model | Facts found | Source / level |
|---|---|---|---|
| Cinema 4D with Redshift (Maxon) | Subscription, MyMaxon account and EULA; Redshift included with every Cinema 4D subscription; Maxon One bundle adds ZBrush, Red Giant, Universe, Capsules | Simulation covers cloth, rigid body, soft body, particles, smoke, flames, liquids; release 2027.0 adds Liquid FX (foam, spray, bubbles); Alembic and USD listed as supported; VDB not mentioned | https://www.maxon.net/en/cinema-4d , https://www.maxon.net/en/maxon-one ; E2, VERIFY 2026-10-29 |
| Maxon prices | No price on fetched pages. Secondary: a reseller lists Maxon One Annual at $1,265.00 (undated); a 2026-10-06 article read 1,425.57 EUR per licence per year, possibly with VAT | search summaries | E8, unverified |
| Maxon promo | 40 percent off first-year new annual subscriptions, 2026-06-22 to 2026-06-28 (ended) | https://digitalproduction.com/2026/06/24/maxon-turns-40-subs-get-lighter/ | E6 |
| Unreal Engine (Epic) | Free for companies under $1 million annual gross revenue; $1,850 per seat per year for larger non-game users (linear content, broadcast, visualisation); 5 percent royalty on games over $1 million lifetime revenue | Article dated 2024-03-12 states this; a 2026 notice reportedly ends Twinmotion and RealityScan inclusion from 2026-05-27 | https://www.engadget.com/epic-will-charge-non-game-developers-1850-per-seat-to-use-unreal-engine-162015997.html (E6); Epic pages 403; the 2026 notice is a search summary of https://www.unrealengine.com/blog/we-are-updating-unreal-engine-twinmotion-and-realitycapture-pricing-in-late-april (E8). VERIFY 2026-10-29 |
| Unreal, film exemption | A third-party summary claims no fees for linear content under the standard EULA; it conflicts with the seat fee above | search summary | E8, unverified |

## 5. Evidence on when each beats Blender

Blender-side facts used (manual, Blender 5.2 LTS pages, E2 for the Blender Foundation,
https://docs.blender.org/manual/en/latest/): built-in liquid domain with spray, foam and bubble
secondary particles, which "are not part of the mesh generation" (physics/fluid/type/domain/liquid/particles.html).

| Need | Where another tool may beat Blender | Evidence | Level |
|---|---|---|---|
| Large or art-directed liquids, pyro, caches with custom attributes | Houdini: node-based simulation, VDB and USD native; Core/FX needed for commercial, Indie under $100K cap | Houdini lists Karma bundled and third-party renderers supported (E2). No independent benchmark of Houdini vs Blender liquids found | Capability E2; superiority unverified |
| Liquids inside a DCC with a renderer you already own | Cinema 4D 2027.0 Liquid FX; Maya Bifrost | Vendor statements above | E2 claims |
| CAD import and design-change updates | KeyShot LiveLinking, 14 CAD plugins, 34 native formats | KeyShot features page | E2 claim; Blender comparison not found, unverified |
| Ready certified material libraries | KeyShot partner libraries (Pantone, RAL, Mold-Tech and others) | KeyShot features page | E2 claim |
| Animation of CAD-driven parts, quick turntables and exploded views | KeyShot timeline, one-click animations | KeyShot manual and features | E2 claim |
| Render speed | Vendor speed claims only (KeyShot AI denoise, others) | none independent found | E8 |
| Real-time or linear content in a game engine | Unreal Engine; free below $1 million revenue | Engadget 2024 | E6 |

## 6. The exchange path back into Blender

Source for all Blender behaviour below: Blender manual pages (E2, VERIFY 2026-10-29):
https://docs.blender.org/manual/en/latest/files/import_export/alembic.html ,
.../modeling/modifiers/modify/mesh_sequence_cache.html ,
.../files/import_export/usd.html ,
.../modeling/volumes/introduction.html ,
.../modeling/volumes/properties.html .

### 6.1 What survives

| Format | Survives | Does not survive or limits | Level |
|---|---|---|---|
| Alembic mesh sequence | Vertices, faces, UVs (Blender exports all UV maps although Alembic formally supports one), vertex colour attributes, custom properties (numbers, strings, lists), animated numeric properties, varying topology and file sequences via Mesh Sequence Cache; velocity for motion blur via a velocity attribute (default name `.velocities`) | No particle systems or armatures; particles exported as animated points; Face Sets carry material names only | E2 |
| USD | Meshes, curves, cameras, lights, materials, point clouds, volumes (OpenVDB prims as Volume objects); UV and primvars read as mesh attributes; velocities and generic attributes for animated geometry via Mesh Sequence Cache; Scale and metersPerUnit options | One-file-per-frame USD sequences not supported; layers and references not handled; 64-bit integer and double primvars unsupported | E2 |
| OpenVDB volume | Frame sequence of VDB files; grids `density`, `color`, `temperature` used by Principled Volume; velocity grid (one vector grid or three scalar grids with x/y/z suffixes) for motion blur, Cycles only, with Velocity Unit (per frame or per second) and Velocity Scale | Level-set grids can be read but not rendered as surfaces; OpenVDB point data not imported; sparse volumes are rendered as dense (performance and memory cost) | E2 |
| Mantaflow side note | Spray, foam and bubbles are separate from the liquid mesh | Needs geometry assigned to render | E2 |

Attributes such as wetness or foam: Alembic custom properties, USD primvars (Mesh Attributes
option) and VDB grids can reach Blender as attributes or grids. Whether a given Houdini point
attribute arrives under a usable name and domain was not verified from a vendor page (see 6.3).

### 6.2 File sizes

No measured per-frame sizes for Alembic, VDB or USD were found. Unverified (reason: sizes depend on
particle count and voxel size; no independent source with numbers). A render-farm article states
that halving voxel size multiplies memory and disk cost roughly 8 times, and recommends VDB over
.bgeo.sc for sparse fields (https://superrendersfarm.com/article/houdini-cloud-rendering-vfx-simulation-deep-dive-2026 ;
E8, search summary). Blender's Alembic page notes smooth meshes without custom normals give
smaller files (E2). Recommended test: write about 10 frames in each format and compare.

### 6.3 Pitfalls

| Pitfall | Evidence | Level |
|---|---|---|
| Time: Alembic stores seconds; Blender converts with the scene frame rate, so a mismatched scene fps changes frame alignment but not duration. Velocity Unit "Second" must be scaled by 1/FPS; "Frame" means no scaling | Blender Alembic and Mesh Sequence Cache pages | E2 |
| Velocity name: Blender reads `.velocities` by default; Houdini writes `v`. One 2021 thread (Blender 2.9) got motion blur with Houdini `v` as a point attribute; another advised keeping the default name. Results conflicted | https://blenderartists.org/t/motion-blur-on-alembic-files-from-houdini/1286707 (2021-02-21) | E6, VERIFY 2026-10-29 |
| Duplicate objects in the export (two cache files) and auto smooth on the Blender mesh broke motion blur in that thread | same | E6 |
| Velocity must exist before Alembic export (for example created with a Trail SOP) | https://www.sidefx.com/forum/post/250974 as summarised by a search tool | E8 |
| Scale: keep Alembic Scale at 1.0 to use Blender units; USD import has Scale and Apply Unit Conversion Scale (metersPerUnit) | Blender manual | E2 |
| Axis: Blender documents forward/up settings elsewhere; no Y-up/Z-up conversion statement for Houdini data was verified | none | unverified |
| Velocity grids: VDB motion blur works only in Cycles and needs the grid name set; units per frame vs per second must match the writer | Blender volume properties page | E2 |
| Alpha threshold: a thread reports geometry vanished until Alpha Threshold was set to zero in Data Passes | blenderartists thread above | E6 |

## Interpretation

Separate from the sources above; this is reasoning, not fact.

- Apprentice caches cannot safely feed a commercial film: the tier is non-commercial by licence,
  and an old but consistent set of community reports says Apprentice cannot write Alembic. Treat
  Apprentice as a prototyping tier only.
- Indie ($299 per year) is the cheapest legal route to Houdini caches for a small commercial
  film, but only below the revenue and funding caps, and the vendor pages do not say that its
  Alembic, VDB or USD output is unrestricted. The ban is on sharing a pipeline with commercial
  Houdini, which a Blender-only render path does not obviously trigger. Needs a written answer
  from SideFX before relying on it.
- For one-off liquid shots the cheapest chain looks like Blender Mantaflow first, then Houdini
  Indie only if Mantaflow quality fails a check shot. No evidence found that Houdini is better;
  the claim rests on general practice, not on a source here.
- KeyShot is a CAD-to-render tool; its documented animation is part, camera, material and
  environment motion, and no liquid simulation is documented. Its value for this template is CAD
  import and certified materials, at $1,299 per year, which is a lot compared with free Blender.
- Maya costs about $2,010 per year at list, Indie price is not public; Bifrost exists in 2026
  plug-in lists. A Maya path only makes sense if someone already holds a licence.
- Cinema 4D with Redshift and Unreal are alternatives, not needed unless a user already owns them.
  Unreal's $1,850 seat fee applies above $1 million revenue; below it, free.
- The exchange path with the fewest documented pitfalls is Alembic meshes plus an explicit
  `.velocities` or tested `v` attribute for liquid surfaces, and VDB sequences with a named velocity
  grid for smoke or fire. USD sequences are weaker (no per-frame USD file sequences).

## Open questions

1. Are Alembic, VDB and USD files written by Houdini Indie free to use in a commercial film that is
   rendered in Blender? Vendor pages are silent; the full current licence agreement must be read.
2. Which extension and restrictions apply to Indie files today (.hiplc or other), and is the Indie
   render resolution truly unlimited?
3. Does Maya's included Arnold watermark batch renders without a separate licence today? Autodesk pages
   were blocked.
4. Current US prices for Maya Indie, Maxon One, Cinema 4D and Core/FX annual upgrade.
5. Is the Y-up to Z-up conversion automatic for Houdini Alembic and USD in the current Blender?
6. Real per-frame sizes of FLIP caches in Alembic, VDB and USD for a product-scale liquid shot.
7. Does KeyShot accept VDB sequences or multi-grid VDB in 2026?

## Bears on

- The opt-in Blender product-render capability: which outside tools to list as optional, and
  which licence cautions to write into the procedure (Apprentice never for commercial caches).
- The liquid-shot procedure: decision between Mantaflow in Blender and an outside simulator.
- The check-shot procedure: add a short motion-blur test for velocity attribute names and units.
- Any template text on cost: prices here are dated 2026-10-29 and must be re-verified before
  being quoted.
