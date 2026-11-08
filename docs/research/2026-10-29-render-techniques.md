# Render techniques for photoreal product stills and film in Blender Cycles

Date: 2026-10-29. Role: researcher. Scope: one bounded question (7 parts), see
the headings. Every source below was retrieved 2026-10-29. Evidence levels
follow `docs/library/procedures/evidence-levels.md` (E2/E4 official Blender
manual and developer docs; E3 papers; E6 reproducible community tests or
practitioner write-ups; E8 unverified opinion, vendor and marketing text).

Reading rules for this report:

- "VERIFY 2026-10-29" beside a source ID means a Blender setting name or
  default was read on that page on this date and must be re-checked against the
  Blender version actually installed.
- "unverified" means no page read in this session states it. The reason is
  given. Nothing unverified is used as a fact.
- Manual pages at docs.blender.org return about 200000 characters of
  navigation before the body, so bodies were read with an offset. Where a page
  excerpt did not state a default, this report says "default not stated".
- What sources say is in sections 1 to 7. My reasoning is only under
  "Interpretation".

## Version status (matters for dispersion and every default)

| Fact | Source | Level |
|---|---|---|
| The "latest" manual is titled Blender 5.2 LTS | S1 | E4 |
| The "dev" manual is titled Blender 5.3 in a search listing and Blender 5.4 on the fetched page; treat dev manual as pre-release | S2 | E4 |
| Blender 5.3 is "in beta, scheduled until November 4, 2026" (so unreleased on the retrieval date) | S6 | E4 |
| Cycles dispersion is a 5.3 feature, so it is NOT in 5.2 LTS | S5 | E4 |

## Source list (all retrieved 2026-10-29)

