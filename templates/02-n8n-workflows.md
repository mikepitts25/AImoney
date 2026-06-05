# n8n Workflow Architecture
## 4 Core Workflows for an AI Voice Agent Agency

> **How to use:** Build these workflows in n8n (self-hosted or n8n Cloud).
> Each section describes the trigger, every node in sequence, and the data
> flowing between them. Screenshots are not needed -- follow the node list
> and connect them in order.

---

## Prerequisites

### Credentials to Configure in n8n First

| Credential | Where to Get It |
|---|---|
| **Supabase** | Project URL + `service_role` key from Supabase Dashboard > Settings > API |
| **Twilio** | Account SID + Auth Token from twilio.com/console |
| **SMTP / Gmail** | Gmail App Password or SMTP credentials for sending emails |
| **Vapi** | API key from dashboard.vapi.ai > Organization > API Keys |

### Webhook Base URL
- n8n Cloud: `https://your-instance.app.n8n.cloud/webhook/`
- Self-hosted: `https://your-domain.com/webhook/` (must be publicly accessible with HTTPS)

---

## Workflow 1: Inbound Call Handler

**Purpose:** Receive the Vapi tool-call webhook when the AI books an appointment
or takes a message, store it in Supabase, notify the client via SMS and email.

### Trigger
**Webhook node** (POST) -- path: `/vapi-book-appointment` and a second
Webhook node for `/vapi-take-message`. Use two separate workflows or an
initial Router/Switch node.

### Node Sequence

```
[Webhook: POST /vapi-book-appointment]
    |
[Set Node: "Extract Call Data"]
    -- Map incoming fields:
       caller_name    = {{ $json.message.toolCallList[0].function.arguments.caller_name }}
       phone_number   = {{ $json.message.toolCallList[0].function.arguments.phone_number }}
       address        = {{ $json.message.toolCallList[0].function.arguments.address }}
       service_needed = {{ $json.message.toolCallList[0].function.arguments.service_needed }}
       preferred_date = {{ $json.message.toolCallList[0].function.arguments.preferred_date }}
       time_window    = {{ $json.message.toolCallList[0].function.arguments.preferred_time_window }}
       is_emergency   = {{ $json.message.toolCallList[0].function.arguments.is_emergency }}
       is_existing    = {{ $json.message.toolCallList[0].function.arguments.is_existing_customer }}
       client_id      = {{ $json.message.call.assistantId }}
       call_id        = {{ $json.message.call.id }}
    |
[Supabase Node: "Insert Lead"]
    -- Table: leads
    -- Operation: Insert
    -- Fields: caller_name, phone_number, address, service_needed,
              urgency (set "emergency" if is_emergency, else "medium"),
              source = "phone", client_id, call_id, status = "new"
    |
[Supabase Node: "Insert Appointment"]   (runs in parallel with notifications below)
    -- Table: appointments
    -- Operation: Insert
    -- Fields: lead_id (from previous insert), client_id,
              scheduled_date, time_window, service_type, status = "scheduled"
    |
[Supabase Node: "Lookup Client"]
    -- Table: clients
    -- Operation: Get
    -- Filter: id = client_id
    -- Returns: client business name, notification_email, notification_phone
    |
    +---> [Twilio Node: "SMS to Client"]
    |         -- To: {{ client.notification_phone }}
    |         -- From: {{ client's Twilio number }}
    |         -- Body: "New {{urgency}} booking from {{caller_name}} at {{address}}.
    |                   Service: {{service_needed}}.
    |                   Scheduled: {{preferred_date}} ({{time_window}}).
    |                   Call back: {{phone_number}}"
    |
    +---> [Email Node: "Email to Client"]
    |         -- To: {{ client.notification_email }}
    |         -- Subject: "[{{COMPANY_NAME}}] New Appointment - {{caller_name}}"
    |         -- Body (HTML): formatted appointment details table
    |
    +---> [Respond to Webhook Node]
              -- Return to Vapi:
              {
                "results": [{
                  "toolCallId": "{{ $json.message.toolCallList[0].id }}",
                  "result": "Appointment booked successfully for {{ preferred_date }} in the {{ time_window }}. Please confirm with the caller."
                }]
              }
```

