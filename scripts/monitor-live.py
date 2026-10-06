#!/usr/bin/env python3
"""Low-overhead local frame capture. Never starts/stops or changes the game."""
import argparse
import csv
import datetime
import io
import json
import math
import os
import plistlib
import re
from pathlib import Path
import statistics
import subprocess
import time


def metrics(rows):
    times = sorted(float(r["dt_us"]) / 1000 for r in rows if float(r["dt_us"]) > 0)
    if not times:
        return None
    n = len(times)
    slowest = times[-max(1, math.ceil(n * .01)):]
    return dict(frames=n, seconds=sum(times) / 1000, fps=n * 1000 / sum(times),
                low1=1000 / statistics.mean(slowest), p99_ms=times[math.ceil(n * .99)-1],
                over11ms=sum(t > 1000 / 90 for t in times),
                over16ms=sum(t > 1000 / 60 for t in times),
                over50ms=sum(t > 50 for t in times), max_ms=times[-1],
                compiles=sum(int(r["compiles"]) for r in rows),
                **{k + "_mean": statistics.mean(float(r[k]) for r in rows)
                   for k in ["commit_us", "prep_us", "flush_us", "block_us", "latwait_us", "cmdbufs"]})


def system_sample(pid):
    ps = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "%cpu=,rss="], capture_output=True, text=True)
    fields = ps.stdout.split()
    vm = subprocess.run(["/usr/bin/vm_stat"], capture_output=True, text=True)
    counters = {}
    for line in vm.stdout.splitlines()[1:]:
        if ":" in line:
            key, value = line.split(":", 1)
            if key in ["Pages free", "Pages active", "Pages inactive", "Pages wired down",
                       "Pages occupied by compressor", "Swapins", "Swapouts", "Pageins", "Pageouts"]:
                try:
                    counters[key] = int(value.strip().rstrip("."))
                except ValueError:
                    pass
    # Scene and foreground focus require user confirmation. Capture only game
    # frames and system performance here, not desktop UI or application names.
    gpu_query = subprocess.run(["/usr/sbin/ioreg", "-r", "-c", "AGXAccelerator", "-a"], capture_output=True)
    try:
        gpu = plistlib.loads(gpu_query.stdout)[0].get("PerformanceStatistics", {})
    except (ValueError, IndexError, plistlib.InvalidFileException):
        gpu = {}
    return dict(game_cpu_percent=float(fields[0]) if fields else None,
                game_rss_mb=float(fields[1])/1024 if len(fields) > 1 else None, vm=counters,
                game_is_foreground=None,
                gpu=gpu)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=int, default=120)
    parser.add_argument("--pid", type=int, required=True, help="macOS host PID of the running game")
    parser.add_argument("--wine-pid", type=int, help="Verified Wine PID; use after restarting game within the same Battle.net session")
    parser.add_argument("--interval", type=float, default=2)
    parser.add_argument("--scene", choices=["unknown", "menu", "training", "match"], default="unknown",
                        help="Use a known scene only after user confirmation")
    args = parser.parse_args()
    if args.seconds <= 0 or args.interval < 1:
        parser.error("seconds must be positive and interval >= 1 second")
    root = Path(os.environ.get("OW120_ROOT", Path.home()/"Library/Application Support/OW120"))
    folder = Path((root/"latest-session.txt").read_text().strip())
    session = json.loads((folder/"session.json").read_text())
    wine_pid = args.wine_pid or session.get("gamePID")
    if not wine_pid:
        parser.error("no game Wine PID found; verify the running process before capture")
    source = folder/f'frames-{wine_pid}.csv'
    if not source.exists() or time.time() - source.stat().st_mtime > 30:
        parser.error("frame source is missing or stale; verify the current game Wine PID")
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    prefix = folder/f"capture-{stamp}"
    with source.open("rb") as stream, Path(str(prefix)+".jsonl").open("w") as log, Path(str(prefix)+".csv").open("wb") as raw:
        header = stream.readline()
        names = header.decode().strip().split(",")
        stream.seek(0, 2)
        start_offset = stream.tell()
        raw.write(header)
        meta = dict(kind="start", wall_time=datetime.datetime.now().astimezone().isoformat(),
                    source=str(source), host_pid=args.pid, wine_pid=wine_pid,
                    offset=start_offset, scene=args.scene, interval_seconds=args.interval)
        log.write(json.dumps(meta)+"\n"); log.flush()
        print("CAPTURE="+str(prefix), flush=True)
        started = time.monotonic(); pending = b""; all_rows = []
        while time.monotonic() - started < args.seconds:
            time.sleep(min(args.interval, max(0, args.seconds-(time.monotonic()-started))))
            pending += stream.read()
            last = pending.rfind(b"\n")
            rows = []
            if last >= 0:
                complete, pending = pending[:last+1], pending[last+1:]
                raw.write(complete); raw.flush()
                for fields in csv.reader(io.StringIO(complete.decode("utf-8"))):
                    if len(fields) == len(names):
                        row = dict(zip(names, fields))
                        try:
                            if all(math.isfinite(float(v)) for v in row.values()) and float(row["dt_us"]) > 0:
                                rows.append(row)
                        except ValueError:
                            pass
            all_rows.extend(rows)
            sample = dict(kind="sample", wall_time=datetime.datetime.now().astimezone().isoformat(),
                          elapsed=time.monotonic()-started, metrics=metrics(rows), **system_sample(args.pid))
            if rows:
                sample.update(first_frame=int(rows[0]["frame"]), last_frame=int(rows[-1]["frame"]))
            log.write(json.dumps(sample)+"\n"); log.flush()
            m = sample["metrics"]
            if m:
                print(f'{sample["elapsed"]:5.1f}s fps={m["fps"]:6.1f} low1={m["low1"]:6.1f} p99={m["p99_ms"]:6.2f}ms >16.7ms={m["over16ms"]:3d} compiles={m["compiles"]} GPU={sample["gpu"].get("Device Utilization %")} scene={args.scene}', flush=True)
            if sample["game_cpu_percent"] is None:
                print("GAME_PROCESS_EXITED", flush=True)
                break
        result = dict(kind="summary", metrics=metrics(all_rows), elapsed=time.monotonic()-started)
        log.write(json.dumps(result)+"\n")
        print(json.dumps(result), flush=True)


if __name__ == "__main__":
    main()
