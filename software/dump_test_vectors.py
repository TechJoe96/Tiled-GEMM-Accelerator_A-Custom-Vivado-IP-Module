"""Generate test vectors for the systolic array's SystemVerilog testbench.
Writes three hex files to tb/data/:
  a_tile.hex:      8x8 int16 A tile (64 values, one per line)
  b_tile.hex:      8x8 int16 B tile (64 values, one per line)
  c_expected.hex:  8x8 int32 expected C tile (= A @ B, 64 values, one per line)
Each value is zero-padded hex in two's complement (4 chars for int16, 8 for int32).
$readmemh in SystemVerilog reads this format directly into an unpacked array.
"""
import os
import numpy as np

def to_hex_twos_complement(val, bits):
    """Convert a (possibly signed) integer to its zero-padded hex string in
    two's complement. Width = bits / 4 hex chars."""
    mask = (1 << bits) - 1
    n_hex = bits // 4
    return f"{int(val) & mask:0{n_hex}x}"
def dump_tile_for_sv(filename, tile, width_bits):
    """Dump a 2D NumPy tile to a file, one value per line, row-major."""
    flat = tile.flatten()
    with open(filename, 'w') as f:
        for v in flat:
            f.write(to_hex_twos_complement(v, width_bits) + '\n')
def main():
    np.random.seed(0)
    N = 8
# Bounded random ints. Keep values small enough that 8 multiplications
    # of two int16 values stay well within int32 range (worst case ~32 * 50 * 50 = 80000).
    A_tile = np.random.randint(-50, 51, size=(N, N), dtype=np.int16)
    B_tile = np.random.randint(-50, 51, size=(N, N), dtype=np.int16)
    C_expected = (A_tile.astype(np.int32) @ B_tile.astype(np.int32)).astype(np.int32)
# Path: this file is at software/, target is tb/data/
    out_dir = os.path.join(os.path.dirname(__file__), '..', 'tb', 'data')
    os.makedirs(out_dir, exist_ok=True)
    dump_tile_for_sv(os.path.join(out_dir, 'a_tile.hex'),     A_tile,     width_bits=16)
    dump_tile_for_sv(os.path.join(out_dir, 'b_tile.hex'),     B_tile,     width_bits=16)
    dump_tile_for_sv(os.path.join(out_dir, 'c_expected.hex'), C_expected, width_bits=32)
    print(f"Wrote test vectors to {out_dir}/")
    print(f"  A[0,0] = {A_tile[0,0]:5d}    (hex {to_hex_twos_complement(A_tile[0,0], 16)})")
    print(f"  B[0,0] = {B_tile[0,0]:5d}    (hex {to_hex_twos_complement(B_tile[0,0], 16)})")


    print(f"  C_expected[0,0] = {C_expected[0,0]:6d}  (hex {to_hex_twos_complement(C_expected[0,0], 32)})")
if __name__ == '__main__':
    main()
