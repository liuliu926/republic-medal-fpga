"""Algorithmic check of the home13 read plan, excluding vendor SDRAM IP.

This model checks the request address and burst state progression, not returned
SDRAM data, FIFO occupancy, clock-domain crossings, or timing on the board.
"""

WIDTH, HEIGHT = 1280, 720
STARTS_X, STARTS_Y = (66, 362, 658, 954), (170, 303, 436, 569)

def expected(x, y):
    for row, sy in enumerate(STARTS_Y):
        if sy <= y < sy + 100:
            for col, sx in enumerate(STARTS_X[:1] if row == 3 else STARTS_X):
                if sx <= x < sx + 80:
                    index = row * 4 + col
                    return 921600 + index * 25600 + (99 - (y - sy)) * 256 + x - sx
    return y * WIDTH + x

def segment_end(x, y):
    for row, sy in enumerate(STARTS_Y):
        if sy <= y < sy + 100:
            for sx in (STARTS_X[:1] if row == 3 else STARTS_X):
                if x < sx:
                    return sx
                if x < sx + 80:
                    return sx + 80
    return WIDTH

def main():
    x = y = addr = bg = count = bursts = 0
    while y < HEIGHT:
        stop = segment_end(x, y)
        n = min(stop - x, 256, 256 - (addr & 255))
        assert 1 <= n <= 256
        assert (addr & 255) + n <= 256
        bursts += 1
        for _ in range(n):
            wanted = expected(x, y)
            assert addr == wanted, (x, y, addr, wanted)
            count += 1
            bg += 1
            if x in (65, 361, 657, 953) and any(sy <= y < sy + 100 for sy in STARTS_Y):
                row = next(i for i, sy in enumerate(STARTS_Y) if sy <= y < sy + 100)
                col = (65, 361, 657, 953).index(x)
                if row != 3 or col == 0:
                    addr = 921600 + (row * 4 + col) * 25600 + (99 - (y - STARTS_Y[row])) * 256
                else:
                    addr += 1
            elif x in (145, 441, 737, 1033) and any(sy <= y < sy + 100 for sy in STARTS_Y):
                row = next(i for i, sy in enumerate(STARTS_Y) if sy <= y < sy + 100)
                addr = bg if row != 3 or x == 145 else addr + 1
            else:
                addr += 1
            x += 1
            if x == WIDTH:
                x = 0
                y += 1
    assert count == WIDTH * HEIGHT
    print(f'OK: {count} pixel requests in {bursts} page-bounded segments')
    print('Scope: address plan only; no SDRAM/FIFO/timing validation')

if __name__ == '__main__':
    main()