| ID | URL | Level |
|---|---|---|
| S1 | https://docs.blender.org/manual/en/latest/render/shader_nodes/shader/principled.html | E4 |
| S2 | https://docs.blender.org/manual/en/dev/render/shader_nodes/shader/principled.html | E4 |
| S3 | https://docs.blender.org/manual/en/latest/render/shader_nodes/shader/glass.html | E4 |
| S4 | https://docs.blender.org/manual/en/latest/render/cycles/render_settings/light_paths.html | E4 |
| S5 | https://developer.blender.org/docs/release_notes/5.3/cycles/ | E4 |
| S6 | https://developer.blender.org/docs/release_notes/5.3/ | E4 |
| S7 | https://docs.blender.org/manual/en/latest/render/cycles/render_settings/sampling.html | E4 |
| S8 | https://docs.blender.org/manual/en/latest/render/cycles/render_settings/film.html | E4 |
| S9 | https://docs.blender.org/manual/en/latest/render/cycles/optimizations/reducing_noise.html | E4 |
| S10 | https://docs.blender.org/manual/en/latest/render/cycles/object_settings/object_data.html | E4 |
| S11 | https://docs.blender.org/manual/en/latest/render/cycles/world_settings.html | E4 |
| S12 | https://docs.blender.org/manual/en/latest/render/shader_nodes/input/light_path.html | E4 |
| S13 | https://docs.blender.org/manual/en/latest/render/shader_nodes/shader/volume_absorption.html | E4 |
| S14 | https://developer.blender.org/docs/release_notes/2.93/cycles/ | E4 |
| S15 | https://developer.blender.org/docs/release_notes/4.0/cycles/ | E4 |
| S16 | https://developer.blender.org/docs/release_notes/4.0/shading/ | E4 |
| S17 | https://docs.blender.org/manual/en/latest/render/shader_nodes/input/bevel.html | E4 |
| S18 | https://docs.blender.org/manual/en/latest/modeling/modifiers/generate/bevel.html | E4 |
| S19 | https://docs.blender.org/manual/en/latest/render/cameras.html | E4 |
| S20 | https://docs.blender.org/manual/en/latest/compositing/types/transform/lens_distortion.html | E4 |
| S21 | https://docs.blender.org/manual/en/latest/render/cycles/render_settings/motion_blur.html | E4 |
| S22 | https://docs.blender.org/manual/en/latest/physics/fluid/type/domain/liquid/diffusion.html | E4 |
| S23 | https://docs.blender.org/manual/en/latest/physics/fluid/type/domain/liquid/mesh.html | E4 |
| S24 | https://docs.blender.org/manual/en/latest/physics/fluid/type/domain/settings.html | E4 |
| S25 | https://www.openimagedenoise.org/documentation.html | E4 |
| S26 | https://pubs.rsc.org/en/content/getauthorversionpdf/C5PY00773A (page itself returned 403; the values below were read in a search-result excerpt of it, not the full text) | E3 |
| S27 | https://pmc.ncbi.nlm.nih.gov/articles/PMC7693781 (peer-reviewed, Polymers 2020) | E3 |
| S28 | https://en.wikipedia.org/wiki/List_of_refractive_indices (secondary compilation) | E8 |
| S29 | https://gandh.com/news-and-resources/materials-for-polymer-optics (vendor page) | E8 |
| S30 | https://devtalk.blender.org/t/taking-a-look-at-optix-7-3-temporal-denoising-for-cycles/18656/106 (community test, posted 2022-01-07, old OptiX 7.3 and OIDN 1.4 era) | E6 |
| S31 | https://research.nvidia.com/publication/2016-06_filtering-distributions-normals-shading-antialiasing (paper: Filtering Distributions of Normals for Shading Antialiasing, HPG 2016; abstract read via search excerpt) | E3 |
| S32 | https://arxiv.org/pdf/2312.16247 (video restoration, warping error and tOF; PDF unreadable by the fetch tool, definitions taken from a search-result excerpt; preprint) | E3 (preprint) |
| S33 | https://arxiv.org/pdf/2505.00209 (warping error as mean over frame pairs, occlusion excluded; search excerpt only; preprint) | E3 (preprint) |
| S34 | https://www.blendernation.com/2024/07/25/fixing-fireflies-in-blender-renders/ | E6 |
| S35 | https://petapixel.com/how-to-create-gradients-of-light-product-photography/ (search excerpt only) | E6 |
| S36 | https://karltayloreducation.com/class/cameras-and-workflow/comment-page-2/ (photography-education reply; search excerpt only) | E8 |
| S37 | https://wiki.olympusgrp.com/production/digital/flame-polishing-acrylic (search excerpt) | E6 |
| S38 | https://www.xometry.com/resources/sheet/about-laser-cutting-acrylic/ (search excerpt) | E8 |
| S39 | https://blenderartists.org/t/how-to-model-a-proper-window-glass/597072 (forum, search excerpt) | E8 |
| S40 | https://80.lv/articles/understanding-native-dispersion-in-blender-5-3 (news article) | E8 |
| S41 | https://superhivemarket.com/products/flicker-fix (commercial add-on, vendor claim, search excerpt) | E8 |

## 1. Transparent and frosted plastic in Cycles

### 1a. IOR and optical constants

| Material | Value | Source | Level |
|---|---|---|---|
| Acrylic (PMMA) n | about 1.49; Abbe number Vd 57 to 58 | S26 (search excerpt), S29 (n only), S28 (1.4893 to 1.4899) | E3 / E8 / E8 |
| Polycarbonate n | about 1.58; Abbe number about 30 (patent range 29 to 32 seen in search results, not opened) | S26 (search excerpt) | E3 |
| Polycarbonate n range | "nd 1.58-1.64" for aromatic polycarbonates | S27 | E3 |
| Polycarbonate n (compilation) | 1.60, wavelength entry garbled | S28 | E8 |
| Water n at about 20 C | 1.333 at 589.29 nm | S28 | E8 |
| Reference wavelength | "standard refractive index measurements are taken at the sodium D line" | S28 | E8 |
| Principled IOR default | "The default value of 1.5 is a good approximation for glass"; range 1.0 to 2.0 | S1 VERIFY 2026-10-29 | E4 |
| Thin Film IOR default | 1.33, "good approximation for water" | S1, S3 VERIFY 2026-10-29 | E4 |

