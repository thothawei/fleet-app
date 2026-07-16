#!/usr/bin/env python3
"""產生叫車 App icon 來源圖（品牌綠 #06C755 + 白色計程車，側視扁平風）。

輸出到 assets/icon/：
  app_icon.png            1024 全出血綠底+計程車（iOS / Android 舊版）
  app_icon_foreground.png 1024 透明底+計程車（Android adaptive 前景，置中；
                          flutter_launcher_icons 另加 16% inset）

用法（在 line-fleet-app 專案根目錄）：
  python3 tool/make_app_icon.py      # 產生來源圖
  dart run flutter_launcher_icons    # 依 pubspec 設定產各平台尺寸

需求：Pillow（pip install pillow）。4x 超取樣後縮圖，邊緣平滑。
"""
import os

from PIL import Image, ImageDraw

GREEN = (6, 199, 85, 255)  # #06C755 LINE green，對齊 app lib/core/theme/app_theme.dart kBrandGreen
WHITE = (255, 255, 255, 255)
S = 4  # 超取樣倍率
BASE = 1024
N = BASE * S
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "icon")


def rounded_rect(d, box, r, fill):
    d.rounded_rectangle([c * S for c in box], radius=r * S, fill=fill)


def ellipse(d, cx, cy, r, fill):
    d.ellipse([(cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S], fill=fill)


def draw_taxi(d, cx, cy, scale=1.0, body=WHITE, hole=GREEN):
    """在 (cx,cy) 為中心畫側視計程車。scale=1 時整體約 660x430。"""
    def X(x):
        return cx + x * scale

    def Y(y):
        return cy + y * scale

    # 車身下半（主體）
    rounded_rect(d, [X(-320), Y(0), X(320), Y(120)], 58, body)
    # 車頂座艙（梯形，白）
    cabin = [(X(-210), Y(0)), (X(-150), Y(-118)), (X(150), Y(-118)), (X(210), Y(0))]
    d.polygon([(px * S, py * S) for px, py in cabin], fill=body)
    # 車窗（兩片，中間 A 柱）
    rounded_rect(d, [X(-176), Y(-96), X(-18), Y(-8)], 20, hole)
    rounded_rect(d, [X(18), Y(-96), X(176), Y(-8)], 20, hole)
    # 車頂 TAXI 燈
    rounded_rect(d, [X(-52), Y(-170), X(52), Y(-120)], 16, body)
    rounded_rect(d, [X(-34), Y(-156), X(-6), Y(-134)], 5, hole)
    rounded_rect(d, [X(6), Y(-156), X(34), Y(-134)], 5, hole)
    # 輪子：胎（挖空）+ 白色輪轂
    for wx in (-190, 190):
        ellipse(d, X(wx), Y(132), 78 * scale, hole)
        ellipse(d, X(wx), Y(132), 34 * scale, body)


def make_full():
    img = Image.new("RGBA", (N, N), GREEN)
    draw_taxi(ImageDraw.Draw(img), BASE / 2, BASE / 2 - 20, scale=1.0)
    return img.resize((BASE, BASE), Image.LANCZOS)


def make_foreground():
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    # flutter_launcher_icons 另加 16% inset，故此處 0.78 讓遮罩後仍飽滿在安全區
    draw_taxi(ImageDraw.Draw(img), BASE / 2, BASE / 2 - 12, scale=0.78, body=WHITE, hole=(0, 0, 0, 0))
    return img.resize((BASE, BASE), Image.LANCZOS)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    make_full().save(os.path.join(OUT, "app_icon.png"))
    make_foreground().save(os.path.join(OUT, "app_icon_foreground.png"))
    print("wrote app_icon.png / app_icon_foreground.png to assets/icon/")
