#!/usr/bin/env python3
"""吃掉回應的 HTTP/WS 代理——用來造出「後端其實成功、只是回應遺失」的正向競態。

背景：TODO 第十輪誠實記錄過 `docker pause` 造不出這個競態（dio 逾時會關掉連線，
凍結中的後端根本沒讀到請求），要驗正向分支需要「轉發請求但吃掉回應」的代理。這就是那支。

用法：
    python3 lossy_proxy.py 8081 127.0.0.1 8080 /path/to/rules.json

rules.json（每個請求重讀一次，改檔即生效）：
    {"blackhole": ["POST:/api/rides/\\d+/complete"], "ws_block": false}

- blackhole：請求照樣送到後端（後端會真的執行），但**不把回應交還給 App**，
  連線掛著不關，直到 App 自己 receiveTimeout。
- ws_block：拒絕 WebSocket 升級，模擬「WS 斷了但 REST 還通」。
"""
import asyncio
import json
import re
import sys
import time

PORT = int(sys.argv[1])
UP_HOST = sys.argv[2]
UP_PORT = int(sys.argv[3])
RULES = sys.argv[4]


def load_rules():
    try:
        with open(RULES) as f:
            return json.load(f)
    except Exception:
        return {"blackhole": [], "ws_block": False}


def log(*a):
    print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)


async def read_head(reader):
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = await reader.read(1)
        if not chunk:
            return None
        data += chunk
    return data


def parse_head(head):
    lines = head.split(b"\r\n")
    first = lines[0].decode("latin1")
    parts = first.split(" ")
    method, path = (parts[0], parts[1]) if len(parts) >= 2 else ("", "")
    headers = {}
    for line in lines[1:]:
        if b":" in line:
            k, v = line.split(b":", 1)
            headers[k.decode("latin1").lower()] = v.decode("latin1").strip()
    return method, path, headers


async def pump(src, dst):
    try:
        while True:
            chunk = await src.read(4096)
            if not chunk:
                break
            dst.write(chunk)
            await dst.drain()
    except Exception:
        pass
    finally:
        try:
            dst.close()
        except Exception:
            pass


async def handle(client_r, client_w):
    up_r = up_w = None
    try:
        head = await read_head(client_r)
        if head is None:
            return
        method, path, headers = parse_head(head)
        rules = load_rules()

        if headers.get("upgrade", "").lower() == "websocket":
            if rules.get("ws_block"):
                log(f"WS BLOCK  {path}")
                client_w.write(b"HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                await client_w.drain()
                client_w.close()
                return
            up_r, up_w = await asyncio.open_connection(UP_HOST, UP_PORT)
            up_w.write(head)
            await up_w.drain()
            log(f"WS OPEN   {path}")
            await asyncio.gather(pump(client_r, up_w), pump(up_r, client_w))
            return

        body = b""
        n = int(headers.get("content-length", "0") or 0)
        if n:
            body = await client_r.readexactly(n)

        key = f"{method}:{path.split('?')[0]}"
        blackhole = any(re.fullmatch(p, key) for p in rules.get("blackhole", []))

        up_r, up_w = await asyncio.open_connection(UP_HOST, UP_PORT)
        # 強制單次請求，省掉 keep-alive 的狀態機；dio 會自己開新連線。
        head = re.sub(rb"\r\nConnection: [^\r\n]*", b"", head, flags=re.I)
        head = head.replace(b"\r\n\r\n", b"\r\nConnection: close\r\n\r\n")
        up_w.write(head + body)
        await up_w.drain()

        resp = await up_r.read(-1)  # 讀到 EOF（上游已 Connection: close）
        status = resp.split(b"\r\n", 1)[0].decode("latin1") if resp else "(empty)"

        if blackhole:
            log(f"BLACKHOLE {key} -> 上游回 {status}，不交還 App")
            await asyncio.sleep(120)  # 掛著不回，讓 App 自己逾時
            return

        log(f"PASS      {key} -> {status}")
        client_w.write(resp)
        await client_w.drain()
    except (asyncio.IncompleteReadError, ConnectionResetError, BrokenPipeError):
        pass
    except Exception as e:  # noqa: BLE001
        log(f"ERROR {e!r}")
    finally:
        for w in (client_w, up_w):
            try:
                if w:
                    w.close()
            except Exception:
                pass


async def main():
    server = await asyncio.start_server(handle, "0.0.0.0", PORT)
    log(f"lossy proxy listening :{PORT} -> {UP_HOST}:{UP_PORT} rules={RULES}")
    async with server:
        await server.serve_forever()


asyncio.run(main())