Interpretation of the table is under "Interpretation". The two plastics differ
by about 0.09 in n and by about 27 in Abbe number; their dispersion differs
strongly (S26).

### 1b. Thin vs solid geometry

| Statement | Source | Level |
|---|---|---|
| Principled BSDF has a "Thin Wall" option: "thickness is assumed to be zero"; useful for "papers, leaves, and window sheets" | S1, S2 VERIFY 2026-10-29 | E4 |
| In the Principled node, Subsurface Radius, Scale and Method become irrelevant when Thin Wall is on | S1 VERIFY 2026-10-29 | E4 |
| A single plane with a glass shader is treated by Cycles "as if it was infinitely thick" (forum claim) | S39 | E8 |
| For thin panes forum users replace refraction with a transparent closure; shadow darkness set by the transparent colour | S39 | E8 |
| Glass shader "can cause noise from caustics"; combine with a Transparent shader for shadows | S3 VERIFY 2026-10-29 | E4 |
| A Light Path driven glass that switches to Transparent BSDF for indirect rays keeps shadows from getting too dark without full caustics | S9 | E4 |

### 1c. Roughness for frosted, tint, anisotropy

| Statement | Source | Level |
|---|---|---|
| Glass BSDF Roughness: "Controls refraction sharpness. Sharp at 0.0, smoother at higher values" | S3 VERIFY 2026-10-29 | E4 |
| Glass BSDF distributions: GGX, Multiscatter GGX, Beckmann (Cycles only). Multiscatter gives "more energy-conserving results and less excessive darkening" | S3 VERIFY 2026-10-29 | E4 |
| Cycles 4.0 replaced the Multiscatter GGX implementation by an approximation; removes the speed and noise penalty; anisotropic materials may not be compensated perfectly | S15 | E4 |
| Roughness anisotropy now also works on Glass BSDF and on Principled transmission (5.3) | S5 | E4 |
| A frosted roughness number for acrylic or polycarbonate: unverified (no page read gives a measured value) | none | - |
| Volume Absorption node inputs Color and Density; "cites water and colored glass" as uses; Volume output must go to the Volume socket of Material Output; units of Density not stated; nothing about nested or overlapping volumes | S13 VERIFY 2026-10-29 | E4 |
| A physical absorption coefficient for a tinted clear plastic: unverified (no source read) | none | - |

### 1d. Caustics and light paths

| Statement | Source | Level |
|---|---|---|
| Light Paths > Caustics: Filter Glossy (values above 0.0 enable it; "1.0 is a good starting value to tweak"), Reflective and Refractive checkboxes to disable those caustics | S4 VERIFY 2026-10-29 | E4 |
| Max Bounces panel: Total, Diffuse, Glossy, Transmission, Volume, Transparent. Defaults not stated on the page read | S4 VERIFY 2026-10-29 | E4 |
| "Use fewer bounces. Diffuse surfaces need the fewest, glossy surfaces need a few more, and glass needs the most" | S9 | E4 |
| Shadow caustics (MNEE): per-object "Cast Shadow Caustics" and "Receive Shadow Caustics" plus a Shadow Caustic light; handles refractive caustics in object shadows only and is approximate | S10 VERIFY 2026-10-29 | E4 |
| Bevel node gives invalid results when a caustic caster, receiver and Shadow Caustic light are all active | S17 VERIFY 2026-10-29 | E4 |
| A scene-wide "No Caustics" option removes a firefly source but loses some light | S9 | E4 |

### 1e. Dispersion in the current Principled BSDF

