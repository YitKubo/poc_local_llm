#!/usr/bin/env python3
"""Concurrency measurement for an OpenAI-compatible endpoint (stdlib only).

  sweep     run N simultaneous streaming requests for N in --levels and report per-request
            speed, aggregate throughput and time-to-first-token (used to size --parallel).
  fairness  one "heavy" key floods the server while a "light" key sends a single request;
            reports how long the light request waited for its first token.

Standalone: stdlib only and no dependency on the rest of the repo, so this file can be copied
to any machine that can reach the endpoint. The paths below assume you run from server/.

Examples (llama.cpp published on loopback via docker-compose.debug.yml):
  set -a; . ./.env; set +a
  scripts/loadtest.py sweep --url http://127.0.0.1:8081 --key "$LLAMA_API_KEY" \
      --model Qwen2.5-1.5B-Instruct --levels 1,2,4,8,12
Through LiteLLM (virtual keys from scripts/create_keys.sh):
  scripts/loadtest.py fairness --url http://127.0.0.1:4000 --model local-qwen \
      --heavy-key sk-alice... --light-key sk-bob...
"""
import argparse
import json
import statistics
import threading
import time
import urllib.error
import urllib.request

PROMPT = "Explain, in detail and with examples, how a hash table works and why resizing matters."


def one_request(url, key, model, max_tokens, prompt=PROMPT):
    """Stream one chat completion. Returns a dict of timings; never raises."""
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0.7,
        "stream": True,
        "stream_options": {"include_usage": True},
    }).encode()
    req = urllib.request.Request(
        url.rstrip("/") + "/v1/chat/completions", data=body, method="POST",
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    t0 = time.monotonic()
    r = {"status": None, "ttft": None, "tokens": 0, "total": None, "gen_tps": None, "error": None}
    t_first = None
    try:
        with urllib.request.urlopen(req, timeout=600) as resp:
            r["status"] = resp.status
            for raw in resp:
                line = raw.decode("utf-8", "replace").strip()
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                try:
                    obj = json.loads(data)
                except ValueError:
                    continue
                if obj.get("usage"):
                    r["tokens"] = obj["usage"].get("completion_tokens", r["tokens"])
                ch = obj.get("choices") or []
                if ch and (ch[0].get("delta") or {}).get("content"):
                    if t_first is None:
                        t_first = time.monotonic()
                        r["ttft"] = t_first - t0
    except urllib.error.HTTPError as e:
        r["status"] = e.code
        r["error"] = f"HTTP {e.code}"
    except Exception as e:  # noqa: BLE001 - measurement tool, report everything
        r["error"] = f"{type(e).__name__}: {e}"
    t_end = time.monotonic()
    r["total"] = t_end - t0
    if t_first is not None and r["tokens"] > 1 and t_end > t_first:
        r["gen_tps"] = (r["tokens"] - 1) / (t_end - t_first)
    return r


def run_parallel(n, fn):
    results = [None] * n
    def worker(i):
        results[i] = fn(i)
    threads = [threading.Thread(target=worker, args=(i,)) for i in range(n)]
    t0 = time.monotonic()
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return results, time.monotonic() - t0


def cmd_sweep(a):
    levels = [int(x) for x in a.levels.split(",")]
    print(f"{'N':>3} {'ok':>3} {'429':>3} {'per-req tok/s (median)':>23} {'min':>6} "
          f"{'aggregate tok/s':>16} {'TTFT median s':>14} {'TTFT max s':>11} {'wall s':>7}")
    for n in levels:
        res, wall = run_parallel(n, lambda i: one_request(a.url, a.key, a.model, a.max_tokens))
        ok = [r for r in res if r["status"] == 200 and r["tokens"]]
        rate_limited = sum(1 for r in res if r["status"] == 429)
        tps = [r["gen_tps"] for r in ok if r["gen_tps"]]
        ttft = [r["ttft"] for r in ok if r["ttft"] is not None]
        agg = sum(r["tokens"] for r in ok) / wall if wall else 0
        print(f"{n:>3} {len(ok):>3} {rate_limited:>3} "
              f"{(statistics.median(tps) if tps else 0):>23.1f} {(min(tps) if tps else 0):>6.1f} "
              f"{agg:>16.1f} {(statistics.median(ttft) if ttft else 0):>14.2f} "
              f"{(max(ttft) if ttft else 0):>11.2f} {wall:>7.1f}", flush=True)
        errs = {r["error"] for r in res if r["error"] and r["status"] != 429}
        if errs:
            print("    errors:", "; ".join(sorted(errs)))


def cmd_fairness(a):
    heavy_res = []
    def heavy(i):
        r = one_request(a.url, a.heavy_key, a.model, a.max_tokens)
        heavy_res.append(r)
        return r
    threads = [threading.Thread(target=heavy, args=(i,)) for i in range(a.heavy_count)]
    for t in threads:
        t.start()
    time.sleep(a.head_start)  # let the heavy user get going before the light user arrives
    light = one_request(a.url, a.light_key, a.model, a.max_tokens)
    for t in threads:
        t.join()
    codes = {}
    for r in heavy_res:
        codes[r["status"]] = codes.get(r["status"], 0) + 1
    print(f"heavy user: {a.heavy_count} simultaneous requests -> status counts {codes}")
    ht = [r["ttft"] for r in heavy_res if r["ttft"] is not None]
    if ht:
        print(f"heavy user TTFT: median {statistics.median(ht):.2f}s, max {max(ht):.2f}s")
    print(f"light user (1 request, arrived {a.head_start}s later): status {light['status']}, "
          f"TTFT {light['ttft'] if light['ttft'] is None else round(light['ttft'], 2)}s, "
          f"{light['gen_tps'] and round(light['gen_tps'], 1)} tok/s, error={light['error']}")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("sweep", "fairness"):
        s = sub.add_parser(name)
        s.add_argument("--url", required=True)
        s.add_argument("--model", required=True)
        s.add_argument("--max-tokens", type=int, default=128)
    s = sub.choices["sweep"]
    s.add_argument("--key", required=True)
    s.add_argument("--levels", default="1,2,4,8,12")
    s.set_defaults(fn=cmd_sweep)
    s = sub.choices["fairness"]
    s.add_argument("--heavy-key", required=True)
    s.add_argument("--light-key", required=True)
    s.add_argument("--heavy-count", type=int, default=20)
    s.add_argument("--head-start", type=float, default=3.0)
    s.set_defaults(fn=cmd_fairness)
    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
