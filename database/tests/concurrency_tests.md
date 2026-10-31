# Concurrent acceptance test

Run this against a disposable database initialized with the schema. The separate `psql`
processes are separate database connections. The `pg_sleep` calls make the lock overlap
easy to observe; both sessions try to claim the same available donation.

1. Prepare one available donation and two `NOTIFIED` NGO claim rows, with active NGO
   organizations, active memberships, and users. Use a disposable test fixture, not
   production data.
2. Save the IDs as `DONATION_ID`, `NGO_A_ID`, `NGO_B_ID`, `USER_A_ID`, and `USER_B_ID`.
3. In two terminals, run the following at approximately the same time:

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c \
  "BEGIN; SELECT pg_sleep(1); SELECT * FROM accept_donation('$DONATION_ID', '$NGO_A_ID', '$USER_A_ID'); COMMIT;"
```

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c \
  "BEGIN; SELECT pg_sleep(1); SELECT * FROM accept_donation('$DONATION_ID', '$NGO_B_ID', '$USER_B_ID'); COMMIT;"
```

Exactly one call must return `success = true, result_code = ACCEPTED`; the other must
return `success = false, result_code = ALREADY_CLAIMED_OR_UNAVAILABLE`. Verify:

```sql
SELECT count(*) = 1 AS one_winner
FROM donation_claims
WHERE donation_id = :'DONATION_ID' AND status = 'ACCEPTED';
```

The function locks the donation row before checking eligibility and changing either the
donation or claim. Both changes and the outbox records commit atomically.
