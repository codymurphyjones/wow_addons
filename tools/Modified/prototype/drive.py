"""Drives a UI prototype in a real Chrome window and screenshots it, so a sketch can be judged in motion.

    python tools/Modified/prototype/drive.py v3_bloom.html script.json

The script is a JSON list of steps:
    ["move", x, y]            move the mouse (in 8 small steps, so hover handlers fire)
    ["down", "Shift"]         hold a key        ["up", "Shift"]    release it
    ["press", "Enter"]        tap a key         ["type", "flash"]  type text
    ["wheel", dy]             scroll the wheel  ["click"] / ["mousedown"] / ["mouseup"]
    ["wait", ms]              let animations run
    ["eval", "js"]            run JavaScript in the page
    ["shot", "name"]          screenshot to shots/<name>.png
"""
import json
import pathlib
import sys

from playwright.sync_api import sync_playwright

HERE = pathlib.Path(__file__).resolve().parent


def main(page_name, script_path):
    steps = json.loads(pathlib.Path(script_path).read_text(encoding="utf-8"))
    shots = HERE / "shots"
    shots.mkdir(exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        page = browser.new_page(viewport={"width": 1280, "height": 760})
        page.on("console", lambda m: print("console:", m.text))
        page.on("pageerror", lambda e: print("PAGE ERROR:", e))
        page.goto((HERE / page_name).as_uri())
        page.wait_for_timeout(300)
        for step in steps:
            kind, args = step[0], step[1:]
            if kind == "move":
                page.mouse.move(args[0], args[1], steps=8)
            elif kind == "down":
                page.keyboard.down(args[0])
            elif kind == "up":
                page.keyboard.up(args[0])
            elif kind == "press":
                page.keyboard.press(args[0])
            elif kind == "type":
                page.keyboard.type(args[0], delay=40)
            elif kind == "wheel":
                page.mouse.wheel(0, args[0])
            elif kind == "click":
                page.mouse.down()
                page.mouse.up()
            elif kind == "mousedown":
                page.mouse.down(button=args[0] if args else "left")
            elif kind == "mouseup":
                page.mouse.up(button=args[0] if args else "left")
            elif kind == "wait":
                page.wait_for_timeout(args[0])
            elif kind == "eval":
                result = page.evaluate(args[0])
                if result is not None:
                    print("eval:", result)
            elif kind == "shot":
                page.screenshot(path=str(shots / (args[0] + ".png")))
                print("shot:", args[0])
        browser.close()


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
