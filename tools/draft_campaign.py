"""Booked-Job Desk: segment a client's customer export and draft a win-back campaign.

Reads a customer CSV (the columns are listed in templates/05-booked-job-desk.md),
keeps the dormant customers, groups them by service type and language, and asks
Claude for two short campaign variants per segment. Nothing is sent from here:
the output is a review sheet for Paola and a send list for the client's own tool.

    pip install "anthropic>=1.13"
    python tools/draft_campaign.py --customers clients/abc/customers.csv \
        --business "ABC Heating & Air" --city "Phoenix, AZ" \
        --theme "Furnace safety check before the first cold snap" \
        --out clients/abc/2026-11

Add --dry-run to segment without calling the API (no key needed).
"""
import argparse
import csv
import datetime as dt
import json
import os
import sys
from collections import defaultdict

MODEL = "claude-opus-5-5"
FALLBACK_BETA = "server-side-fallback-2026-07-01"

DRAFT_SCHEMA = {
    "type": "object",
    "properties": {
        "variants": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "subject": {"type": "string"},
                    "email_body": {"type": "string"},
                    "sms": {"type": "string"},
                },
                "required": ["subject", "email_body", "sms"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["variants"],
    "additionalProperties": False,
}

SYSTEM = (
    "You write win-back messages that a home-service contractor sends to its OWN past "
    "customers. Write as the business, warm and plain, like a note from the office "
    "manager, not like an ad. Rules: one clear reason to book now tied to the theme; "
    "no invented discounts, prices, guarantees or urgency the business didn't supply; "
    "no mention of AI; keep the merge field {first_name} exactly as written; the email "
    "body is 60-110 words and ends with a simple way to book (reply, or call "
    "{business_phone}); the SMS is at most 300 characters, starts with the business "
    "name and ends with 'Reply STOP to opt out.' Write in the language you are asked for."
)


def parse_date(value):
    for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%m/%d/%y", "%d.%m.%Y"):
        try:
            return dt.datetime.strptime(value.strip(), fmt).date()
        except (ValueError, AttributeError):
            continue
    return None


def truthy(value):
    return str(value or "").strip().lower() in {"y", "yes", "true", "1", "x"}


def load_segments(path, dormant_months, today):
    cutoff = today - dt.timedelta(days=int(dormant_months * 30.4))
    segments = defaultdict(list)
    skipped = defaultdict(int)
    with open(path, newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            last = parse_date(row.get("last_job_date", ""))
            if truthy(row.get("unsubscribed")):
                skipped["unsubscribed"] += 1
            elif truthy(row.get("has_upcoming_job")):
                skipped["already scheduled"] += 1
            elif last is None:
                skipped["no last_job_date"] += 1
            elif last > cutoff:
                skipped["not dormant"] += 1
            elif not (row.get("email") or "").strip() and not truthy(row.get("sms_consent")):
                skipped["no email and no text consent"] += 1
            else:
                lang = (row.get("language") or "en").strip().lower()[:2] or "en"
                service = (row.get("last_service") or "general service").strip().lower()
                row["_can_email"] = "yes" if (row.get("email") or "").strip() else "no"
                row["_can_text"] = "yes" if truthy(row.get("sms_consent")) and (row.get("phone") or "").strip() else "no"
                segments[(service, lang)].append(row)
    return segments, skipped


def draft(client, args, service, lang, rows):
    language = "Spanish (Latin American, natural, not literal)" if lang == "es" else "English (US)"
    user = (
        f"Business: {args.business} in {args.city}. Phone: {{business_phone}}.\n"
        f"Campaign theme: {args.theme}\n"
        f"Audience: {len(rows)} past customers whose last job was '{service}' "
        f"and who haven't booked in {args.dormant_months}+ months.\n"
        f"Extra facts the business approved (use only these): {args.facts or 'none'}\n"
        f"Language: {language}\n"
        "Give two variants that differ in angle (e.g. safety vs. convenience)."
    )
    resp = client.beta.messages.create(
        model=MODEL,
        max_tokens=4000,
        betas=[FALLBACK_BETA],
        fallbacks="default",
        system=SYSTEM,
        output_config={"format": {"type": "json_schema", "schema": DRAFT_SCHEMA}},
        messages=[{"role": "user", "content": user}],
    )
    if resp.stop_reason == "refusal":
        return []
    text = next((b.text for b in resp.content if b.type == "text"), "")
    return json.loads(text).get("variants", [])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--customers", required=True)
    ap.add_argument("--business", required=True)
    ap.add_argument("--city", required=True)
    ap.add_argument("--theme", required=True)
    ap.add_argument("--facts", default="", help="approved facts, e.g. 'Tune-up is $89 through Dec 15'")
    ap.add_argument("--dormant-months", type=int, default=12)
    ap.add_argument("--min-segment", type=int, default=15, help="smaller segments merge into 'general service'")
    ap.add_argument("--out", required=True, help="output folder")
    ap.add_argument("--today", help="YYYY-MM-DD, for testing")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    today = dt.date.fromisoformat(args.today) if args.today else dt.date.today()
    segments, skipped = load_segments(args.customers, args.dormant_months, today)

    # fold tiny segments into a general one per language
    merged = defaultdict(list)
    for (service, lang), rows in segments.items():
        key = (service, lang) if len(rows) >= args.min_segment else ("general service", lang)
        merged[key].extend(rows)

    os.makedirs(args.out, exist_ok=True)
    send_path = os.path.join(args.out, "send_list.csv")
    with open(send_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["segment", "language", "first_name", "email", "phone", "can_email", "can_text", "last_job_date", "send_date"])
        for (service, lang), rows in sorted(merged.items()):
            for r in rows:
                w.writerow([service, lang, r.get("first_name", ""), r.get("email", ""), r.get("phone", ""),
                            r["_can_email"], r["_can_text"], r.get("last_job_date", ""), ""])

    print(f"Dormant customers by segment ({args.dormant_months}+ months):")
    for (service, lang), rows in sorted(merged.items(), key=lambda kv: -len(kv[1])):
        print(f"  {service:<24} {lang}  {len(rows):>5}")
    print("Skipped:", dict(skipped) or "none")
    print(f"Send list: {send_path}")

    if args.dry_run:
        return

    try:
        import anthropic
    except ImportError:
        sys.exit("pip install 'anthropic>=1.13' (or use --dry-run)")
    client = anthropic.Anthropic()
    drafts_path = os.path.join(args.out, "drafts_for_review.csv")
    with open(drafts_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["segment", "language", "customers", "variant", "subject", "email_body", "sms", "status", "reviewer_notes"])
        for (service, lang), rows in sorted(merged.items()):
            variants = draft(client, args, service, lang, rows)
            if not variants:
                w.writerow([service, lang, len(rows), "-", "", "", "", "WRITE BY HAND (model declined)", ""])
            for i, v in enumerate(variants, 1):
                w.writerow([service, lang, len(rows), i, v["subject"], v["email_body"], v["sms"], "NEEDS REVIEW", ""])
    print(f"Drafts for Paola's review: {drafts_path}")


if __name__ == "__main__":
    main()