| Statement | Source | Level |
|---|---|---|
| Dispersion was added to the Principled BSDF Transmission panel in Blender 5.3 (beta on retrieval date); Cycles only | S5, S2 VERIFY 2026-10-29 | E4 |
| Inputs named "Dispersion Scale" (range 0.0 to 1.0 in a figure caption) and "Dispersion Abbe Number"; defaults not stated | S2 VERIFY 2026-10-29 | E4 |
| Dispersion is roughly proportional to Dispersion Scale divided by Abbe Number; lower Abbe number with higher IOR gives stronger dispersion | S2 VERIFY 2026-10-29 | E4 |
| Dispersion samples visible wavelengths randomly; to reduce colour noise use more Samples and a higher Indirect Light Clamping value | S2 VERIFY 2026-10-29 | E4 |
| The 5.2 LTS Principled page contains no dispersion input | S1 | E4 |
| News article calls it an RGB-based implementation, not spectral | S40 (search excerpt, not confirmed on the fetched page) | E8 |
| Before 5.3, dispersion was faked with per-channel IOR values | S40 (search excerpt) | E8 |
| Thin Film (iridescence) exists on Principled and Glass BSDF, Cycles only; thickness in nm, 0 disables, "interference is strongest between roughly 100 and 1000 nm" | S1, S3 VERIFY 2026-10-29 | E4 |

## 2. Machined (cut) edges vs sheet faces

| Statement | Source | Level |
|---|---|---|
| Laser cutting of acrylic yields a clear, flame-polished edge; routed edges can be rough or frosted and are commonly sanded then flame polished; laser cut suited to thin sheet | S37, S38 | E6 / E8 |
| Cast and extruded acrylic differ in how edges cut and frost | S38 | E8 |
| Bevel node: shading-only rounded edges, does not change geometry; "A slight edge rounding helps catch specular highlights, as real edges do"; Samples default 4; "very expensive", about 20% slowdown, better for baking or stills; remaining noise handled with more AA samples; Cycles only | S17 VERIFY 2026-10-29 | E4 |
| Bevel node does not work with Open Shading Language on the OptiX backend | S17 VERIFY 2026-10-29 | E4 |
| Bevel modifier Limit Method: None, Angle, Weight, Vertex Group; Segments; Width and Width Type (Offset, Width, Depth, Percent, Absolute); Harden Normals needs a custom split normals attribute; Face Strength pairs with a following Weighted Normals modifier with Face Influence checked | S18 VERIFY 2026-10-29 | E4 |
| Normal Map strength interpolation was changed in 4.0 to avoid normals going below the surface for strength above 1 | S16 | E4 |
| Weighted Normal modifier page: unverified (URL returned 404; no setting names read) | none | - |
| Specular roughness numbers for a satin or sawn plastic edge: unverified (no measured source) | none | - |
| Splitting edge faces from sheet faces into separate material slots is a modelling choice; no source needed or read | - | - |

## 3. Matte black, anodised, brushed metal

| Statement | Source | Level |
|---|---|---|
| Sheen "simulates very small surface fibers"; for cloth it adds "a soft velvet like reflection near edges"; it can also simulate dust | S1 VERIFY 2026-10-29 | E4 |
| Sheen is the top layer above coat and emission, uses a microfiber model (4.0 onward); Cycles only | S16 | E4 |
| Principled Specular inputs: Distribution, IOR Level ("0.5 means no adjustment"), Tint, Anisotropy (0.0 to 1.0), Anisotropic Rotation, Tangent; anisotropy is Cycles only | S1 VERIFY 2026-10-29 | E4 |
| Anisotropic direction depends on a tangent input; effect not shown in EEVEE (forum report) | search excerpt, URL not opened | E8 |
| Specular aliasing arises from "very small, bright glossy highlights" much smaller than a pixel; filtering the normal distribution makes shading "temporally stable" (real-time method) | S31 | E3 |
| Anodised aluminium base colour, roughness, metallic values: unverified (no source read) | none | - |
| Matte black plastic base colour value that avoids grey: unverified (no source read; only manual advice below) | none | - |
| "Try to keep the maximum value [of shader colour components] to 0.8 or less and make your lights brighter" | S9 | E4 |

## 4. Studio lighting

