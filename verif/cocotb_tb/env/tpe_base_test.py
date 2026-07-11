"""Common raise/drop-objection scaffolding shared by every block's pyuvm
uvm_test. Subclasses build self.env in build_phase and implement
run_test_body() instead of run_phase() directly."""
from pyuvm import uvm_test


class TpeBaseTest(uvm_test):
    async def run_phase(self):
        self.raise_objection()
        await self.run_test_body()
        self.drop_objection()

    async def run_test_body(self):
        raise NotImplementedError