### Key Configuration Notes
- The Respond to Webhook node MUST return data in Vapi's expected format with `results` array containing `toolCallId` and `result` string.
- The `assistantId` from the call payload maps to your `client_id` -- this is how you know which business this call belongs to.
- For the "take message" webhook, follow the same pattern but skip the appointment insert and adjust the SMS/email content.

---

## Workflow 2: Missed Call Follow-Up

**Purpose:** When a call goes unanswered or the caller hangs up before the AI
collects their info, automatically send a follow-up SMS and notify the client.

### Trigger
**Webhook node** (POST) -- path: `/vapi-end-of-call`

Configure this URL as the **Server URL** in the Vapi assistant settings.
Vapi sends an `end-of-call-report` event to this URL after every call.

### Node Sequence

```
[Webhook: POST /vapi-end-of-call]
    |
[IF Node: "Was Call Completed?"]
    -- Condition: Check if call was successful
       TRUE path  = {{ $json.message.analysis?.structuredData?.call_outcome }}
                    is one of: "appointment_booked", "message_taken", "transferred"
       FALSE path = call_outcome is "hangup" OR duration < 15 seconds
                    OR structuredData is empty
    |
    |--- TRUE path ---> [Supabase Node: "Log Completed Call"]
    |                       -- Table: calls
    |                       -- Insert: call_id, client_id, caller_phone,
    |                                  duration, transcript, summary,
    |                                  structured_data, outcome = "completed",
    |                                  created_at
    |
    |--- FALSE path ---> [Set Node: "Extract Missed Call Data"]
                            -- caller_phone = {{ $json.message.call.customer.number }}
                            -- client_id = {{ $json.message.call.assistantId }}
                            -- call_id = {{ $json.message.call.id }}
                            |
                         [Supabase Node: "Log Missed Call"]
                            -- Table: calls
                            -- Insert: call_id, client_id, caller_phone,
                                      duration, outcome = "missed"
                            |
                         [Supabase Node: "Lookup Client"]
                            -- Get client's Twilio number and info
                            |
                         [IF Node: "Have Caller Phone?"]
                            |
                            |--- YES ---> [Twilio Node: "SMS Follow-Up to Caller"]
                            |                -- From: client's Twilio number
                            |                -- To: caller_phone
                            |                -- Body: "Hi! We noticed we missed your
                            |                  call at {{COMPANY_NAME}}. We'd love to
                            |                  help! Reply to this text or call us back
                            |                  at {{CLIENT_PHONE}}. We're available
                            |                  {{BUSINESS_HOURS}}."
                            |
                            +-----------> [Twilio Node: "SMS to Client"]
                            |                -- Notify client of missed call
                            |
                            +-----------> [Email Node: "Email to Client"]
                                             -- Subject: "[MISSED CALL] {{caller_phone}}"
                                             -- Body: call details + "caller did not
                                               complete the conversation"
```

### Key Configuration Notes
- Vapi includes `call.customer.number` in the webhook payload -- this is the caller's phone.
- Set the **End of Call Report** messages in the Vapi Server URL settings to ensure you receive the full analysis.
- The 15-second threshold catches calls where the caller hung up during the greeting.
- The SMS from the client's Twilio number keeps the branding consistent -- the caller sees the same number they originally called.

---

## Workflow 3: Client Reporting (Daily + Weekly)

**Purpose:** Aggregate call data and send each client a formatted report
showing call volume, leads captured, appointments booked, and missed calls.

