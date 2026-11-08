# Render scale-out for Blender Cycles: multi-GPU, rented GPUs, render farms, determinism, cost model

Date: 2026-10-29. Role: researcher. Scope: one bounded question, five parts (see "Question").
Local reference machine: one RTX 4080 SUPER (16 GB). Nothing was signed up for, bought, rented, installed, uploaded or contacted.

Conventions: evidence levels E1-E8 from `docs/library/procedures/evidence-levels.md`. "[Sn]" points to the Sources table at the end (URL, retrieval date 2026-10-29, level). Every price, GPU spec and service feature carries `VERIFY 2026-10-29`. "unverified" means not found on the vendor's own page (or Blender Open Data) in this session, with the reason. Vendor statements are claims of the vendor, not measurements.

## Question
1. Multi-GPU in one machine for Cycles. 2. Rented GPUs by the hour. 3. Managed render farms with Blender. 4. Determinism across machines. 5. A simple cost model with a worked example (900 frames, 60 s/frame, RTX 4080-class).

## Findings

### 1. Multi-GPU in one machine

| Fact | Source | Level |
|---|---|---|
| Each GPU can only access its own memory; the exception is NVIDIA GPUs linked with NVLink, which can share memory "at a small performance cost". Quote: "Typically, no, each GPU can only access its own memory." | [S1] | E4 |
| With CUDA, OptiX, HIP and Metal, if GPU memory is full Blender tries to use system memory (slower, "usually still faster than CPU"). | [S1] | E4 |
| OptiX needs compute capability 5.0+ and NVIDIA driver 575 or newer; devices are enabled per backend in Preferences, then the scene Device is set to GPU Compute. | [S1] | E4 |
| Using one card for both display and render can make Blender unresponsive; the manual says the real fix is a separate card for each task. | [S1] | E4 |
| Vendor-run test, 2x RTX 5090, Blender 4.5 LTS, OptiX, 200% resolution, median of 3: bmw27 49.45 s -> 32.06 s (1.54x); classroom 23.09 -> 14.54 s (1.59x); junkshop 19.71 -> 15.00 s (1.31x). Same article reports 2x RTX 4090 at 1.58x / 1.63x / 1.38x (per search-result summary; table in fetched page showed the 5090 rows). Vendor says its advice is to add machines, not cards. | [S3] | E8 |
| One user, 4x RTX A6000, ~1 s frames, scene rebuilt per frame: one process on 4 GPUs 1.2 s/image; one process on 1 GPU 1.0 s/image; four processes, one GPU each, 2.7 s per image per process = ~0.67 s/image effective (about 1.5x the single GPU, not 4x). CPU near 100% on all threads. A community reply: a frame has CPU scene init, GPU render, CPU image save, so extra GPUs do not speed the CPU steps. Reply (Jan 2023): animation scales best with one instance per GPU rendering different frames, with Overwrite off and Placeholder on. | [S4] | E6 (single report) |
| Vendor blog: readers report 4x RTX 4090 only 10-25% faster than 1; one client 8 min/frame on 1 card vs 6 min on 4. Claimed fix: split the frame range, one Blender instance per GPU. Promotional, no benchmark data behind the fix. | [S5] | E8 |
| NVLink on rented consumer cards: RTX 4090 reported as PCIe-only, no NVLink (third-party tracker summary, not vendor). | [S12] | E8 |

Gaps: Blender Open Data has no multi-GPU scaling view; its pages fetched here were JavaScript shells with no data [S34]. No independent (non-vendor) multi-GPU Cycles scaling table was found.

### 2. Rented GPUs by the hour

Prices in USD per GPU-hour unless stated. All `VERIFY 2026-10-29`.

