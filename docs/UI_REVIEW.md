# Midnight Premiere UI verification

The interface was rebuilt using the supplied skill at `D:/compiler project/.agents/skills/modern-web-ui/SKILL.md`.

Verified in the running browser:

- Desktop layout at 1440px: page content width 1425px, with no horizontal page overflow.
- Mobile layout at 390px: content width 375px, with no horizontal page overflow; seat controls measure 44 x 44px and scroll within their own map.
- Selecting Dune updates the active show, featured artwork, screen, date, and seat inventory.
- Selecting B4 updates the seat summary and total to INR 300.
- Customer form accepts input and displays the API's duplicate-email error without changing an existing customer.
- Booking history displays saved tickets, customers, seats, amounts, and cancellation controls.
- Database lab executes the customer SELECT against the live database and displays four rows.
- Fonts are served locally; the Prata font endpoint returns HTTP 200.
- JavaScript syntax checks pass for public/app.js and src/server.js.
- Browser console was clear before the intentional duplicate-email request.

The PostgreSQL schema, booking functions, payment behavior, and existing data were preserved. The previously completed database tests remain in TEST_EVIDENCE.md. This UI pass did not create a new booking.

Screenshots: `midnight-premiere.png`, `mobile-redesign.png`, and `database-lab-redesign.png`.
