"""Booked-Job Desk: count booked jobs for a campaign from the client's own job board.

A booked job = a job CREATED on or after the send date and within the window
(default 30 days), for a customer on the send list (matched by email or phone),
excluding customers who had a job scheduled before the send. Disputed rows are
the client's call, so review the output with them.

    python tools/reconcile_ledger.py --send-list clients/abc/2026-11/send_list.csv \
        --jobs clients/abc/jobs_export.csv --send-date 2026-11-20 --rate 75
"""
import argparse
import csv
import datetime as dt
import re


def norm_phone(p):
    digits = re.sub(r"\D", "", p or "")
    return digits[-10:] if len(digits) >= 10 else ""


def norm_email(e):
    return (e or "").strip().lower()


def parse_date(value):
    for fmt in ("%Y-%m-%d", "%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d %H:%M"):
        try:
            return dt.datetime.strptime((value or "").strip(), fmt).date()
        except ValueError:
            continue
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--send-list", required=True)
    ap.add_argument("--jobs", required=True, help="job board export: customer_email, customer_phone, created_date, job_total")
    ap.add_argument("--send-date", required=True, help="YYYY-MM-DD")
    ap.add_argument("--window-days", type=int, default=30)
    ap.add_argument("--rate", type=float, default=75.0, help="$ per booked job")
    ap.add_argument("--out", default="ledger.csv")
    args = ap.parse_args()

    send_date = dt.date.fromisoformat(args.send_date)
    end = send_date + dt.timedelta(days=args.window_days)

    emails, phones = {}, {}
    with open(args.send_list, newline="", encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            name = r.get("first_name", "")
            if norm_email(r.get("email")):
                emails[norm_email(r["email"])] = name
            if norm_phone(r.get("phone")):
                phones[norm_phone(r["phone"])] = name

    booked, seen = [], set()
    with open(args.jobs, newline="", encoding="utf-8-sig") as f:
        for j in csv.DictReader(f):
            created = parse_date(j.get("created_date"))
            if not created or not (send_date <= created <= end):
                continue
            e, p = norm_email(j.get("customer_email")), norm_phone(j.get("customer_phone"))
            key = e or p
            if key in seen:
                continue  # one booked job per customer per campaign
            if e in emails or p in phones:
                seen.add(key)
                booked.append({"customer": emails.get(e) or phones.get(p), "email": e, "phone": p,
                               "created_date": created.isoformat(), "job_total": j.get("job_total", "")})

    with open(args.out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["customer", "email", "phone", "created_date", "job_total"])
        w.writeheader()
        w.writerows(booked)

    revenue = sum(float(re.sub(r"[^\d.]", "", b["job_total"]) or 0) for b in booked)
    print(f"Window {send_date} to {end}: {len(booked)} booked jobs, ${revenue:,.0f} in job value")
    print(f"Pilot invoice at ${args.rate:.0f}/job: ${len(booked) * args.rate:,.0f}")
    print(f"Ledger written to {args.out}. Review it with the client before invoicing.")


if __name__ == "__main__":
    main()
