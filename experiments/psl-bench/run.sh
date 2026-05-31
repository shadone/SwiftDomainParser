#!/bin/bash
# PSL load-strategy benchmark driver. Compiles each variant with -O, captures
# compile wall-time + binary size, then runs each 5x and keeps the min.
set -u
cd "$(dirname "$0")"
DAT="../../Sources/PublicSuffixListKit/Resources/public_suffix_list.dat"
B=build
mkdir -p "$B"

timed() { { /usr/bin/time -p "$@" ; } 2>&1 | awk '/^real/{print $2}'; }
run_to() { local secs=$1; shift; "$@" & local pid=$!
  ( sleep "$secs"; kill -9 $pid 2>/dev/null ) & local w=$!
  wait $pid 2>/dev/null; local rc=$?; kill -9 $w 2>/dev/null; return $rc; }

# compile a variant: name, entryfile, [generated-source]
compile() { local name=$1 entry=$2 extra=${3:-}
  mkdir -p "$B/$name"; cp "$entry" "$B/$name/main.swift"
  local files=(core.swift); [ -n "$extra" ] && files+=("$extra"); files+=("$B/$name/main.swift")
  local t; t=$(timed swiftc -O "${files[@]}" -o "$B/bench_$name")
  echo "$name compile=${t}s size=$(stat -f%z "$B/bench_$name")"
}

echo "== generating artifacts =="
mkdir -p "$B/gen"; cp gen.swift "$B/gen/main.swift"
swiftc -O core.swift "$B/gen/main.swift" -o "$B/gen_exe" || exit 1
"$B/gen_exe" "$DAT" "$B" || exit 1
for f in blob.bin blob_direct.bin gen_B.swift gen_C_single.swift gen_C_chunked.swift gen_D.swift; do
  echo "  $f  $(stat -f%z "$B/$f") bytes"
done
echo

echo "== compiling variants (-O) =="
compile base    main_base.swift
compile A       main_A.swift
compile B       main_B.swift        "$B/gen_B.swift"
compile C       main_C.swift        "$B/gen_C_chunked.swift"
compile D       main_D.swift        "$B/gen_D.swift"
compile E       main_E.swift
echo

echo "== C single-literal compile probe (timeout 300s) =="
mkdir -p "$B/Cs"; cp main_C_single.swift "$B/Cs/main.swift"
t0=$(date +%s)
if run_to 300 swiftc -O core.swift "$B/gen_C_single.swift" "$B/Cs/main.swift" -o "$B/bench_Cs"; then
  echo "C_single compile=$(( $(date +%s)-t0 ))s size=$(stat -f%z "$B/bench_Cs") COMPILED"
else
  echo "C_single DID NOT COMPILE within $(( $(date +%s)-t0 ))s (killed)"
fi
echo

echo "== running (min build_ms of 5 runs) =="
minrun() { local bin=$1; shift; for i in 1 2 3 4 5; do "$bin" "$@"; done \
  | awk -F'build_ms=' '{split($2,a,"\t"); print a[1]"\t"$0}' | sort -n | head -1 | cut -f2-; }
minrun "$B/bench_A" "$B/blob.bin" 3000
minrun "$B/bench_B" 3000
minrun "$B/bench_C" 3000
minrun "$B/bench_D" 3000
minrun "$B/bench_E" "$B/blob_direct.bin" 3000
[ -x "$B/bench_Cs" ] && minrun "$B/bench_Cs"