| Statement | Source | Level |
|---|---|---|
| Area light Spread: "simulate the effect of a honeycomb or grid placed in front of a softbox"; 180 degrees is the diffuse emitter, lower angles are more focused; added 2.93 | S14 | E4 |
| The 5.2 area light manual section read does not mention Spread; Spread default and range: unverified | S1 sibling page https://docs.blender.org/manual/en/latest/render/lights/light_object.html | E4 |
| Area light shapes: Rectangle, Square, Disk, Ellipse; "choosing the appropriate shape will enhance the believability" | same light_object page | E4 |
| Light linking arrived in 4.0: lights affect only chosen objects; shadow linking controls shadow blockers; linking to world lighting was "planned for a future version" in the 4.0 notes | S15 | E4 |
| Object settings in 5.2: Light Linking uses "Receiver Collection" and "Shadow Blocker Collection" | S10 VERIFY 2026-10-29 | E4 |
| Object Ray Visibility: Camera, Diffuse, Glossy, Transmission, Volume Scatter, Shadow; "more efficient than a shader node setup" | S10 VERIFY 2026-10-29 | E4 |
| World: visibility per ray type is done with a Mix node driven by Light Path "Is Camera Ray"; adding "Is Glossy Ray" makes the high-resolution image visible in reflections; the World page read lists no per-ray toggles | S11 VERIFY 2026-10-29 | E4 |
| Light Path outputs: Is Camera Ray, Is Shadow Ray, Is Diffuse Ray, Is Glossy Ray, Is Singular Ray, Is Reflection Ray, Is Transmission Ray, Is Volume Scatter Ray | S12 VERIFY 2026-10-29 | E4 |
| Light Tree "doesn't account for custom falloff, ray visibility, or complex shader setups with textures" | S7 VERIFY 2026-10-29 | E4 |
| Shadow Catcher: object receives only shadow rays; output depends on the Shadow Catcher pass | S10 VERIFY 2026-10-29 | E4 |
| Gradients on glass come from a diffuser between a strip light and the subject; reflected softboxes show hard edges on glossy parts; grids on strip boxes control spill; a gridded spot gives "nasty spots on the glass" (practitioner view) | S35 | E6 |
| Light Falloff node "Smooth factor" caps how much a light contributes to nearby surfaces | S9 | E4 |
| A dark floor with readable shadows, and the gridded-softbox size and distance numbers: unverified (no source read) | none | - |

## 5. Real-lens camera

| Statement | Source | Level |
|---|---|---|
| Products: wide angles are avoided because they distort; sweet spot near 100 mm full frame (about 80 mm on APS-size) | S36 | E8 |
| 90 to 105 mm leaves room for lighting; a 60 mm macro forces close working distance | S36 (search excerpt) | E8 |
| Camera Depth of Field: Focus Object (deactivates Focus Distance), Focus Distance, Aperture panel with F-Stop ("lower values give a stronger effect"), Blades (minimum 3), Rotation, Ratio (1.0 none) | S19 VERIFY 2026-10-29 | E4 |
| Sensor Fit: Auto, Horizontal, Vertical; Size/Width/Height "useful for matching a real camera and lens" | S19 VERIFY 2026-10-29 | E4 |
| Shift keeps horizontal lines level, unlike rotating the camera | S19 | E4 |
| Default sensor size and Focal Length field text: unverified (not in the page excerpt read) | none | - |
| Compositor Lens Distortion node: Type Radial or Horizontal; Distortion; Dispersion ("creating a rainbow colored fringe", simulates chromatic aberration); Jitter (faster, noisier); Fit | S20 VERIFY 2026-10-29 | E4 |
| A native vignette node: unverified (not searched; a vignette can be a mask plus Mix, see Interpretation) | none | - |
| Pixel filter default is Blackman-Harris; Width has lower = crisper, higher = softer and less aliasing; default width not stated | S8 VERIFY 2026-10-29 | E4 |

## 6. Liquid realism

