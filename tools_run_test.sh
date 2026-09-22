#!/bin/bash
# Runs a Godot test INVISIBLY and SILENTLY via the mirror project C:/Users/super/ex-odyssey-test
# (junctions to the real folders; its project.godot = real one + no-focus/off-screen/dummy-audio overrides).
# Usage: bash /c/Users/super/ex-odyssey/tools_run_test.sh res://tests/x.tscn [extra args...]
#        bash /c/Users/super/ex-odyssey/tools_run_test.sh -s res://tests/x.gd --headless
G="/c/Users/super/Downloads/Godot_v4.6.1-stable_win64.exe/Godot_v4.6.1-stable_win64_console.exe"
T=/c/Users/super/ex-odyssey-test
VISIBLE=0; [ -f /c/Users/super/ex-odyssey/.tests_visible ] && VISIBLE=1
export VISIBLE
python - <<'PY'
import re
src=open(r"C:/Users/super/ex-odyssey/project.godot",encoding="utf8").read()
src=src.replace('config/name="EX Odyssey"','config/name="EX Odyssey"\nconfig/use_custom_user_dir=false',1)
import os
vis=os.environ.get("VISIBLE")=="1"
pos=['window/size/initial_position_type=1'] if vis else ['window/size/initial_position_type=0','window/size/initial_position=Vector2i(20000, 20000)']
over={"display":['window/size/no_focus=true']+pos+['window/size/mode=0','window/size/always_on_top=false'],
      "audio":['driver/driver="Dummy"']}
for sec,lines in over.items():
    m=re.search(r"^\[%s\]\s*$"%sec,src,re.M)
    if m: src=src[:m.end()]+"\n"+"\n".join(lines)+src[m.end():]
    else: src+="\n[%s]\n"%sec+"\n".join(lines)+"\n"
open(r"C:/Users/super/ex-odyssey-test/project.godot","w",encoding="utf8").write(src)
PY
# always refresh import + global class cache (new class_name scripts appear constantly)
"$G" --headless --audio-driver Dummy --path "$T" --import >/dev/null 2>&1
if [ "$VISIBLE" = 1 ]; then exec "$G" --audio-driver Dummy --path "$T" "$@"; fi
exec "$G" --audio-driver Dummy --position 20000,20000 --path "$T" "$@"
