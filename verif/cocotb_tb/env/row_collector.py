"""Reusable pyuvm subscriber collecting {addr: rdata} from a
SyncPortMonitor's analysis port for read transactions. Originally written
for the Matrix Compute Engine's output buffer readback (M2); promoted here
since the DMA testbench (M3) needs the identical pattern for its SRAM/DDR
backdoor readback. See sync_port_monitor.py -- txn.rdata already
corresponds to txn.addr in the same transaction, no reordering needed."""
import pyuvm


class RowCollector(pyuvm.uvm_subscriber):
    def build_phase(self):
        self.collected = {}

    def write(self, txn):
        if txn.en and not txn.we:
            self.collected[txn.addr] = txn.rdata

    def clear(self):
        self.collected = {}
