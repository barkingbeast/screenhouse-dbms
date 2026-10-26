# Entity relationships

```mermaid
erDiagram
  CUSTOMERS ||--o{ BOOKINGS : makes
  MOVIES ||--o{ SHOWS : scheduled_as
  THEATRES ||--o{ SCREENS : contains
  SCREENS ||--o{ SEATS : contains
  SCREENS ||--o{ SHOWS : hosts
  SHOWS ||--o{ BOOKINGS : receives
  SHOWS ||--o{ SHOW_SEATS : offers
  SEATS ||--o{ SHOW_SEATS : appears_in
  BOOKINGS o|--o{ SHOW_SEATS : currently_owns
  BOOKINGS ||--|{ BOOKING_SEATS : records
  SHOW_SEATS ||--o{ BOOKING_SEATS : has_history
  BOOKINGS ||--|{ PAYMENTS : records
  PAYMENTS ||--|| LEDGER_TRANSACTIONS : posts
  LEDGER_TRANSACTIONS ||--|{ LEDGER_ENTRIES : contains
  LEDGER_ACCOUNTS ||--o{ LEDGER_ENTRIES : groups
  LEDGER_TRANSACTIONS o|--o| LEDGER_TRANSACTIONS : reverses
```

`show_seats` is current inventory; `booking_seats` is historical membership. The composite keys validate that a booking and its seat allocation refer to the same show, and that every seat belongs to the show's screen.

Every payment/refund posts one journal with two entries. Refund journals reference the original payment journal through reverses_id. Journal and payment records reject UPDATE, DELETE, and TRUNCATE; deferred constraints verify balances at commit.
