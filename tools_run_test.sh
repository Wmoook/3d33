#!/bin/bash
# Runs a Godot test INVISIBLY and SILENTLY via a mirror project next to this repo (<repo>-test: junctions to
# the real folders; its project.godot = the real one + no-focus / off-screen / dummy-audio overrides).
# The mirror is created automatically on first use, so a fresh clone on another PC works as-is.
# Godot binary: $GODOT_BIN if set, else the usual download path, else any Godot_v4.6.1 console exe under
# ~/Downloads, else `godot` on PATH.
# Usage: bash tools_run_test.sh res://tests/x.tscn [extra args...]
#        bash tools_run_test.sh -s res://tests/x.gd --headless
# Visible mode (watch the test render): create an empty file .tests_visible in the repo root.
R="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="${R}-test"

G="${GODOT_BIN:-}"
if [ -z "$G" ] || [ ! -x "$G" ]; then
	G="$HOME/Downloads/Godot_v4.6.1-stable_win64.exe/Godot_v4.6.1-stable_win64_console.exe"
fi
if [ ! -x "$G" ]; then
	G="$(find "$HOME/Downloads" -maxdepth 3 -iname 'Godot_v4.6.1*console*.exe' 2>/dev/null | head -1)"
fi
if [ -z "$G" ] || [ ! -x "$G" ]; then
	G="$(command -v godot || command -v godot4 || true)"
fi
if [ -z "$G" ]; then
	echo "tools_run_test.sh: Godot 4.6.1 not found - set GODOT_BIN to the console exe" >&2
	exit 1
fi

# mirror project (first run, or after a fresh clone)
if [ ! -d "$T" ]; then
	mkdir -p "$T"
	for d in assets levels scenes scripts shaders tests; do
		cmd //c mklink //J "$(cygpath -w "$T/$d")" "$(cygpath -w "$R/$d")" >/dev/null 2>&1 || ln -s "$R/$d" "$T/$d"
	done
fi
cp -f "$R/tools/visible_fix.gd" "$T/visible_fix.gd"

VISIBLE=0; [ -f "$R/.tests_visible" ] && VISIBLE=1
export VISIBLE R T
python - <<'PY'
import re, os
R, T = os.environ["R"], os.environ["T"]
src=open(os.path.join(R,"project.godot"),encoding="utf8").read()
src=src.replace('config/name="EX Odyssey"','config/name="EX Odyssey"\nconfig/use_custom_user_dir=false',1)
vis=os.environ.get("VISIBLE")=="1"
pos=['window/size/initial_position_type=1'] if vis else ['window/size/initial_position_type=0','window/size/initial_position=Vector2i(20000, 20000)']
over={"display":(['window/size/no_focus=false'] if vis else ['window/size/no_focus=true'])+pos+['window/size/mode=0','window/size/always_on_top=false'],
      "audio":['driver/driver="Dummy"']}
if vis:
    over["autoload"]=['VisibleFix="*res://visible_fix.gd"']
for sec,lines in over.items():
    m=re.search(r"^\[%s\]\s*$"%sec,src,re.M)
    if m: src=src[:m.end()]+"\n"+"\n".join(lines)+src[m.end():]
    else: src+="\n[%s]\n"%sec+"\n".join(lines)+"\n"
open(os.path.join(T,"project.godot"),"w",encoding="utf8").write(src)
PY
# always refresh import + global class cache (new class_name scripts appear constantly)
"$G" --headless --audio-driver Dummy --path "$T" --import >/dev/null 2>&1
if [ "$VISIBLE" = 1 ]; then exec "$G" --audio-driver Dummy --path "$T" "$@"; fi
exec "$G" --audio-driver Dummy --position 20000,20000 --path "$T" "$@"
