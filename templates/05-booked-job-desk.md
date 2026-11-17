# The Booked-Job Desk: Build Kit
## Everything you need to run a client, from onboarding to invoice

> This kit goes with `operating-plan.html`. Practise the whole loop on
> `templates/sample-customers.csv` and `templates/sample-jobs.csv` (fake data)
> before you touch a real client's file.

---

## 1. The one-page pilot agreement (send before any data changes hands)

```
REACTIVATION PILOT AGREEMENT: Colibri Code LLC and {{CLIENT_BUSINESS}}

1. What we do: we prepare one win-back campaign to {{CLIENT_BUSINESS}}'s past
   customers who haven't booked in 12+ months. {{CLIENT_BUSINESS}} approves every
   message before it sends. Messages send from {{CLIENT_BUSINESS}}'s own systems.

2. What it costs: $0 up front. $75 per booked job.

3. Booked job: a job created in {{CLIENT_BUSINESS}}'s job board within 30 days of
   the send, for a customer on the approved send list, who had no job already
   scheduled at send time. One per customer per campaign. We reconcile from
   {{CLIENT_BUSINESS}}'s own job export on days 7, 14 and 30. Disputed rows are
   decided in {{CLIENT_BUSINESS}}'s favour.

4. Invoice: after day 30, payable within 14 days by card or bank transfer (Stripe).

5. Data: we use the customer export only to run this campaign, store it in one
   access-controlled folder, and delete it within 30 days of the end of the
   engagement on request. We never sell, share or reuse it.

6. Consent: {{CLIENT_BUSINESS}} confirms these are its own customers, and that any
   customer marked for text messages has given consent to receive them.

7. Either side can stop at any time. Jobs booked before stopping are still billable.

Signed: ________________ (Colibri Code)   ________________ ({{CLIENT_BUSINESS}})
```

---

## 2. Onboarding checklist (Paola, 30-minute screenshare)

- [ ] Agreement signed
- [ ] **Customer export** (Jobber: Clients → export; Housecall Pro: Customers → export). We need the columns in section 3. Rename columns in a sheet if the export uses different names.
- [ ] **Job export** with created dates. This is the ledger source, so ask how to export it on day 7.
- [ ] **Text consent:** where do they record it? If they don't, **email only**.
- [ ] Any customers in **Florida or Oklahoma?** Email only unless written consent is on file.
- [ ] **Sending channel:** Jobber Campaigns (Marketing Suite), Housecall Pro's marketing tools if their plan has them, or their own email platform on their domain.
- [ ] **Email domain health:** SPF, DKIM and DMARC records exist, and the sending tool adds one-click unsubscribe. Use a free checker; if anything is missing, fix it with their web person first.
- [ ] **Approved facts:** current offer or price (if any), booking phone, service area, hours. **We only use what they write down.**
- [ ] **Who books the replies?** Name and phone of their office person. Spanish replies: does Paola answer them, or their team?
- [ ] Google review link (for the review-request add-on later)

---

## 3. Customer CSV columns (what the scripts expect)

| Column | Required | Notes |
|---|---|---|
| `first_name` | yes | used as `{first_name}` in messages |
| `email` | one of email / phone | blank = no email |
| `phone` | one of email / phone | texts only if `sms_consent` = yes |
| `last_job_date` | yes | YYYY-MM-DD or MM/DD/YYYY |
| `last_service` | recommended | free text, e.g. "furnace repair" |
| `language` | optional | `es` for Spanish-speaking customers (Paola can tag these) |
| `sms_consent` | optional | yes / no. Treat blank as no |
| `unsubscribed` | optional | yes = excluded |
| `has_upcoming_job` | optional | yes = excluded |

---

## 4. Segment and draft (Mike)

```bash
# 1. Segment only (no API key needed) and check the counts look right
python tools/draft_campaign.py --customers clients/abc/customers.csv \
  --business "ABC Heating & Air" --city "Phoenix, AZ" \
  --theme "Furnace safety check before the first cold snap" \
  --out clients/abc/2026-11 --dry-run

# 2. Draft (needs ANTHROPIC_API_KEY, or an `ant auth login` profile)
python tools/draft_campaign.py ... --facts "Tune-up \$89 through Dec 15" --out clients/abc/2026-11
```

Outputs:
- `send_list.csv`: who gets the campaign, and whether by email, text or both
- `drafts_for_review.csv`: 2 variants per segment, all marked `NEEDS REVIEW`

**No API?** Paste this into the Claude app, once per segment:

```
You write win-back messages that {{BUSINESS}} in {{CITY}} sends to its OWN past
customers. Theme: {{THEME}}. Audience: {{N}} customers whose last job was
{{SERVICE}} and who haven't booked in 12+ months. Approved facts (use only
these): {{FACTS}}. Language: {{English / Spanish}}.
Write 2 variants. Each one: a subject line; an email of 60-110 words, warm and plain
like a note from the office manager, ending with "reply to this email or call
{business_phone}"; and an SMS of at most 300 characters that starts with the
business name and ends "Reply STOP to opt out." Keep {first_name} as written. No
invented discounts, prices, guarantees, or mention of AI.
```

