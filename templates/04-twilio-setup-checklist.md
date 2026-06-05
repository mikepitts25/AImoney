# Twilio Setup Checklist
## Buying a Number, Connecting to Vapi, Configuring SMS

> **How to use:** Follow these steps for EACH client you onboard. Budget
> 30-60 minutes for the first one (account setup), 10-15 minutes per
> additional client.

---

## Phase 1: Twilio Account Setup (One-Time)

Do this once for your agency. All client numbers live under your single
Twilio account.

- [ ] **1.1** Sign up at [twilio.com](https://www.twilio.com) with your agency email
- [ ] **1.2** Upgrade from trial to a paid account (required for A2P 10DLC and production use)
  - Add a credit card or set up billing
  - Trial accounts cannot register for A2P 10DLC
  - Trial accounts add a "sent from Twilio" prefix to SMS messages
- [ ] **1.3** Note your credentials from the Twilio Console dashboard:
  - **Account SID**: `ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`
  - **Auth Token**: `xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`
  - Store these securely -- you will need them for Vapi and n8n
- [ ] **1.4** Enable geographic permissions for US calling:
  - Console > Voice > Settings > Geo Permissions
  - Ensure "United States" is checked under both Voice and SMS

---

## Phase 2: Buy a Phone Number (Per Client)

Each client gets their own dedicated local number.

- [ ] **2.1** Go to Console > Phone Numbers > Buy a Number
- [ ] **2.2** Search with these filters:
  - **Country**: United States
  - **Type**: Local
  - **Capabilities**: Voice + SMS (both checked)
  - **Area code**: Match the client's local area code (e.g., 602 for Phoenix)
    - Using a local area code increases answer rates and builds trust
- [ ] **2.3** Purchase the number
  - Cost: ~$1.15/month per number + usage charges
  - Usage: ~$0.0085/min inbound voice, ~$0.0140/min outbound voice
  - SMS: ~$0.0079/segment sent, ~$0.0079/segment received
- [ ] **2.4** Label the number in Twilio Console:
  - Click the number > Friendly Name > Enter: `{{CLIENT_BUSINESS_NAME}} - AI Receptionist`
- [ ] **2.5** Record the number in your client database:
  - Number: `+1XXXXXXXXXX`
  - SID: `PNxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`

---

## Phase 3: Connect Number to Vapi

This makes Vapi answer calls to the Twilio number with your AI assistant.

### Option A: Import via Vapi Dashboard (Recommended for Starting Out)

- [ ] **3.1** Log in to [dashboard.vapi.ai](https://dashboard.vapi.ai)
- [ ] **3.2** Go to **Phone Numbers** in the left sidebar
- [ ] **3.3** Click **Import** > Select **Twilio**
- [ ] **3.4** Enter your Twilio credentials:
  - **Account SID**: from Phase 1
  - **Auth Token**: from Phase 1
  - **Phone Number**: the number you just bought (e.g., `+16025551234`)
- [ ] **3.5** Assign an assistant:
  - Select the Vapi assistant you created for this client
  - Or leave unassigned and set it later
- [ ] **3.6** Verify the connection:
  - Call the number from your personal phone
  - The Vapi assistant should answer
  - If it rings out or goes to Twilio's default voicemail, check Step 3.4

### Option B: Import via Vapi API

```bash
curl -X POST "https://api.vapi.ai/phone-number" \
  -H "Authorization: Bearer YOUR_VAPI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "twilio",
    "twilioAccountSid": "ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "twilioAuthToken": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "number": "+16025551234",
    "assistantId": "YOUR_ASSISTANT_ID"
  }'
```

### What Happens Behind the Scenes

When you import a Twilio number into Vapi:
1. Vapi updates the number's **Voice webhook** in Twilio to point to Vapi's servers
2. Incoming calls to that number get routed to Vapi's infrastructure
3. Vapi handles speech-to-text, LLM processing, and text-to-speech
4. Your Server URL (n8n webhook) receives events during and after the call

**Important:** Do NOT manually change the Voice webhook URL in Twilio Console
after importing -- it will break the Vapi connection.

---

## Phase 4: Configure Call Forwarding / Fallback

Set up what happens when the AI cannot handle a call (transfer to human).

- [ ] **4.1** In Vapi Dashboard > Assistant Settings > **Transfer** section:
  - Add the client's real office number as a transfer destination
  - Label it: "Office" or "Dispatch"
- [ ] **4.2** Configure transfer conditions in the system prompt:
  - The system prompt template (see 01-vapi-system-prompt.md) already includes
    scenarios where the AI should transfer (complaints, complex technical questions)
- [ ] **4.3** Set up a fallback for Vapi outages (optional but recommended):
  - In Twilio Console > the phone number > Voice Configuration
  - Under "Primary Handler Fails," set a fallback URL or forward to client's number
  - Note: only configure the fallback section, not the primary webhook

---

## Phase 5: A2P 10DLC Registration (Required for SMS)

As of 2025, US carriers block unregistered SMS from application-to-person
(A2P) sources. You MUST register before sending any SMS (missed call
follow-ups, lead auto-texts, etc.).

### Step-by-Step Registration

- [ ] **5.1** Go to Twilio Console > **Messaging** > **Trust Hub** > **A2P Registration**

- [ ] **5.2** Register Your Brand (your agency, done once):
  - **Brand Type**: Select your entity type
    - **Standard Brand** ($44 one-time fee): if your agency is an LLC/Corp with an EIN
    - **Sole Proprietor** ($4 one-time fee): if you are operating as an individual
  - **Required information**:
    - Legal business name (must match IRS records exactly)
    - EIN (Employer Identification Number) -- or SSN for sole proprietors
    - Business address
    - Website URL
    - Business type and industry
    - Contact email and phone
  - **Timeline**: 1-3 business days for brand approval

- [ ] **5.3** Create a Campaign (one per use case):
  - **Use case**: Select "Mixed" or "Customer Care" for AI receptionist SMS
  - **Description**: "Automated follow-up messages from AI receptionist service
    for home service businesses. Messages include missed call follow-ups,
    appointment confirmations, and lead acknowledgments."
  - **Sample messages** (provide 2-3):
    1. "Hi! We noticed we missed your call at ABC Heating. We'd love to help! Reply to this text or call us back at (602) 555-1234."
    2. "Your appointment with ABC Heating is confirmed for Tuesday 6/10 between 8-10 AM. Reply STOP to opt out."
    3. "Thanks for reaching out to ABC Heating! We got your request and someone will be in touch shortly."
  - **Opt-in description**: "Callers opt in by calling the business phone number.
    Website leads opt in by submitting the service request form which includes
    SMS consent language."
  - **Opt-out keywords**: STOP, CANCEL, UNSUBSCRIBE
  - **Help keyword**: HELP
  - **Cost**: $15 one-time vetting fee + $1.50-10/month per campaign
  - **Timeline**: 10-15 business days for campaign approval (currently delayed due to volume)

- [ ] **5.4** Associate Phone Numbers with the Campaign:
  - After campaign approval, add each client's Twilio number to the campaign
  - Console > Messaging > A2P > Campaigns > [your campaign] > Phone Numbers > Add

- [ ] **5.5** Add opt-out handling to your n8n workflows:
  - When someone texts STOP, Twilio handles the opt-out automatically
  - Your workflows should check the opt-out list before sending SMS
  - Twilio manages a built-in opt-out list per number

### A2P 10DLC Cost Summary

| Item | Cost | Frequency |
|---|---|---|
| Brand registration (standard) | $44 | One-time |
| Brand registration (sole prop) | $4 | One-time |
| Campaign vetting | $15 | One-time per campaign |
| Campaign monthly fee | $1.50-$10 | Monthly per campaign |
| Per-message carrier surcharge | $0.003-$0.005 | Per SMS segment |

---

## Phase 6: Test Everything

Run through this checklist for every new client before going live.

### Voice Tests
- [ ] **6.1** Call the Twilio number from a cell phone
  - AI should answer with the client's greeting
  - If no answer: check Vapi phone number import and assistant assignment
- [ ] **6.2** Test the full booking flow:
  - Give your name, phone, address, describe a service need
  - Confirm an appointment time
  - Verify: n8n webhook fires, data appears in Supabase, SMS + email arrive
- [ ] **6.3** Test the emergency flow:
  - Say "I smell gas" or "my pipe burst and water is flooding everywhere"
  - AI should fast-track information collection
  - Verify: urgency is flagged as "emergency" in the lead record
- [ ] **6.4** Test a missed call:
  - Call and hang up after 3 seconds
  - Verify: end-of-call webhook fires, missed call logged, follow-up SMS sent to your phone
- [ ] **6.5** Test the transfer flow:
  - Ask to speak to a manager or describe a billing complaint
  - AI should attempt transfer to the configured number

### SMS Tests
- [ ] **6.6** Trigger a website lead submission
  - Fill out the web form with test data
  - Verify: lead appears in Supabase, SMS received by "client," auto-SMS received by "lead"
- [ ] **6.7** Reply STOP to an SMS
  - Verify: Twilio handles opt-out, no further SMS sent to that number

### Reporting Tests
- [ ] **6.8** Manually trigger the daily report workflow in n8n
  - Verify: email arrives with correct metrics
- [ ] **6.9** Check Supabase views:
  - Query `SELECT * FROM daily_call_summary WHERE client_id = '...'`
  - Verify data matches your test calls

---

## Quick Reference: Monthly Costs Per Client

| Item | Cost |
|---|---|
| Twilio phone number | $1.15/month |
| Twilio voice (est. 200 calls x 2 min avg) | ~$3.40/month |
| Twilio SMS (est. 100 messages) | ~$0.79/month |
| A2P 10DLC campaign fee | $1.50-$10/month |
| Vapi usage (est. 200 calls x 2 min avg) | ~$20-40/month (depends on plan) |
| **Total infrastructure cost per client** | **~$27-55/month** |

Your margin: charge $297-$997/month per client depending on call volume and plan.

---

## Troubleshooting

| Problem | Check |
|---|---|
| Calls not answered by AI | Vapi Dashboard > Phone Numbers > verify assistant is assigned |
| Calls go to Twilio voicemail | Voice webhook was overwritten -- re-import number in Vapi |
| SMS not delivered | A2P 10DLC registration not approved -- check campaign status |
| SMS shows "trial" prefix | Upgrade Twilio from trial to paid account |
| Webhook not firing | Check n8n webhook URL is correct in Vapi Server URL settings |
| Wrong client getting notifications | Verify `assistantId` maps to correct `client_id` in Supabase |
| Caller hears silence | Check Vapi voice provider credentials (ElevenLabs API key) |
| AI sounds robotic | Adjust voice settings: increase `stability` to 0.7, `similarityBoost` to 0.8 |
