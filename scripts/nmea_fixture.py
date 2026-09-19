#!/usr/bin/env python3
"""Synthetic NMEA 0183 fixture. Never a source of real vessel measurements.

TCP: python3 scripts/nmea_fixture.py
UDP: python3 scripts/nmea_fixture.py --udp --target 127.0.0.1 --port 10110
The coordinate/speed/wind sequence is deterministic; --start-time fixes UTC too.
Only Python's standard library is required. Default network endpoints are loopback.
"""

import argparse
from datetime import datetime, timedelta, timezone
import ipaddress
import math
import socket
import sys
import time


METERS_PER_SECOND_PER_KNOT = 1852.0 / 3600.0
EARTH_RADIUS_METERS = 6_371_000.0
START_LATITUDE = 40.950000
START_LONGITUDE = 29.050000


def sentence(body, corrupt=False):
    """Wrap an ASCII body with XOR checksum and the NMEA CRLF terminator."""
    checksum = 0
    for byte in body.encode("ascii"):
        checksum ^= byte
    if corrupt:
        checksum ^= 1
    return "${}*{:02X}\r\n".format(body, checksum)


def coordinate(value, latitude):
    absolute = abs(value)
    degrees = int(absolute)
    minutes = (absolute - degrees) * 60
    formatted = ("{:02d}{:07.4f}" if latitude else "{:03d}{:07.4f}").format(degrees, minutes)
    hemisphere = ("N" if value >= 0 else "S") if latitude else ("E" if value >= 0 else "W")
    return formatted, hemisphere


def sample(index, latitude, longitude):
    """Return one internally consistent, synthetic boat/wind sample."""
    heading = 315.0 + 2.0 * math.sin(index / 20.0)
    stw = 6.2 + 0.25 * math.sin(index / 13.0)
    heading_radians = math.radians(heading)
    east_knots = math.sin(heading_radians) * stw + 0.35
    north_knots = math.cos(heading_radians) * stw + 0.12
    sog = math.hypot(east_knots, north_knots)
    cog = math.degrees(math.atan2(east_knots, north_knots)) % 360
    true_direction = round(2.0 + 8.0 * math.sin(index / 18.0), 2) % 360
    true_speed = 14.0 + 1.2 * math.sin(index / 23.0)
    true_angle = (true_direction - heading) % 360
    # FROM-wind vector plus boat's through-water TO-vector gives apparent FROM-wind.
    apparent_east = math.sin(math.radians(true_direction)) * true_speed + math.sin(heading_radians) * stw
    apparent_north = math.cos(math.radians(true_direction)) * true_speed + math.cos(heading_radians) * stw
    apparent_angle = (math.degrees(math.atan2(apparent_east, apparent_north)) - heading) % 360
    return {
        "latitude": latitude, "longitude": longitude, "heading": heading,
        "stw": stw, "sog": sog, "cog": cog,
        "true_direction": true_direction, "true_speed": true_speed,
        "true_angle": true_angle, "apparent_angle": apparent_angle,
        "apparent_speed": math.hypot(apparent_east, apparent_north),
        "east_mps": east_knots * METERS_PER_SECOND_PER_KNOT,
        "north_mps": north_knots * METERS_PER_SECOND_PER_KNOT,
    }


def bodies(reading, timestamp, wind_source="all", include_wind=True):
    lat, ns = coordinate(reading["latitude"], True)
    lon, ew = coordinate(reading["longitude"], False)
    utc = timestamp.strftime("%H%M%S") + ".00"
    date = timestamp.strftime("%d%m%y")
    position = "{},{},{},{}".format(lat, ns, lon, ew)
    yield "GPRMC,{},A,{},{:.2f},{:.2f},{},,,A".format(utc, position, reading["sog"], reading["cog"], date)
    yield "GPGGA,{},{},1,10,0.8,0.0,M,0.0,M,,".format(utc, position)
    yield "GPVTG,{:.2f},T,,M,{:.2f},N,{:.2f},K,A".format(reading["cog"], reading["sog"], reading["sog"] * 1.852)
    yield "IIHDT,{:.2f},T".format(reading["heading"])
    yield "IIVHW,{:.2f},T,,M,{:.2f},N,{:.2f},K".format(reading["heading"], reading["stw"], reading["stw"] * 1.852)
    if not include_wind:
        return
    if wind_source in ("all", "mwd"):
        yield "WIMWD,{:.2f},T,,M,{:.2f},N,{:.2f},M".format(reading["true_direction"], reading["true_speed"], reading["true_speed"] * METERS_PER_SECOND_PER_KNOT)
    if wind_source in ("all", "mwvt"):
        yield "WIMWV,{:.2f},T,{:.2f},N,A".format(reading["true_angle"], reading["true_speed"])
    if wind_source in ("all", "apparent"):
        yield "WIMWV,{:.2f},R,{:.2f},N,A".format(reading["apparent_angle"], reading["apparent_speed"])


