"""Execute audited original ARM64e geometry routines, not rewritten branches.

Requires unicorn and capstone installed outside the repository. Does not
connect to a device. UIKit/ObjC calls and the original grid geometry are
explicit fixtures, so results prove branch behavior, not a live GUI trace.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path

from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
from unicorn import Uc, UC_ARCH_ARM64, UC_MODE_ARM, UC_HOOK_CODE
from unicorn.arm64_const import (
    UC_ARM64_REG_X0, UC_ARM64_REG_X1, UC_ARM64_REG_X2,
    UC_ARM64_REG_X3, UC_ARM64_REG_X4, UC_ARM64_REG_X30,
    UC_ARM64_REG_PC, UC_ARM64_REG_SP, UC_ARM64_REG_D0,
    UC_ARM64_REG_D1, UC_ARM64_REG_D2, UC_ARM64_REG_D3,
)


def floating(machine, register, value=None):
    if value is None:
        return struct.unpack('<d', struct.pack('<Q', machine.reg_read(register)))[0]
    machine.reg_write(register, struct.unpack('<Q', struct.pack('<d', value))[0])


class OriginalGeometry:
    def __init__(self, binary, disable_al, prior_library, columns=3, rows=4):
        # Lock the inspected geometry code; reject unknown versions/architectures.
        if struct.unpack_from('<I', binary)[0] != 0xfeedfacf:
            raise ValueError('Supply the audited thin arm64e slice, not a fat file')
        code = binary[0x4000:0x4000 + 12008]
        if hashlib.sha256(code).hexdigest() != '00a02d5118d67ae1ab42c735dbcab325b0716ddcdb82214bda92f0f4c9b87971':
            raise ValueError('Unverified PrimalFolder executable code')
        self.uc = Uc(UC_ARCH_ARM64, UC_MODE_ARM)
        self.uc.mem_map(0, 0x50000)
        self.uc.mem_write(0, binary)
        self.uc.mem_write(0x102d0, bytes([prior_library, disable_al, 1, 0, 0]))
        self.uc.mem_write(0xc178, struct.pack('<Q', 0x30000))
        self.uc.mem_write(0x30000, struct.pack('<d', 1953.0))
        self.columns, self.rows = columns, rows
        self.trace = []
        self.decoded = {i.address: i for i in Cs(CS_ARCH_ARM64, CS_MODE_ARM).disasm(code, 0x4000)}
        self.uc.hook_add(UC_HOOK_CODE, self.step)

    def step(self, uc, address, size, unused):
        del size, unused
        ins = self.decoded.get(address)
        dependency_entries = (0x6338, 0x63b0, 0x6428, 0x64a0, 0x6590, 0x6518)
        if ins and ins.mnemonic in ('pacibsp', 'autibsp') and address not in dependency_entries:
            # PAC is not an emulator dependency: only stack return signing is
            # bypassed. The original instructions/branch conditions stay intact.
            uc.reg_write(UC_ARM64_REG_PC, address + 4)
            return
        if ins and ins.mnemonic == 'retab':
            uc.reg_write(UC_ARM64_REG_PC, uc.reg_read(UC_ARM64_REG_X30))
            return
        if address == 0x49c0:
            self.trace.append('rect updates shared classification')
        if address in (0x4c10, 0x4d80):
            self.trace.append('reads prior shared classification=' + str(uc.mem_read(0x102d0, 1)[0]))
        if address == 0x4c84:
            # Original (non-Primal) grid: 3x4, 13-point cells + 3-point gaps.
            # Substitute at the opaque signed function pointer call only.
            floating(uc, UC_ARM64_REG_D0, self.columns * 13 + (self.columns - 1) * 3)
            floating(uc, UC_ARM64_REG_D1, self.rows * 13 + (self.rows - 1) * 3)
            self.trace.append('forwards original grid size')
            uc.reg_write(UC_ARM64_REG_PC, address + 4)
            return
        if address == 0x4a98:
            for reg, value in [(UC_ARM64_REG_D0, 0), (UC_ARM64_REG_D1, 0),
                               (UC_ARM64_REG_D2, 13), (UC_ARM64_REG_D3, 13)]:
                floating(uc, reg, value)
            self.trace.append('forwards original small-cell rect')
            uc.reg_write(UC_ARM64_REG_PC, address + 4)
            return
        # Explicit UIKit/ObjC dependency stubs, common to all contrasts.
        if address in (0x70b8, 0x70d8):  # retain / autoreleased-return retain
            pass
        elif address == 0x70a8:  # release
            pass
        elif address == 0x7668:  # layout->_layoutConfiguration (KVC)
            uc.reg_write(UC_ARM64_REG_X0, 0x31000)
        elif address == 0x7548:
            uc.reg_write(UC_ARM64_REG_X0, self.columns)
        elif address == 0x7528:
            uc.reg_write(UC_ARM64_REG_X0, self.rows)
        elif address in (0x6338, 0x63b0, 0x6428, 0x64a0, 0x6590):
            uc.reg_write(UC_ARM64_REG_X0, 0)  # audited non-iPad device alternatives
        elif address == 0x6518:
            uc.reg_write(UC_ARM64_REG_X0, 1)  # native-height 2796 device branch
        else:
            return
        uc.reg_write(UC_ARM64_REG_PC, uc.reg_read(UC_ARM64_REG_X30))

    def call(self, method, cell=0, max_count=12):
        start = {'size': 0x4bbc, 'rect': 0x4934}[method]
        self.uc.reg_write(UC_ARM64_REG_SP, 0x4f000)
        self.uc.reg_write(UC_ARM64_REG_X30, 0x40000)
        for reg in (UC_ARM64_REG_X0, UC_ARM64_REG_X1):
            self.uc.reg_write(reg, 0x31000)
        self.uc.reg_write(UC_ARM64_REG_X2, 0x31000 if method == 'size' else cell)
        self.uc.reg_write(UC_ARM64_REG_X3, 0x31000)
        self.uc.reg_write(UC_ARM64_REG_X4, max_count)
        self.uc.emu_start(start, 0x40000, count=10000)
        if self.uc.reg_read(UC_ARM64_REG_PC) != 0x40000:
            raise RuntimeError('Routine failed to return within bounded instruction count')
        regs = [UC_ARM64_REG_D0, UC_ARM64_REG_D1]
        if method == 'rect':
            regs += [UC_ARM64_REG_D2, UC_ARM64_REG_D3]
        return [floating(self.uc, reg) for reg in regs]


def run(binary):
    results = []
    for enabled in (1, 0, 1):  # A -> B -> A, fixture inputs otherwise identical
        model = OriginalGeometry(binary, enabled, 1)
        initial_size = model.call('size')
        first_rect = model.call('rect')
        later_size = model.call('size')
        row = {'disableAL': enabled, 'prior_shared_library_flag': 1,
               'first_canvas_points': initial_size, 'first_cell_rect': first_rect,
               'shared_flag_after_rect': model.uc.mem_read(0x102d0, 1)[0],
               'later_canvas_points': later_size, 'trace': model.trace}
        assert first_rect == [0.0, 0.0, 64.0, 64.0]
        assert initial_size == ([45.0, 61.0] if enabled else [64.0, 64.0])
        assert later_size == [64.0, 64.0]
        results.append(row)
    control = OriginalGeometry(binary, 1, 0)
    assert control.call('size') == [64.0, 64.0]
    stock_grid = OriginalGeometry(binary, 1, 1, columns=3, rows=3)
    stock_canvas = stock_grid.call('size')
    stock_rect = stock_grid.call('rect', max_count=9)
    assert stock_canvas == [45.0, 45.0] and stock_rect == [0.0, 0.0, 64.0, 64.0]
    return {'original_instruction_code_sha256': hashlib.sha256(binary[0x4000:0x4000+12008]).hexdigest(),
            'contrast': results, 'fresh_flag_control': [64, 64],
            'three_by_three_grid_control': {'canvas_points': stock_canvas,
                'first_cell_rect': stock_rect,
                'meaning': 'Simulated stock grid also permits size mismatch; no Bolders executable runs in this emulator. Not a live Primal-only app test.'},
            'dependency_stubs': 'ObjC KVC/retain/release, original 13px-cell grid, iPhone15,3 predicates and CF version',
            'device_preferences_changed': False, 'live_drag_contrast_executed': False,
            'interpretation': 'Original dimension branch and stale-state scenario reproduced in emulator, not actual UIKit/cache or live callback trace.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('thin_binary')
    parser.add_argument('output')
    args = parser.parse_args()
    result = run(Path(args.thin_binary).read_bytes())
    Path(args.output).write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