| Statement | Source | Level |
|---|---|---|
| Water IOR 1.333 at 589.29 nm | S28 | E8 |
| Viscosity in Blender is kinematic; water: Viscosity Base 1.002, Exponent 6 (1.002 x 10^-6 m2/s); dynamic 1.002 cP at 20 C | S22 VERIFY 2026-10-29 | E4 |
| Surface Tension is in grid units, "Higher value will produce liquids with greater surface tension"; no default or water value given | S22 VERIFY 2026-10-29 | E4 |
| Mesh panel: Upres Factor, Particle Radius (grid-cell units, shared with the domain value), Smoothing Positive (smoother, can remove small drops), Smoothing Negative (sharper, more ragged), Concavity Upper and Lower (higher values smooth and fill concave regions; lower greater than upper gives "distorted, non-manifold meshes"), Mesh Generator Final or Preview | S23 VERIFY 2026-10-29 | E4 |
| Speed Vectors creates a `velocity` attribute for motion blur; Cycles also needs Deformation Motion Blur | S23 VERIFY 2026-10-29 | E4 |
| Domain: Resolution Divisions, Time Scale, CFL Number, Timesteps Maximum and Minimum, Narrow Band Width ("keep it as thin as possible"); defaults not stated | S24 VERIFY 2026-10-29 | E4 |
| Thin film on a surface: Principled and Glass BSDF Thin Film inputs, thickness nm, film IOR 1.33 (water) | S1, S3 VERIFY 2026-10-29 | E4 |
| Splash and secondary particles (spray, foam, bubbles) settings: unverified (page not read) | none | - |
| Wetting (contact angle, thin water sheets on a surface) and a drying fade: unverified (no source found) | none | - |
| Numeric settings that make a liquid read as water rather than gel (particle count, upres, smoothing counts): unverified (only forum reports of "ketchup" look at high viscosity were seen, not opened) | none | - |
| Particles and physics should be baked, else motion blur may be incorrect or inconsistent | S21 VERIFY 2026-10-29 | E4 |

## 7. Temporal stability (flicker)

### 7a. Causes and remedies as sourced

| Statement | Source | Level |
|---|---|---|
| Seed: "Use Animated Seed changes the seed each frame, which the page recommends for animations" | S7 VERIFY 2026-10-29 | E4 |
| Counter-evidence: with Animated Seed off, OptiX temporal denoising looked more stable but produced structured patterns across frames, worst at low samples; adaptive sampling "kind of acts like an animated seed"; tested on old OptiX 7.3 and OIDN 1.4 | S30 | E6 |
| OIDN docs: the RT filter "is not temporally stable"; no animation section exists | S25 | E4 |
| OIDN: albedo and normal "should be first denoised in a prefiltering step", then pass with `cleanAux` (default false); denoising with noisy auxiliary features "reserved for previews"; `quality` HIGH is the default and is for final frames | S25 | E4 |
| Blender Denoise: Denoiser Automatic, OpenImageDenoise ("typically the highest quality"), OptiX (NVIDIA only); Passes None, Albedo, Albedo + Normal (page recommends at least Albedo); Prefilter None, Fast, Accurate; Quality High, Balanced, Fast; Use GPU | S7 VERIFY 2026-10-29 | E4 |
| Adaptive Sampling: Noise Threshold "typical values 0.1 to 0.001"; 0 means automatic estimate; Min Samples default 0 (automatic); Time Limit | S7 VERIFY 2026-10-29 | E4 |
| Path Guiding: CPU only; Training Samples 0 trains to the end, "128 to 256 is usually enough"; Surface and Volume toggles | S7 VERIFY 2026-10-29 | E4 |
| Clamping: Direct Light and Indirect Light, 0.0 disables; clamping dims bright lights; clamp indirect separately because it causes more fireflies | S4, S9 VERIFY 2026-10-29 | E4 |
| Fireflies come from caustics and tiny intense lights; clamp too low "sucks the life out of the image" (practitioner view); lower gradually | S34 | E6 |
| Pixel filter: Box (none), Gaussian, Blackman-Harris (default); width lower = crisper | S8 VERIFY 2026-10-29 | E4 |
| Motion blur: Position (Start, Center, End), Shutter in frames (1.0 = one frame), Rolling Shutter, Shutter Curve; defaults not stated | S21 VERIFY 2026-10-29 | E4 |
| Dispersion adds colour noise needing more samples and a higher indirect clamp | S2 VERIFY 2026-10-29 | E4 |
| Light Tree can reduce noise at more cost per sample; ignores ray visibility | S7 VERIFY 2026-10-29 | E4 |
| Filter Glossy blurs glossy reflections after rough bounces; start at 1.0 | S4 VERIFY 2026-10-29 | E4 |
| A commercial add-on offers a 3-frame temporal median filter against flicker (vendor claim) | S41 | E8 |
| Averaging several low-sample renders with different seeds loses energy (forum claim) | search excerpt, URL not opened | E8 |
| Noise-vs-sample count needed for transparent/frosted (the "roughly double" lesson), filter width 1.75 px: unverified (no source; filter width default not stated on the page) | none | - |
| Studio-internal flicker measurement practice: unverified (no public source found) | none | - |

