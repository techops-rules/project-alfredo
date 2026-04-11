# Email Filter Rules

## Always surface (keywords in subject)
- invoice, payment due, appointment, school, medical
- flight, reservation, confirmation, renewal
- action required, response needed, expiring

## Always ignore (senders)
- noreply@, marketing@, newsletter@, promotions@

## Always ignore (keywords)
- unsubscribe, sale, % off, limited time, deal, coupon
- social media, liked your, commented on, followed you

## Notes
- Unknown senders: ignore unless subject matches "always surface" keywords
- Calendar invites from any sender: always surface
- Shipping/tracking: surface only if from a known contact or recent order
