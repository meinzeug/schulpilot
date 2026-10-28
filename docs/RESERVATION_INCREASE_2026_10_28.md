# Explicit reservation increase

The operator requested an increase of EUR 3 per AI job. The local operator
command `schulpilot.reservation_adjustment` applies this once per explicit
operation ID, with an expected provider revision and audit records. It refuses
to run while queued or running jobs are present. Existing cost receipts, open
reservations, account limits, emergency stops, models, privacy approvals and
output limits are not changed.

The stored budget exchange quote is USD-to-EUR 0.890869; EUR 3 therefore adds
USD 3.367499, rounded up to the next microdollar. The currency quote is an
accounting estimate, not a claim about the actual bank exchange rate. The
separate 8% estimated fee allowance remains unchanged. Holds are not charges;
reported actual costs are settled as before, and unknown charges stay held.

The existing EUR-denominated child limits, family limits and the service-wide
monthly USD limit remain authoritative. A higher hold can therefore prevent
concurrent jobs when little budget remains. Very large inputs may still exceed
the requested higher hold; the conservative image preflight remains active.
The separate Schulbuddy binding keeps its verified model/provider/effort; the
base provider revision changes so in-flight snapshots are rejected.

Before production use: back up project configuration and database, complete
build and tests, and use a fixed idempotency key. Once the matching source is
deployed, run locally with the exact currently verified provider revision:

```sh
python -m schulpilot.reservation_adjustment --expected-revision 33 --operation reserve-plus-3eur-20261028
```

The command is not exposed over HTTP. It never invokes a provider, and does not
implicitly select or approve Terra. Roll back by an explicit, audited operator
change to the saved values; do not roll back the database over newer activity.