### 7b. Published temporal metrics

| Metric | What it is | Source | Level |
|---|---|---|---|
| Warping error | pixel-wise difference between a frame and the previous frame warped by estimated optical flow, occluded regions excluded, averaged over consecutive pairs | S33 (search excerpt) | E3 (preprint) |
| Relative warping error (RWE) | warping error minus the same value for the reference frames, because raw warping error is non-zero even for ground truth | S32 (search excerpt) | E3 (preprint) |
| tOF | compares optical flow of the output sequence against flow of the ground truth | S32 (search excerpt) | E3 (preprint) |
| Caveat | optical flow is unreliable on noisy input, so flow estimated on the noisy frames can corrupt the metric | search excerpt of a patent, not opened | E8 |

## Lessons from the prior project vs the sources

| Lesson | Verdict | Basis |
|---|---|---|
| Split cut edges from sheet faces, satin edges | Confirmed in kind: sawn or routed acrylic edges are frosted, laser edges are clear. The right finish depends on the cutting process | S37, S38 (E6/E8) |
| Small bevel on every edge | Confirmed: the manual says edge rounding "catches specular highlights, as real edges do". Node vs geometry is the open choice | S17 (E4) |
| Slight glass-like tint | No source on values; absorption node is the documented route | S13 (E4) |
| Gridded softbox, rim lights read as a fake white sheet | Confirmed: softboxes reflect with hard edges on glossy parts; grids control spill; Spread emulates a grid | S35 (E6), S14 (E4) |
| HDRI visible to glossy rays only | Supported: Light Path Is Camera Ray and Is Glossy Ray switch the visible background; documented mix trick, no world toggle found on the page | S11, S12 (E4) |
| Matte black needs no sheen | Consistent: sheen is documented as fibre or dust | S1 (E4) |
| No film grain on finals; accurate denoise | Consistent with OIDN prefilter advice; not contradicted | S25, S7 (E4) |
| Animated seed off to avoid vibrating grain | Contradicted by the manual's recommendation and only partly supported by one old community test. Needs a measured A/B | S7 (E4), S30 (E6) |
| Roughly double samples for transparent/frosted | No source; unverified | - |
| Filter width about 1.75 px | No source for the value; direction (wider = softer, less aliasing) confirmed | S8 (E4) |
| Clamp indirect, cap procedural detail | Clamping confirmed. Procedural-detail cap is consistent with the specular-aliasing paper but unmeasured in Cycles | S4, S9, S31 |
| Motion blur on | Documented; stability benefit not sourced | S21 (E4) |

## Interpretation (mine, not from sources)

- Acrylic at n about 1.49 and polycarbonate at about 1.58 are close enough that
  the Principled default of 1.5 is a fair start for acrylic. For polycarbonate
  set the IOR explicitly and, in 5.3, set the Abbe number near 30 versus about
  57 for acrylic to make dispersion differ between the two parts.
- For parts a few millimetres thick, a closed solid with an interior volume
  (absorption) behaves more physically than Thin Wall, which has zero
  thickness and therefore no tint depth. Thin Wall is appropriate for film-thin
  parts only. Both choices are untested here.
- Frosted clear plastic is probably best built as Glass or Principled
  transmission with roughness raised, since manual roughness semantics are
  "refraction sharpness". The value must be found by a look-development
  comparison, not from a table.
