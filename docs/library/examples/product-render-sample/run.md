# Commands for the sample scene

Run from the repo root with bash. `R` is the render output root: an
absolute path outside the repo and outside cloud-synced folders. `T` is the
tools folder, `X` this folder. Every Blender run goes through `blender_run`.

    R=<absolute output root>; T=docs/library/tools; X=docs/library/examples/product-render-sample
    L="--lock $R/blender.lock.json"   # {"version": "5.2.3", "path": "<portable blender.exe>", "sha256": "<hash>"}

Gates without a GPU (stages 2 and 3, lint):

    python $T/blender_run.py $L --self-test --log $R/logs/selftest.log --record $R/records/selftest.json
    python $T/blender_run.py $L --log $R/logs/build.log $X/scene.py -- --preset $X/presets/check.json \
        --out $R/blend --save $R/blend/sample_check.blend --no-render
    python $T/blender_run.py $L --blend $R/blend/sample_check.blend --log $R/logs/extract.log \
        $T/blender_extract.py -- --out $R/records/extract.json --frames 1-120 --objects Base,Lid,Ball,HingePin --samples-every 4
    python $T/fit_check.py $R/records/extract.json --spec $X/fit.json
    python $T/camera_path.py $X/waypoints.json --fps 24 --check
    python $T/render_overlay.py --spec $X/labels.json --extract $R/records/extract.json --out $R/records/track.json
    python $T/motion_check.py $R/records/extract.json --holds 84-120 --waypoints $X/waypoints.json --track $R/records/track.json
    python $T/scene_lint.py $R/records/extract.json --preset $X/presets/check.json

Renders (long jobs; the STATE files live in `.work/jobs/render/`):

    CMD='["python", "<abs T>/blender_run.py", "--lock", "<abs R>/blender.lock.json", "--log", "{log}",
          "<abs X>/scene.py", "--", "--preset", "<abs X>/presets/<preset>.json", "--out", "{out}",
          "--first", "{first}", "--last", "{last}", "--device-type", "OPTIX"]'
    python $T/render_chunks.py plan --state <abs repo>/.work/jobs/render/<job>.json --first 1 --last 120 \
        --chunk 30 --out $R/frames/<job> --logs $R/logs/<job> --cmd "$CMD"
    scripts/bg.sh start <job> -- python $T/render_chunks.py run --state <abs repo>/.work/jobs/render/<job>.json
    python $T/render_chunks.py status --state <abs repo>/.work/jobs/render/<job>.json

Check stills (stage 4) and the seed A/B window (frames 92-103):

    python $T/blender_run.py $L --log $R/logs/check.log $X/scene.py -- --preset $X/presets/check.json \
        --out $R/frames/check --frames 1,45,70,84,100
    python $T/blender_run.py $L --log $R/logs/seedA.log $X/scene.py -- --preset $X/presets/check.json \
        --out $R/frames/seed_fixed --first 92 --last 103 --seed-mode fixed
    python $T/blender_run.py $L --log $R/logs/seedB.log $X/scene.py -- --preset $X/presets/check.json \
        --out $R/frames/seed_animated --first 92 --last 103 --seed-mode animated
    python $T/flicker_metric.py $R/frames/seed_fixed --first 92 --last 103 --grid 4x3 --compare $R/frames/seed_animated

QC, encode, verify, bundle (stages 8 and 9):

    python $T/frame_audit.py $R/frames/final --first 1 --last 120 --chunk 30 --width 960 --height 540
    python $T/color_check.py $R/frames/final --first 1 --last 120 --no-crush-check
    python $T/flicker_metric.py $R/frames/final --first 1 --last 120 --window 92-120 --grid 4x3
    python $T/render_sheets.py contact $R/frames/final --pattern frame_####.png --every 8 --first 1 --last 120 \
        --label "FINAL 960X540 512 SPP" --out $R/sheets/final_contact.png
    python $T/blender_run.py $L --log $R/logs/encode.log $T/render_encode.py -- --frames $R/frames/final \
        --pattern frame_####.png --first 1 --last 120 --fps 24 --out $R/video/final.mp4 --overlay $R/records/track.json
    python $T/encode_verify.py $R/video/final.mp4 --frames 120 --fps 24 --width 960 --height 540
    python $T/render_bundle.py --dest $R/delivery --version v1 --video $R/video/final.mp4 \
        --include $X --record $R/records/*.json