### Trigger
**Schedule Trigger node** -- Two instances:
- Daily: Cron `0 8 * * 1-6` (8 AM Mon-Sat, client's timezone)
- Weekly: Cron `0 8 * * 1` (8 AM Monday)

### Node Sequence

```
[Schedule Trigger: Daily at 8 AM]
    |
[Supabase Node: "Get Active Clients"]
    -- Table: clients
    -- Filter: status = "active"
    -- Returns: array of all active clients
    |
[Split In Batches Node]
    -- Process each client one at a time
    |
    [Supabase Node: "Get Yesterday's Calls"]
        -- Table: calls
        -- Filter: client_id = current client AND
                   created_at >= yesterday 00:00 AND
                   created_at < today 00:00
        |
    [Supabase Node: "Get Yesterday's Leads"]
        -- Table: leads
        -- Filter: client_id = current client AND
                   created_at >= yesterday 00:00
        |
    [Supabase Node: "Get Yesterday's Appointments"]
        -- Table: appointments
        -- Filter: client_id = current client AND
                   created_at >= yesterday 00:00
        |
    [Code Node: "Calculate Metrics"]
        -- JavaScript:
        const calls = $('Get Yesterday\'s Calls').all();
        const leads = $('Get Yesterday\'s Leads').all();
        const appointments = $('Get Yesterday\'s Appointments').all();

        return [{
          json: {
            total_calls: calls.length,
            completed_calls: calls.filter(c => c.json.outcome === 'completed').length,
            missed_calls: calls.filter(c => c.json.outcome === 'missed').length,
            new_leads: leads.length,
            appointments_booked: appointments.length,
            emergency_calls: leads.filter(l => l.json.urgency === 'emergency').length,
            avg_duration: calls.length > 0
              ? Math.round(calls.reduce((sum, c) => sum + (c.json.duration || 0), 0) / calls.length)
              : 0,
            // Build a summary table of each call
            call_details: calls.map(c => ({
              time: c.json.created_at,
              caller: c.json.caller_phone,
              duration: c.json.duration + 's',
              outcome: c.json.outcome
            }))
          }
        }];
        |
    [IF Node: "Any Activity?"]
        -- Condition: total_calls > 0
        |
        |--- YES ---> [Email Node: "Send Daily Report"]
        |                -- To: client.notification_email
        |                -- Subject: "[{{COMPANY_NAME}}] Daily Call Report - {{date}}"
        |                -- Body (HTML):
        |                   <h2>Your AI Receptionist Report for {{date}}</h2>
        |                   <table>
        |                     <tr><td>Total Calls</td><td>{{total_calls}}</td></tr>
        |                     <tr><td>Answered</td><td>{{completed_calls}}</td></tr>
        |                     <tr><td>Missed/Hangups</td><td>{{missed_calls}}</td></tr>
        |                     <tr><td>New Leads</td><td>{{new_leads}}</td></tr>
        |                     <tr><td>Appointments Booked</td><td>{{appointments_booked}}</td></tr>
        |                     <tr><td>Emergency Calls</td><td>{{emergency_calls}}</td></tr>
        |                     <tr><td>Avg Call Duration</td><td>{{avg_duration}}s</td></tr>
        |                   </table>
        |                   <h3>Call Log</h3>
        |                   {{call_details table}}
        |
        |--- NO  ---> (skip, no email for zero-activity days)
```

### Weekly Report Variation
- Same structure but query the past 7 days instead of 1.
- Add week-over-week comparison (store previous week's metrics or query 14 days back).
- Include a "Top Issues" section by grouping `service_needed` from the leads table.
- Send to client.notification_email with subject: `[Weekly Summary] ...`

---

## Workflow 4: Website Lead Capture

**Purpose:** When a potential customer submits a form on the client's website,
capture the lead in Supabase, notify the client, and optionally trigger an
outbound AI call or SMS.

### Trigger
**Webhook node** (POST) -- path: `/website-lead`

The client's website form submits to this URL. Provide them with a simple
JavaScript snippet (included below).

### Node Sequence

```
[Webhook: POST /website-lead]
    |
[Set Node: "Normalize Lead Data"]
    -- name          = {{ $json.body.name }}
    -- phone         = {{ $json.body.phone }}
    -- email         = {{ $json.body.email }}
    -- address       = {{ $json.body.address }}
    -- service       = {{ $json.body.service_needed }}
    -- message       = {{ $json.body.message }}
    -- client_id     = {{ $json.body.client_id }}  (embedded in the form as hidden field)
    -- source        = "website"
    -- submitted_at  = {{ $now }}
    |
[Supabase Node: "Insert Lead"]
    -- Table: leads
    -- Fields: caller_name=name, phone_number=phone, email,
              address, service_needed=service, notes=message,
              client_id, source, status="new"
    |
[Supabase Node: "Lookup Client"]
    -- Get client info for notifications
    |
    +---> [Twilio Node: "SMS to Client"]
    |         -- "New website lead: {{name}} needs {{service}} at {{address}}.
    |            Phone: {{phone}}. Email: {{email}}."
    |
    +---> [Email Node: "Email to Client"]
    |         -- Subject: "[Web Lead] {{name}} - {{service}}"
    |         -- Formatted HTML with all lead details
    |
    +---> [IF Node: "Auto-SMS Enabled?"]
    |         -- Check: client.auto_sms_leads = true
    |         |
    |         YES ---> [Twilio Node: "SMS to Lead"]
    |                     -- From: client's Twilio number
    |                     -- To: lead's phone
    |                     -- "Hi {{name}}, thanks for reaching out to
    |                        {{COMPANY_NAME}}! We got your request about
    |                        {{service}} and someone will be in touch shortly.
    |                        If it's urgent, call us at {{CLIENT_PHONE}}."
    |
    +---> [Respond to Webhook Node]
              -- HTTP 200:
              { "success": true, "message": "Lead received" }
```

### Website Form Snippet (give to client)

```html
<form id="service-request" onsubmit="submitLead(event)">
  <input name="name" placeholder="Your Name" required>
  <input name="phone" type="tel" placeholder="Phone Number" required>
  <input name="email" type="email" placeholder="Email">
  <input name="address" placeholder="Service Address" required>
  <select name="service_needed">
    <option value="">What do you need help with?</option>
    <option value="ac_repair">AC Repair</option>
    <option value="heating_repair">Heating Repair</option>
    <option value="plumbing">Plumbing</option>
    <option value="water_heater">Water Heater</option>
    <option value="maintenance">Maintenance / Tune-Up</option>
    <option value="other">Other</option>
  </select>
  <textarea name="message" placeholder="Tell us more (optional)"></textarea>
  <input type="hidden" name="client_id" value="YOUR_CLIENT_UUID_HERE">
  <button type="submit">Request Service</button>
</form>

<script>
async function submitLead(e) {
  e.preventDefault();
  const form = e.target;
  const data = Object.fromEntries(new FormData(form));
  try {
    const res = await fetch('https://your-n8n.app.n8n.cloud/webhook/website-lead', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data)
    });
    if (res.ok) {
      form.innerHTML = '<p>Thanks! We will be in touch shortly.</p>';
    }
  } catch (err) {
    alert('Something went wrong. Please call us instead.');
  }
}
</script>
```

---

## Workflow Summary

| # | Workflow | Trigger | Key Nodes | Output |
|---|---|---|---|---|
| 1 | Inbound Call Handler | Vapi tool-call webhook (POST) | Webhook, Set, Supabase x3, Twilio, Email, Respond to Webhook | Lead + appointment in DB, SMS + email to client, response to Vapi |
| 2 | Missed Call Follow-Up | Vapi end-of-call webhook (POST) | Webhook, IF, Supabase x2, Twilio x2, Email | Missed call logged, SMS to caller, notification to client |
| 3 | Client Reporting | Schedule Trigger (daily/weekly cron) | Schedule, Supabase x4, Split In Batches, Code, IF, Email | Formatted report emailed to each active client |
| 4 | Website Lead Capture | Webhook from web form (POST) | Webhook, Set, Supabase x2, Twilio x2, Email, IF, Respond to Webhook | Lead in DB, notifications sent, optional auto-SMS to lead |