- Dispersion in 5.3 and a Compositor Lens Distortion Dispersion are two
  different effects: one is inside the material and cheap to see in thick
  parts, the other is a lens-style edge fringe. A single, small amount of
  lens dispersion avoids the noise cost of material dispersion.
- Because the Light Tree ignores ray visibility (S7), a light made invisible
  to camera or glossy rays may sample worse with Light Tree on. Test this
  before locking a rig.
- Light linking exists for lights, not the world (S15); the HDRI-for-glossy
  rays trick must therefore use the shader-side Light Path switch.
- Fixed seed removes the changing noise pattern but leaves a static pattern
  that can look like a dirty screen; animated seed changes it every frame but
  can look like boiling grain. Neither is known best; the cure is enough
  samples that the choice is invisible, plus OIDN with prefiltered albedo and
  normal. This must be checked with a measurement.
- A practical flicker_metric: render a locked-camera sequence, mask moving
  and edge regions, compute per-pixel temporal standard deviation of
  luminance in static regions and a warping-error value on the denoised
  frames using flow from clean passes (albedo or normal) instead of the noisy
  beauty. Compare against a high-sample reference (RWE style). This is
  derived from S32, S33 and not a studio standard.
- A vignette can be a radial mask multiplied in the compositor; it needs no
  special node. Unverified as a Blender-specific recipe.

## Open questions

1. Is Blender 5.3 final in time for this template, and what are the defaults
   of Dispersion Scale and Dispersion Abbe Number? (Read the final manual.)
2. What are the Max Bounces, Clamping, Filter Width and Noise Threshold
   defaults in the installed version? None were stated on the pages read.
3. Is a fixed or an animated seed better for OIDN in current Cycles? Needs an
   A/B with a flicker metric on the same scene.
4. Does the Bevel node (random samples per shading point) add temporal noise
   compared with a geometry bevel plus Harden Normals and Weighted Normals?
   The Weighted Normal modifier page could not be read.
5. What roughness and absorption numbers read as satin edge, frosted face
   and tinted clear plastic? Needs a measured or photographed reference.
6. Is there a per-ray-type visibility toggle for the World in 5.2 or later, or
   is the Light Path mix the only route? The page read lists none.
7. Which fluid secondary-particle and wetting settings read as water on a
   product surface, and is a shader-driven drying fade better done with a
   wetness mask driven by a texture or by the sim? No source found.
8. Does the camera Sensor Size default and the vignette recipe need a source
   before they are written into presets?

## Bears on

- A lookdev material library: acrylic, polycarbonate, frosted, tinted clear,
  matte black without sheen, anodised, brushed metal (anisotropy), satin
  cut-edge material; IOR and Abbe number table (S26, S28); Thin Wall vs solid
  rule; dispersion option gated on Blender 5.3.
- A cinematographer lighting rig: gridded strip and softbox area lights with
  Spread (S14), diffuser gradient, rim lights hidden from glossy and
  transmission rays by Light Path switches (S10, S12), light linking (S15),
  dark floor, shadow catcher.
- Render presets: final preset with OIDN High quality, Passes Albedo + Normal,
  Prefilter Accurate (S7, S25), indirect clamp, Filter Glossy, caustics off or
  MNEE, pixel filter width, motion blur on, no film grain, seed policy
  pending open question 3.
- A flicker_metric tool: temporal std in static regions and warping error or
  RWE (S32, S33), run on denoised frames, with a locked-camera test clip.
- A scene_lint check: Thin Wall vs solid mismatch, Bevel node with caustic
  setup (S17), sheen above 0 on a matte-black material, Principled IOR left at
  default on polycarbonate, dispersion node use when Blender is below 5.3,
  Light Tree with ray-visibility-limited lights, Concavity Lower above Upper
  in a fluid domain (S23), missing Speed Vectors with fluid motion blur (S23).
- A camera preset: 85 to 100 mm, F-Stop and Focus Object, Lens Distortion
  Dispersion small, vignette (S19, S20, S36).