def frames(start_time, count=None, drop_wind_after=None, wind_source="all", corrupt_every=0):
    latitude, longitude = START_LATITUDE, START_LONGITUDE
    index = 0
    sentence_number = 0
    while count is None or index < count:
        reading = sample(index, latitude, longitude)
        include_wind = drop_wind_after is None or index < drop_wind_after
        output = []
        for body in bodies(reading, start_time + timedelta(seconds=index), wind_source, include_wind):
            sentence_number += 1
            corrupt = corrupt_every > 0 and sentence_number % corrupt_every == 0
            output.append(sentence(body, corrupt))
        yield "".join(output).encode("ascii")
        latitude += math.degrees(reading["north_mps"] / EARTH_RADIUS_METERS)
        longitude += math.degrees(reading["east_mps"] / (EARTH_RADIUS_METERS * math.cos(math.radians(reading["latitude"]))))
        index += 1


def send_frames(send, options):
    deadline = time.monotonic()
    for index, frame in enumerate(frames(options.start_time, options.count, options.drop_wind_after, options.wind_source, options.corrupt_every)):
        delay = deadline - time.monotonic()
        if delay > 0:
            time.sleep(delay)
        send(frame)
        if options.drop_wind_after is not None and index == options.drop_wind_after:
            print("Synthetic wind stopped; GPS, heading and STW continue.", file=sys.stderr, flush=True)
        deadline += 1.0


def nonnegative(value):
    number = int(value)
    if number < 0:
        raise argparse.ArgumentTypeError("must be zero or greater")
    return number


def port_number(value):
    number = int(value)
    if not 1 <= number <= 65535:
        raise argparse.ArgumentTypeError("must be between 1 and 65535")
    return number


def utc_time(value):
    if value.lower() == "now":
        return datetime.now(timezone.utc).replace(microsecond=0)
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise argparse.ArgumentTypeError("use an ISO 8601 UTC timestamp, e.g. 2026-09-14T09:00:00Z") from error
    if parsed.tzinfo is None:
        raise argparse.ArgumentTypeError("timestamp must include Z or a UTC offset")
    return parsed.astimezone(timezone.utc).replace(microsecond=0)


def ipv4_address(value):
    try:
        return str(ipaddress.IPv4Address(value))
    except ipaddress.AddressValueError as error:
        raise argparse.ArgumentTypeError("use a numeric IPv4 address") from error


def arguments():
    parser = argparse.ArgumentParser(description="Synthetic NMEA 0183 at 1 Hz. Defaults to a loopback-only, one-client TCP server.")
    parser.add_argument("--udp", action="store_true", help="send UDP unicast instead of accepting one TCP client")
    parser.add_argument("--bind", type=ipv4_address, default="127.0.0.1", help="TCP listen address (default: 127.0.0.1)")
    parser.add_argument("--target", type=ipv4_address, default="127.0.0.1", help="UDP destination (default: 127.0.0.1)")
    parser.add_argument("--port", type=port_number, default=10110, help="TCP listen or UDP destination port (default: 10110)")
    parser.add_argument("--count", type=nonnegative, help="number of one-second frames; omitted means continuous")
    parser.add_argument("--drop-wind-after", type=nonnegative, metavar="N", help="omit every wind sentence after N frames; keep GPS/heading/STW")
    parser.add_argument("--wind-source", choices=("all", "mwd", "mwvt", "apparent"), default="all", help="wind sentence family (default: all)")
    parser.add_argument("--corrupt-every", type=nonnegative, default=0, metavar="N", help="deliberately corrupt every Nth checksum; 0 disables (default)")
    parser.add_argument("--start-time", type=utc_time, default="now", help="initial UTC time; use an ISO timestamp for byte-for-byte reproducibility")
    parser.add_argument("--print-only", action="store_true", help="print NMEA to stdout at 1 Hz without opening any socket")
    options = parser.parse_args()
    target = ipaddress.IPv4Address(options.target)
    if options.udp and (target.is_multicast or target.is_unspecified or int(target) & 255 == 255):
        parser.error("UDP fixture supports an explicit unicast target only; no multicast/broadcast")
    return options


def main():
    options = arguments()
    print("SYNTHETIC NMEA TEST DATA — no vessel sensor measurements.", file=sys.stderr, flush=True)
    try:
        if options.print_only:
            def output(frame):
                sys.stdout.buffer.write(frame)
                sys.stdout.buffer.flush()
            send_frames(output, options)
        elif options.udp:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sender:
                print("UDP unicast to {}:{}".format(options.target, options.port), file=sys.stderr, flush=True)
                send_frames(lambda frame: sender.sendto(frame, (options.target, options.port)), options)
        else:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
                server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                server.bind((options.bind, options.port))
                server.listen(1)
                print("TCP listening on {}:{}; waiting for one client".format(options.bind, options.port), file=sys.stderr, flush=True)
                with server.accept()[0] as client:
                    client.settimeout(10)
                    print("Client connected; emitting synthetic frames at 1 Hz.", file=sys.stderr, flush=True)
                    send_frames(client.sendall, options)
    except KeyboardInterrupt:
        print("\nFixture stopped; sockets closed.", file=sys.stderr)
    except (BrokenPipeError, ConnectionResetError):
        print("Client disconnected; fixture closed.", file=sys.stderr)
    except OSError as error:
        print("Fixture error: {}".format(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
