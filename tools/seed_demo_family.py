#!/usr/bin/env python3
"""App Review / ekran goruntusu icin veri dolu bir demo aile olusturur.

Yalniz PUBLIC API uclarini kullanir (self-service kayit, davet, katilim, konum).
Hicbir secret gerektirmez ve gercek kullanici verisine dokunmaz. Basariliysa
son satirda reviewer/test icin kullanilabilecek davet kodunu yazar.

Kullanim:
  python3 tools/seed_demo_family.py --api https://<worker>.workers.dev [--quiet]
"""
import argparse
import json
import sys
import time
import urllib.error
import urllib.request

# Kas / Patara bolgesinde gercekci rota noktalari (canli harita ve rota gecmisi icin)
ROUTE_A = [(36.2021, 29.6413), (36.2035, 29.6440), (36.2052, 29.6468), (36.2070, 29.6491), (36.2088, 29.6515)]
ROUTE_B = [(36.1975, 29.6350), (36.1990, 29.6372), (36.2008, 29.6395), (36.2024, 29.6418)]

UA = 'SavaronaAilem/0.3.5 (demo seeding)'


def call(api, method, path, body=None, token=None):
    data = None if body is None else json.dumps(body).encode()
    headers = {'content-type': 'application/json', 'user-agent': UA}
    if token:
        headers['authorization'] = f'Bearer {token}'
    request = urllib.request.Request(api + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            raw = response.read().decode()
            return response.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as error:
        return error.code, {'_error': error.read().decode(errors='replace')[:300]}


def seed_route(api, account, route, log):
    now_ms = int(time.time() * 1000)
    for index, (lat, lng) in enumerate(route):
        captured = now_ms - (len(route) - 1 - index) * 10 * 60 * 1000
        status, result = call(api, 'POST', '/v1/location', {
            'captured_at': captured,
            'lat': lat,
            'lng': lng,
            'speed_mps': 6.4 + index * 0.7,
            'heading_deg': 45 + index * 8,
            'accuracy_m': 8 + index,
            'battery_pct': 88 - index * 3,
            'sequence_no': index + 1,
        }, token=account['device_token'])
        if status != 200:
            log(f'  konum {index} yazilamadi: {status} {result}')
            return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--api', required=True)
    parser.add_argument('--quiet', action='store_true')
    args = parser.parse_args()
    api = args.api.rstrip('/')

    def log(message):
        if not args.quiet:
            print(message, file=sys.stderr)

    log('Demo aile olusturuluyor...')
    status, owner = call(api, 'POST', '/v1/families', {
        'family_name': 'App Review Demo Family',
        'owner_name': 'Demo Anne',
        'device_name': 'Demo iPhone',
        'platform': 'ios',
    })
    if status != 201:
        print(f'aile olusturulamadi: {status} {owner}', file=sys.stderr)
        return 1

    log('Ikinci uye davet ediliyor...')
    status, invite = call(api, 'POST', '/v1/invites', token=owner['device_token'])
    if status != 201:
        print(f'davet olusturulamadi: {status} {invite}', file=sys.stderr)
        return 1
    status, member = call(api, 'POST', '/v1/join', {
        'invite_code': invite['invite_code'],
        'member_name': 'Demo Baba',
        'device_name': 'Demo Android',
        'platform': 'android',
    })
    if status != 201:
        print(f'katilim basarisiz: {status} {member}', file=sys.stderr)
        return 1

    log('Konum ve rota gecmisi yaziliyor...')
    if not seed_route(api, owner, ROUTE_A, log) or not seed_route(api, member, ROUTE_B, log):
        return 1

    status, review_invite = call(api, 'POST', '/v1/invites', token=owner['device_token'])
    if status != 201:
        print(f'davet kodu uretilemedi: {status} {review_invite}', file=sys.stderr)
        return 1

    status, snapshot = call(api, 'GET', '/v1/family/snapshot', token=owner['device_token'])
    located = [m for m in snapshot.get('members', []) if m.get('lat') is not None]
    log(f'Hazir: {len(snapshot.get("members", []))} uye, {len(located)} tanesinin konumu var.')

    # stdout'a YALNIZ davet kodu yazilir - workflow bunu dogrudan okur.
    print(review_invite['invite_code'])
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
