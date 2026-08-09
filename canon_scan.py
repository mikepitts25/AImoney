import re, sys, html as H

FILES = ['agency-plan.html', 'agency-steps.html']

BANNED_STATS = [
    (r'\b62%\s*(of|hang)', 'banned 62% stat'),
    (r'\$1,200\b(?![^<]{0,40}(Bundle|established|tier|ARPU|CAC|monthly))', '$1,200 (check: banned per-missed-call figure?)'),
    (r'\b21x\b', 'banned 2007 21x stat'),
    (r'\$45[,K]', 'banned $45K loss claim'),
    (r'30-40%\s*of (calls|the time)', 'banned 30-40% missed-calls'),
    (r'78%\s*of (callers|consumers)', 'banned 78% hang-up'),
    (r'(Fewer than|<|less than)\s*1%[^<]{0,40}AI', 'banned <1% AI adoption'),
    (r'500,000\+\s*home', 'banned 500k businesses'),
    (r'\$3,000-\$10,000\s*job', 'banned per-missed-call job value'),
    (r'unlimited (calls|minutes)', 'forbidden "unlimited" pricing claim'),
]

OFF_LADDER_PRICES = [
    (r'\$697\b', '$697 not on ladder'),
    (r'\$997/mo', '$997/mo not on ladder'),
    (r'\$2,000-\$3,000/month', 'off-ladder monthly range'),
    (r'\$500-\$2,000/month', 'off-ladder monthly range'),
]

OWNER_DRIFT = [
    (r'Paola[^.<]{0,70}\b(cold call|cold email|quotes? the price|closing|prospect list|Smartlead campaign|Apollo)', 'Paola assigned Mike-owned sales work'),
    (r'Both[^.<]{0,40}\b(demo call|sales call|cold call)', '"Both" on a single-owner sales task'),
    (r'whoever is (more )?comfortable', 'ambiguous ownership'),
]

TIME_DRIFT = [
    (r'20-25 hours/week', 'stale hours claim'),
    (r'~22 hrs/week(?! each &mdash; this table)', 'stale hours claim'),
    (r'9-11 ?AM local time', 'ambiguous calling window'),
    (r'\b(free trial|7-day free)', 'free trial contradicts $250 paid pilot'),
]

MODEL_DRIFT = [
    (r'gpt-4o', 'stale model id'),
    (r'claude-3-(opus|sonnet|haiku)(?![^<]{0,60}deprecat)', 'stale model id'),
    (r'Ubuntu 22\.04', 'stale OS'),
    (r'YOUR_IP:5678', 'plain-IP webhook'),
    (r'N8N_PROTOCOL=http\b', 'plain HTTP n8n'),
]

GROUPS = [('BANNED STAT', BANNED_STATS), ('OFF-LADDER PRICE', OFF_LADDER_PRICES),
          ('OWNER DRIFT', OWNER_DRIFT), ('TIME/OFFER DRIFT', TIME_DRIFT), ('STALE TECH', MODEL_DRIFT)]

# lines inside the deliberate "stop using these" callout are exempt
EXEMPT_MARKERS = ['Stop using these three', 'stop-using', 'traces to a 202', 'Oldroyd', 'banned', 'do not quote', 'Never say &ldquo;unlimited', 'Never say "unlimited']


CANON_NUMBERS = [
    (r'~?60 dials', 'stale dial number (canon is 50/week = 15+15+20)'),
    (r'100 dials', 'stale dial number (canon is 50/week)'),
    (r'20 dials (?:a|per) day', 'dials/day implies weekday sessions Mike does not have'),
    (r'3-5\s*pm CET(?![^<]{0,80}(day job|nobody|full-timer))', 'forbidden window quoted without the day-job caveat'),
    (r'15:00-17:00 CET(?![^<]{0,120}(nobody|day job|Saturday|full-timer))', 'forbidden weekday window without caveat'),
    (r'golden window(?![^<]{0,120}(Saturday|nobody|day job))', '"golden window" without the Saturday/day-job caveat'),
]
GROUPS.append(('CANON NUMBER', CANON_NUMBERS))

total = 0
for f in FILES:
    lines = open(f).read().split('\n')
    for i, line in enumerate(lines, 1):
        if any(m in line for m in EXEMPT_MARKERS):
            continue
        for gname, pats in GROUPS:
            for pat, why in pats:
                if re.search(pat, line, re.I):
                    total += 1
                    txt = re.sub(r'<[^>]+>', ' ', line).strip()
                    print(f'{f}:{i}  [{gname}] {why}')
                    print(f'      {txt[:150]}')
                    break
print(f'\nTOTAL FLAGS: {total}')