| Provider / GPU | VRAM | Price | Basis | Source | Level |
|---|---|---|---|---|---|
| RunPod RTX 4090 | 24 GB | 0.34 community; 0.89 secure | per GPU-hour, billed per second | [S6] | E2 |
| RunPod RTX 5090 | 32 GB | 0.69 community; 1.19 secure | per GPU-hour | [S6] | E2 |
| RunPod L40S | 48 GB | 0.79 community; 1.09 secure | per GPU-hour | [S6] | E2 |
| RunPod RTX A6000 | 48 GB | 0.33 community; 0.59 secure | per GPU-hour | [S6] | E2 |
| RunPod RTX 6000 Ada | 48 GB | 0.74 community; 0.99 secure | per GPU-hour | [S6] | E2 |
| Lambda RTX A6000 | 48 GB | 1.09 (1x, 2x, 4x listed) | per GPU-hour, billed by the minute, plus tax | [S13] | E2 |
| Lambda A10 / Quadro RTX 6000 | 24 / 24 GB | 1.29 / 0.69 | per GPU-hour | [S13] | E2 |
| Lambda L40S, RTX 4090, RTX 5090 | - | not listed on the pages fetched | - | [S13] | unverified (not on page) |
| Vast.ai any GPU | - | live marketplace grid, host-set; page rendered no prices | per GPU-hour, billed per second | [S9][S10] | unverified (dynamic) |
| Vast.ai RTX 4090 (third-party tracker, updated 2026-10-28) | 24 GB | 0.374 (floor, 8-GPU config) to 0.669 across 5 configs | per GPU-hour | [S12] | E8 |

RunPod storage (USD): container disk 0.10/GB/month running, not charged stopped; volume disk 0.10/GB/month running, 0.20 stopped; network volume 0.07/GB/month under 1 TB, 0.05 over 1 TB. `VERIFY 2026-10-29` [S7] E2. The RunPod pricing page card rate matched the Secure column; the Community/Secure split came from the page's structured data as read by the fetch tool [S6].

Data egress:

| Provider | Statement | Source | Level |
|---|---|---|---|
| RunPod | "no fees for data ingress or egress" `VERIFY 2026-10-29` | [S7] | E2 |
| Lambda | "no egress fees" `VERIFY 2026-10-29` | [S13] | E2 |
| Vast.ai | bandwidth billed "per byte transferred", upload and download, rate varies by host; no figure on page `VERIFY 2026-10-29` | [S10] | E2 |

Blender and custom software:

| Fact | Source | Level |
|---|---|---|
| RunPod runs Docker containers; pull from any compatible registry (Docker Hub, GHCR, ECR) and build reusable templates. `VERIFY 2026-10-29` | [S8] | E2 |
| Vast.ai instances "run your choice of Docker image"; custom templates/images supported; Data Movement and Cloud Sync (Google Drive, S3) listed. scp/rsync not confirmed on the page. `VERIFY 2026-10-29` | [S11] | E2 |
| Headless Linux Cycles on CUDA/OptiX needs no display; run with `--gpus all` via the NVIDIA Container Toolkit. Community images exist (a media company's open-source Blender headless images, tags seen only up to 3.3.1; a render-node image whose GPU testing was "work in progress"; a desktop image that does not support GPU rendering). A Blender bug report says Cycles found no device inside Docker until devices were enumerated manually. Seen in search results only (pages not fetched). | [S14] | E8 |
| Lambda: attached SSD persists between sessions; per plan 512 GiB (1x A6000) to 1 TiB (2x/4x A6000). Custom software on a VM is not described on the page; unverified. `VERIFY 2026-10-29` | [S13] | E2 |

Custom add-ons and caches: both RunPod and Vast.ai accept your own container image (above), so a compiled add-on and a cache can be baked into an image or copied to a volume. This is an inference from "custom image supported"; no page tested a Blender add-on specifically (see Interpretation). Paperspace, DigitalOcean and hyperscalers (AWS, GCP, Azure) were not researched (call budget; pricing pages are dynamic).

### 3. Managed render farms with Blender

Rates are as published; all `VERIFY 2026-10-29`. OB = OctaneBench-style benchmark unit; GarageFarm's page did not define "OB" [S15].

| Farm | Published rate | Blender versions | Add-ons | Sim caches | Upload limit | Confidentiality | Source (level) |
|---|---|---|---|---|---|---|---|
| GarageFarm | USD per OB-hour: Low 0.004, Medium 0.006, High 0.012. CPU per GHz-hour 0.024 / 0.036 / 0.072. Per-node ranges: CPU 0.66-17.27, GPU 1.12-25.76 USD per node-hour. Trial credit 25 USD (pricing page) vs 50 USD (Blender page): sources disagree. | Pricing page: not stated (benchmarks 4.2.0, 4.5.0). Blender page: "almost every version"; custom/experimental branches via support. | Custom plugin install only for Medium and High priority; FLIP Fluids named as supported; others on request. | "All cache types supported" (geometry nodes bakes, particles, Alembic); bake fluid/cloth/smoke locally first and link properly. | not stated | NDA (own or customer's, after legal review); transfers encrypted; partner ISO 27001; data kept 28 days after last job (first 7 guaranteed). | [S15][S16] (E2) |
| RebusFarm | GPU 0.53 US cent per OB-hour; CPU 1.41 US cent per GHz-hour; 1 RenderPoint = 1.18 USD; volume discount 5% (500 RP) to 60% (50,000 RP); free trial 25 RP; no minimum; price independent of machine count. | 2.79b through 5.1 incl. 4.5 LTS; "all official stable and LTS releases". | Installed add-ons work; others via support check. | Farm-side sim service not described; user must "bake simulations, caches, and time-dependent Geometry Nodes" before submit. | not stated | NDA page and data protection declaration linked, terms not read. | [S17][S18] (E2) |
| Ranch Computing | EUR excl. tax per OB-hour: Low 0.005-0.006, Medium 0.007-0.008, High 0.009-0.010 (two prices per tier, difference not labelled). CPU EUR per GHz-hour 0.011-0.016. 20% GPU discount on low and high priority GPU projects (as stated); 50% academic; 30 EUR first-project credit. Capacity: Low 40-56 cards, Medium 80, High 120. | not stated | not stated | not stated | not stated | secure transfer, per-project authentication; files available 7 days, deleted after 15 days. | [S19][S20][S21] (E2) |
| Fox Renderfarm | CPU only found: USD per node-hour Ordinary 1.224 down to Diamond 0.734 (by cumulative recharge 0 to 10,000 USD). GPU rates: unverified (tab not rendered). 25 USD trial. Formula on page: single frame cost = render time per frame x unit price x cores. | "2.63 or later" | Named plugin list (e.g. several sky, scatter, rig and water add-ons); others unverified | not stated | not stated | TPN-accredited, ISO 27001, NDAs available. | [S24][S25] (E2) |
| SheepIt | Free, volunteer machines, donation-funded. Blender 5.2 listed. | Stable releases only, "within days" | Owner cannot run own script (farm embeds its own single-frame script); add-on support not stated. | Fluid bakes "supported in theory but not recommended"; paths must be relative. | 2,048 MB per project | Not addressed on the pages read; terms and privacy policy not read. Files go to other people's machines. | [S22][S23] (E2) |
| Concierge Render | unverified: no current official page found; domain redirected to a different company's site (server-supplied redirect). Third-party listing: from 0.35 USD per GPU-hour, 5 USD credit, up to 500 GPUs per project. | unverified | unverified | unverified | unverified | unverified | [S26] (E8) |

SheepIt extras: Nvidia GPU only (AMD ended January 2023), one GPU per client; Cycles with compositing uses the "layers" frame-splitting method; OpenEXR supported with limits (full-frame, animation only, max 4096x2160) [S23] E2. Note a blog figure of 750 MB seen in search results conflicts with the FAQ's 2,048 MB; the FAQ is the vendor page and is used here.

### 4. Determinism across machines

| Fact | Source | Level |
|---|---|---|
| Seed: "Seed value for integrator to get different noise patterns". Animated Seed changes the seed per frame; manual recommends it for animation because "a varying noise pattern is less noticeable". | [S2] | E4 |
| Denoiser choices: OptiX (some older NVIDIA GPUs), OpenImageDenoise ("typically provides the highest quality"), Automatic (prefers OpenImageDenoise, GPU-accelerated when supported). A Use GPU option for denoising exists and needs extra GPU memory. | [S2] | E4 |
| Bug reports (search-result snippets only; the issue pages returned HTTP 403): two renders of the same scene on one machine can differ because path guiding is not fully deterministic, one commenter got an exact match single-threaded (#101726); CPU vs GPU inconsistency mostly with volumetrics and translucency, scenes with only diffuse, gloss, refraction, transmission were consistent (#78432, duplicate of #50193); GPU smoke noisier than CPU (T54577); a CUDA fast-math flag caused a GPU/CPU shader difference, disabling it cost about 15% speed (#53348). | [S31] | E6 (reports, not re-run) |
| 2015 developer mailing-list opinion: splitting one render between CPU and CUDA has the drawback "inconsistent random number generator across the image". Old; current behaviour may differ. | [S33] | E8 |
| Vendor claim (a farm that sells uniform hardware): mixed hardware gives "inconsistent noise distribution, depth-of-field artifacts, and visible color shifts between consecutive frames"; recommends identical hardware on all nodes. | [S32] | E8 |
| No source found stating Cycles output is bit-identical across GPU models, drivers, OSes or CPU vs GPU, and none stating it is not under controlled test. GarageFarm gives no node-consistency guidance beyond "kept up to date" and an automatic test job; Ranch renders one low-resolution frame first as a check. | [S16][S20] | E2 |

## Interpretation
Separate from the sources above; this is my reading.

- Multi-GPU in one box: speedup per frame is sub-linear (1.3-1.6x for two cards in the only measured set, vendor-run). For an animation the better unit is one Blender process per GPU, each on its own frame range, because scene init and image save are CPU-bound and serial inside one process. This matches the prior project's result: a second instance on an already saturated GPU adds nothing; a second instance only helps when it has its own GPU (or the first leaves GPU idle in CPU phases).
- VRAM: each card needs the whole scene. The scene must fit the smallest card; 16 GB local vs 24 GB (4090), 32 GB (5090), 48 GB (L40S, A6000) rented. System-memory fallback exists but slows rendering. NVLink is not needed and is not available on the consumer cards listed.
- Rented GPU + custom add-on: the practical route is a container image with the compiled add-on baked in, plus the cache on a volume. Bake first; if the cache is read by a modifier, the add-on may still be needed on the render node to load it. This is untested in this session.
- Farms: the cheapest published GPU rates (OB-hour) look similar across GarageFarm Low, RebusFarm and Ranch Low (about 0.4-0.6 US cent). They differ in what matters for a custom setup: GarageFarm names FLIP Fluids and "all cache types" but gates custom plugins to Medium/High priority; RebusFarm asks for pre-baked caches and a support check for add-ons; SheepIt cannot run a custom compiled add-on in any realistic way and is public volunteer hardware, so it is a poor fit for confidential or add-on-dependent work.
- Determinism: assume noise patterns differ across GPU models, drivers, OS and CPU vs GPU, and treat that as a risk to test, not a fact to rely on. Safer rules for a shot: one hardware class, one driver, one Blender build per shot; Animated Seed on; a fixed (not Automatic) denoiser with the same denoise device; never split one frame across CPU and GPU; render a short overlap range (for example 10 frames) on two nodes and compare before committing a full job. Frame-splitting inside a frame (SheepIt layers, farm tile splitting) is the highest-risk mode; per-frame distribution across identical nodes is the lowest.
- Speed ratios between cards come from secondary relays of Open Data and an unsourced ranking (below), so the cost model has an E8 ceiling on its estimates.

## 5. Cost model

```
cost = frames x s_per_frame_ref x (1 / speed_ratio) x price_per_hour / 3600
speed_ratio = Blender score (target card) / Blender score (reference card)
farm (per OB-hour): cost = frames x s_per_frame_ref / 3600 x OB_rating_ref x rate_per_OB_hour
```
(Farm billing counts benchmark-points x hours, so the farm cost is roughly independent of which GPU the farm assigns. Inference from the OB-hour pricing model [S15][S17][S19].)

Inputs found (Blender score, unit-less Open Data style):

| Card | Score | Source | Level |
|---|---|---|---|
| RTX 4080 SUPER | 8,163 | Relay of Blender Open Data on a third-party page, "last updated 2026-10-26"; run count not given [S27] | E6 (secondary relay; Open Data itself not readable here [S34]) |
| RTX 4090 | 11,568 (Blender 5.2.0, OptiX, 99 runs) | [S27] | E6 (secondary relay) |
| RTX 5090, L40S, RTX A6000 | 14,945 / 9,239 / 5,387 | A ranking site, "last updated Oct 2026", unit and source not stated [S29] | E8 |
| RTX 5090 (earlier) | 17,800 (Blender 3.6.0, one result) | [S28] (published 2025-01-18) | E6, weak |

Worked example: 900 frames x 60 s = 54,000 s = 15.00 h on an RTX 4080-class reference card (the local card's own cost is power only; not priced here). Prices are the RunPod rates above, USD per GPU-hour, `VERIFY 2026-10-29`.

| Target | speed_ratio vs 4080 SUPER | Hours | Community rate -> cost | Secure rate -> cost | Weakest input |
|---|---|---|---|---|---|
| RTX 4090 | 11,568 / 8,163 = 1.42 | 10.59 | 0.34 -> 3.60 USD | 0.89 -> 9.42 USD | E6 |
| RTX 5090 | 14,945 / 9,232 = 1.62 | 9.27 | 0.69 -> 6.39 USD | 1.19 -> 11.03 USD | E8 |
| L40S | 9,239 / 9,232 = 1.00 | 15.00 | 0.79 -> 11.85 USD | 1.09 -> 16.35 USD | E8 |
| RTX A6000 | 5,387 / 9,232 = 0.58 | 25.71 | 0.33 -> 8.48 USD | 0.59 -> 15.17 USD (Lambda 1.09 -> 28.02 USD) | E8 |

(Reference score 9,232 for the 4080 SUPER in the E8 rows is from the same ranking site, for a consistent ratio; the 4090 row uses the Open Data relay pair.) Results rest on the weakest input, so treat every figure as an estimate (E7/E8), not a quote. Not included: image/idle time, container start-up and upload time, storage (for example 5 GB for one day on a RunPod network volume at 0.07 USD/GB/month is about 0.01 USD), failed or re-rendered frames, taxes, and the 1.3-1.6x multi-GPU factor if several cards are rented in one pod.

Farm example (per 100 OB of reference-card rating, because the 4080 SUPER's OB rating was not found and is unverified): 15.00 h x 100 OB = 1,500 OB-hours. GarageFarm Low 0.004 -> 6.00 USD, High 0.012 -> 18.00 USD; RebusFarm 0.0053 -> 7.95 USD before RenderPoint discounts (1 RP = 1.18 USD; volume discount applies when buying RP); Ranch Low EUR 0.005-0.006 -> EUR 7.50-9.00 excl. tax. Multiply by (card OB / 100) once an OB rating is found. `VERIFY 2026-10-29`. Level: E2 price x E8 unit-assumption.

## Open questions
1. OB (or Blender Open Data score) rating of the local RTX 4080 SUPER, so farm quotes can be computed; Open Data live data was not readable in this session.
2. Do the cheaper farms (RebusFarm, Ranch, Fox) accept a compiled third-party add-on plus a baked cache, and what is the upload limit? Needs a support question or a free-trial test job (not done; no contact allowed).
3. Fox Renderfarm GPU rates, Lambda L40S/RTX 4090/5090 availability, Vast.ai live rates and bandwidth rates per TB: unverified (dynamic or unrendered pages).
4. Does a Blender container with a compiled add-on find the GPU and load a baked cache on RunPod/Vast.ai? Needs a small paid test (needs human approval).
5. Real noise difference between two GPU models for this project's materials; test with a 10-frame overlap before any mixed-hardware run.
6. Concierge Render: the official current product page and rates (identity of the service and its rates unconfirmed).
7. Paperspace, DigitalOcean and hyperscaler GPU instances were not researched.

## Bears on
- `render_estimate` tool: use the formula and price table above as inputs; store per-provider price, unit, source URL, and retrieval date; mark every price `VERIFY` with date; carry the weakest evidence level into the output; keep the speed-ratio table separate so it can be refreshed from Open Data.
- `render-wrangler` agent: one Blender process per GPU on disjoint frame ranges, Overwrite off / Placeholder on; never split a frame across CPU and GPU; pin hardware class, driver and Blender build per shot; run a 10-frame overlap check across nodes before a full job; start containers with `--gpus all` and check device detection.
- `render-technical-director` GO/NO-GO: add checks for VRAM fit per card (16 GB local), add-on and cache portability (farm support, upload size, relative paths), confidentiality terms (NDA, retention days), cost range from the worked example, and a determinism test result.
- Template docs: any farm choice involving custom add-ons needs a human decision (ADR) and a confirmed support reply.

## Sources
All retrieved 2026-10-29. Levels: E2 vendor page (claims), E4 authoritative reference, E6 community/independent report or secondary relay, E8 unverified or vendor-marketing.

| ID | URL | Level |
|---|---|---|
| S1 | https://projects.blender.org/blender/blender-manual/raw/branch/main/manual/render/cycles/gpu_rendering.rst (rendered: https://docs.blender.org/manual/en/latest/render/cycles/gpu_rendering.html) | E4 |
| S2 | https://projects.blender.org/blender/blender-manual/raw/branch/main/manual/render/cycles/render_settings/sampling.rst | E4 |
| S3 | https://superrendersfarm.com/article/multi-gpu-scaling-render-farm-benchmark-2026 (vendor-run; published 2026-06-24, updated 2026-10-04) | E8 |
| S4 | https://devtalk.blender.org/t/multi-instance-multi-gpu-rendering-is-slower-than-expected/25173 | E6 |
| S5 | https://irendering.net/how-to-fix-poor-multi-gpu-scaling-on-4-rtx-4090-in-blender-cycles/ (vendor, 2025-12-02) | E8 |
| S6 | https://www.runpod.io/pricing | E2 |
| S7 | https://docs.runpod.io/pods/pricing | E2 |
| S8 | https://docs.runpod.io/pods/overview | E2 |
| S9 | https://vast.ai/pricing | E2 |
| S10 | https://docs.vast.ai/documentation/instances/pricing | E2 |
| S11 | https://docs.vast.ai/documentation/instances/overview | E2 |
| S12 | https://computeprices.com/providers/vast/gpus/rtx4090 (tracker); NVLink remark from a search-result summary of third-party pages | E8 |
| S13 | https://lambda.ai/service/gpu-cloud and https://lambda.ai/pricing | E2 |
| S14 | https://github.com/nytimes/rd-blender-docker ; https://docs.linuxserver.io/images/docker-blender/ ; https://github.com/crowdrender/cr-docker ; https://projects.blender.org/blender/blender-addons/issues/72550 (search results only, not fetched) | E8 |
| S15 | https://garagefarm.net/pricing | E2 |
| S16 | https://garagefarm.net/blender-render-farm | E2 |
| S17 | https://rebusfarm.net/buy | E2 |
| S18 | https://rebusfarm.net/3d-software/blender-render-farm | E2 |
| S19 | https://www.ranchcomputing.com/en/prices/ | E2 |
| S20 | https://www.ranchcomputing.com/en/faq-en/ | E2 |
| S21 | https://www.ranchcomputing.com/ | E2 |
| S22 | https://www.sheepit-renderfarm.com/ | E2 |
| S23 | https://www.sheepit-renderfarm.com/faq | E2 |
| S24 | https://www.foxrenderfarm.com/blender-render-farm.html | E2 |
| S25 | https://www.foxrenderfarm.com/pricing.html | E2 |
| S26 | https://coreweave.com/blog/concierge-render-product-update-september-2020 ; https://all3dp.com/2/best-render-farm/ (search results only); https://conciergerender.com/ (redirect, not followed) | E8 |
| S27 | https://www.renderjuice.com/gpus/rtx-4090-for-blender (relays Blender Open Data) | E6 |
| S28 | https://www.notebookcheck.net/GeForce-RTX-5090-crushes-RTX-4090-in-Blender-benchmark-leads-predecessor-by-almost-37.948848.0.html | E6 |
| S29 | https://www.topcpu.net/en/gpu-r/blender | E8 |
| S31 | https://projects.blender.org/blender/blender/issues/101726 ; .../issues/78432 ; .../issues/53348 ; https://developer.blender.org/T54577 (snippets only; HTTP 403 on fetch) | E6 |
| S32 | https://irendering.net/redshift-render-farm-scaling-how-vfx-studios-handle-tight-deadlines-without-pipeline-compromise/ (vendor, 2026-09-15) | E8 |
| S33 | https://archive.blender.org/lists/bf-cycles/2015-September/002421.html | E8 |
| S34 | https://opendata.blender.org/ and https://opendata.blender.org/benchmarks/query/ (fetched; JavaScript shell, no table rendered) | unverified |