---

## 5. Review rules (Paola: nothing sends unreviewed)

1. Every fact is in the approved-facts list. Delete anything that isn't.
2. It reads like a person from the business wrote it, with no hype words.
3. The Spanish is natural, not translated word for word. Adjust *usted* or *tú* to match the client's style.
4. The SMS starts with the business name, ends with opt-out wording, and is 300 characters or fewer.
5. Mark the chosen variant `APPROVED`, then send a preview to the client: "Reply OK to send on {{date}} at 8:30am your time."

---

## 6. Ready-to-adapt templates

### November-December: HVAC (English)
**Subject:** Before the first real cold night, {first_name}

> Hi {first_name}, it's the team at {{BUSINESS}}. It's been a while since we were out to your place, so a quick reminder before the cold sets in: a furnace that's sat since last winter is the one that quits on the coldest night. We're booking safety checks now. Reply to this email or call {business_phone} and we'll find a time that works. Thanks for being a customer. {{OWNER_NAME}}

**SMS:** {{BUSINESS}}: Hi {first_name}, booking furnace safety checks before the cold sets in. Want a spot? Reply YES or call {business_phone}. Reply STOP to opt out.

### Noviembre-diciembre: HVAC (Spanish)
**Asunto:** Antes de la primera noche fría, {first_name}

> Hola {first_name}, le escribe el equipo de {{BUSINESS}}. Hace tiempo que no le visitamos, así que un recordatorio antes del frío: un calentador que no se ha revisado desde el invierno pasado es el que falla en la noche más fría. Estamos agendando revisiones de seguridad. Responda a este correo o llame al {business_phone} y buscamos un horario que le convenga. Gracias por su confianza. {{OWNER_NAME}}

**SMS:** {{BUSINESS}}: Hola {first_name}, estamos agendando revisiones del calentador antes del frío. ¿Le apartamos un horario? Responda SÍ o llame al {business_phone}. Responda STOP para no recibir más mensajes.

### March-April: AC tune-up (the year's biggest win-back)
**Subject:** Beat the first heatwave, {first_name}

> Hi {first_name}, it's {{BUSINESS}}. Every year the first hot week brings a rush of AC calls, and the wait gets long. If your system hasn't had a tune-up since last summer, now's the easy time to do it. Reply here or call {business_phone} and we'll get you on the schedule before the rush. {{OWNER_NAME}}

### Water heater (plumbing, any month)
**Subject:** How old is your water heater, {first_name}?

> Hi {first_name}, it's {{BUSINESS}}. Most tank water heaters last 8-12 years, and a yearly flush helps them get there. If it's been a while, we can check yours and tell you honestly whether it's got years left. Reply or call {business_phone}. {{OWNER_NAME}}

### Open-estimate follow-up (Desk retainer, weekly)
**Subject:** Any questions on your estimate, {first_name}?

> Hi {first_name}, just checking in on the estimate we sent for {{JOB_TYPE}}. Happy to answer questions or adjust anything. If the timing isn't right, no problem at all. Just reply here or call {business_phone}. {{OWNER_NAME}}

*(One follow-up at day 7 and one at day 21. Never more than two.)*

---

## 7. Sending (Mike)

- **Jobber Campaigns:** build a segment that matches `send_list.csv` (or import tags), paste in the approved copy, and schedule for 8:30am client time.
- **Own email platform:** import `send_list.csv` rows where `can_email = yes`, with the unsubscribe header on, from the client's authenticated domain.
- **Texts:** only rows with `can_text = yes`, from the client's own texting tool, 8am-9pm recipient local time.
- Write the actual send date into `send_list.csv`, which the ledger needs.

---

## 8. Ledger and invoice (Paola: days 7, 14, 30)

```bash
python tools/reconcile_ledger.py --send-list clients/abc/2026-11/send_list.csv \
  --jobs clients/abc/jobs_export_day30.csv --send-date 2026-11-20 --rate 75 \
  --out clients/abc/2026-11/ledger.csv
```

The job export needs `customer_email`, `customer_phone`, `created_date` and `job_total`. Review `ledger.csv` with the client, remove anything they dispute, then send the Stripe invoice with the ledger attached.

**Desk retainer invoice:** $400 + $40 × booked jobs that month (all campaigns plus the estimate sweep), capped at $1,500.

---

## 9. The case study (after the first pilot)

> "{{CLIENT}} in {{CITY}} had {{N}} customers who hadn't booked in a year. One campaign, approved by the owner and sent from their own Jobber, booked {{X}} jobs worth ${{Y}} in 30 days. They paid ${{X×75}}."

Get written permission before using the client's name. Otherwise say "an HVAC company in Phoenix".
