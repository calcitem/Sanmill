#!/usr/bin/env python3
"""Generate the offline land and popularity masks used by Variants.

The input is Natural Earth's public-domain 1:110m land GeoJSON. Region
polygons are deliberately approximate: they communicate broad popularity
areas without presenting national borders or country-level precision.

Requires Pillow. Pass --source to reuse a verified local GeoJSON file.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import urllib.request
from pathlib import Path
from typing import Iterable, Sequence

from PIL import Image, ImageChops, ImageDraw


SOURCE_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_110m_land.geojson"
)
SOURCE_SHA256 = "9e0729ee253ca7d7a5c4ae9395fb1902264c5377c52e224d13dd85010e2835d9"
OUTPUT_WIDTH = 1024
OUTPUT_HEIGHT = 512
SUPERSAMPLE = 4

Point = tuple[float, float]
Polygon = Sequence[Point]


def rectangle(west: float, south: float, east: float, north: float) -> Polygon:
    return (
        (west, south),
        (east, south),
        (east, north),
        (west, north),
    )


CHINA: Polygon = (
    (74, 37),
    (80, 49),
    (96, 54),
    (122, 53),
    (134, 47),
    (132, 42),
    (124, 40),
    (123, 29),
    (121, 22),
    (111, 21),
    (104, 23),
    (98, 25),
    (91, 28),
    (84, 30),
)

KOREAN_PENINSULA: Polygon = (
    (124, 39.7),
    (124.8, 40.7),
    (126, 41.2),
    (128, 41.7),
    (129.1, 42.5),
    (130.8, 42.3),
    (130.2, 40),
    (129.5, 37),
    (129.7, 35),
    (127.5, 34),
    (126, 34.2),
    (125.3, 37),
)

KOREAN_PENINSULA_EXCLUSION: Polygon = (
    (123.5, 39.4),
    (124.3, 41.2),
    (129, 43.2),
    (131.2, 42.6),
    (130.8, 38.2),
    (130.1, 34.4),
    (127.5, 33),
    (124.7, 33.6),
    (124.8, 37),
)


REGIONS: dict[str, tuple[Polygon, ...]] = {
    "standard_9mm": (
        rectangle(-180, -60, -30, 85),  # The Americas
        rectangle(-75, 58, -10, 85),  # All of Greenland
        rectangle(-13, 34, 48, 72),  # Europe
        rectangle(-18, 9, 36, 38),  # North Africa
        rectangle(32, 9, 62, 43),  # The Middle East
        (
            (112, -13),
            (128, -13),
            (136, -11),
            (142, -11),
            (143, -17),
            (154, -27),
            (154, -39),
            (146, -44),
            (130, -40),
            (115, -35),
            (112, -22),
        ),  # Australia without Southeast Asian islands
        rectangle(141, -12, 155, 1),  # Papua New Guinea
        rectangle(155, -25, 180, 1),  # Melanesia and Pacific islands
        rectangle(165, -50, 180, -32),  # New Zealand
        CHINA,
        rectangle(128, 29, 147, 47),  # Japan
        (
            (60, 38),
            (82, 38),
            (92, 28),
            (94, 24),
            (93, 20),
            (89, 20),
            (88, 5),
            (78, 5),
            (68, 21),
            (60, 25),
        ),  # India, Pakistan and Bangladesh
    ),
    "twelve_mens_morris": (
        rectangle(-20, -36, 53, 11.5),
        rectangle(-20, 11.5, 42, 17),  # Exclude the Arabian Peninsula
        rectangle(25, 35, 46, 43),  # Turkey
    ),
    "morabaraba": (
        (
            (16, -35),
            (36, -35),
            (39, -22),
            (34, -14),
            (22, -15),
            (16, -24),
        ),
    ),
    "dooz": (
        (
            (44.5, 39.5),
            (49, 39.8),
            (54, 38),
            (61.5, 37.5),
            (63, 34),
            (61.5, 25.2),
            (58, 26),
            (56, 26.5),
            (51, 28),
            (48, 30),
            (46, 33),
            (44, 36),
        ),  # Iran
        (
            (60.5, 35.5),
            (64, 38.2),
            (70, 38.5),
            (74.8, 37),
            (74, 34),
            (69, 29.5),
            (64, 29),
            (60.5, 32),
        ),  # Afghanistan
        (
            (67, 36),
            (70, 37),
            (75, 37),
            (75, 41),
            (70, 41),
            (67, 39),
        ),  # Tajikistan
    ),
    "lasker_morris": (rectangle(5, 45, 19, 56),),
    "russian_mill": (
        (
            (28, 70),
            (42, 71),
            (60, 68),
            (60, 46),
            (50, 45),
            (47, 42),
            (40, 44),
            (40, 50),
            (35, 52),
            (33, 56),
            (28, 60),
            (31, 63),
            (29, 66),
        ),
        (
            (20, 44),
            (41, 44),
            (41, 53),
            (31, 53),
            (22, 50),
        ),  # Ukraine and Moldova
        rectangle(23, 51, 33, 57),  # Belarus
        (
            (21, 56),
            (24, 54),
            (29, 54),
            (29, 60),
            (24, 60),
            (21, 58),
        ),  # Estonia, Latvia and Lithuania
        rectangle(19, 54, 23, 56),  # Kaliningrad
    ),
    "cham_gonu": (KOREAN_PENINSULA,),
    "zhi_qi": (
        (
            (116, 25),
            (116.8, 23.4),
            (119.2, 23.4),
            (120.8, 25),
            (120.3, 28.4),
            (118.2, 28.8),
            (116.7, 27),
        ),  # Fujian
        rectangle(119.5, 21.5, 122.5, 26),  # Taiwan
    ),
    "cheng_san_qi": (
        (
            (95, 21),
            (109, 21),
            (109, 34),
            (101, 36),
            (95, 30),
        ),
    ),
    "da_san_qi": (
        (
            (97, 28),
            (99, 24),
            (101, 22),
            (105, 22),
            (108, 21),
            (113, 22),
            (116, 24),
            (116, 31),
            (112, 34),
            (102, 34),
        ),
    ),
    "mul_mulan": (
        rectangle(94, -12, 143, 15),
        rectangle(114, 5, 129, 22),  # The Philippines
    ),
    "nerenchi": (
        (
            (79.5, 9.8),
            (80.3, 10.1),
            (81.8, 9.8),
            (82.1, 7.2),
            (81, 5.5),
            (79.5, 5.7),
            (79.3, 8.5),
        ),
    ),
    "el_filja": (
        (
            (-14, 35),
            (-6, 35.8),
            (0, 35.8),
            (4, 36.5),
            (9, 36.5),
            (9, 18),
            (-6, 18),
            (-14, 28),
        ),
    ),
}

EXCLUSIONS: dict[str, tuple[Polygon, ...]] = {
    "standard_9mm": (KOREAN_PENINSULA_EXCLUSION,),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        type=Path,
        help="Use an existing ne_110m_land.geojson instead of downloading it.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "assets" / "maps",
    )
    return parser.parse_args()


def read_source(source: Path | None) -> bytes:
    if source is not None:
        data = source.read_bytes()
    else:
        with urllib.request.urlopen(SOURCE_URL) as response:
            data = response.read()

    digest = hashlib.sha256(data).hexdigest()
    if digest != SOURCE_SHA256:
        raise ValueError(
            f"Unexpected Natural Earth SHA-256: {digest}; "
            f"expected {SOURCE_SHA256}."
        )
    return data


def project(point: Sequence[float], width: int, height: int) -> Point:
    longitude, latitude = point
    return (
        (longitude + 180.0) / 360.0 * width,
        (90.0 - latitude) / 180.0 * height,
    )


def draw_polygons(
    image: Image.Image,
    polygons: Iterable[Polygon],
    *,
    fill: int,
) -> None:
    drawer = ImageDraw.Draw(image)
    for polygon in polygons:
        drawer.polygon(
            [project(point, image.width, image.height) for point in polygon],
            fill=fill,
        )


def build_land_mask(geojson: dict[str, object]) -> Image.Image:
    size = (OUTPUT_WIDTH * SUPERSAMPLE, OUTPUT_HEIGHT * SUPERSAMPLE)
    land = Image.new("L", size, 0)
    drawer = ImageDraw.Draw(land)

    features = geojson["features"]
    assert isinstance(features, list)
    for feature in features:
        assert isinstance(feature, dict)
        geometry = feature["geometry"]
        assert isinstance(geometry, dict)
        geometry_type = geometry["type"]
        coordinates = geometry["coordinates"]
        assert isinstance(coordinates, list)

        if geometry_type == "Polygon":
            polygon_groups = [coordinates]
        elif geometry_type == "MultiPolygon":
            polygon_groups = coordinates
        else:
            raise ValueError(f"Unsupported geometry type: {geometry_type}")

        for rings in polygon_groups:
            assert isinstance(rings, list) and rings
            drawer.polygon(
                [project(point, land.width, land.height) for point in rings[0]],
                fill=255,
            )
            for hole in rings[1:]:
                drawer.polygon(
                    [project(point, land.width, land.height) for point in hole],
                    fill=0,
                )

    return land


def save_alpha_mask(mask: Image.Image, path: Path) -> None:
    resized = mask.resize(
        (OUTPUT_WIDTH, OUTPUT_HEIGHT),
        resample=Image.Resampling.LANCZOS,
    )
    rgba = Image.new("RGBA", resized.size, (255, 255, 255, 0))
    rgba.putalpha(resized)
    rgba.save(path, optimize=True)


def main() -> None:
    args = parse_args()
    source_bytes = read_source(args.source)
    geojson = json.loads(source_bytes.decode("utf-8"))
    assert isinstance(geojson, dict)

    output: Path = args.output
    output.mkdir(parents=True, exist_ok=True)
    land = build_land_mask(geojson)
    save_alpha_mask(land, output / "world_land.png")

    for variant_id, polygons in REGIONS.items():
        selection = Image.new("L", land.size, 0)
        draw_polygons(selection, polygons, fill=255)
        if variant_id in EXCLUSIONS:
            draw_polygons(selection, EXCLUSIONS[variant_id], fill=0)
        popularity = ImageChops.multiply(land, selection)
        if popularity.getbbox() is None:
            raise ValueError(f"Popularity mask is empty: {variant_id}")
        save_alpha_mask(popularity, output / f"mill_variant_{variant_id}.png")

    print(f"Generated {len(REGIONS) + 1} map assets in {output}")


if __name__ == "__main__":
    main()
