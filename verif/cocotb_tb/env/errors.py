"""Shared exception taxonomy for scoreboard/test failures, so a failure's
*type* (not just its message) tells you which category of bug caught it --
see docs/verification/bug_list.md for the full catalog:

- MismatchError   -- a scoreboard's golden-model/shadow-model compare found
                      a data mismatch (bugs #1/#2/#3/#4).
- CModelError     -- the C++ golden model itself failed/errored (nonzero
                      exit), as opposed to its output mismatching RTL --
                      see golden_model.py (bugs #8/#9/#10).
- pyuvm.UVMError/UVMFatalError (uvm_error()/uvm_fatal()) -- a single
                      status/register-level check failed (bugs #5/#6/#7).
"""


class MismatchError(AssertionError):
    """A scoreboard compare (RTL vs. golden model/shadow) found a data
    mismatch. Subclasses AssertionError since it's conceptually the same
    "this should have been equal and wasn't" -- just given its own name so
    it reads distinctly from a generic Python assert in failure summaries."""
