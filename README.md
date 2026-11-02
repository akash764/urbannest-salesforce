# UrbanNest Real Estate: Salesforce Platform & Automation

**Platform:** Salesforce Sales Cloud + Experience Cloud  
**Integrations:** Razorpay Payment Gateway + WhatsApp Business API  
**Project Reference:** UN-BRD-001 (v1.4)  

---

## 🏗️ Project Architecture & Components

```
urbannest-salesforce/
├── sfdx-project.json
├── force-app/main/default/
│   ├── classes/
│   │   ├── RazorpayWebhookHandler.cls     # Public REST webhook endpoint (HMAC SHA-256 verification)
│   │   ├── RazorpayPaymentService.cls     # Payment Link creation callout & dispatch service
│   │   ├── EnquiryController.cls          # Public guest enquiry intake, duplicate matching & round robin
│   │   ├── BookingLifecycleHandler.cls    # 1:1 Booking enforcement & House status state machine
│   │   ├── CancellationRefundService.cls  # Manager approval, 10% deduction, 3-day SLA & house release
│   │   └── WhatsAppNotificationService.cls# WhatsApp Business API alerts for visits & payments
│   ├── lwc/
│   │   ├── enquiryForm/                   # Responsive Experience Cloud Lead Enquiry Form
│   │   ├── projectBrochure/               # Project showcase, building gallery & 1/2/3 BHK unit matrix
│   │   └── generatePaymentLink/           # Quick Action for Sales Execs to send Razorpay links
│   └── objects/
│       ├── Project__c/                    # Project records (Budget, State, Description)
│       ├── Apartment__c/                  # Apartment Towers/Blocks
│       ├── House_Unit__c/                 # Individual 1, 2, 3 BHK units
│       ├── Payment__c/                    # Razorpay transactions & status rollups
│       ├── Cancellation_Refund__c/        # Drop-out, manager approval & finance refund tracking
│       └── Vehicle_Request__c/            # Site visit transport dispatch
```

---

## 🚀 Setup & Deployment Guide

### 1. Deploying to Salesforce Org
Run the following SFDX / Salesforce CLI command from this folder:
```bash
sf project deploy start --target-org <YourOrgAlias>
```

### 2. Configure Named Credentials
To enable outbound callouts to Razorpay and WhatsApp:
1. Go to **Setup -> Security -> Named Credentials**.
2. Create **External Credential & Named Credential**:
   - `Razorpay_API`: Endpoint `https://api.razorpay.com`
   - Authentication Protocol: `Basic Authentication` using your Razorpay Key ID and Key Secret.
   - `WhatsApp_Business_API`: Endpoint `https://graph.facebook.com`

### 3. Setup Razorpay Webhook Endpoint
1. Go to **Setup -> User Interface -> Sites and Experience Sites**.
2. Open your public site guest profile (or Force.com public site) and grant Apex Class access to `RazorpayWebhookHandler`.
3. In your **Razorpay Merchant Dashboard**:
   - Navigate to **Settings -> Webhooks -> Add New Webhook**.
   - URL: `https://<Your-Site-Domain>/services/apexrest/api/razorpay/webhook`
   - Secret: Enter your chosen secret (update `DEFAULT_WEBHOOK_SECRET` in `RazorpayWebhookHandler.cls` or custom metadata).
   - Active Events:
     - `payment_link.paid`
     - `payment.captured`
     - `payment_link.expired`

### 4. Experience Cloud Public Website Configuration
1. In **Setup -> Digital Experiences**, create an LWR or Aura site (e.g. *UrbanNest Properties*).
2. Ensure **Public Access** is enabled in *Administration -> Pages*.
3. Add the `enquiryForm` component to the Homepage and the `projectBrochure` component to the Project Brochure page.
4. In **Guest User Profile**, grant Read access to `Project__c`, `Apartment__c`, `House_Unit__c`, and Create access to `Lead`.

### 5. Duplicate Rules & Lead Routing
1. Go to **Setup -> Data Cloud / Duplicate Management -> Duplicate Rules**.
2. Ensure standard duplicate rule on `Lead` matches on:
   - `(Lead: Email EXACT) OR (Lead: Phone EXACT)`
3. Ensure `Lead Source` picklist values contain only:
   - `Phone Enquiry`
   - `Own Website`

---

## 📊 Business Logic Summary

| Event | System Behavior |
|---|---|
| **Web Enquiry Submitted** | Checked against existing leads on Phone & Email; if new, created with `Own Website` source and assigned via Round Robin. |
| **Phone Enquiry** | Sales Executive manually enters lead with `Phone Enquiry` source; owned by creator. |
| **Booking Opportunity Created** | Validates that House Unit is not already booked under active Opportunity; sets House Unit status to `Under Offer`. |
| **Razorpay Advance Paid** | Webhook marks `Payment__c` as `Paid`; Opportunity advances to `Document Collection`; House Unit updates to `Reserved`. |
| **Full Settlement Paid** | Opportunity advances to `Construction Milestone`; House Unit updates to `Sold`. |
| **Key Handover** | Opportunity marked `Key Handover` (Closed Won); House Unit updates to `Occupied`. |
| **Cancellation Requested** | Manager approves -> 10% deduction applied, 90% refund due in 3 business days. Finance completes refund -> House Unit reverts to `Available` and Opportunity moves to `Closed Lost`. |
